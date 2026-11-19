#include "nodes.h"
#include "../agent_behaviours/considerations.h"
#include "../score_aggregation.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTNodes::_bind_methods() {
	BIND_ENUM_CONSTANT(RUNNING);
	BIND_ENUM_CONSTANT(FAILURE);
	BIND_ENUM_CONSTANT(SUCCESS);
	BIND_ENUM_CONSTANT(SKIP);

	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNBTNodes::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNBTNodes::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum,Min,Max,Mean,Multiply,First Non Zero", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NoodleNodes.EvaluationMethod"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("get_tree_root"), &NNBTNodes::get_tree_root);

	ClassDB::bind_method(D_METHOD("interrupt"), &NNBTNodes::interrupt);
	ClassDB::bind_method(D_METHOD("reset"), &NNBTNodes::reset);
	ClassDB::bind_method(D_METHOD("get_is_running"), &NNBTNodes::get_is_running);

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("get_score"), &NNBTNodes::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY), "", "get_score");

	ClassDB::bind_method(D_METHOD("get_tick_result"), &NNBTNodes::get_tick_result);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick_result", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1,Skip:-2"), "", "get_tick_result");

	// Signals.
}

// Constructor and destructor.

NNBTNodes::NNBTNodes() {
	_score = 0.0;
	_evaluation_method = EVALUATION_MULTIPLY;
	_tick_result = Status::SUCCESS;
	_is_running = false;
	_run_owner = ObjectID();
	_run_delta = 0.0f;
	_num_child_btnodes = 0;
	_num_child_considerations = 0;
	_has_reported_extra_enabled_child = false;
#ifdef DEBUG_ENABLED
	_last_visited_timestamp = 0;
	_last_evaluated_timestamp = 0;
#endif
}

NNBTNodes::~NNBTNodes() {
}

// Getters and Setters.

void NNBTNodes::set_evaluation_method(EvaluationMethod evaluation_method) {
	_evaluation_method = evaluation_method;
}

NoodleNodes::EvaluationMethod NNBTNodes::get_evaluation_method() const {
	return _evaluation_method;
}

float NNBTNodes::get_score() const {
	return _score;
}

NNBTNodes::Status NNBTNodes::get_tick_result() const {
	return _tick_result;
}

bool NNBTNodes::get_is_running() const {
	return _is_running;
}

ObjectID NNBTNodes::get_run_owner() const {
	return _run_owner;
}

void NNBTNodes::set_run_owner(ObjectID p_owner) {
	_run_owner = p_owner;
}

NodePath NNBTNodes::get_tree_root() const {
	Node *furthest_node = const_cast<NNBTNodes *>(this);
	Node *parent_node = furthest_node->get_parent();
	while (Object::cast_to<NNBTNodes>(parent_node)) {
		furthest_node = parent_node;
		parent_node = furthest_node->get_parent();
	}
	return get_path_to(furthest_node);
}

// Handling methods.

void NNBTNodes::reset() {
	interrupt();
	for (int i = 0; i < _num_child_btnodes; i++) {
		_child_btnodes[i]->reset();
	}
}

float NNBTNodes::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	_score = 0.0f;

	// Evaluate the child considerations.
	if (_num_child_considerations < 1) {
		return _score;
	}
	ScoreAggregation aggregation(_evaluation_method);
	for (unsigned int i = 0; i < _num_child_considerations; i++) {
		NNConsiderations *considerationNode = _child_considerations[i];
		if (!considerationNode->get_is_enabled())
			continue;
		float child_score = considerationNode->evaluate();
		if (considerationNode->get_has_vetoed()) {
			_score = 0.0f;
			return _score; // Veto zeroes out the score for the entire group.
		}
		if (aggregation.add(child_score)) {
			break;
		}
	} //endfor children

	_score = aggregation.result();
	return _score;
}

NNBTNodes::Status NNBTNodes::tick(float delta) {
#ifdef DEBUG_ENABLED
	_last_visited_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
	// Disabled nodes never start a run. A reference may have stamped an owner
	// onto this node just before calling tick(), so clear it here to keep the
	// invariant that a node with no active run has no run owner.
	if (!get_is_enabled()) {
		_run_owner = ObjectID();
		return Status::FAILURE;
	}

	if (!_is_running) {
		_is_running = true;
		_run_delta = delta;
		_on_before_run(delta);
		if (!_is_running) {
			// The before_run hook interrupted the run it had just started.
			return Status::FAILURE;
		}
	}

	Status result = _tick(delta);
	// Only the wrapper writes the tick result, so it always describes the most recent tick.
	_tick_result = result;
	if (_is_running && (result == Status::SUCCESS || result == Status::FAILURE)) {
		float run_delta = _run_delta;
		_is_running = false;
		_run_owner = ObjectID();
		_run_delta = 0.0f;
		_interrupt_active_children();
		_on_after_run(run_delta);
	}
	// SKIP is not terminal, so the run stays active for a later interrupt or
	// terminal result.
	return result;
}

NNBTNodes::Status NNBTNodes::_tick(float delta) {
	return Status::RUNNING;
}

void NNBTNodes::interrupt() {
	if (!_is_running) {
		return;
	}

	float run_delta = _run_delta;
	_is_running = false;
	_run_owner = ObjectID();
	_run_delta = 0.0f;
	_interrupt_active_children();
	_on_interrupt(run_delta);
}

// Lifecycle hooks.

void NNBTNodes::_on_before_run(float delta) {
}

void NNBTNodes::_on_after_run(float delta) {
}

void NNBTNodes::_on_interrupt(float delta) {
}

void NNBTNodes::_interrupt_active_children() {
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		_child_btnodes[i]->interrupt();
	}
}

void NNBTNodes::_interrupt_other_active_children(const NNBTNodes *p_keep) {
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		if (_child_btnodes[i] == p_keep) {
			continue;
		}
		_child_btnodes[i]->interrupt();
	}
}

void NNBTNodes::_on_is_enabled_changed(bool p_is_enabled) {
	if (p_is_enabled) {
		// Re-enabling is a no-op; the next tick starts a fresh run.
		return;
	}
	// Disabling interrupts the active run and resets the subtree exactly once.
	reset();
}

// Godot virtuals.

void NNBTNodes::_notification(int p_what) {
	if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		// Update the child pointers if the child nodes are changed
		// somehow. This caching of the pointers is done to avoid
		// the expensive godot::Object::cast_to calls later.
		update_child_vectors();
	}
}

void NNBTNodes::update_child_vectors() {
	_child_btnodes.clear();
	_child_considerations.clear();
	for (int i = 0; i < get_child_count(); i++) {
		if (NNBTNodes *btnode = godot::Object::cast_to<NNBTNodes>(get_child(i))) {
			_child_btnodes.push_back(btnode);
		} else if (NNConsiderations *consideration = godot::Object::cast_to<NNConsiderations>(get_child(i))) {
			_child_considerations.push_back(consideration);
		}
	}
	_num_child_btnodes = (unsigned int)_child_btnodes.size();
	_num_child_considerations = (unsigned int)_child_considerations.size();
	// The child structure changed, so any previous structural report is stale.
	_has_reported_extra_enabled_child = false;
}

// Structural helper functions.

int NNBTNodes::_count_enabled_child_btnodes() const {
	int count = 0;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		if (_child_btnodes[i]->get_is_enabled()) {
			++count;
		}
	}
	return count;
}

void NNBTNodes::_report_extra_enabled_child_btnodes() {
	if (_has_reported_extra_enabled_child) {
		return;
	}

	bool has_enabled_child = false;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		if (!has_enabled_child) {
			has_enabled_child = true;
			continue;
		}

		_has_reported_extra_enabled_child = true;
		ERR_PRINT(String(get_class()) + " must have exactly one behaviour-tree child; ignoring extra enabled child " + String(btnode->get_name()) + ".");
		return;
	}
}

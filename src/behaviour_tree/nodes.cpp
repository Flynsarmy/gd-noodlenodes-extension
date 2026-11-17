#include "nodes.h"
#include "../agent_behaviours/considerations.h"
#include "blackboard.h"
#include "root.h"
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

	ClassDB::bind_method(D_METHOD("set_reset_rule", "reset_rule"), &NNBTNodes::set_reset_rule);
	ClassDB::bind_method(D_METHOD("get_reset_rule"), &NNBTNodes::get_reset_rule);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "reset_rule", PROPERTY_HINT_ENUM, "WhenTicked:0,WhenCompleted:1,WhenTickedAfterBeingCompleted:2,Never:3"), "set_reset_rule", "get_reset_rule");

	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNBTNodes::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNBTNodes::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum:0,Min:1,Max:2,Mean:3,Multiply:4,FirstNonZero:5"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("get_tree_root"), &NNBTNodes::get_tree_root);

	ClassDB::bind_method(D_METHOD("get_blackboard_resource"), &NNBTNodes::get_blackboard_resource_ref);
	ClassDB::bind_method(D_METHOD("get_blackboard", "key", "default_value"), &NNBTNodes::get_blackboard, Variant());
	ClassDB::bind_method(D_METHOD("set_blackboard", "key", "value"), &NNBTNodes::set_blackboard);
	ClassDB::bind_method(D_METHOD("has_blackboard", "key"), &NNBTNodes::has_blackboard);
	ClassDB::bind_method(D_METHOD("erase_blackboard", "key"), &NNBTNodes::erase_blackboard);
	ClassDB::bind_method(D_METHOD("get_actor"), &NNBTNodes::get_actor);

	ClassDB::bind_method(D_METHOD("interrupt"), &NNBTNodes::interrupt);

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_score", "score"), &NNBTNodes::set_score);
	ClassDB::bind_method(D_METHOD("get_score"), &NNBTNodes::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_NONE), "set_score", "get_score");

	ClassDB::bind_method(D_METHOD("set_tick_result", "tick_result"), &NNBTNodes::set_tick_result);
	ClassDB::bind_method(D_METHOD("get_tick_result"), &NNBTNodes::get_tick_result);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tick_result", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1,Skip:-2"), "set_tick_result", "get_tick_result");

	ClassDB::bind_method(D_METHOD("set_internal_status", "internal_status"), &NNBTNodes::set_internal_status);
	ClassDB::bind_method(D_METHOD("get_internal_status"), &NNBTNodes::get_internal_status);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "internal_status", PROPERTY_HINT_ENUM, "Unticked:0,Ticked:1,Completed:2"), "set_internal_status", "get_internal_status");

	// ClassDB::bind_method(D_METHOD("_tick", "blackboard", "delta"), &NNBTNodes::tick);

	// Signals.
	//ADD_SIGNAL(MethodInfo("btnode_entered", PropertyInfo(Variant::OBJECT, "blackboard"), PropertyInfo(Variant::FLOAT, "delta")));
	//ADD_SIGNAL(MethodInfo("btnode_ticked", PropertyInfo(Variant::OBJECT, "blackboard"), PropertyInfo(Variant::FLOAT, "delta")));
	//ADD_SIGNAL(MethodInfo("btnode_exited", PropertyInfo(Variant::OBJECT, "blackboard"), PropertyInfo(Variant::FLOAT, "delta")));
}

// Constructor and destructor.

NNBTNodes::NNBTNodes() {
	_cached_tree_root_path = NodePath();
	_is_tree_root_path_cached = false;
	_score = 0.0;
	_evaluation_method = NNBTNodesEvaluationMethod::Multiply;
	_invert_score = false;
	_tick_result = Status::SUCCESS;
	_internal_status = BT_INTERNAL_STATUS_UNTICKED;
	_reset_rule = NNBTNodesResetRule::WHEN_TICKED_AFTER_BEING_COMPLETED;
	_has_reset_rule_changed = false;
	_is_running = false;
	_run_owner = ObjectID();
	_run_blackboard = Variant();
	_run_delta = 0.0f;
	//_is_first_tick = true;
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

void NNBTNodes::set_evaluation_method(int evaluation_method) {
	_evaluation_method = evaluation_method;
}

int NNBTNodes::get_evaluation_method() const {
	return _evaluation_method;
}

void NNBTNodes::set_score(float score) {
	_score = score;
}

float NNBTNodes::get_score() const {
	return _score;
}

void NNBTNodes::set_tick_result(Status tick_result) {
	_tick_result = tick_result;
}

NNBTNodes::Status NNBTNodes::get_tick_result() const {
	return _tick_result;
}

void NNBTNodes::set_internal_status(int internal_status) {
#ifdef DEBUG_ENABLED
	_last_visited_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
	switch (_reset_rule) {
		case NNBTNodesResetRule::WHEN_COMPLETED: {
			if (internal_status == BT_INTERNAL_STATUS_COMPLETED) {
				reset_bt_node();
				//_is_first_tick = true;
			}
		} break;
		case NNBTNodesResetRule::WHEN_TICKED_AFTER_BEING_COMPLETED: {
			if (_internal_status == BT_INTERNAL_STATUS_COMPLETED &&
					internal_status == BT_INTERNAL_STATUS_TICKED) {
				reset_bt_node();
				//_is_first_tick = true;
			}
		} break;
		case NNBTNodesResetRule::WHEN_TICKED: {
			if (internal_status == BT_INTERNAL_STATUS_TICKED && (_internal_status != BT_INTERNAL_STATUS_UNTICKED || _has_reset_rule_changed)) {
				reset_bt_node();
				//_is_first_tick = true;
			}
		} break;
		default: {
		} break;
	}

	_internal_status = internal_status;
	_has_reset_rule_changed = false;
}

int NNBTNodes::get_internal_status() const {
	return _internal_status;
}

void NNBTNodes::set_reset_rule(int reset_rule) {
	_has_reset_rule_changed = (reset_rule != _reset_rule);
	_reset_rule = reset_rule;
}

int NNBTNodes::get_reset_rule() const {
	return _reset_rule;
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
	if (_is_tree_root_path_cached) {
		return _cached_tree_root_path;
	}

	Node *current_node = const_cast<NNBTNodes *>(this);
	NodePath path;

	while (current_node) {
		path = this->get_path_to(current_node);
		current_node = current_node->get_parent();
		if (!Object::cast_to<NNBTNodes>(current_node)) {
			break;
		}
	}

	_is_tree_root_path_cached = true;
	_cached_tree_root_path = path;
	return path;
}

// Blackboard and actor helpers.

NNBlackboard *NNBTNodes::get_blackboard_resource() const {
	for (Node *node = const_cast<NNBTNodes *>(this); node != nullptr; node = node->get_parent()) {
		if (NNBTRoot *root = godot::Object::cast_to<NNBTRoot>(node)) {
			return root->get_blackboard_resource();
		}
	}
	return nullptr;
}

Ref<NNBlackboard> NNBTNodes::get_blackboard_resource_ref() const {
	return Ref<NNBlackboard>(get_blackboard_resource());
}

Variant NNBTNodes::get_blackboard(const String &key, const Variant &default_value) const {
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return default_value;
	}
	return board->get_value(key, default_value);
}

bool NNBTNodes::set_blackboard(const String &key, const Variant &value) {
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return false;
	}
	return board->set_value(key, value);
}

bool NNBTNodes::has_blackboard(const String &key) const {
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return false;
	}
	return board->has_value(key);
}

bool NNBTNodes::erase_blackboard(const String &key) {
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return false;
	}
	return board->erase_value(key);
}

Node *NNBTNodes::get_actor() const {
	for (Node *node = const_cast<NNBTNodes *>(this); node != nullptr; node = node->get_parent()) {
		if (NNBTRoot *root = godot::Object::cast_to<NNBTRoot>(node)) {
			return root->get_actor();
		}
	}
	return nullptr;
}

// Handling methods.

void NNBTNodes::reset() {
	interrupt();
	_internal_status = BT_INTERNAL_STATUS_UNTICKED;
	for (int i = 0; i < _num_child_btnodes; i++) {
		_child_btnodes[i]->reset();
	}
	/**
	for( int i = 0; i < get_child_count(); i++ ) {
		if( NNBTNodes* btnode = godot::Object::cast_to<NNBTNodes>(get_child(i)) ) {
			btnode->reset();
		}
	}
	/**/
}

/**
void NNBTNodes::reset_for_looping() {
	_internal_status = BT_INTERNAL_STATUS_UNTICKED;
	for( int i = 0; i < get_child_count(); i++ ) {
		if( NNBTNodes* btnode = godot::Object::cast_to<NNBTNodes>(get_child(i)) ) {
			btnode->reset_for_looping();
		}
	}
}
/**/

float NNBTNodes::evaluate() {
//if( !get_is_enabled() ) return 0.0f;
//if( Engine::get_singleton()->is_editor_hint() ) return 0.0f;
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	_score = 0.0f;

	// Evaluate the child considerations.
	if (_num_child_considerations < 1) {
		return _score;
	}
	//int num_children = get_child_count();
	//if( num_children < 1 ) {
	//    return _score;
	//}
	float child_score = 0.0f;
	unsigned int num_evaluated = 0;
	for (unsigned int i = 0; i < _num_child_considerations; i++) {
		//Node* node = get_child(i);
		//if( node == nullptr ) continue;
		//NNConsiderations* considerationNode = godot::Object::cast_to<NNConsiderations>(node);
		//if( considerationNode == nullptr ) continue;
		NNConsiderations *considerationNode = _child_considerations[i];
		if (!considerationNode->get_is_enabled())
			continue;
		child_score = considerationNode->evaluate();
		if (considerationNode->get_has_vetoed()) {
			_score = 0.0f;
			return 0.0f; // Veto zeroes out the score for the entire group.
		}

		switch (_evaluation_method) {
			case NNBTNodesEvaluationMethod::Min: {
				if (num_evaluated == 0)
					_score = child_score;
				if (child_score < _score)
					_score = child_score;
			} break;
			case NNBTNodesEvaluationMethod::Max: {
				if (num_evaluated == 0)
					_score = child_score;
				if (child_score > _score)
					_score = child_score;
			} break;
			case NNBTNodesEvaluationMethod::Multiply: {
				if (num_evaluated == 0)
					_score = child_score;
				else
					_score *= child_score;
				// If after multiplication we are at 0.0, then none of the
				// other considerations will ever change the result, so bail.
				if (_score == 0.0f) {
					if (_invert_score) {
						_score = 1.0f;
						return 1.0f;
					}
					_score = 0.0f;
					return 0.0f;
				}
			} break;
			case NNBTNodesEvaluationMethod::FirstNonZero: {
				if (child_score > 0.0f) {
					if (_invert_score) {
						_score = 1.0f - child_score;
					} else {
						_score = child_score;
					}
					return _score;
				}
			} break;
			default:
				_score += child_score;
		} //end switch evaluation method
		++num_evaluated;

	} //endfor children

	if (_evaluation_method == NNBTNodesEvaluationMethod::Mean && num_evaluated > 0) {
		_score = _score / ((float)num_evaluated);
	}

	if (_invert_score) {
		_score = 1.0f - _score;
	}

	return _score;
}

NNBTNodes::Status NNBTNodes::tick(Variant blackboard, float delta) {
	// Disabled nodes never start a run. A reference may have stamped an owner
	// onto this node just before calling tick(), so clear it here to keep the
	// invariant that a node with no active run has no run owner.
	if (!get_is_enabled()) {
		_run_owner = ObjectID();
		return Status::FAILURE;
	}

	if (!_is_running) {
		_is_running = true;
		_run_blackboard = blackboard;
		_run_delta = delta;
		_on_before_run(blackboard, delta);
		if (!_is_running) {
			// The before_run hook interrupted the run it had just started.
			return Status::FAILURE;
		}
	}

	Status result = _tick(blackboard, delta);
	if (_is_running && (result == Status::SUCCESS || result == Status::FAILURE)) {
		Variant run_blackboard = _run_blackboard;
		float run_delta = _run_delta;
		_is_running = false;
		_run_owner = ObjectID();
		_run_blackboard = Variant();
		_run_delta = 0.0f;
		_interrupt_active_children();
		_on_after_run(run_blackboard, run_delta);
	}
	// SKIP is not terminal, so the run stays active for a later interrupt or
	// terminal result.
	return result;
}

NNBTNodes::Status NNBTNodes::_tick(Variant blackboard, float delta) {
	return Status::RUNNING;
}

void NNBTNodes::interrupt() {
	if (!_is_running) {
		return;
	}

	Variant run_blackboard = _run_blackboard;
	float run_delta = _run_delta;
	_is_running = false;
	_run_owner = ObjectID();
	_run_blackboard = Variant();
	_run_delta = 0.0f;
	_interrupt_active_children();
	_on_interrupt(run_blackboard, run_delta);
}

// Lifecycle hooks.

void NNBTNodes::_on_before_run(Variant blackboard, float delta) {
}

void NNBTNodes::_on_after_run(Variant blackboard, float delta) {
}

void NNBTNodes::_on_interrupt(Variant blackboard, float delta) {
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

		_is_tree_root_path_cached = false;
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

#include "ticked_nodes.h"
#include "parallel.h"
#include <state_tree/root.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>

using namespace godot;

/**
 * Returns true if `child_state` is currently one of the branch's active child states.
 */
static bool _has_active_child_state(NNSTBranchNodes *branch, NNSTTickedNodes *child_state) {
	std::vector<NNSTTickedNodes *> active_states = branch->_get_active_child_states();
	for (unsigned int i = 0; i < active_states.size(); i++) {
		if (active_states[i] == child_state) {
			return true;
		}
	}

	return false;
}

// Method binds.

void NNSTTickedNodes::_bind_methods() {
	// ClassDB::bind_method(D_METHOD("set_root", "total_tick_usec"), &NNSTTickedNodes::set_root);
	ClassDB::bind_method(D_METHOD("get_root"), &NNSTTickedNodes::get_root);

	ClassDB::bind_method(D_METHOD("get_blackboard", "key", "default"), &NNSTTickedNodes::get_blackboard, Variant());
	ClassDB::bind_method(D_METHOD("set_blackboard", "key", "value"), &NNSTTickedNodes::set_blackboard);

	ClassDB::bind_method(D_METHOD("set_score", "score"), &NNSTTickedNodes::set_score);
	ClassDB::bind_method(D_METHOD("get_score"), &NNSTTickedNodes::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_NONE), "set_score", "get_score");

	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNSTTickedNodes::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNSTTickedNodes::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum:0,Min:1,Max:2,Mean:3,Multiply:4,FirstNonZero:5"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("set_on_entered_condition", "is_entered"), &NNSTTickedNodes::set_is_on_entered_condition_true);
	ClassDB::bind_method(D_METHOD("get_on_entered_condition"), &NNSTTickedNodes::get_is_on_entered_condition_true);
	//ADD_PROPERTY(PropertyInfo(Variant::INT, "child_state_selection_rule", PROPERTY_HINT_ENUM, "OnEnterConditionMethod:0,UtilityScoring:1" ), "set_child_state_selection_rule","get_child_state_selection_rule");

	ClassDB::bind_method(D_METHOD("transition_to", "new_state_nodepath"), &NNSTTickedNodes::transition_to);

	GDVIRTUAL_BIND(on_enter_condition);
	GDVIRTUAL_BIND(on_enter_state);
	GDVIRTUAL_BIND(on_exit_state);
	GDVIRTUAL_BIND(on_tick, "delta");

	ADD_SIGNAL(MethodInfo("state_check_enter_condition"));
	ADD_SIGNAL(MethodInfo("state_entered"));
	ADD_SIGNAL(MethodInfo("state_ticked", PropertyInfo(Variant::FLOAT, "delta")));
	ADD_SIGNAL(MethodInfo("state_exited"));
}

// Constructor and destructor.

NNSTTickedNodes::NNSTTickedNodes() {
	_is_on_entered_condition_true = true;
	_evaluation_method = NNSTTickedNodesEvaluationMethod::Multiply;
	_score = 0.0;
	_invert_score = false;
	_root = nullptr;
}

NNSTTickedNodes::~NNSTTickedNodes() {
}

// Getters and Setters.

void NNSTTickedNodes::set_root(NNSTRoot *p_root) {
	_root = p_root;

	if (!Engine::get_singleton()->is_editor_hint()) {
		for (unsigned int i = 0; i < _num_child_states; i++) {
			NNSTTickedNodes *stnode = _child_states[i];
			stnode->set_root(p_root);
		}
	}
}

NNSTRoot *NNSTTickedNodes::get_root() const {
	return _root;
}

bool NNSTTickedNodes::set_blackboard(const String &p_key, const Variant &p_value) {
	ERR_FAIL_COND_V_MSG(_root == nullptr, false, "Tree root not set on this node. Can't retrieve blackboard.");

	return get_root()->get_blackboard().set(p_key, p_value);
}

Variant NNSTTickedNodes::get_blackboard(const String &p_key, const Variant &p_default) const {
	ERR_FAIL_COND_V_MSG(_root == nullptr, p_default, "Tree root not set on this node. Can't retrieve blackboard.");

	return get_root()->get_blackboard().get(p_key, p_default);
};

void NNSTTickedNodes::set_score(float score) {
	_score = score;
}

float NNSTTickedNodes::get_score() const {
	return _score;
}

void NNSTTickedNodes::set_evaluation_method(int evaluation_method) {
	_evaluation_method = evaluation_method;
}

int NNSTTickedNodes::get_evaluation_method() const {
	return _evaluation_method;
}

void NNSTTickedNodes::set_is_on_entered_condition_true(bool is_on_entered_condition_true) {
	_is_on_entered_condition_true = is_on_entered_condition_true;
}

bool NNSTTickedNodes::get_is_on_entered_condition_true() const {
	return _is_on_entered_condition_true;
}

// Handling methods.

void NNSTTickedNodes::send_event(String name) {
	for (unsigned int i = 0; i < _num_child_transitions; i++) {
		if (_child_transitions[i]->get_event_name() == name) {
			if (_child_transitions[i]->_can_transition()) {
				transition_to(_child_transitions[i]->get_to().slice(1));
			}
			return;
		}
	}

	for (unsigned int i = 0; i < _num_active_states; i++) {
		_active_states[i]->send_event(name);
	}
}

float NNSTTickedNodes::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	_score = 0.0f;

	// Evaluate the children.
	if (_num_child_considerations == 0) {
		return _score;
	}
	float child_score = 0.0;
	unsigned int num_evaluated = 0;

	for (unsigned int i = 0; i < _num_child_considerations; i++) {
		NNConsiderations *considerationNode = _child_considerations[i];
		if (!considerationNode->get_is_enabled())
			continue;
		child_score = considerationNode->evaluate();
		if (considerationNode->get_has_vetoed()) {
			_score = 0.0f;
			return 0.0f; // Veto zeroes out the score for the entire group.
		}

		switch (_evaluation_method) {
			case NNSTTickedNodesEvaluationMethod::Min: {
				if (num_evaluated == 0)
					_score = child_score;
				if (child_score < _score)
					_score = child_score;
			} break;
			case NNSTTickedNodesEvaluationMethod::Max: {
				if (num_evaluated == 0)
					_score = child_score;
				if (child_score > _score)
					_score = child_score;
			} break;
			case NNSTTickedNodesEvaluationMethod::Multiply: {
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
			case NNSTTickedNodesEvaluationMethod::FirstNonZero: {
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

	if (_evaluation_method == NNSTTickedNodesEvaluationMethod::Mean && num_evaluated > 0) {
		_score = _score / ((float)num_evaluated);
	}

	if (_invert_score) {
		_score = 1.0f - _score;
	}

	return _score;
}

void NNSTTickedNodes::transition_to(NodePath path_to_node) {
	// NNSTBranchNodes *parent = godot::Object::cast_to<NNSTBranchNodes>(get_parent());
	// if (!parent) {
	// 	return;
	// }
	NNSTTickedNodes *to_state = get_node<NNSTTickedNodes>(path_to_node);
	if (to_state == nullptr) {
		return;
	}

	NNSTBranchNodes *common_ancestor = _get_common_ancestor(this, to_state);
	if (common_ancestor == nullptr) {
		return;
	}

	if (!_can_transition_to(this, to_state)) {
		return;
	}

	// If the common ancestor is a parallel node, the to_node's lineage is already
	// partially active and we'll need to figure out where the youngest non-active
	// part is so let's not worry about that for now.
	if (common_ancestor->is_class("NNSTParallel")) {
		return;
	}

	// The branch hasn't been entered yet (for example a transition requested
	// before the root's first tick). There is no active child to transition out
	// of, and entering the new one here would leave the branch's ancestors out
	// of sync, so wait for the tree to enter this branch normally.
	const std::vector<NNSTTickedNodes *> active_child_states = common_ancestor->_get_active_child_states();
	if (active_child_states.empty()) {
		return;
	}

	// Get the to_states lineage before changing anything, so a broken lineage
	// can't leave the tree with the old branch transitioned out. The lineage is
	// ordered from the to_state up to the common ancestor.
	Vector<NNSTBranchNodes *> lineage;
	NNSTBranchNodes *parent = to_state;
	lineage.push_back(parent);
	while (parent != nullptr && parent != common_ancestor) {
		parent = godot::Object::cast_to<NNSTBranchNodes>(parent->get_parent());
		lineage.push_back(parent);
	}

	if (lineage.size() < 2 || lineage[lineage.size() - 1] != common_ancestor) {
		return;
	}

	// Transition out the from_states lineage.
	NNSTTickedNodes *child = active_child_states[0];
	common_ancestor->_remove_active_child_state(child);
	child->_transition_out();

	// An on_exit_state() callback may have transitioned the branch while its
	// old states were exiting. Don't overwrite that transition with this one.
	if (common_ancestor->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
			!common_ancestor->_get_active_child_states().empty()) {
		return;
	}

	// Transition in the to_states lineage from the common ancestor down. Each
	// branch is given its new active child before that child is entered, so a
	// state's on_enter_state() always sees a consistent tree: its ancestors are
	// active and its own active child is already registered. Entering the
	// lineage bottom-up (as this used to) entered a state before its ancestors
	// were registered, so any transition_to() it requested was seen as coming
	// from a branch that had never been entered and was discarded.
	common_ancestor->_add_active_child_state(godot::Object::cast_to<NNSTTickedNodes>(lineage[lineage.size() - 2]));

	// The root node itself has no root pointer. Resolve it from the common
	// ancestor so the entered states still receive the tree root.
	NNSTRoot *tree_root = get_root();
	if (tree_root == nullptr) {
		tree_root = godot::Object::cast_to<NNSTRoot>(common_ancestor);
	}

	for (int i = (int)lineage.size() - 1; i >= 1; i--) {
		NNSTBranchNodes *lineage_branch = lineage[i];
		NNSTTickedNodes *lineage_child = godot::Object::cast_to<NNSTTickedNodes>(lineage[i - 1]);

		// A transition requested from an on_enter_state() callback (in this
		// loop or in the transition out above) may have moved the tree away
		// from this lineage. Stop rather than re-entering stale states or
		// overwriting the nested transition.
		if (lineage_branch->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
				!_has_active_child_state(lineage_branch, lineage_child)) {
			return;
		}

		// Register the branch's own child before entering it, so its
		// _transition_in() doesn't evaluate and choose a different child than
		// the one being transitioned to.
		if (i > 1 && lineage_child->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
			NNSTBranchNodes *next_branch = godot::Object::cast_to<NNSTBranchNodes>(lineage_child);
			NNSTTickedNodes *next_child = godot::Object::cast_to<NNSTTickedNodes>(lineage[i - 2]);
			if (next_branch != nullptr && !_has_active_child_state(next_branch, next_child)) {
				next_branch->_add_active_child_state(next_child);
			}
		}

		if (lineage_child->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
			if (tree_root != nullptr) {
				lineage_child->set_root(tree_root);
			}
			lineage_child->_transition_in();
		}
	}
}

void NNSTTickedNodes::_transition_in() {
	// Logic defined in child classes
};

void NNSTTickedNodes::_transition_out() {
	if (_internal_status == 0) {
		return;
	}

	for (int i = _num_active_states - 1; i >= 0; i--) {
		NNSTTickedNodes *cur_active_state = _active_states[i];
		cur_active_state->_transition_out();
	}

	on_exit_state();
	set_internal_status(ST_INTERNAL_STATUS_INACTIVE);
	_active_states.clear();
	_num_active_states = 0;
};

bool NNSTTickedNodes::on_enter_condition() {
	if (has_method("on_enter_condition")) {
		return call("on_enter_condition");
	}
	emit_signal("state_check_enter_condition");
	return _is_on_entered_condition_true;
}

void NNSTTickedNodes::on_enter_state() {
	call("on_enter_state");
	emit_signal("state_entered");
}

void NNSTTickedNodes::on_exit_state() {
	call("on_exit_state");
	emit_signal("state_exited");
}

void NNSTTickedNodes::on_tick(float delta) {
	call("on_tick", delta);
	emit_signal("state_ticked", delta);

	for (unsigned int i = 0; i < _num_active_states; i++) {
		NNSTTickedNodes *stnode = _active_states[i];

		stnode->on_tick(delta);
	}

#ifdef DEBUG_ENABLED
	_last_visited_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
}

// Godot virtuals.

void NNSTTickedNodes::_notification(int p_what) {
	NNSTBranchNodes::_notification(p_what);

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		for (unsigned int i = 0; i < _num_child_states; i++) {
			NNSTTickedNodes *stnode = _child_states[i];
			stnode->set_root(get_root());
		}

		// This will do nothing if we already have an active child. We want to
		// call it on child order changed incase the root has no active children
		// when another child gets added.
		if (_internal_status == ST_INTERNAL_STATUS_ACTIVE) {
			_transition_in();
		}
	}
}
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

// Opens a root scope for the lifetime of the guard and closes it on every exit
// path, so a deferred change request from a callback is always drained against
// the settled hierarchy exactly once.
namespace {
class ChangeScopeGuard {
public:
	explicit ChangeScopeGuard(NNSTRoot *p_root) :
			_root(p_root) {
		if (_root != nullptr) {
			_root->_begin_scope();
		}
	}
	~ChangeScopeGuard() {
		if (_root != nullptr) {
			_root->_end_scope();
		}
	}

private:
	NNSTRoot *_root;
};
} // namespace

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
	ClassDB::bind_method(D_METHOD("get_activation_generation"), &NNSTTickedNodes::get_activation_generation);
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
	_is_exiting = false;
	_root = nullptr;
	_activation_generation = 0;
}

NNSTTickedNodes::~NNSTTickedNodes() {
}

// Getters and Setters.

void NNSTTickedNodes::set_root(NNSTRoot *p_root) {
	_root = p_root;

	if (!Engine::get_singleton()->is_editor_hint()) {
		const std::vector<ObjectID> child_state_ids = _child_states;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode != nullptr) {
				stnode->set_root(p_root);
			}
		}
	}
}

NNSTRoot *NNSTTickedNodes::get_root() const {
	return _root;
}

NNSTRoot *NNSTTickedNodes::_get_tree_root() const {
	if (_root != nullptr) {
		return _root;
	}
	// The root node itself has no root pointer; walk ancestors so its children
	// can still open change scopes during entry.
	for (Node *ancestor = get_parent(); ancestor != nullptr; ancestor = ancestor->get_parent()) {
		if (NNSTRoot *chart_root = godot::Object::cast_to<NNSTRoot>(ancestor)) {
			return chart_root;
		}
	}
	return nullptr;
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

uint64_t NNSTTickedNodes::get_activation_generation() const {
	return _activation_generation;
}

// Handling methods.

void NNSTTickedNodes::send_event(String name) {
	_process_transitions(NNSTRoot::TriggerType::EVENT, name);
}

bool NNSTTickedNodes::is_parallel() const {
	return false;
}

bool NNSTTickedNodes::_process_transitions(int trigger_type, const String &event_name) {
	if (!get_is_active()) {
		return false;
	}

	// Try every transition in child order. A matching transition can still
	// decline (failed guard, stale target), in which case the remaining
	// transitions, and then the active children, get a chance to handle the
	// trigger. This keeps the existing parent-to-leaf priority ordering.
	for (unsigned int i = 0; i < _num_child_transitions; i++) {
		NNSTTransition *transition = _child_transitions[i];
		if (transition == nullptr || transition->get_to().is_empty() ||
				!transition->is_triggered_by(trigger_type)) {
			continue;
		}
		if (trigger_type == NNSTRoot::TriggerType::EVENT && transition->get_event_name() != event_name) {
			continue;
		}
		if (!transition->_can_transition()) {
			continue;
		}
		if (transition_to(transition->get_to().slice(1))) {
			return true;
		}
	}

	// STATE_ENTER is dispatched only to the state whose activation generated
	// the queued request. We must not broadcast it to active descendants here:
	// entering a compound state also enters its children, and every child
	// queues its own entry request. A recursive broadcast would therefore
	// evaluate a child's STATE_ENTER transitions twice for a single real entry
	// (once from this ancestor and once from its own queued request), which can
	// burn through guarded transitions that count evaluations. Parallel
	// children still get STATE_ENTER coverage because each activation queues
	// its own request. Other triggers keep the recursive fan-out below.
	if (trigger_type == NNSTRoot::TriggerType::STATE_ENTER) {
		return false;
	}

	// Not handled here: give the active children the same chance. A parallel
	// node is a fan-out point: every still-active region must be visited even
	// after another region handled the trigger, so sibling regions can react
	// to the same event. Compound/normal states stop at the first match.
	bool any_child_handled = false;
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *state = _get_active_state(active_state_ids[i]);
		if (state == nullptr || !state->_process_transitions(trigger_type, event_name)) {
			continue;
		}
		if (!is_parallel()) {
			return true;
		}
		any_child_handled = true;
	}
	return any_child_handled;
}

bool NNSTTickedNodes::_finish_transition(NNSTRoot *p_root) {
	// A finished transition is a state change. Mark it on the root so automatic
	// transitions relying on StateIsActiveGuard can be re-evaluated.
	if (p_root != nullptr) {
		p_root->mark_state_change_pending();
	}
	return true;
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

bool NNSTTickedNodes::transition_to(NodePath path_to_node) {
	// Hold a change scope across the whole transition. Every success/failure
	// return path leaves this wrapper, so callbacks that set expression
	// properties, send events or mark state changes only queue work until the
	// transition has finished and the hierarchy is settled.
	NNSTRoot *scope_root = _get_tree_root();
	if (scope_root == nullptr) {
		return _transition_to_impl(path_to_node);
	}
	ChangeScopeGuard scope(scope_root);
	return _transition_to_impl(path_to_node);
}

bool NNSTTickedNodes::_transition_to_impl(NodePath path_to_node) {
	// NNSTBranchNodes *parent = godot::Object::cast_to<NNSTBranchNodes>(get_parent());
	// if (!parent) {
	// 	return false;
	// }
	NNSTTickedNodes *to_state = get_node<NNSTTickedNodes>(path_to_node);
	if (to_state == nullptr) {
		return false;
	}

	// Remember the owning chart so a successful transition can flag a state
	// change even if the exit callbacks free or reparent this state.
	NNSTRoot *chart_root = _get_tree_root();

	// Re-entering any part of an exiting lineage would be undone by the
	// outer exit, potentially leaving active descendants of an inactive state.
	for (Node *ancestor = to_state; ancestor != nullptr; ancestor = ancestor->get_parent()) {
		NNSTTickedNodes *state = godot::Object::cast_to<NNSTTickedNodes>(ancestor);
		if (state != nullptr && state->_is_exiting) {
			return false;
		}
	}

	NNSTBranchNodes *common_ancestor = _get_common_ancestor(this, to_state);
	if (common_ancestor == nullptr) {
		return false;
	}

	if (!_can_transition_to(this, to_state)) {
		return false;
	}

	// If the common ancestor is a parallel node, the to_node's lineage is already
	// partially active and we'll need to figure out where the youngest non-active
	// part is so let's not worry about that for now.
	if (common_ancestor->is_class("NNSTParallel")) {
		return false;
	}

	// The branch hasn't been entered yet (for example a transition requested
	// before the root's first tick). There is no active child to transition out
	// of, and entering the new one here would leave the branch's ancestors out
	// of sync, so wait for the tree to enter this branch normally.
	const std::vector<NNSTTickedNodes *> active_child_states = common_ancestor->_get_active_child_states();
	if (active_child_states.empty()) {
		return false;
	}

	// Get the to_states lineage before changing anything, so a broken lineage
	// can't leave the tree with the old branch transitioned out. The lineage is
	// ordered from the to_state up to the common ancestor. Only instance IDs
	// are kept because the exit callback below can free or reparent any of
	// these nodes.
	std::vector<ObjectID> lineage;
	NNSTBranchNodes *parent = to_state;
	lineage.push_back(ObjectID(parent->get_instance_id()));
	while (parent != nullptr && parent != common_ancestor) {
		parent = godot::Object::cast_to<NNSTBranchNodes>(parent->get_parent());
		if (parent == nullptr) {
			break;
		}
		lineage.push_back(ObjectID(parent->get_instance_id()));
	}

	if (lineage.size() < 2 || lineage[lineage.size() - 1] != ObjectID(common_ancestor->get_instance_id())) {
		return false;
	}

	const ObjectID common_ancestor_id = ObjectID(common_ancestor->get_instance_id());

	// Transition out the from_states lineage. The child stays registered as the
	// common ancestor's active child until its exit completes. An on_exit_state()
	// callback is allowed to request a transition to a sibling; that nested
	// transition must still see the state that is exiting as the active child,
	// otherwise it would be discarded as a transition from a branch that was
	// never entered. _transition_out() is reentrancy-safe, so the nested
	// transition's own attempt to transition this state out is a no-op.
	NNSTTickedNodes *child = active_child_states[0];
	child->_transition_out();
	common_ancestor->_remove_active_child_state(child);

	// An on_exit_state() callback may have transitioned the branch while its
	// old states were exiting. Don't overwrite that transition with this one.
	// The event was still handled, so report success and leave the tree as the
	// nested transition left it. Resolve the branch again because the callback
	// may also have freed it.
	common_ancestor = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(common_ancestor_id));
	if (common_ancestor == nullptr) {
		return _finish_transition(chart_root);
	}
	if (common_ancestor->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
			!common_ancestor->_get_active_child_states().empty()) {
		return _finish_transition(chart_root);
	}

	// Exit callbacks can reparent the target or one of its ancestors. IDs
	// remain valid in that case, but the captured lineage no longer does.
	for (unsigned int i = 1; i < lineage.size(); i++) {
		NNSTBranchNodes *branch = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(lineage[i]));
		NNSTTickedNodes *state = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[i - 1]));
		if (branch == nullptr || state == nullptr || state->get_parent() != branch) {
			return _finish_transition(chart_root);
		}
	}

	// Transition in the to_states lineage from the common ancestor down. Each
	// branch is given its new active child before that child is entered, so a
	// state's on_enter_state() always sees a consistent tree: its ancestors are
	// active and its own active child is already registered. Entering the
	// lineage bottom-up (as this used to) entered a state before its ancestors
	// were registered, so any transition_to() it requested was seen as coming
	// from a branch that had never been entered and was discarded.
	NNSTTickedNodes *lineage_first_child = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[lineage.size() - 2]));
	if (lineage_first_child == nullptr) {
		return _finish_transition(chart_root);
	}
	common_ancestor->_add_active_child_state(lineage_first_child);

	// The root node itself has no root pointer. Resolve it from the common
	// ancestor so the entered states still receive the tree root.
	NNSTRoot *tree_root = get_root();
	if (tree_root == nullptr) {
		tree_root = godot::Object::cast_to<NNSTRoot>(common_ancestor);
	}

	for (int i = (int)lineage.size() - 1; i >= 1; i--) {
		NNSTBranchNodes *lineage_branch = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(lineage[i]));
		NNSTTickedNodes *lineage_child = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[i - 1]));
		if (lineage_branch == nullptr || lineage_child == nullptr) {
			return _finish_transition(chart_root);
		}

		// A transition requested from an on_enter_state() callback (in this
		// loop or in the transition out above) may have moved the tree away
		// from this lineage. Stop rather than re-entering stale states or
		// overwriting the nested transition. The nested transition handled the
		// event, so report success.
		if (lineage_branch->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
				!_has_active_child_state(lineage_branch, lineage_child)) {
			return _finish_transition(chart_root);
		}

		// Register the branch's own child before entering it, so its
		// _transition_in() doesn't evaluate and choose a different child than
		// the one being transitioned to.
		if (i > 1 && lineage_child->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE) {
			NNSTBranchNodes *next_branch = godot::Object::cast_to<NNSTBranchNodes>(lineage_child);
			NNSTTickedNodes *next_child = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[i - 2]));
			if (next_branch != nullptr && next_child != nullptr && !_has_active_child_state(next_branch, next_child)) {
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

	return _finish_transition(chart_root);
}

void NNSTTickedNodes::_transition_in() {
	// Logic defined in child classes
};

void NNSTTickedNodes::_transition_out() {
	if (_internal_status == ST_INTERNAL_STATUS_INACTIVE || _is_exiting) {
		return;
	}

	// on_exit_state() runs user code that may request a transition. When that
	// transition transitions this state out (typically to redirect to a
	// sibling), it calls back into _transition_out() while the outer exit is
	// still in progress. The flag makes the nested call a no-op so each state
	// exits exactly once and on_exit_state() cannot recurse into itself.
	_is_exiting = true;
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (int i = (int)active_state_ids.size() - 1; i >= 0; i--) {
		// A callback from an earlier child may have already removed this state
		// or transitioned the branch. Re-check before resolving/dereferencing.
		if (!_has_active_state(active_state_ids[i])) {
			continue;
		}
		NNSTTickedNodes *cur_active_state = _resolve_state(active_state_ids[i]);
		if (cur_active_state == nullptr) {
			continue;
		}
		cur_active_state->_transition_out();
	}

	on_exit_state();
	set_internal_status(ST_INTERNAL_STATUS_INACTIVE);
	_active_states.clear();
	_num_active_states = 0;
	_is_exiting = false;
};

bool NNSTTickedNodes::on_enter_condition() {
	if (has_method("on_enter_condition")) {
		return call("on_enter_condition");
	}
	emit_signal("state_check_enter_condition");
	return _is_on_entered_condition_true;
}

void NNSTTickedNodes::on_enter_state() {
	// Stamp this activation before any user callback runs. A callback can
	// transition away and re-enter this state; the new activation gets a new
	// generation, which makes the entry request we queue below stale if it is
	// still pending when the new activation's request is drained.
	const uint64_t generation = ++_activation_generation;

	// Hold an entry scope across the user callback and the automatic-transition
	// request. A guard or on_enter_state() that queues changes must not run the
	// pipeline while the state's entry is still in progress.
	NNSTRoot *root = _get_tree_root();
	if (root == nullptr || Engine::get_singleton()->is_editor_hint()) {
		call("on_enter_state");
		emit_signal("state_entered");
		return;
	}

	ChangeScopeGuard scope(root);
	call("on_enter_state");
	emit_signal("state_entered");

	// Automatic transitions are evaluated when the state is entered. Route
	// through the root so the change pipeline's reentrancy lock is honoured,
	// carrying the identity of this activation.
	root->process_state_enter(this, generation);
}

void NNSTTickedNodes::on_exit_state() {
	call("on_exit_state");
	emit_signal("state_exited");
}

void NNSTTickedNodes::on_tick(float delta) {
	// A deleted active child (for example during teardown or an explicit free)
	// cannot be replaced from inside the child order notification. Do the
	// normal selection now that the tree is in a safe state.
	if (_needs_reselection && _internal_status == ST_INTERNAL_STATUS_ACTIVE && _active_states.empty()) {
		_needs_reselection = false;
		_transition_in();
	}

	call("on_tick", delta);
	emit_signal("state_ticked", delta);

	// The callback above (and every child tick below) may free, remove or
	// reparent active states. Snapshot IDs and re-resolve before each child.
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_active_state(active_state_ids[i]);
		if (stnode == nullptr) {
			continue;
		}

		stnode->on_tick(delta);
	}

#ifdef DEBUG_ENABLED
	_last_visited_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif
}

// Godot virtuals.

void NNSTTickedNodes::_notification(int p_what) {
	if (p_what == NOTIFICATION_PREDELETE) {
		// A child being deleted cannot run on_exit_state() safely. Drop it from
		// its parent's active list before the pointer becomes invalid so a root
		// tick later in the frame can never dereference a destroyed node.
		if (NNSTBranchNodes *parent_branch = godot::Object::cast_to<NNSTBranchNodes>(get_parent())) {
			parent_branch->_on_child_predelete(this);
		}
		return;
	}

	NNSTBranchNodes::_notification(p_what);

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		const std::vector<ObjectID> child_state_ids = _child_states;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode != nullptr) {
				stnode->set_root(get_root());
			}
		}

		// This will do nothing if we already have an active child. We want to
		// call it on child order changed incase the root has no active children
		// when another child gets added. If the change was caused by a child
		// being deleted, wait for the next tick so teardown doesn't enter new
		// states. A node that has already left the tree (for example while its
		// parent is being freed) must not enter states either.
		if (_internal_status == ST_INTERNAL_STATUS_ACTIVE && is_inside_tree() && !_last_notification_had_child_removal && !_needs_reselection) {
			_transition_in();
		}
	}
}
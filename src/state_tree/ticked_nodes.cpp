#include "ticked_nodes.h"
#include "../expression_util.h"
#include "../score_aggregation.h"
#include "history.h"
#include "parallel.h"
#include "transition.h"
#include <state_tree/root.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/object.hpp>

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

/**
 * Drops the Phase A registrations of a history restore that was aborted by an
 * exiting or entering callback, so the abandoned remembered subtree cannot be
 * inherited by a later entry. The history is resolved by ID because callbacks
 * may have freed or moved it.
 */
static void _discard_history_registrations(const ObjectID &history_id, const NNSTHistoryStateSnapshot &history_entry) {
	if (history_id.is_null()) {
		return;
	}

	NNSTHistory *history = godot::Object::cast_to<NNSTHistory>(ObjectDB::get_instance(history_id));
	if (history != nullptr) {
		history->_discard_registrations(history_entry);
	}
}

// Method binds.

void NNSTTickedNodes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_root"), &NNSTTickedNodes::get_root);

	ClassDB::bind_method(D_METHOD("set_is_final", "is_final"), &NNSTTickedNodes::set_is_final);
	ClassDB::bind_method(D_METHOD("get_is_final"), &NNSTTickedNodes::get_is_final);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_final", PROPERTY_HINT_NONE), "set_is_final", "get_is_final");

	ClassDB::bind_method(D_METHOD("set_hosted_success_event", "event_name"), &NNSTTickedNodes::set_hosted_success_event);
	ClassDB::bind_method(D_METHOD("get_hosted_success_event"), &NNSTTickedNodes::get_hosted_success_event);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "hosted_success_event", PROPERTY_HINT_NONE), "set_hosted_success_event", "get_hosted_success_event");

	ClassDB::bind_method(D_METHOD("set_hosted_failure_event", "event_name"), &NNSTTickedNodes::set_hosted_failure_event);
	ClassDB::bind_method(D_METHOD("get_hosted_failure_event"), &NNSTTickedNodes::get_hosted_failure_event);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "hosted_failure_event", PROPERTY_HINT_NONE), "set_hosted_failure_event", "get_hosted_failure_event");

	ClassDB::bind_method(D_METHOD("get_score"), &NNSTTickedNodes::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY), "", "get_score");

	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNSTTickedNodes::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNSTTickedNodes::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum,Min,Max,Mean,Multiply,First Non Zero", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NoodleNodes.EvaluationMethod"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("set_on_entered_condition", "is_entered"), &NNSTTickedNodes::set_is_on_entered_condition_true);
	ClassDB::bind_method(D_METHOD("get_on_entered_condition"), &NNSTTickedNodes::get_is_on_entered_condition_true);
	ClassDB::bind_method(D_METHOD("get_activation_generation"), &NNSTTickedNodes::get_activation_generation);

	ClassDB::bind_method(D_METHOD("transition_to", "new_state_nodepath"), &NNSTTickedNodes::transition_to);

	GDVIRTUAL_BIND(on_enter_condition);
	GDVIRTUAL_BIND(on_enter_state);
	GDVIRTUAL_BIND(on_exit_state);
	GDVIRTUAL_BIND(on_tick, "delta");

	ADD_SIGNAL(MethodInfo("state_check_enter_condition"));
	ADD_SIGNAL(MethodInfo("state_entered"));
	ADD_SIGNAL(MethodInfo("state_ticked", PropertyInfo(Variant::FLOAT, "delta")));
	ADD_SIGNAL(MethodInfo("state_exited"));
	ADD_SIGNAL(MethodInfo("event_received", PropertyInfo(Variant::STRING, "name")));
	ADD_SIGNAL(MethodInfo("transition_pending",
			PropertyInfo(Variant::FLOAT, "initial_delay"),
			PropertyInfo(Variant::FLOAT, "remaining_delay")));
	ADD_SIGNAL(MethodInfo("hosted_root_finished",
			PropertyInfo(Variant::OBJECT, "root", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT, "Node"),
			PropertyInfo(Variant::BOOL, "succeeded")));
}

// Constructor and destructor.

NNSTTickedNodes::NNSTTickedNodes() {
	_root_host.configure(this);
	_is_final = false;
	_hosted_success_event = "hosted_succeeded";
	_hosted_failure_event = "hosted_failed";
	_is_on_entered_condition_true = true;
	_evaluation_method = EVALUATION_MULTIPLY;
	_score = 0.0;
	_invert_score = false;
	_is_exiting = false;
	_root = nullptr;
	_activation_generation = 0;
	_pending_transition_id = ObjectID();
	_pending_initial_delay = 0.0;
	_pending_remaining_delay = 0.0;
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

void NNSTTickedNodes::set_is_final(bool is_final) {
	_is_final = is_final;
}

bool NNSTTickedNodes::get_is_final() const {
	return _is_final;
}

void NNSTTickedNodes::set_hosted_success_event(const String &p_event_name) {
	_hosted_success_event = p_event_name;
}

String NNSTTickedNodes::get_hosted_success_event() const {
	return _hosted_success_event;
}

void NNSTTickedNodes::set_hosted_failure_event(const String &p_event_name) {
	_hosted_failure_event = p_event_name;
}

String NNSTTickedNodes::get_hosted_failure_event() const {
	return _hosted_failure_event;
}

void NNSTTickedNodes::_on_internal_status_changed(bool p_is_active) {
	if (p_is_active) {
		_root_host.activate();
	} else {
		_root_host.deactivate();
	}
}

void NNSTTickedNodes::_on_hosted_root_finished(bool p_succeeded, Node *p_root) {
	// The handler is user code: it can transition, reparent or free this state,
	// so the event only goes out for the activation the report started in.
	const ActivationIdentity activation = _capture_activation_identity();
	const String event_name = p_succeeded ? _hosted_success_event : _hosted_failure_event;
	const ObjectID id = ObjectID(get_instance_id());

	emit_signal("hosted_root_finished", Variant(p_root), p_succeeded);

	if (ObjectDB::get_instance(id) == nullptr || event_name.is_empty() || !_is_dispatch_activation_valid(activation)) {
		return;
	}

	send_event(event_name);
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

float NNSTTickedNodes::get_score() const {
	return _score;
}

void NNSTTickedNodes::set_evaluation_method(EvaluationMethod evaluation_method) {
	_evaluation_method = evaluation_method;
}

NoodleNodes::EvaluationMethod NNSTTickedNodes::get_evaluation_method() const {
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

NNSTRoot *NNSTTickedNodes::_resolve_tree_root() const {
	// A reparented state can still hold the root of its previous chart until
	// the new parent's child order notification updates it. Only trust the
	// cached root while it is actually an ancestor.
	if (_root != nullptr && _root->is_ancestor_of(const_cast<NNSTTickedNodes *>(this))) {
		return _root;
	}

	Node *node = get_parent();
	while (node != nullptr) {
		NNSTRoot *root = godot::Object::cast_to<NNSTRoot>(node);
		if (root != nullptr) {
			return root;
		}
		node = node->get_parent();
	}
	return nullptr;
}

NNSTTickedNodes::ActivationIdentity NNSTTickedNodes::_capture_activation_identity() const {
	ActivationIdentity identity;
	identity.epoch = get_activation_epoch();

	const Node *parent = get_parent();
	identity.parent_id = parent != nullptr ? ObjectID(parent->get_instance_id()) : ObjectID();

	const NNSTRoot *tree_root = _resolve_tree_root();
	identity.root_id = tree_root != nullptr ? ObjectID(tree_root->get_instance_id()) : ObjectID();

	return identity;
}

bool NNSTTickedNodes::_is_dispatch_activation_valid(uint64_t p_epoch, ObjectID p_parent_id, ObjectID p_root_id) const {
	if (get_activation_epoch() != p_epoch) {
		return false;
	}

	if (_internal_status != ST_INTERNAL_STATUS_ACTIVE) {
		return false;
	}

	// A state reparented out of the chart can stay ACTIVE until the tree
	// notices, so membership is part of the activation's identity.
	if (!is_inside_tree()) {
		return false;
	}

	const Node *parent = get_parent();
	if (parent == nullptr || ObjectID(parent->get_instance_id()) != p_parent_id) {
		return false;
	}

	const NNSTRoot *tree_root = _resolve_tree_root();
	const ObjectID root_id = tree_root != nullptr ? ObjectID(tree_root->get_instance_id()) : ObjectID();
	return root_id == p_root_id;
}

void NNSTTickedNodes::send_event(String name) {
	// Events belong to the chart. Route them through the root so they are
	// queued and processed in order, even when a callback sends one while
	// another event is still being processed.
	NNSTRoot *tree_root = _resolve_tree_root();
	if (tree_root != nullptr) {
		tree_root->send_event(name);
		return;
	}

	// Detached subtree: there is no chart to queue the event, so dispatch it
	// directly to this state.
	_dispatch_event(name);
}

bool NNSTTickedNodes::_dispatch_event(const String &name) {
	NNSTRoot *tree_root = _resolve_tree_root();
	if (tree_root != nullptr && tree_root->get_is_event_processing_halted()) {
		return true;
	}

	// The signal callback is user code: it may transition this state out (and
	// possibly back in) or reparent it. Capture the activation it started from
	// so a stale activation cannot keep dispatching.
	const ActivationIdentity activation = _capture_activation_identity();

	// The state receives the event before it or its children consume it.
	emit_signal("event_received", name);

	// The callback already consumed/redirected this event. Do not evaluate
	// this state's transitions, and report it consumed so ancestors stop too.
	if (!_is_dispatch_activation_valid(activation)) {
		return true;
	}

	// Innermost active states get the first chance to handle the event.
	if (_dispatch_event_to_children(name)) {
		return true;
	}

	// A child callback may have exited this state (or replaced its activation).
	if (!_is_dispatch_activation_valid(activation)) {
		return true;
	}

	// Only handle the event here if no active child consumed it.
	return _handle_event(name);
}

bool NNSTTickedNodes::_dispatch_event_to_children(const String &name) {
	// Snapshot the IDs because an event handler may free, remove or reparent
	// active siblings while the event is being delivered.
	const std::vector<ObjectID> active_state_ids = _active_states;

	// A child callback can exit, re-enter or reparent this state. Capture the
	// activation so the loop cannot deliver the event on behalf of a parent
	// that is no longer the same live activation.
	const ActivationIdentity activation = _capture_activation_identity();

	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *state = _get_active_state(active_state_ids[i]);
		if (state == nullptr) {
			continue;
		}

		if (state->_dispatch_event(name)) {
			return true;
		}

		// Do not deliver the event to stale sibling states or handle it here
		// once the child's callbacks have transitioned this activation away.
		if (!_is_dispatch_activation_valid(activation)) {
			return true;
		}

		NNSTRoot *tree_root = _resolve_tree_root();
		if (tree_root != nullptr && tree_root->get_is_event_processing_halted()) {
			return true;
		}
	}

	return false;
}

bool NNSTTickedNodes::_handle_event(const String &name) {
	const std::vector<ObjectID> transition_ids = _get_matching_transition_ids(name);

	// Every guard and transition below is user code that can exit, re-enter or
	// reparent this state. Capture the activation first and stop as soon as it
	// is no longer the same live activation.
	const ActivationIdentity activation = _capture_activation_identity();

	for (unsigned int i = 0; i < transition_ids.size(); i++) {
		ObjectID transition_id = transition_ids[i];
		NNSTTransition *transition = godot::Object::cast_to<NNSTTransition>(ObjectDB::get_instance(transition_id));
		if (transition == nullptr || transition->get_parent() != this) {
			continue;
		}

		// A declining transition (failed guard) does not consume the event, so
		// the remaining transitions still get a chance. The guard itself is
		// user code, though, and may have transitioned this state away: a
		// stale activation stops the event here.
		if (!transition->_can_transition()) {
			if (!_is_dispatch_activation_valid(activation)) {
				return true;
			}
			continue;
		}

		// The guard may have transitioned this state even when it returned
		// true. Never apply the transition on behalf of a stale activation.
		if (!_is_dispatch_activation_valid(activation)) {
			return true;
		}

		// The guard runs user code which may free or reparent this transition.
		// Re-resolve it before reading its target.
		transition = godot::Object::cast_to<NNSTTransition>(ObjectDB::get_instance(transition_id));
		if (transition == nullptr || transition->get_parent() != this) {
			continue;
		}

		// Transitions and guards may have reparented this state; check again
		// immediately before applying the transition.
		if (!_is_dispatch_activation_valid(activation)) {
			return true;
		}

		if (_request_transition(transition, false)) {
			return true;
		}

		// A rejected transition may still have run callbacks that replaced
		// this activation. If so, stop; otherwise the remaining transitions
		// keep their chance.
		if (!_is_dispatch_activation_valid(activation)) {
			return true;
		}
	}

	return false;
}

bool NNSTTickedNodes::is_parallel() const {
	return false;
}

bool NNSTTickedNodes::_process_transitions(int trigger_type, const String &event_name) {
	if (!get_is_active()) {
		return false;
	}

	// Guards are user code and can exit, re-enter or reparent this state while
	// its automatic transitions are evaluated. Capture the activation so a
	// transition is never applied on behalf of a stale one.
	const ActivationIdentity activation = _capture_activation_identity();

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
			if (!_is_dispatch_activation_valid(activation)) {
				return true;
			}
			continue;
		}
		if (!_is_dispatch_activation_valid(activation)) {
			return true;
		}

		// Reuse the root's transition request machinery so automatic
		// transitions share delay handling, activation-identity checks, the
		// transition budget and the `taken` signal with event transitions.
		if (_request_transition(transition, false)) {
			return true;
		}
		if (!_is_dispatch_activation_valid(activation)) {
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

void NNSTTickedNodes::_clear_pending_transition() {
	_pending_transition_id = ObjectID();
	_pending_initial_delay = 0.0;
	_pending_remaining_delay = 0.0;
}

NNSTTransition *NNSTTickedNodes::_resolve_pending_transition() const {
	if (_pending_transition_id.is_null()) {
		return nullptr;
	}

	NNSTTransition *transition = Object::cast_to<NNSTTransition>(ObjectDB::get_instance(_pending_transition_id));
	if (transition == nullptr || transition->get_parent() != this) {
		return nullptr;
	}
	return transition;
}

bool NNSTTickedNodes::_request_transition(NNSTTransition *transition, bool immediately) {
	if (transition == nullptr || transition->get_parent() != this) {
		return false;
	}
	if (!get_is_active()) {
		return false;
	}

	if (!immediately) {
		// Re-requesting the transition that is already pending must not reset
		// its timer. A different transition supersedes the pending one.
		if (_resolve_pending_transition() == transition) {
			return true;
		}

		const float delay = transition->evaluate_delay();
		if (delay > 0.0f) {
			_pending_transition_id = ObjectID(transition->get_instance_id());
			_pending_initial_delay = delay;
			_pending_remaining_delay = delay;
			return true;
		}
	}

	// `immediately` forces a pending transition to run now, so the pending
	// state is cleared before the transition itself is executed.
	_clear_pending_transition();
	return _execute_transition(transition);
}

bool NNSTTickedNodes::_execute_transition(NNSTTransition *transition) {
	if (transition == nullptr || transition->get_parent() != this) {
		return false;
	}
	if (!get_is_active()) {
		return false;
	}

	ObjectID history_id;
	NNSTHistoryStateSnapshot history_entry;
	NNSTTickedNodes *target_state = _resolve_transition_target(transition, history_id, history_entry);
	if (target_state == nullptr) {
		ERR_PRINT(vformat("Transition '%s' has an invalid target '%s'.", NNExpressionUtil::path_of(transition), transition->get_to()));
		return false;
	}

	// The target existing does not mean the transition can be applied;
	// _transition_to_state runs the full preflight and only emits `taken` for
	// an accepted transition.
	return _transition_to_state(target_state, transition, history_id, history_entry);
}

NNSTTickedNodes *NNSTTickedNodes::_resolve_target_node(Node *target_node, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry) {
	r_history_id = ObjectID();
	r_history_entry = NNSTHistoryStateSnapshot();

	NNSTTickedNodes *to_state = Object::cast_to<NNSTTickedNodes>(target_node);
	if (to_state != nullptr) {
		return to_state;
	}

	// A history is a pseudo-state, so it never becomes the target itself. The
	// first state of its restore snapshot is the entry state; the history
	// identity and snapshot entry are carried into the plan so the two restore
	// phases can run inside _perform_transition. A history without a usable
	// snapshot or default state resolves to null, which leaves the tree
	// untouched and keeps the normal invalid-target reporting for real
	// non-state targets.
	NNSTHistory *history = Object::cast_to<NNSTHistory>(target_node);
	if (history == nullptr) {
		return nullptr;
	}

	const std::vector<NNSTHistoryStateSnapshot> snapshot = history->_get_restore_snapshot();
	if (snapshot.empty()) {
		return nullptr;
	}

	r_history_id = ObjectID(history->get_instance_id());
	r_history_entry = snapshot[0];
	return Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(r_history_entry.state_id));
}

NNSTTickedNodes *NNSTTickedNodes::_resolve_transition_target(NNSTTransition *transition, ObjectID &r_history_id, NNSTHistoryStateSnapshot &r_history_entry) {
	if (transition == nullptr) {
		r_history_id = ObjectID();
		r_history_entry = NNSTHistoryStateSnapshot();
		return nullptr;
	}

	return _resolve_target_node(transition->get_node_or_null(transition->get_to()), r_history_id, r_history_entry);
}

void NNSTTickedNodes::_process_pending_transition(float delta) {
	if (_pending_transition_id.is_null()) {
		return;
	}

	// A pending transition never survives the state it belongs to.
	if (!get_is_active()) {
		_clear_pending_transition();
		return;
	}

	NNSTTransition *transition = _resolve_pending_transition();
	if (transition == nullptr) {
		_clear_pending_transition();
		return;
	}

	_pending_remaining_delay -= delta;
	const float remaining_delay = _pending_remaining_delay > 0.0f ? _pending_remaining_delay : 0.0f;
	const ObjectID pending_id = _pending_transition_id;
	emit_signal("transition_pending", _pending_initial_delay, remaining_delay);

	if (_pending_remaining_delay > 0.0f) {
		return;
	}

	// The signal handler may have superseded/cancelled the pending transition
	// or transitioned this state out. Only run the transition that is still
	// pending after the signal returned.
	if (_pending_transition_id != pending_id) {
		return;
	}
	transition = Object::cast_to<NNSTTransition>(ObjectDB::get_instance(pending_id));
	if (transition == nullptr || transition->get_parent() != this) {
		_clear_pending_transition();
		return;
	}
	if (!get_is_active()) {
		_clear_pending_transition();
		return;
	}

	// Clear before executing so a reentrant request for the same transition
	// cannot see itself as still pending.
	_clear_pending_transition();
	_execute_transition(transition);
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
	if (_invert_score) {
		_score = 1.0f - _score;
	}

	return _score;
}

bool NNSTTickedNodes::transition_to(NodePath path_to_node) {
	ObjectID history_id;
	NNSTHistoryStateSnapshot history_entry;
	NNSTTickedNodes *to_state = _resolve_target_node(get_node_or_null(path_to_node), history_id, history_entry);
	if (to_state == nullptr) {
		return false;
	}

	// A script-driven transition has no NNSTTransition, so no `taken` signal.
	// Route through the shared execution path so event-driven, delayed and
	// automatic transitions all share the same preflight, transition budget,
	// transaction and `taken` semantics.
	return _transition_to_resolved_target(to_state, history_id, history_entry);
}

bool NNSTTickedNodes::_transition_to_resolved_target(NNSTTickedNodes *to_state, const ObjectID &history_id, const NNSTHistoryStateSnapshot &history_entry) {
	// Hold a change scope across the whole transition. Every success/failure
	// return path leaves this wrapper, so callbacks that set expression
	// properties, send events or mark state changes only queue work until the
	// transition has finished and the hierarchy is settled.
	NNSTRoot *scope_root = _get_tree_root();
	if (scope_root == nullptr) {
		return _transition_to_state(to_state, nullptr, history_id, history_entry);
	}
	ChangeScopeGuard scope(scope_root);
	return _transition_to_state(to_state, nullptr, history_id, history_entry);
}

bool NNSTTickedNodes::_preflight_transition(NNSTTickedNodes *to_state, TransitionPlan &r_plan) {
	if (to_state == nullptr) {
		return false;
	}

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

	// _can_transition_to() rejects self-transitions and targets that are
	// descendants of this state.
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

	r_plan.to_state = to_state;
	r_plan.common_ancestor = common_ancestor;
	r_plan.active_child = active_child_states[0];
	r_plan.lineage = lineage;
	return true;
}

bool NNSTTickedNodes::_transition_to_state(NNSTTickedNodes *to_state, NNSTTransition *transition_to_take, const ObjectID &history_id, const NNSTHistoryStateSnapshot &history_entry) {
	// Callbacks in this transition can send events. Keep them queued until this
	// transition and every nested transition it causes have finished, even when
	// it was started directly from GDScript or on_tick() instead of by an
	// event. The outermost scope drains the queue.
	NNSTRoot::TransitionTransaction transition_transaction(_resolve_tree_root());

	TransitionPlan plan;
	if (!_preflight_transition(to_state, plan)) {
		return false;
	}
	plan.history_id = history_id;
	plan.history_entry = history_entry;

	// Count applied transitions for the root's infinite-loop guard. This runs
	// after all validation, so rejected transitions are never counted and
	// `taken` is not emitted for a transition the root refuses to apply.
	NNSTRoot *tree_root = _resolve_tree_root();
	if (tree_root != nullptr && !tree_root->_register_applied_transition()) {
		return false;
	}

	if (transition_to_take != nullptr) {
		// `taken` fires exactly once per accepted transition, before any state
		// exit callback. Snapshot the identities read afterwards because a
		// handler may free or reparent anything.
		const ObjectID transition_id = ObjectID(transition_to_take->get_instance_id());
		const ObjectID target_id = ObjectID(to_state->get_instance_id());
		transition_to_take->emit_signal("taken");

		transition_to_take = Object::cast_to<NNSTTransition>(ObjectDB::get_instance(transition_id));
		if (transition_to_take == nullptr || transition_to_take->get_parent() != this) {
			return false;
		}
		if (!get_is_active()) {
			return false;
		}

		// A `taken` handler changing the tree is an expected reentrancy case,
		// not a configuration error, so the failed re-check stays silent.
		to_state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(target_id));
		plan = TransitionPlan();
		if (!_preflight_transition(to_state, plan)) {
			return false;
		}
		// The `taken` handler may have replaced the target, but the history
		// restore identity still belongs to this accepted transition. The
		// snapshot is re-resolved through its IDs in _perform_transition.
		plan.history_id = history_id;
		plan.history_entry = history_entry;
	}

	return _perform_transition(plan);
}

bool NNSTTickedNodes::_perform_transition(TransitionPlan &plan) {
	const std::vector<ObjectID> &lineage = plan.lineage;
	NNSTBranchNodes *common_ancestor = plan.common_ancestor;
	if (common_ancestor == nullptr) {
		return false;
	}

	const ObjectID common_ancestor_id = ObjectID(common_ancestor->get_instance_id());

	// The root node itself has no root pointer. Resolve it from the parent
	// chain before the exit callbacks, which may reparent the tree, so the
	// entered states still receive the correct tree root.
	NNSTRoot *tree_root = _resolve_tree_root();

	// Transition out the from_states lineage. The child stays registered as the
	// common ancestor's active child until its exit completes. An on_exit_state()
	// callback is allowed to request a transition to a sibling; that nested
	// transition must still see the state that is exiting as the active child,
	// otherwise it would be discarded as a transition from a branch that was
	// never entered. _transition_out() is reentrancy-safe, so the nested
	// transition's own attempt to transition this state out is a no-op.
	NNSTTickedNodes *child = plan.active_child;
	child->_transition_out();
	common_ancestor->_remove_active_child_state(child);

	// An on_exit_state() callback may have transitioned the branch while its
	// old states were exiting. Don't overwrite that transition with this one.
	// The event was still handled, so report success and leave the tree as the
	// nested transition left it. Resolve the branch again because the callback
	// may also have freed it.
	common_ancestor = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(common_ancestor_id));
	if (common_ancestor == nullptr) {
		return _finish_transition(tree_root);
	}
	if (common_ancestor->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
			!common_ancestor->_get_active_child_states().empty()) {
		return _finish_transition(tree_root);
	}

	// Exit callbacks can reparent the target or one of its ancestors. IDs
	// remain valid in that case, but the captured lineage no longer does.
	for (unsigned int i = 1; i < lineage.size(); i++) {
		NNSTBranchNodes *branch = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(lineage[i]));
		NNSTTickedNodes *state = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[i - 1]));
		if (branch == nullptr || state == nullptr || state->get_parent() != branch) {
			return _finish_transition(tree_root);
		}
	}

	// Phase A (history targets only): pre-register the remembered children on
	// compound branches, bottom-up and without running user callbacks. The
	// lineage below then enters the entry state, whose _transition_in() sees a
	// registered child and short-circuits instead of selecting its own initial
	// child. The history and every remembered state are resolved again because
	// the exit callbacks may have freed or moved them. Only the entry state's
	// subtree is pre-registered; the other top-level entries are not part of
	// this transition.
	if (plan.history_id.is_valid()) {
		NNSTHistory *restored_history = godot::Object::cast_to<NNSTHistory>(ObjectDB::get_instance(plan.history_id));
		if (restored_history != nullptr) {
			std::vector<NNSTHistoryStateSnapshot> entry_entries;
			entry_entries.push_back(plan.history_entry);
			restored_history->_pre_register(entry_entries);
		}
	}

	// Transition in the to_states lineage from the common ancestor down. Each
	// branch is given its new active child before that child is entered, so a
	// state's on_enter_state() always sees a consistent tree: its ancestors are
	// active and its own active child is already registered. Entering the
	// lineage bottom-up would enter a state before its ancestors were
	// registered, so any transition_to() it requested would be seen as coming
	// from a branch that had never been entered and would be discarded.
	NNSTTickedNodes *lineage_first_child = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[lineage.size() - 2]));
	if (lineage_first_child == nullptr) {
		_discard_history_registrations(plan.history_id, plan.history_entry);
		return _finish_transition(tree_root);
	}
	common_ancestor->_add_active_child_state(lineage_first_child);

	for (int i = (int)lineage.size() - 1; i >= 1; i--) {
		NNSTBranchNodes *lineage_branch = godot::Object::cast_to<NNSTBranchNodes>(ObjectDB::get_instance(lineage[i]));
		NNSTTickedNodes *lineage_child = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(lineage[i - 1]));
		if (lineage_branch == nullptr || lineage_child == nullptr) {
			_discard_history_registrations(plan.history_id, plan.history_entry);
			return _finish_transition(tree_root);
		}

		// A transition requested from an on_enter_state() callback (in this
		// loop or in the transition out above) may have moved the tree away
		// from this lineage. Stop rather than re-entering stale states or
		// overwriting the nested transition. The nested transition handled the
		// event, so report success.
		if (lineage_branch->get_internal_status() != ST_INTERNAL_STATUS_ACTIVE ||
				!_has_active_child_state(lineage_branch, lineage_child)) {
			_discard_history_registrations(plan.history_id, plan.history_entry);
			return _finish_transition(tree_root);
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

	// Phase B (history targets only): the lineage loop entered the entry state
	// itself, and its Phase A registration made it short-circuit. Enter the
	// remembered descendants now, including the inner state of every parallel
	// region the entry state selected. Everything is resolved again because the
	// callbacks may have freed or moved nodes.
	if (plan.history_id.is_valid()) {
		NNSTHistory *restored_history = godot::Object::cast_to<NNSTHistory>(ObjectDB::get_instance(plan.history_id));
		NNSTBranchNodes *restored_compound = restored_history != nullptr ? godot::Object::cast_to<NNSTBranchNodes>(restored_history->get_parent()) : nullptr;
		NNSTTickedNodes *entry_state = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(plan.history_entry.state_id));
		NNSTBranchNodes *entry_branch = godot::Object::cast_to<NNSTBranchNodes>(entry_state);
		if (restored_compound != nullptr && entry_branch != nullptr &&
				restored_compound->get_internal_status() == ST_INTERNAL_STATUS_ACTIVE &&
				restored_compound->_is_active_child_state(entry_state)) {
			restored_history->_enter(entry_branch, plan.history_entry.children, tree_root);
		} else {
			// The entry state was replaced or the compound exited while it was
			// being entered. Nothing will consume the pre-registered subtree.
			_discard_history_registrations(plan.history_id, plan.history_entry);
		}
	}

	return _finish_transition(tree_root);
}

void NNSTTickedNodes::_transition_in() {
	// Logic defined in child classes
};

void NNSTTickedNodes::_transition_out() {
	// Leaving a state always cancels its pending transition, even if this is
	// the reentrant no-op call from a nested exit.
	_clear_pending_transition();

	if (_internal_status == ST_INTERNAL_STATUS_INACTIVE || _is_exiting) {
		return;
	}

	// on_exit_state() runs user code that may request a transition. When that
	// transition transitions this state out (typically to redirect to a
	// sibling), it calls back into _transition_out() while the outer exit is
	// still in progress. The flag makes the nested call a no-op so each state
	// exits exactly once and on_exit_state() cannot recurse into itself.
	_is_exiting = true;

	// Only a real exit reaches this point, so derived classes capture state
	// that the exit is about to destroy exactly once here. A nested exit
	// requested by an exit callback returns on the guard above and does not
	// call this hook again.
	_on_transition_out_begin();

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
	// An exit callback may have queued a new pending transition; it must not
	// outlive the state either.
	_clear_pending_transition();
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

	if (_is_final) {
		// Re-resolve: the callbacks above can free or reparent the chart.
		NNSTRoot *report_root = _get_tree_root();
		if (report_root != nullptr) {
			report_root->_report_finished(true);
		}
	}

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
		// Events sent from the on_enter_state() callbacks of the states this
		// transition in enters wait until it has finished.
		NNSTRoot::TransitionTransaction transition_transaction(_resolve_tree_root());
		_transition_in();
	}

	call("on_tick", delta);
	emit_signal("state_ticked", delta);

	// Delayed transitions are processed after the user tick and before the
	// children tick so a transition that elapses this frame exits the state
	// before its children run.
	_process_pending_transition(delta);

	// Roots hosted by this state tick at the state tree's own rate, after the
	// user tick and any pending transition.
	if (get_is_active()) {
		_root_host.tick(delta);
	}

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
			// on_enter_state() callbacks run inside this transition in; events
			// they send are queued until it has finished.
			NNSTRoot::TransitionTransaction transition_transaction(_resolve_tree_root());
			_transition_in();
		}
	}
}
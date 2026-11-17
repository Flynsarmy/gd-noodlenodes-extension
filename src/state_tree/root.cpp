#include "root.h"
#include "../agent_behaviours/sensors.h"
#include "nodes.h"
#include "transition.h"

#include "../performance_monitor_singleton.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#ifdef DEBUG_ENABLED
#include "../debugger/debugger_overlay.h"
#include <vector>
#endif

using namespace godot;

// Method binds.

void NNSTRoot::_bind_methods() {
	BIND_ENUM_CONSTANT(NONE);
	BIND_ENUM_CONSTANT(EVENT);
	BIND_ENUM_CONSTANT(STATE_ENTER);
	BIND_ENUM_CONSTANT(PROPERTY_CHANGE);
	BIND_ENUM_CONSTANT(STATE_CHANGE);

	ClassDB::bind_method(D_METHOD("set_blackboard", "blackboard"), &NNSTRoot::set_blackboard);
	ClassDB::bind_method(D_METHOD("get_blackboard"), &NNSTRoot::get_blackboard);
	// The blackboard is a Dictionary<String, Variant>. Typed dictionary hints use
	// the format "key_type;value_type", where "Variant" accepts any value type.
	ADD_PROPERTY(
			PropertyInfo(
					Variant::DICTIONARY,
					"blackboard",
					PROPERTY_HINT_DICTIONARY_TYPE,
					vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")),
			"set_blackboard",
			"get_blackboard");

	ClassDB::bind_method(D_METHOD("set_expression_property", "name", "value"), &NNSTRoot::set_expression_property);
	ClassDB::bind_method(D_METHOD("get_expression_property", "name", "default"), &NNSTRoot::get_expression_property, Variant());
	ClassDB::bind_method(D_METHOD("set_initial_expression_properties", "properties"), &NNSTRoot::set_initial_expression_properties);
	ClassDB::bind_method(D_METHOD("get_initial_expression_properties"), &NNSTRoot::get_initial_expression_properties);
	ADD_PROPERTY(
			PropertyInfo(
					Variant::DICTIONARY,
					"initial_expression_properties",
					PROPERTY_HINT_DICTIONARY_TYPE,
					vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")),
			"set_initial_expression_properties",
			"get_initial_expression_properties");

#ifdef DEBUG_ENABLED
	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_total_tick_usec", "total_tick_usec"), &NNSTRoot::set_total_tick_usec);
	ClassDB::bind_method(D_METHOD("get_total_tick_usec"), &NNSTRoot::get_total_tick_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "total_tick_usec", PROPERTY_HINT_NONE), "set_total_tick_usec", "get_total_tick_usec");
#endif

	ClassDB::bind_method(D_METHOD("tick", "delta"), &NNSTRoot::tick);

	// ClassDB::bind_method(D_METHOD("get_active_states"), &NNSTRoot::get_active_states);

	ClassDB::bind_method(D_METHOD("get_child_sensors"), &NNSTRoot::get_child_sensors);

	ADD_SIGNAL(MethodInfo("event_received", PropertyInfo(Variant::STRING, "name")));
}

// Constructor and destructor.

NNSTRoot::NNSTRoot() {
#ifdef DEBUG_ENABLED
	_total_tick_usec = 0;
#endif

	_is_processing_events = false;
	_is_dispatching_event = false;
	_event_processing_halted = false;
	_transitions_this_processing_pass = 0;
	_transition_transaction_depth = 0;

	_child_sensors.clear();
	_num_child_sensors = 0;

	_blackboard = Dictionary();
	// Typed as Dictionary<String, Variant>. A NIL value type accepts any value.
	_blackboard.set_typed(Variant::STRING, StringName(), Variant(), Variant::NIL, StringName(), Variant());

	_initial_expression_properties = Dictionary();
	_initial_expression_properties_applied = false;

	_queued_events.clear();
	_property_change_pending = false;
	_state_change_pending = false;
	_locked_down = false;

	_queued_state_enters.clear();
	_transitions_processing_active = false;

	_scope_depth = 0;
}

NNSTRoot::~NNSTRoot() {
}

// Getters and Setters.

#ifdef DEBUG_ENABLED
void NNSTRoot::set_total_tick_usec(uint64_t total_tick_usec) {
	_total_tick_usec = total_tick_usec;
}

uint64_t NNSTRoot::get_total_tick_usec() const {
	return _total_tick_usec;
}
#endif

void NNSTRoot::set_blackboard(Dictionary blackboard) {
	// assign() enforces the String key type: non-String keys are rejected with
	// an error and the existing blackboard is left untouched.
	_blackboard.assign(blackboard);
};
Dictionary NNSTRoot::get_blackboard() const {
	return _blackboard;
};

void NNSTRoot::set_initial_expression_properties(const Dictionary &p_properties) {
	_initial_expression_properties = p_properties;
}

Dictionary NNSTRoot::get_initial_expression_properties() const {
	return _initial_expression_properties;
}

void NNSTRoot::_apply_initial_expression_properties() {
	if (_initial_expression_properties_applied) {
		return;
	}
	_initial_expression_properties_applied = true;

	Array keys = _initial_expression_properties.keys();
	for (int i = 0; i < keys.size(); i++) {
		Variant key = keys[i];
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			ERR_PRINT("Expression property names must be strings. Ignoring initial expression property with key " + String(key));
			continue;
		}
		// Expression properties share the blackboard with expression guards so
		// both use the exact same names inside Expression objects.
		_blackboard[String(key)] = _initial_expression_properties[key];
	}
}

void NNSTRoot::set_expression_property(const StringName &p_name, const Variant &p_value) {
	_apply_initial_expression_properties();

	_blackboard[String(p_name)] = p_value;
	_property_change_pending = true;
	_run_changes();
}

Variant NNSTRoot::get_expression_property(const StringName &p_name, const Variant &p_default) const {
	return _blackboard.get(String(p_name), p_default);
}

// Handling methods

void NNSTRoot::tick(float delta) {
#ifdef DEBUG_ENABLED
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();
#endif

	if (_num_active_states == 0) {
		_needs_reselection = false;
		// Entering the initial states runs on_enter_state() callbacks. Events
		// they send must wait until the whole transition in has finished.
		TransitionTransaction transition_transaction(this);
		_transition_in();
	}

	// Update the sensors.
	for (unsigned int i = 0; i < _num_child_sensors; i++) {
		NNSensors *sensor = godot::Object::cast_to<NNSensors>(_child_sensors[i]);
		// NNSensors *sensor = _child_sensors[i];
		if (!sensor->get_is_enabled()) {
			continue;
		}
		sensor->evaluate_sensor_value();
	} //endfor sensors

	// If there are active states, tick their custom method from the
	// root to the active leaf. The list is snapshotted by instance ID because
	// a child's on_tick() may free, remove or reparent another active child.
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_active_state(active_state_ids[i]);
		if (stnode == nullptr) {
			continue;
		}

		stnode->set_root(this);
		stnode->on_tick(delta);
	}
#ifdef DEBUG_ENABLED
	_total_tick_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
	NNPerformanceMonitorSingleton::get_singleton()->increment_total_time_elapsed_state_trees_usec(_total_tick_usec);
#endif
}

void NNSTRoot::send_event(String name) {
	// Events are queued so a callback that sends another event never processes
	// it recursively. The chart is invalid once a processing pass has been
	// aborted by the transition budget.
	if (_event_processing_halted) {
		return;
	}

	_event_queue.push_back(name);
	_try_drain_event_queue();
}

void NNSTRoot::_try_drain_event_queue() {
	// An in-flight event dispatch owns the queue: a send_event() from inside a
	// callback is queued and processed after the current event, including its
	// bubbling to ancestors, has finished.
	if (_is_processing_events) {
		return;
	}

	// A transition cascade owns the queue too. Processing an event now would
	// run callbacks in the middle of the transition that is still on the stack.
	if (_transition_transaction_depth > 0) {
		return;
	}

	// The automatic-change pipeline and transition/entry scopes own the queue
	// as well: events queued from a guard or on_enter_state()/on_exit_state()
	// must wait until the change that is currently settling has completed.
	if (_scope_depth > 0 || _locked_down) {
		return;
	}

	if (_event_processing_halted) {
		_event_queue.clear();
		return;
	}

	// One processing pass is the whole drain: the transition budget is only
	// reset when the queue is empty and the outermost send_event() returns.
	_is_processing_events = true;
	_transitions_this_processing_pass = 0;

	while (!_event_queue.empty()) {
		if (_event_processing_halted) {
			break;
		}

		String event_name = _event_queue.front();
		_event_queue.erase(_event_queue.begin());

		// Only this single delivery owns the dispatch flag. Nested send_event()
		// calls still queue into _event_queue because _is_processing_events is
		// true for the whole drain, but automatic state/property changes raised
		// by its callbacks must wait until delivery - including root handling -
		// has finished. They are settled in the gap below before the next event.
		_is_dispatching_event = true;

		// The chart receives the event before any of its states do.
		emit_signal("event_received", event_name);

		bool consumed = false;
		const std::vector<ObjectID> active_state_ids = _active_states;
		for (unsigned int i = 0; i < active_state_ids.size(); i++) {
			NNSTTickedNodes *state = _get_active_state(active_state_ids[i]);
			if (state == nullptr) {
				continue;
			}

			if (state->_dispatch_event(event_name)) {
				consumed = true;
				break;
			}

			if (_event_processing_halted) {
				break;
			}
		}

		// The root is the last state to see the event. Its own transitions only
		// run when no active child consumed it.
		if (!consumed && !_event_processing_halted) {
			_try_root_event_transitions(event_name);
		}

		// Delivery is complete. Settle everything this event made pending now,
		// before the next queued event is dispatched: state changes first, then
		// property changes, with any already-queued events left in FIFO order
		// for the next loop iteration. The drain still owns the queue, so a
		// nested _try_drain_event_queue() from the change pipeline is a no-op.
		_is_dispatching_event = false;
		_run_changes();
	}

	if (_event_processing_halted) {
		// Never process events queued behind a runaway pass.
		_event_queue.clear();
	}
	_is_processing_events = false;

	// The per-event gap above settles the normal case. This final pass is a
	// fallback for changes left pending by an aborted/iteration-capped gap or
	// by a pass that was entered with an already-empty queue, now that nothing
	// owns the queue any more.
	_run_changes();
}

NNSTRoot::TransitionTransaction::TransitionTransaction(NNSTRoot *p_root) :
		_root_id(p_root != nullptr ? ObjectID(p_root->get_instance_id()) : ObjectID()) {
	if (p_root != nullptr) {
		p_root->_transition_transaction_depth++;
	}
}

NNSTRoot::TransitionTransaction::~TransitionTransaction() {
	if (_root_id.is_null()) {
		return;
	}

	// A callback may have freed the chart root while the transition was in
	// flight; never dereference a stale pointer.
	NNSTRoot *tree_root = godot::Object::cast_to<NNSTRoot>(ObjectDB::get_instance(_root_id));
	if (tree_root != nullptr) {
		tree_root->_end_transition_transaction();
	}
}

void NNSTRoot::_end_transition_transaction() {
	if (_transition_transaction_depth > 0) {
		_transition_transaction_depth--;
	}

	if (_transition_transaction_depth > 0) {
		return;
	}

	// The outermost transition and all of its callbacks have finished. Settle
	// the state/property changes they made BEFORE dispatching any queued event:
	// an automatic R1->R2 guarded on the new state/property must settle first,
	// otherwise a queued "later" event would still reach the stale R1.
	// _run_changes() hands any still-queued events to _try_drain_event_queue()
	// once changes are settled, so state -> property -> event order is kept and
	// the whole-pass transition budget is not reset per event. An event
	// dispatch, an entry scope or the change pipeline still owns the queue and
	// makes both calls no-ops in that case; the owner releases it later.
	_run_changes();
	_try_drain_event_queue();
}

bool NNSTRoot::_register_applied_transition() {
	if (_event_processing_halted) {
		return false;
	}

	// Transitions applied outside an event processing pass (for example from
	// on_tick() or the automatic-change pipeline) are not part of a pass and
	// are not counted. Automatic STATE_ENTER cascades have their own bound.
	if (!_is_processing_events) {
		return true;
	}

	_transitions_this_processing_pass++;
	if (_transitions_this_processing_pass <= MAX_PROCESSING_PASS_TRANSITIONS) {
		return true;
	}

	_event_processing_halted = true;
	_event_queue.clear();
	ERR_PRINT(vformat("NNSTRoot: infinite loop detected: more than %d transitions in one processing pass. Aborting event processing; the state tree is now invalid.", MAX_PROCESSING_PASS_TRANSITIONS));
	return false;
}

bool NNSTRoot::get_is_event_processing_halted() const {
	return _event_processing_halted;
}

bool NNSTRoot::_is_active_child_activation_valid(ObjectID p_state_id, uint64_t p_epoch) const {
	if (p_state_id.is_null()) {
		// The root had no active child when its guard started. A child that
		// appeared since then means the guard transitioned the chart.
		return _get_active_child_states().empty();
	}

	NNSTTickedNodes *state = _get_active_state(p_state_id);
	return state != nullptr && state->get_activation_epoch() == p_epoch;
}

bool NNSTRoot::_try_root_event_transitions(const String &name) {
	const std::vector<ObjectID> transition_ids = _get_matching_transition_ids(name);
	for (unsigned int i = 0; i < transition_ids.size(); i++) {
		ObjectID transition_id = transition_ids[i];
		NNSTTransition *transition = godot::Object::cast_to<NNSTTransition>(ObjectDB::get_instance(transition_id));
		if (transition == nullptr || transition->get_parent() != this) {
			continue;
		}

		// A declining transition (failed guard) does not consume the event.
		// The root is not a state in the tree, so guards that need the chart
		// root are evaluated with the active child as their state context.
		NNSTTickedNodes *guard_state = nullptr;
		const std::vector<ObjectID> active_state_ids = _active_states;
		for (unsigned int j = 0; j < active_state_ids.size(); j++) {
			guard_state = _get_active_state(active_state_ids[j]);
			if (guard_state != nullptr) {
				break;
			}
		}

		// The guard is user code and may transition the chart. Capture the
		// child it was evaluated against so a stale root transition is not
		// applied if the chart moved on.
		const ObjectID guard_state_id = guard_state != nullptr ? ObjectID(guard_state->get_instance_id()) : ObjectID();
		const uint64_t guard_state_epoch = guard_state != nullptr ? guard_state->get_activation_epoch() : 0;

		if (!transition->_can_transition(guard_state)) {
			// A replaced activation also abandons the remaining root
			// transitions: the chart already handled the event itself.
			if (!_is_active_child_activation_valid(guard_state_id, guard_state_epoch)) {
				return false;
			}
			continue;
		}

		// The guard may have transitioned the chart even though it returned
		// true. Never apply the transition for a stale active child.
		if (!_is_active_child_activation_valid(guard_state_id, guard_state_epoch)) {
			return false;
		}

		// Guards run user code which may free or reparent this transition.
		transition = godot::Object::cast_to<NNSTTransition>(ObjectDB::get_instance(transition_id));
		if (transition == nullptr || transition->get_parent() != this) {
			continue;
		}

		// The transition's target is authored relative to the transition node,
		// which is a child of this root, so it is one level deep.
		Node *target_node = get_node_or_null(transition->get_to().slice(1));
		NNSTTickedNodes *to_state = godot::Object::cast_to<NNSTTickedNodes>(target_node);
		if (to_state == nullptr) {
			continue;
		}

		if (_run_transition_to(to_state)) {
			return true;
		}

		if (_event_processing_halted) {
			return false;
		}
	}

	return false;
}

/**
 * Collects the active state IDs of a subtree, deepest first. Used by
 * _run_transition_to() because a root transition has to be started from a
 * state that is not an ancestor of the target.
 */
static void _collect_active_states_deepest_first(NNSTTickedNodes *state, std::vector<ObjectID> &states) {
	const std::vector<NNSTTickedNodes *> active_children = state->_get_active_child_states();
	for (unsigned int i = 0; i < active_children.size(); i++) {
		if (active_children[i] != nullptr) {
			_collect_active_states_deepest_first(active_children[i], states);
		}
	}
	if (state != nullptr) {
		states.push_back(ObjectID(state->get_instance_id()));
	}
}

bool NNSTRoot::_run_transition_to(NNSTTickedNodes *to_state) {
	if (to_state == nullptr) {
		return false;
	}

	// A candidate transition below runs user callbacks that may free the
	// target, so keep only its instance ID between attempts.
	const ObjectID to_state_id = ObjectID(to_state->get_instance_id());

	// Snapshot the active children: transition_to() runs user callbacks that
	// can free or replace them.
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *active_state = _get_active_state(active_state_ids[i]);
		if (active_state == nullptr) {
			continue;
		}

		std::vector<ObjectID> candidates;
		_collect_active_states_deepest_first(active_state, candidates);

		for (unsigned int j = 0; j < candidates.size(); j++) {
			NNSTTickedNodes *from_state = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(candidates[j]));
			NNSTTickedNodes *target = godot::Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(to_state_id));
			if (from_state == nullptr || target == nullptr || from_state == target) {
				continue;
			}

			// The existing transition logic cannot start from an ancestor of
			// the target (or descend into an ancestor), so try a state that is
			// unrelated to it. The deepest such state is tried first.
			if (from_state->is_ancestor_of(target) || target->is_ancestor_of(from_state)) {
				continue;
			}

			if (from_state->transition_to(from_state->get_path_to(target))) {
				return true;
			}

			if (_event_processing_halted) {
				return false;
			}
		}
	}

	return false;
}

// ---------------------------------------------------------------------------
// Automatic-transition change pipeline.
//
// State changes and property changes are processed before queued events so a
// transition that a change triggers settles before the next change is handled.
// ---------------------------------------------------------------------------

void NNSTRoot::mark_state_change_pending() {
	_state_change_pending = true;
	_run_changes();
}

bool NNSTRoot::is_processing_changes() const {
	return _locked_down || _scope_depth > 0 || _is_processing_events || _transition_transaction_depth > 0;
}

void NNSTRoot::_begin_scope() {
	++_scope_depth;
}

void NNSTRoot::_end_scope() {
	if (_scope_depth > 0) {
		--_scope_depth;
	}
	if (_scope_depth != 0) {
		// An outer transition/entry scope is still open. Its close will drain.
		return;
	}

	// The outermost scope closed. Drain the settled configuration: automatic
	// STATE_ENTER transitions first, then the priority-ordered change pipeline.
	// The reentrancy guards inside both runners make nested requests from
	// callbacks join the in-flight work instead of recursing.
	_run_queued_state_enters();
	_run_changes();
}

void NNSTRoot::process_state_enter(NNSTTickedNodes *p_state, uint64_t p_generation) {
	if (p_state == nullptr) {
		return;
	}

	// Queue the state rather than evaluating its automatic transitions here.
	// A matching STATE_ENTER transition transitions to another state, whose
	// on_enter_state() calls back into process_state_enter(); evaluating inline
	// would recurse the C stack without bound for a transition cycle. The
	// runner below drains the queue iteratively with a bounded iteration count.
	// The generation ties this request to the exact activation that produced it.
	QueuedStateEnter request;
	request.state_id = ObjectID(p_state->get_instance_id());
	request.generation = p_generation;
	_queued_state_enters.push_back(request);
	_run_queued_state_enters();
}

void NNSTRoot::_run_queued_state_enters() {
	if (_scope_depth > 0) {
		// An entry/transition scope is open. Only queue here; the outermost
		// scope close drains the queue against the settled hierarchy.
		return;
	}
	if (_transitions_processing_active) {
		// A runner is already active higher on the stack. The state we just
		// queued will be evaluated by it once it returns from its current work.
		return;
	}

	_transitions_processing_active = true;

	int iterations = 0;
	while (!_queued_state_enters.empty()) {
		// A circular chain of automatic STATE_ENTER transitions can keep
		// entering states forever. Cap the work so the engine does not hang.
		if (++iterations > 100) {
			ERR_PRINT("Infinite loop detected in automatic state transitions (STATE_ENTER cascade). Aborting transition processing.");
			_queued_state_enters.clear();
			break;
		}

		QueuedStateEnter request = _queued_state_enters[0];
		_queued_state_enters.erase(_queued_state_enters.begin());

		NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(request.state_id));
		if (state == nullptr || !state->get_is_active() ||
				state->get_activation_generation() != request.generation) {
			// The state was freed, transitioned out, or re-entered before this
			// request could be evaluated. Its current activation either does
			// not exist or is a different one, so this request is stale.
			continue;
		}

		state->_process_transitions(TriggerType::STATE_ENTER, String());
	}

	_transitions_processing_active = false;
}

void NNSTRoot::_run_changes() {
	// Defer while a single event is being delivered, a transition cascade, a
	// transition/entry scope or another change pass owns the queue. The owner
	// releases it later. The whole-drain _is_processing_events flag deliberately
	// does NOT block here: the event loop settles changes in the gap after each
	// fully dispatched event, while still owning the queue for FIFO ordering
	// and whole-pass transition accounting.
	if (_locked_down || _scope_depth > 0 || _transition_transaction_depth > 0 || _is_dispatching_event) {
		return;
	}
	_locked_down = true;

	int iterations = 0;
	while (_state_change_pending || _property_change_pending || !_event_queue.empty()) {
		// A guarded automatic transition can queue another change. Cap the
		// work so a circular chain of transitions cannot hang the engine.
		if (++iterations > 100) {
			ERR_PRINT("Automatic transition loop detected in state tree. Aborting change processing.");
			break;
		}

		// Re-evaluate priority from the top after every single change. A change
		// can queue or mark higher-priority work (e.g. a PROPERTY_CHANGE that
		// enters a state and queues an event plus a STATE_CHANGE); processing
		// the event before the newly pending state change would violate the
		// state -> property -> event ordering.
		// 1. State changes (a transition finished).
		if (_state_change_pending) {
			_state_change_pending = false;
			_process_transitions(TriggerType::STATE_CHANGE, String());
			continue;
		}

		// 2. Property changes (an expression property was set).
		if (_property_change_pending) {
			_property_change_pending = false;
			_process_transitions(TriggerType::PROPERTY_CHANGE, String());
			continue;
		}

		// 3. Queued events, oldest first. Hand the queue to the event pipeline
		// so they use the same dispatch, activation-identity and budget rules.
		if (!_event_queue.empty()) {
			_locked_down = false;
			_try_drain_event_queue();
			return;
		}
	}

	_locked_down = false;
}

bool NNSTRoot::_process_transitions(int trigger_type, const String &event_name) {
	if (!get_is_active()) {
		return false;
	}

	// Snapshot IDs: an on_enter_state()/on_exit_state() callback or a guard can
	// free, remove or reparent active states while we are iterating.
	bool any_handled = false;
	const std::vector<ObjectID> active_state_ids = _active_states;
	for (unsigned int i = 0; i < active_state_ids.size(); i++) {
		NNSTTickedNodes *stnode = _get_active_state(active_state_ids[i]);
		if (stnode == nullptr) {
			continue;
		}
		if (stnode->_process_transitions(trigger_type, event_name)) {
			// A parallel child fans out to all of its own active regions before
			// reporting handled. Keep visiting the root's other active children
			// so a parallel node never cuts short a wider fan-out; normal states
			// keep first-match-wins.
			if (stnode->is_parallel()) {
				any_handled = true;
				continue;
			}
			return true;
		}
	}
	return any_handled;
}

/**
 * Searches children for states to activate using the appropriate
 * activation method based on the `get_child_state_selection_rule()` setting.
 *
 * Only activates up to 1 child for each node (CompoundState).
 */
void NNSTRoot::_evaluate_child_activations(std::vector<ObjectID> &nodes) {
	// std::vector<NNSTNode *> nodes;

	// Snapshot child IDs because on_enter_condition() / evaluate() callbacks can
	// remove, reparent or free siblings while this is running.
	const std::vector<ObjectID> child_state_ids = _child_states;

	if (get_child_state_selection_rule() == NNSTNodeChildStateSelectionRule::ON_ENTER_CONDITION_METHOD) {
		// Childs are evaluated by using the user-defined on_enter_condition method.
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode == nullptr || !stnode->get_is_enabled()) {
				continue;
			}

			if (!stnode->on_enter_condition()) {
				continue;
			}

			// Activate the child and evaluate its children
			nodes.push_back(child_state_ids[i]);

			// Only 1 child gets activated
			break;
		}
	} else if (get_child_state_selection_rule() == NNSTNodeChildStateSelectionRule::UTILITY_SCORING) {
		// Childs are evaluated by using Utility-based scoring.
		ObjectID highest_scoring_state_to_activate;
		float highest_score = -9999999.9999;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode == nullptr || !stnode->get_is_enabled()) {
				continue;
			}

			float score = stnode->evaluate();
			if (score > highest_score) {
				highest_score = score;
				highest_scoring_state_to_activate = child_state_ids[i];
			}
		}

		// Return the highest scoring state that can activate.
		if (!highest_scoring_state_to_activate.is_null()) {
			// Activate the child and evaluate its children
			nodes.push_back(highest_scoring_state_to_activate);
		}
	}

	// return nodes;
}

void NNSTRoot::_transition_in() {
	// Entering the root may run automatic STATE_ENTER transitions. Lock the
	// change pipeline for the duration so their resulting state changes are
	// applied afterwards, with a consistent active hierarchy.
	const bool was_locked = _locked_down;
	_locked_down = true;
	_apply_initial_expression_properties();

	_needs_reselection = false;
	set_internal_status(ST_INTERNAL_STATUS_ACTIVE);

	if (_num_active_states == 0) {
		std::vector<ObjectID> new_active_states;
		_evaluate_child_activations(new_active_states);
		_apply_active_states(new_active_states, this);
	}

	_locked_down = was_locked;
	if (!was_locked) {
		_run_changes();
	}
};

// Godot virtuals.

void NNSTRoot::_notification(int p_what) {
	NNSTBranchNodes::_notification(p_what);

#ifdef DEBUG_ENABLED
	if (p_what == NOTIFICATION_ENTER_TREE || p_what == NOTIFICATION_EXIT_TREE) {
		if (!Engine::get_singleton()->is_editor_hint()) {
			NNDebuggerOverlay *debugger_overlay = NNDebuggerOverlay::get_singleton();
			if (debugger_overlay != nullptr) {
				if (p_what == NOTIFICATION_ENTER_TREE) {
					debugger_overlay->register_state_tree(get_instance_id());
				} else {
					debugger_overlay->deregister_state_tree(get_instance_id());
				}
			}
		}
	}
#endif

	if (p_what == NOTIFICATION_READY || p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		// Wait until this node has entered the tree and run _ready before
		// trusting a child order notification. Readiness is deliberately
		// separate from the active status so an inactive branch still refreshes
		// its child caches (and sensors below) for a later transition in.
		if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED && !is_node_ready()) {
			return;
		}

		const std::vector<ObjectID> child_state_ids = _child_states;
		for (unsigned int i = 0; i < child_state_ids.size(); i++) {
			NNSTTickedNodes *stnode = _get_child_state(child_state_ids[i]);
			if (stnode != nullptr) {
				stnode->set_root(this);
			}
		}

		_child_sensors.clear();
		for (unsigned int i = 0; i < get_child_count(); i++) {
			if (NNSensors *sensor = godot::Object::cast_to<NNSensors>(get_child(i))) {
				_child_sensors.push_back(sensor);
			}
		}
		_num_child_sensors = (unsigned int)_child_sensors.size();

		// This will do nothing if we already have an active child. We want to
		// call it on child order changed incase the root has no active children
		// when another child gets added. If the change was caused by a child
		// being deleted, wait for the next tick so teardown doesn't enter new
		// states. A node that has already left the tree (for example while its
		// parent is being freed) must not enter states either.
		//
		// Only the root's own readiness may activate it. A child order change
		// must not enter a ready-but-inactive root: inactive here means it was
		// transitioned out on purpose, so its owner decides when to re-enter it.
		if (is_inside_tree() && !_last_notification_had_child_removal && !_needs_reselection &&
				(p_what == NOTIFICATION_READY || _internal_status == ST_INTERNAL_STATUS_ACTIVE)) {
			// on_enter_state() callbacks run inside this transition in; events
			// they send are queued until it has finished.
			TransitionTransaction transition_transaction(this);
			_transition_in();
		}

		return;
	}
}

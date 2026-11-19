#pragma once

#include "../host.h"
#include "../root_context.h"
#include "../tick_scheduler.h"
#include "branch_nodes.h"
#include "node.h"
#include <agent_behaviours/sensors.h>
#include <cstdint>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <vector>

namespace godot {

class NNSTRoot : public NNSTBranchNodes {
	GDCLASS(NNSTRoot, NNSTBranchNodes)

private:
	// Events are processed one at a time, in FIFO order. send_event() only
	// starts the drain loop when the root is not already inside one, so
	// callbacks that send another event queue it instead of recursing.
	std::vector<String> _event_queue;
	// True for the whole drain loop, from the outermost send_event() until the
	// queue is empty. Callbacks that send further events queue them instead of
	// recursing, and the transition budget is counted once for the entire pass.
	bool _is_processing_events;
	// True only while a single event is being delivered (the event_received
	// signal, active-state fan-out/bubbling and root event transitions). The
	// automatic-change pipeline stays blocked while this is set, but is settled
	// in the gap once this event has fully dispatched and before the next
	// queued event is dequeued. This gives state/property changes priority over
	// events queued by an earlier event.
	bool _is_dispatching_event;
	// Set when a processing pass exceeds the transition budget. The chart is
	// invalid from then on and further events are ignored.
	bool _event_processing_halted;
	unsigned int _transitions_this_processing_pass;
	// Number of transition cascades currently in flight. While it is non-zero,
	// send_event() only enqueues: a transition and every callback it runs must
	// complete before the next queued change is processed, even when the
	// transition was started directly with transition_to() instead of by an
	// event.
	unsigned int _transition_transaction_depth;

	// Starts processing the event queue when neither an event dispatch nor a
	// transition cascade owns it. Callers that already own the queue (the
	// drain loop and transition callbacks) leave it to that owner.
	void _try_drain_event_queue();
	// Ends one transition cascade and drains the queue once the outermost
	// cascade has finished.
	void _end_transition_transaction();

	// Applies root-level transitions for a processed event. The root is the
	// last state to see an event, after all active children had their chance.
	bool _try_root_event_transitions(const String &name);
	// True while the captured active child (identified by instance ID and
	// activation epoch) is still the root's active child. A null ID means the
	// root had no active child when it was captured. Root transition guards
	// run user code that can transition the chart, so a root transition must
	// never be applied on behalf of a stale child activation.
	bool _is_active_child_activation_valid(ObjectID p_state_id, uint64_t p_epoch) const;
	// Starts a transition to to_state from the active child (or one of its
	// active descendants) so the existing transition logic is reused.
	bool _run_transition_to(NNSTTickedNodes *to_state);

	NNTickScheduler _tick_scheduler;
	NNHostedRoot _hosted_root;

	// Leaves the chart inactive from the current active set, without running
	// the change pipeline from the exit callbacks.
	void _reset_chart();

	void _on_scene_tree_process_frame();
	void _on_scene_tree_physics_frame();
	bool _auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due);

#ifdef DEBUG_ENABLED
	uint64_t _total_tick_usec;
#endif
	TypedArray<NNSensors> _child_sensors;
	unsigned int _num_child_sensors;

	NNRootContext _root_context;

	// Initial values for expression properties. Applied once, when the root
	// first transitions in, before any state is entered.
	Dictionary _initial_expression_properties;
	bool _initial_expression_properties_applied;

	// Pending change tracking. Changes are processed in a fixed order:
	// state changes, then property changes, then queued events.
	std::vector<String> _queued_events;
	bool _property_change_pending;
	bool _state_change_pending;
	bool _locked_down;

	// Automatic STATE_ENTER transitions are queued instead of being evaluated
	// inline. Entering a state runs its STATE_ENTER transitions, which can
	// transition to another state and enter it in turn; a transition cycle would
	// otherwise recurse the C stack until it overflows. _transitions_processing_active
	// makes those reentrant entry requests join the queue, and the bounded
	// runner below drains it iteratively.
	//
	// Each request also captures the activation generation of the state at the
	// moment it was entered, so a request that outlived its activation (exit
	// then re-entry before the drain) can be discarded instead of evaluating
	// the newer activation a second time.
	struct QueuedStateEnter {
		ObjectID state_id;
		uint64_t generation;
	};
	std::vector<QueuedStateEnter> _queued_state_enters;
	bool _transitions_processing_active;

	// Depth of the transition/entry scopes currently open. While > 0, change
	// requests only mark/queue pending work; the outermost scope close drains
	// them against a fully settled active hierarchy. This covers transition
	// entry points that do not go through _run_changes() (direct transition_to,
	// STATE_ENTER cascades, on_tick reselection) so an on_exit_state()/guard
	// callback can never run the change pipeline inside an unfinished
	// transition.
	unsigned int _scope_depth;

	void _run_changes();
	void _run_queued_state_enters();
	void _apply_initial_expression_properties();

protected:
	static void _bind_methods();

	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

public:
	NNSTRoot();
	~NNSTRoot();

	// Trigger types describe what can cause an automatic transition to be
	// evaluated. Values are flags so they can be combined in a bit mask.
	enum TriggerType {
		NONE = 0,
		EVENT = 1,
		STATE_ENTER = 2,
		PROPERTY_CHANGE = 4,
		STATE_CHANGE = 8,
	};

	enum ProcessThread {
		IDLE = NNTickScheduler::IDLE,
		PHYSICS = NNTickScheduler::PHYSICS,
		MANUAL = NNTickScheduler::MANUAL,
	};

	// The maximum number of transitions a single processing pass may apply
	// before the chart is considered to be looping.
	static constexpr unsigned int MAX_PROCESSING_PASS_TRANSITIONS = 100;

	// Getters and setters for attributes.

	bool is_root() const override { return true; }

	NNHostedRoot *get_hosted_root() override { return &_hosted_root; }

	void set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;

	void set_expression_property(const StringName &p_name, const Variant &p_value);
	Variant get_expression_property(const StringName &p_name, const Variant &p_default = Variant()) const;

	void set_initial_expression_properties(const Dictionary &p_properties);
	Dictionary get_initial_expression_properties() const;

	void set_process_thread(int p_process_thread);
	int get_process_thread() const;
	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.
	virtual void send_event(String name) override;

	// RAII scope for one transition cascade. Creating it defers queued events
	// until the outermost scope is destroyed, which is what keeps a transition
	// and all of its callbacks transactional. A null root makes it a no-op.
	class TransitionTransaction {
	private:
		ObjectID _root_id;

	public:
		explicit TransitionTransaction(NNSTRoot *p_root);
		~TransitionTransaction();
		TransitionTransaction(const TransitionTransaction &) = delete;
		TransitionTransaction &operator=(const TransitionTransaction &) = delete;
	};

	// Registers an applied transition against the current processing pass.
	// Returns false when the pass exceeded its transition budget, in which
	// case the root has halted and the caller must not apply the transition.
	// Called by NNSTTickedNodes::transition_to(); transitions applied outside
	// an event processing pass are not counted.
	bool _register_applied_transition();
	bool get_is_event_processing_halted() const;

	// Emits "finished". Final states call this when they are entered.
	void _report_finished(bool p_succeeded);

	bool auto_tick_step(int p_process_thread, double p_delta);

	virtual void _transition_in() override;

	// Runs automatic transitions that are triggered when a state is entered.
	// Called from NNSTTickedNodes::on_enter_state(). The generation identifies
	// the specific activation that generated this request.
	void process_state_enter(NNSTTickedNodes *p_state, uint64_t p_generation);

	// Marks a state change as pending and processes it when it is safe to do so.
	void mark_state_change_pending();
	bool is_processing_changes() const;

	// Transition/entry scope tracking. Called by NNSTTickedNodes around every
	// transition_to() and on_enter_state() so deferred work is drained only
	// once the outermost scope closes.
	void _begin_scope();
	void _end_scope();

	// Walks the active hierarchy and lets its transitions handle the trigger.
	// Returns true when a transition handled the trigger.
	virtual bool _process_transitions(int trigger_type, const String &event_name = String());

	void tick(float delta);

	TypedArray<NNSensors> get_child_sensors() { return _child_sensors; };

	// Godot virtuals.
	void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNSTRoot::TriggerType)
VARIANT_ENUM_CAST(NNSTRoot::ProcessThread)

#pragma once

#include "branch_nodes.h"
#include "node.h"
#include <agent_behaviours/sensors.h>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <vector>

namespace godot {

class NNSTRoot : public NNSTBranchNodes {
	GDCLASS(NNSTRoot, NNSTBranchNodes)

private:
	// Events are processed one at a time, in FIFO order. send_event() only
	// starts the drain loop when the root is not already inside one, so
	// callbacks that send another event queue it instead of recursing.
	std::vector<String> _event_queue;
	bool _is_processing_events;
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

#ifdef DEBUG_ENABLED
	uint64_t _total_tick_usec;
#endif
	// TypedArray<NNSTNodes> _active_states;
	// std::vector<NNSTNodes *> _active_states_vector;
	TypedArray<NNSensors> _child_sensors;
	unsigned int _num_child_sensors;

	Dictionary _blackboard;

protected:
	static void _bind_methods();

public:
	NNSTRoot();
	~NNSTRoot();

	// The maximum number of transitions a single processing pass may apply
	// before the chart is considered to be looping.
	static constexpr unsigned int MAX_PROCESSING_PASS_TRANSITIONS = 100;

	// Getters and setters for attributes.

	void set_blackboard(Dictionary blackboard);
	Dictionary get_blackboard() const;

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

	virtual void _transition_in() override;
	virtual void _evaluate_child_activations(std::vector<ObjectID> &nodes) override;

	void tick(float delta);

	TypedArray<NNSensors> get_child_sensors() { return _child_sensors; };

	// Godot virtuals.
	void _notification(int p_what);
};

} //namespace godot

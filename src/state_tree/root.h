#pragma once

#include "branch_nodes.h"
#include "node.h"
#include <agent_behaviours/sensors.h>
#include <cstdint>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <vector>

namespace godot {

class NNSTRoot : public NNSTBranchNodes {
	GDCLASS(NNSTRoot, NNSTBranchNodes)

private:
#ifdef DEBUG_ENABLED
	uint64_t _total_tick_usec;
#endif
	// TypedArray<NNSTNodes> _active_states;
	// std::vector<NNSTNodes *> _active_states_vector;
	TypedArray<NNSensors> _child_sensors;
	unsigned int _num_child_sensors;

	Dictionary _blackboard;

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

	// Getters and setters for attributes.

	void set_blackboard(Dictionary blackboard);
	Dictionary get_blackboard() const;

	void set_expression_property(const StringName &p_name, const Variant &p_value);
	Variant get_expression_property(const StringName &p_name, const Variant &p_default = Variant()) const;

	void set_initial_expression_properties(const Dictionary &p_properties);
	Dictionary get_initial_expression_properties() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.
	virtual void send_event(String name) override;

	virtual void _transition_in() override;
	virtual void _evaluate_child_activations(std::vector<ObjectID> &nodes) override;

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
};

} //namespace godot

VARIANT_ENUM_CAST(NNSTRoot::TriggerType)

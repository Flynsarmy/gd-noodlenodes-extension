#pragma once

#include "../agent_behaviours/considerations.h"
#include "../noodle_nodes.h"
#include "definitions.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNBTNodes : public NoodleNodes {
	GDCLASS(NNBTNodes, NoodleNodes)

public:
	NNBTNodes();
	~NNBTNodes();

	// Getters and setters for attributes.

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
#endif

	void set_evaluation_method(int evaluation_method);
	int get_evaluation_method() const;

	enum Status {
		SKIP = -2,
		FAILURE = -1,
		RUNNING = 0,
		SUCCESS = 1,
	};

	enum NNBTNodesEvaluationMethod {
		Sum = 0,
		Min = 1,
		Max = 2,
		Mean = 3,
		Multiply = 4,
		FirstNonZero = 5,
		//OneMinusScore=6
	};

	void set_score(float score);
	float get_score() const;

	void set_tick_result(Status tick_result);
	Status get_tick_result() const;

	void set_internal_status(int internal_status);
	int get_internal_status() const;

	void set_reset_rule(int reset_rule);
	int get_reset_rule() const;

	enum NNBTNodesResetRule {
		WHEN_TICKED = 0,
		WHEN_COMPLETED,
		WHEN_TICKED_AFTER_BEING_COMPLETED,
		NEVER,
	};

	// Handling functions.

	virtual float evaluate();

	// Wrapper that manages the node's run lifecycle around _tick().
	Status tick(Variant blackboard, float delta);

	virtual void reset();
	//virtual void reset_for_looping();
	virtual void reset_bt_node() {};
	virtual void update_child_vectors();

	// Force-stops the current run, interrupting the node's active subtree.
	// Safe to call on a node that is not running.
	void interrupt();

	inline virtual bool has_completed() { return (_internal_status == BT_INTERNAL_STATUS_COMPLETED); };

	NodePath get_tree_root() const;

	// Godot virtuals.
	virtual void _notification(int p_what);

private:
	mutable NodePath _cached_tree_root_path;
	mutable bool _is_tree_root_path_cached;
	float _score;
	int _evaluation_method;
	bool _invert_score;
	Status _tick_result;
	int _internal_status;
	int _reset_rule;
	bool _has_reset_rule_changed;
	// Run lifecycle state. A run starts on the first tick after the node has no
	// active run and ends on a terminal result or an interrupt.
	bool _is_running;
	Variant _run_blackboard;
	float _run_delta;

protected:
	static void _bind_methods();

	// Node-specific tick implementation. Returns the tick result the wrapper
	// exposes through tick().
	virtual Status _tick(Variant blackboard, float delta);

	// Lifecycle hooks. Every before_run is matched by exactly one after_run or
	// interrupt for the same run.
	virtual void _on_before_run(Variant blackboard, float delta);
	virtual void _on_after_run(Variant blackboard, float delta);
	virtual void _on_interrupt(Variant blackboard, float delta);

	// Interrupts every behaviour-tree child that still has an active run.
	void _interrupt_active_children();
	// Interrupts every behaviour-tree child with an active run except p_keep.
	void _interrupt_other_active_children(const NNBTNodes *p_keep);

	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

	//bool   _is_first_tick;
	std::vector<NNBTNodes *> _child_btnodes;
	unsigned int _num_child_btnodes;
	std::vector<NNConsiderations *> _child_considerations;
	unsigned int _num_child_considerations;
	bool _has_reported_extra_enabled_child;

	// Structural helper functions.
	int _count_enabled_child_btnodes() const;
	void _report_extra_enabled_child_btnodes();
#ifdef DEBUG_ENABLED
	uint64_t _last_evaluated_timestamp;
	uint64_t _last_visited_timestamp;
#endif
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTNodes::Status)

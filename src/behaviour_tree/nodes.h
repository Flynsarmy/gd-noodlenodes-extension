#pragma once

#include "../agent_behaviours/considerations.h"
#include "../noodle_nodes.h"
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

	void set_evaluation_method(EvaluationMethod evaluation_method);
	EvaluationMethod get_evaluation_method() const;

	enum Status {
		SKIP = -2,
		FAILURE = -1,
		RUNNING = 0,
		SUCCESS = 1,
	};

	void set_score(float score);
	float get_score() const;

	Status get_tick_result() const;

	// Handling functions.

	virtual float evaluate();

	// Wrapper that manages the node's run lifecycle around _tick().
	Status tick(float delta);

	virtual void reset();
	virtual void update_child_vectors();

	// Force-stops the current run, interrupting the node's active subtree.
	// Safe to call on a node that is not running.
	void interrupt();

	// True while a run is active.
	bool get_is_running() const;
	// The reference that is currently driving the run, or a null ID when no run
	// is active or the node is not driven through a node reference.
	ObjectID get_run_owner() const;
	// Marks the driver of the next or active run.
	void set_run_owner(ObjectID p_owner);

	NodePath get_tree_root() const;

	// Godot virtuals.
	virtual void _notification(int p_what);

private:
	float _score;
	EvaluationMethod _evaluation_method;
	Status _tick_result;
	// Run lifecycle state. A run starts on the first tick after the node has no
	// active run and ends on a terminal result or an interrupt.
	bool _is_running;
	ObjectID _run_owner;
	float _run_delta;

protected:
	static void _bind_methods();

	// Node-specific tick implementation. Returns the tick result the wrapper
	// exposes through tick().
	virtual Status _tick(float delta);

	// Lifecycle hooks. Every before_run is matched by exactly one after_run or
	// interrupt for the same run.
	virtual void _on_before_run(float delta);
	virtual void _on_after_run(float delta);
	virtual void _on_interrupt(float delta);

	// Interrupts every behaviour-tree child that still has an active run.
	void _interrupt_active_children();
	// Interrupts every behaviour-tree child with an active run except p_keep.
	void _interrupt_other_active_children(const NNBTNodes *p_keep);

	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

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

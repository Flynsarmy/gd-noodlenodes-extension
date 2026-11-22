#pragma once

#include "../agent_behaviours/sensors.h"
#include "../debugger/blackboard_watch.h"
#include "../debugger/debug_root.h"
#include "../host.h"
#include "../root_context.h"
#include "../tick_scheduler.h"
#include "blackboard.h"
#include "nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <vector>

namespace godot {

class NNBTRoot : public NNBTNodes {
	GDCLASS(NNBTRoot, NNBTNodes)

private:
	NNRootContext _root_context;

	NNTickScheduler _tick_scheduler;
	NNHostedRoot _hosted_root;
#ifdef DEBUG_ENABLED
	NNDebugRoot _debug_root;
	NNBlackboardDebugWatch _debug_blackboard_watch;
	int64_t _debug_tick_count;
	// The last node the most recent tick reached, stored as an ObjectID so a
	// freed node is detected instead of dereferenced.
	ObjectID _debug_last_leaf_id;
#endif
	// Monotonic tree time. It is never reset, so recorded cooldown start times
	// stay in the past. Double so a long session keeps the precision of the
	// per-frame deltas.
	double _elapsed_time;
	// The deepest node on the active path after the last tick. It is stored as
	// an ObjectID so a freed node is detected instead of dereferenced.
	ObjectID _running_action_id;
	// The enabled behaviour-tree child driven by the active run, if any. It is
	// stored as an ObjectID so a freed child is detected instead of dereferenced.
	ObjectID _ticked_child_id;

	void _on_scene_tree_process_frame();
	void _on_scene_tree_physics_frame();
	bool _auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due);
	void _update_running_action(Status p_result);
	ObjectID _find_active_descendant_id(NNBTNodes *p_node) const;

	// Child structure helpers.
	void _refresh_child_sensors();
	void _reconcile_active_child();

#ifdef DEBUG_ENABLED
	uint64_t _total_tick_usec;
#endif
protected:
	static void _bind_methods();

	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

	std::vector<NNSensors *> _child_sensors;
	unsigned int _num_child_sensors;

public:
	enum ProcessThread {
		IDLE = NNTickScheduler::IDLE,
		PHYSICS = NNTickScheduler::PHYSICS,
		MANUAL = NNTickScheduler::MANUAL,
	};

	NNBTRoot();
	~NNBTRoot();

	// Getters and setters for attributes.

	bool is_root() const override { return true; }

	NNHostedRoot *get_hosted_root() override { return &_hosted_root; }
#ifdef DEBUG_ENABLED
	NNDebugRoot *get_debug_root() override { return &_debug_root; }
	NNBlackboardDebugWatch *get_debug_blackboard_watch() override { return &_debug_blackboard_watch; }
	Dictionary get_debug_snapshot() const override;
	int64_t get_debug_tick_count() const { return _debug_tick_count; }
	// Called by the node wrapper on every tick, so the snapshot can report the
	// node the root's most recent tick reached.
	void _debug_note_ticked(NNBTNodes *p_node);
	// The last node the most recent tick reached, resolved through ObjectDB.
	NNBTNodes *peek_last_leaf() const;
#endif

	void set_assigned_blackboard(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_assigned_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;

	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;
	void set_process_thread(int p_process_thread);
	int get_process_thread() const;

	// Shared body of the SceneTree frame-signal handlers, and the deterministic
	// driver for tests and custom schedulers. Returns true when this call
	// actually ticked the tree.
	bool auto_tick_step(int p_process_thread, double p_delta);

	// The deepest node on the active path after the last tick, or null when
	// nothing is active. Resolved by ObjectID, so a freed node yields null.
	NNBTNodes *get_running_action() const;

	// The total delta the tree has been ticked with since it was created.
	double get_elapsed_time() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.

	Status tick(float delta);

	virtual Status _tick(float delta) override;

	virtual void reset() override;

	// Godot virtuals.
	void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTRoot::ProcessThread)

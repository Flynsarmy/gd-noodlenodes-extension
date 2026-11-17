#pragma once

#include "../agent_behaviours/sensors.h"
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
	// The explicitly assigned blackboard. Null means no board was assigned, in
	// which case the private per-root fallback below is used.
	Ref<NNBlackboard> _blackboard;
	// Private per-root fallback board. It is never exposed as a property, so it
	// is never serialised and every instantiated root gets its own.
	Ref<NNBlackboard> _local_blackboard;

	// The explicit actor is stored as an ObjectID so a freed actor is detected
	// instead of being dereferenced.
	ObjectID _actor_id;
	NodePath _actor_node_path;

	// Auto-tick state. The frame counter counts eligible frame signal emissions
	// for tick_rate and is re-armed whenever the schedule changes.
	bool _auto_tick;
	int _tick_rate;
	int _process_thread;
	Variant _tick_argument;
	uint64_t _auto_tick_frame;
	// The deepest node on the active path after the last tick. It is stored as
	// an ObjectID so a freed node is detected instead of dereferenced.
	ObjectID _running_action_id;
	// The enabled behaviour-tree child driven by the active run, if any. It is
	// stored as an ObjectID so a freed child is detected instead of dereferenced.
	ObjectID _ticked_child_id;
	// The SceneTree whose frame signals are currently connected, if any. It is
	// stored as an ObjectID because get_tree() is not reliable on tree exit.
	ObjectID _process_tree_id;

	// Auto-tick helpers.
	bool _is_auto_tick_due();
	void _update_frame_connections();
	void _disconnect_frame_connections();
	void _on_scene_tree_process_frame();
	void _on_scene_tree_physics_frame();
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
	// Selects which SceneTree frame signal drives automatic ticking. MANUAL
	// connects neither signal so a custom scheduler can call the tree.
	enum ProcessThread {
		IDLE = 0,
		PHYSICS = 1,
		MANUAL = 2,
	};

	NNBTRoot();
	~NNBTRoot();

	// Getters and setters for attributes.

	void set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;

	// Auto-tick configuration.
	void set_auto_tick(bool p_auto_tick);
	bool get_auto_tick() const;
	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;
	void set_process_thread(int p_process_thread);
	int get_process_thread() const;
	void set_tick_argument(const Variant &p_tick_argument);
	Variant get_tick_argument() const;

	// Shared body of the SceneTree frame-signal handlers, and the deterministic
	// driver for tests and custom schedulers. Returns true when this call
	// actually ticked the tree.
	bool auto_tick_step(int p_process_thread, double p_delta);

	// The deepest node on the active path after the last tick, or null when
	// nothing is active. Resolved by ObjectID, so a freed node yields null.
	NNBTNodes *get_running_action() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.

	// Public tick entry point. Forwards to the lifecycle wrapper on NNBTNodes
	// so the GDScript tick signature stays unchanged.
	Status tick(Variant blackboard, float delta);

	virtual Status _tick(Variant blackboard, float delta) override;

	virtual void reset() override;

	// Godot virtuals.
	virtual void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTRoot::ProcessThread)

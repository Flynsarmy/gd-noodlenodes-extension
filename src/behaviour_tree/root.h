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

#ifdef DEBUG_ENABLED
	uint64_t _total_tick_usec;
#endif
protected:
	static void _bind_methods();

	std::vector<NNSensors *> _child_sensors;
	unsigned int _num_child_sensors;

public:
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

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.

	// Public tick entry point. Forwards to the lifecycle wrapper on NNBTNodes
	// so the GDScript tick signature stays unchanged.
	Status tick(Variant blackboard, float delta);

	virtual Status _tick(Variant blackboard, float delta) override;

	// Godot virtuals.
	virtual void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

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
	// The resource-backed blackboard is authoritative for the new blackboard
	// helpers. It always holds a valid NNBlackboard instance.
	Ref<NNBlackboard> _blackboard;

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
	NNBlackboard *get_blackboard_resource() const override;

	void set_actor(Node *p_actor);
	Node *get_actor() const override;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.

	virtual Status tick(Variant blackboard, float delta) override;

	// Godot virtuals.
	virtual void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

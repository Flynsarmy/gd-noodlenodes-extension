#pragma once

#include "../agent_behaviours/sensors.h"
#include "nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNBTRoot : public NNBTNodes {
	GDCLASS(NNBTRoot, NNBTNodes)

private:
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

#ifdef DEBUG_ENABLED
	uint64_t get_total_tick_usec() const;
	void set_total_tick_usec(uint64_t total_tick_usec);
#endif

	// Handling functions.

	// Public tick entry point. Forwards to the lifecycle wrapper on NNBTNodes
	// so the GDScript tick signature stays unchanged.
	Status tick(Variant blackboard, float delta);

	// Force-stops the whole tree. Safe to call when the tree is idle.
	void interrupt();

	virtual Status _tick(Variant blackboard, float delta) override;

	// Godot virtuals.
	virtual void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

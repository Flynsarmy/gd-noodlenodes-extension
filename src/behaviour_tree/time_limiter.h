#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTTimeLimiter : public NNBTDecoratorNodes {
	GDCLASS(NNBTTimeLimiter, NNBTDecoratorNodes)

private:
	float _time_limit;
	float _time_spent;

protected:
	static void _bind_methods();

public:
	NNBTTimeLimiter();
	~NNBTTimeLimiter();

	// Getters and setters for attributes.

	void set_time_limit(float time_limit);
	float get_time_limit() const;

	float get_time_spent() const;

	// Handling functions.

	virtual void reset_bt_node() override;
	virtual Status _tick(Variant blackboard, float delta) override;

protected:
	virtual void _on_interrupt(Variant blackboard, float delta) override;
};

} //namespace godot

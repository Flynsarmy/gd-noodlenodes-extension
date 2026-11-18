#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTLimiter : public NNBTDecoratorNodes {
	GDCLASS(NNBTLimiter, NNBTDecoratorNodes)

private:
	int _max_repeat_times;
	int _current_repeat_times;
	int _tick_result;

protected:
	static void _bind_methods();

public:
	NNBTLimiter();
	~NNBTLimiter();

	// Getters and setters for attributes.

	int get_max_repeat_times() const;
	void set_max_repeat_times(int repeat_times);

	// Handling functions.

	virtual void reset() override;

	virtual Status _tick(float delta) override;
};

} //namespace godot

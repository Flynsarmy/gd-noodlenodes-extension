#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRepeatUntil : public NNBTDecoratorNodes {
	GDCLASS(NNBTRepeatUntil, NNBTDecoratorNodes)

private:
	int _max_repeat_times;
	int _times_repeated;
	Status _expected_tick_result;

protected:
	static void _bind_methods();

	virtual void _on_before_run(float delta) override;
	virtual void _on_after_run(float delta) override;
	virtual void _on_interrupt(float delta) override;

public:
	NNBTRepeatUntil();
	~NNBTRepeatUntil();

	// Getters and setters for attributes.

	int get_max_repeat_times() const;
	void set_max_repeat_times(int max_repeat_times);
	int get_times_repeated() const;
	Status get_expected_tick_result() const;
	void set_expected_tick_result(Status expected_tick_result);

	// Handling functions.

	virtual Status _tick(float delta) override;
};

} //namespace godot

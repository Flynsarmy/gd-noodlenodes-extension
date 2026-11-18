#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRepeater : public NNBTDecoratorNodes {
	GDCLASS(NNBTRepeater, NNBTDecoratorNodes)

private:
	int _repeat_times;
	int _times_repeated;

protected:
	static void _bind_methods();

	virtual void _on_before_run(Variant blackboard, float delta) override;
	virtual void _on_after_run(Variant blackboard, float delta) override;
	virtual void _on_interrupt(Variant blackboard, float delta) override;

public:
	NNBTRepeater();
	~NNBTRepeater();

	// Getters and setters for attributes.

	int get_repeat_times() const;
	void set_repeat_times(int repeat_times);

	int get_times_repeated() const;
	void set_times_repeated(int repeat_times);

	// Handling functions.
	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot

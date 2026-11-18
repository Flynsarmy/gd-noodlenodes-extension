#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTDelayer : public NNBTDecoratorNodes {
	GDCLASS(NNBTDelayer, NNBTDecoratorNodes)

private:
	float _wait_time;
	float _time_waited;
	bool _is_delay_elapsed;

protected:
	static void _bind_methods();

public:
	NNBTDelayer();
	~NNBTDelayer();

	// Getters and setters for attributes.

	void set_wait_time(float wait_time);
	float get_wait_time() const;

	float get_time_waited() const;

	// Handling functions.

	virtual Status _tick(float delta) override;

protected:
	virtual void _on_before_run(float delta) override;
	virtual void _on_after_run(float delta) override;
	virtual void _on_interrupt(float delta) override;
};

} //namespace godot

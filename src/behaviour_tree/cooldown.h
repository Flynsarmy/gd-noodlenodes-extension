#pragma once

#include "decorator_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBTRoot;

class NNBTCooldown : public NNBTDecoratorNodes {
	GDCLASS(NNBTCooldown, NNBTDecoratorNodes)

private:
	float _cooldown_seconds;
	// The owning root's elapsed time when the current cooldown started, or
	// negative when the node is not cooling down.
	double _cooldown_start_time;

	Status _cooldown_return_value;

	NNBTRoot *_find_root() const;

protected:
	static void _bind_methods();

public:
	NNBTCooldown();
	~NNBTCooldown();

	// Getters and setters for attributes.

	void set_cooldown_seconds(float cooldown_seconds);
	float get_cooldown_seconds() const;

	float get_remaining_cooldown() const;

	void set_cooldown_return_value(Status cooldown_return_value);
	Status get_cooldown_return_value() const;

	// Handling functions.

	virtual void reset() override;
	virtual Status _tick(float delta) override;
};

} //namespace godot

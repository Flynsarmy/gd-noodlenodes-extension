#pragma once

#include "../sensor.h"

namespace godot {

class NNBehaviour;

class NNTimeSinceBehaviourSensor : public NNSensor {
	GDCLASS(NNTimeSinceBehaviourSensor, NNSensor)

private:
	ObjectID _behaviour_id;
	float _duration;

	NNBehaviour *_resolve_behaviour() const;

protected:
	static void _bind_methods();

public:
	NNTimeSinceBehaviourSensor();
	~NNTimeSinceBehaviourSensor();

	// Handling functions.

	virtual float evaluate_sensor_value() override;

	// Getters and setters for attributes.

	void set_behaviour(NNBehaviour *behaviour);
	NNBehaviour *get_behaviour() const;

	void set_duration(float duration);
	float get_duration() const;
};

} //namespace godot

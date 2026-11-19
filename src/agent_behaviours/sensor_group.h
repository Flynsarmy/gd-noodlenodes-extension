#pragma once

#include "sensors.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNSensorGroup : public NNSensors {
	GDCLASS(NNSensorGroup, NNSensors)

private:
	EvaluationMethod _evaluation_method;
	bool _invert_sensor_value;

	std::vector<NNSensors *> _child_sensors;

protected:
	static void _bind_methods();

public:
	NNSensorGroup();
	~NNSensorGroup();

	// Getters and setters for attributes.

	void set_evaluation_method(EvaluationMethod evaluation_method);
	EvaluationMethod get_evaluation_method() const;

	void set_invert_sensor_value(bool invert_sensor_value);
	bool get_invert_sensor_value() const;

	// Handling functions.

	virtual float evaluate_sensor_value() override;

	// Godot virtuals.
	void _notification(int p_what);
};

} //namespace godot

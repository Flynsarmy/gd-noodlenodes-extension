#pragma once

#include "../sensor.h"
#include "distance_vector_sensor.h"

namespace godot {

class NNDistanceVector3Sensor : public NNSensor {
	GDCLASS(NNDistanceVector3Sensor, NNSensor)

private:
	DistanceVectorSensorCore<Vector3> _core;

protected:
	static void _bind_methods();

public:
	NNDistanceVector3Sensor();
	~NNDistanceVector3Sensor();

	// Handling functions.

	virtual float evaluate_sensor_value() override;

	// Getters and setters for attributes.

	// Configuration values.

	void set_to_vector3(Vector3 to);
	Vector3 get_to_vector3() const;

	void set_from_vector3(Vector3 from);
	Vector3 get_from_vector3() const;

	void set_max_distance(float max_distance);
	float get_max_distance() const;

	void set_is_distance_calculated(bool is_distance_calculated);
	bool get_is_distance_calculated() const;

	void set_is_direction_vector_calculated(bool is_direction_vector_calculated);
	bool get_is_direction_vector_calculated() const;

	// Debugging / current values.

	void set_from_to_vector3(Vector3 from_to);
	Vector3 get_from_to_vector3() const;

	void set_direction_vector3(Vector3 direction);
	Vector3 get_direction_vector3() const;

	void set_distance(float distance);
	float get_distance() const;

	void set_distance_squared(float distance_squared);
	float get_distance_squared() const;
};

} //namespace godot

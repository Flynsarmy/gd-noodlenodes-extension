#pragma once

#include "../sensor.h"
#include "range_normalizer.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

class NNBlackboardSensor : public NNSensor {
	GDCLASS(NNBlackboardSensor, NNSensor)

private:
	String _key;
	float _default_value;
	NNRangeNormalizer _normalizer;

	float _read_value() const;

protected:
	static void _bind_methods();

public:
	NNBlackboardSensor();
	~NNBlackboardSensor();

	// Handling functions.

	virtual float evaluate_sensor_value() override;

	// Getters and setters for attributes.

	void set_key(const String &p_key);
	String get_key() const;

	void set_default_value(float p_default_value);
	float get_default_value() const;

	void set_range_min_value(float p_range_min_value);
	float get_range_min_value() const;

	void set_range_max_value(float p_range_max_value);
	float get_range_max_value() const;
};

} //namespace godot

#pragma once

#include <godot_cpp/core/math.hpp>

namespace godot {

template <typename TVector>
class DistanceVectorSensorCore {
public:
	DistanceVectorSensorCore() {
		distance = 0.0f;
		distance_squared = 0.0f;
		max_distance = 100.0f;
		_recalculate_max_distance();

		is_distance_calculated = false;
		is_direction_vector_calculated = false;
	}

	float evaluate() {
		from_to_vector = from_vector - to_vector;
		distance_squared = from_to_vector.length_squared();
		if (is_distance_calculated || is_direction_vector_calculated) {
			distance = Math::sqrt(distance_squared);
		}
		if (is_direction_vector_calculated) {
			direction_vector = distance > 0.0f ? from_to_vector / distance : TVector();
		}
		return distance_squared * one_over_max_distance_squared;
	}

	void set_max_distance(float p_max_distance) {
		max_distance = p_max_distance;
		_recalculate_max_distance();
	}

	TVector from_vector;
	TVector to_vector;
	TVector from_to_vector;
	TVector direction_vector;
	float distance;
	float distance_squared;
	float max_distance;
	float max_distance_squared;
	float one_over_max_distance_squared;
	bool is_distance_calculated;
	bool is_direction_vector_calculated;

private:
	void _recalculate_max_distance() {
		max_distance_squared = max_distance * max_distance;
		one_over_max_distance_squared = 1.0f / max_distance_squared;
	}
};

} //namespace godot

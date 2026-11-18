#pragma once

#include <godot_cpp/core/math.hpp>

namespace godot {

class NNRangeNormalizer {
public:
	NNRangeNormalizer();

	void set_bounds(float p_min, float p_max);
	float get_min() const;
	float get_max() const;

	float clamp(float p_value) const;
	float normalize(float p_value) const;

private:
	float _min;
	float _max;
	float _one_over_length;

	void _recalculate();
};

inline NNRangeNormalizer::NNRangeNormalizer() :
		_min(0.0f),
		_max(100.0f),
		_one_over_length(0.0f) {
	_recalculate();
}

inline void NNRangeNormalizer::set_bounds(float p_min, float p_max) {
	_min = p_min;
	_max = p_max;
	_recalculate();
}

inline float NNRangeNormalizer::get_min() const { return _min; }
inline float NNRangeNormalizer::get_max() const { return _max; }

inline float NNRangeNormalizer::clamp(float p_value) const {
	if (p_value < _min) {
		return _min;
	}
	if (p_value > _max) {
		return _max;
	}
	return p_value;
}

inline float NNRangeNormalizer::normalize(float p_value) const {
	// A zero reciprocal marks a degenerate or non-finite range.
	if (_one_over_length == 0.0f) {
		return 0.0f;
	}
	const float normalized = (p_value - _min) * _one_over_length;
	if (!Math::is_finite(normalized)) {
		return 0.0f;
	}
	if (normalized < 0.0f) {
		return 0.0f;
	}
	if (normalized > 1.0f) {
		return 1.0f;
	}
	return normalized;
}

inline void NNRangeNormalizer::_recalculate() {
	const float length = _max - _min;
	if (length > 0.0f && Math::is_finite(length)) {
		const float one_over_length = 1.0f / length;
		_one_over_length = Math::is_finite(one_over_length) ? one_over_length : 0.0f;
	} else {
		_one_over_length = 0.0f;
	}
}

} //namespace godot

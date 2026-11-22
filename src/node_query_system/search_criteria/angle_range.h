#pragma once

#include "activation_curve.h"

#include <godot_cpp/core/math.hpp>

namespace godot {

// Shared angle window for the angle criteria. The reference direction and the
// node type stay in the criterion that owns them.
class NNAngleRange {
public:
	NNAngleRange(float p_min_degrees, float p_max_degrees);

	void initialize(bool p_fix_degenerate_range);

	void set_min_degrees(float p_min_degrees);
	void set_max_degrees(float p_max_degrees);

	float get_min_degrees() const;
	float get_max_degrees() const;

	bool filters(float p_angle) const;
	float score(float p_angle) const;

private:
	float _min_degrees;
	float _max_degrees;
	float _min_radians;
	float _max_radians;
	float _one_over_span_radians;

	void _recalculate_span();
};

inline NNAngleRange::NNAngleRange(float p_min_degrees, float p_max_degrees) :
		_min_degrees(p_min_degrees),
		_max_degrees(p_max_degrees),
		_min_radians(Math::deg_to_rad(p_min_degrees)),
		_max_radians(Math::deg_to_rad(p_max_degrees)) {
	_recalculate_span();
}

inline void NNAngleRange::initialize(bool p_fix_degenerate_range) {
	if (p_fix_degenerate_range && _max_degrees <= _min_degrees) {
		_max_degrees = _min_degrees + 1.0f;
		if (_max_degrees > 180.0f) {
			_max_degrees = 180.0f;
			_min_degrees = 179.0f;
		}
	}
	_min_radians = Math::deg_to_rad(_min_degrees);
	_max_radians = Math::deg_to_rad(_max_degrees);
	_recalculate_span();
}

inline void NNAngleRange::set_min_degrees(float p_min_degrees) {
	if (p_min_degrees < -180.0f) {
		return;
	}
	_min_degrees = p_min_degrees;
	_min_radians = Math::deg_to_rad(_min_degrees);
	_recalculate_span();
}

inline void NNAngleRange::set_max_degrees(float p_max_degrees) {
	if (p_max_degrees > 180.0f) {
		return;
	}
	_max_degrees = p_max_degrees;
	_max_radians = Math::deg_to_rad(_max_degrees);
	_recalculate_span();
}

inline float NNAngleRange::get_min_degrees() const { return _min_degrees; }
inline float NNAngleRange::get_max_degrees() const { return _max_degrees; }

inline bool NNAngleRange::filters(float p_angle) const {
	return p_angle < _min_radians || p_angle > _max_radians;
}

inline float NNAngleRange::score(float p_angle) const {
	if (p_angle >= _max_radians) {
		return 1.0f;
	}
	if (p_angle <= _min_radians) {
		return 0.0f;
	}
	return (p_angle - _min_radians) * _one_over_span_radians;
}

inline void NNAngleRange::_recalculate_span() {
	const float span_radians = _max_radians - _min_radians;
	_one_over_span_radians = 1.0f / span_radians;
}

inline void apply_angle_range(const NNAngleRange &p_range, bool p_use_for_filtering, bool p_use_for_scoring, const NNActivationCurveSampler &p_activation_curve, float p_angle, bool &r_filter_out, float &r_score) {
	bool is_filtered = false;
	float score = 1.0f;
	if (p_use_for_filtering) {
		is_filtered = p_range.filters(p_angle);
	}
	if (p_use_for_scoring) {
		score = p_activation_curve.sample(p_range.score(p_angle));
	}
	r_filter_out = is_filtered;
	r_score = score;
}

} //namespace godot

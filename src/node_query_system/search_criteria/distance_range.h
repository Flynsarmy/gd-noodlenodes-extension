#pragma once

#include "activation_curve.h"

namespace godot {

// Shared range maths for the distance criteria. The criterion keeps ownership
// of whatever position it measures from, so only the distance limits and the
// score mapping live here.
class NNDistanceRange {
public:
	NNDistanceRange();

	void set_min_distance(float p_min_distance);
	void set_max_distance(float p_max_distance);

	float get_min_distance() const;
	float get_max_distance() const;

	bool filters(float p_distance_squared) const;
	float score(float p_distance_squared) const;

private:
	float _min_distance;
	float _max_distance;
	float _min_distance_squared;
	float _max_distance_squared;
	float _one_over_span_length;

	void _recalculate_span();
};

inline NNDistanceRange::NNDistanceRange() :
		_min_distance(0.0f),
		_max_distance(100.0f),
		_min_distance_squared(0.0f),
		_max_distance_squared(_max_distance * _max_distance) {
	_recalculate_span();
}

inline void NNDistanceRange::set_min_distance(float p_min_distance) {
	if (p_min_distance < 0.0f || p_min_distance >= _max_distance) {
		return;
	}
	_min_distance = p_min_distance;
	_min_distance_squared = _min_distance * _min_distance;
	_recalculate_span();
}

inline void NNDistanceRange::set_max_distance(float p_max_distance) {
	if (p_max_distance <= _min_distance) {
		return;
	}
	_max_distance = p_max_distance;
	_max_distance_squared = _max_distance * _max_distance;
	_recalculate_span();
}

inline float NNDistanceRange::get_min_distance() const { return _min_distance; }
inline float NNDistanceRange::get_max_distance() const { return _max_distance; }

inline bool NNDistanceRange::filters(float p_distance_squared) const {
	return p_distance_squared < _min_distance_squared || p_distance_squared > _max_distance_squared;
}

inline float NNDistanceRange::score(float p_distance_squared) const {
	if (p_distance_squared >= _max_distance_squared) {
		return 1.0f;
	}
	if (p_distance_squared <= _min_distance_squared) {
		return 0.0f;
	}
	return (p_distance_squared - _min_distance_squared) * _one_over_span_length;
}

inline void NNDistanceRange::_recalculate_span() {
	const float span_length = _max_distance_squared - _min_distance_squared;
	_one_over_span_length = 1.0f / span_length;
}

inline void apply_distance_range(const NNDistanceRange &p_range, bool p_use_for_filtering, bool p_use_for_scoring, const NNActivationCurveSampler &p_activation_curve, float p_distance_squared, bool &r_filter_out, float &r_score) {
	bool is_filtered = false;
	float score = 1.0f;
	if (p_use_for_filtering) {
		is_filtered = p_range.filters(p_distance_squared);
	}
	if (p_use_for_scoring) {
		score = p_activation_curve.sample(p_range.score(p_distance_squared));
	}
	r_filter_out = is_filtered;
	r_score = score;
}

} //namespace godot

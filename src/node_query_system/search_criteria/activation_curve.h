#pragma once

#include "../../response_curve.h"
#include <godot_cpp/classes/curve.hpp>

namespace godot {

// Resolves the curve type up front: worker threads must not cast Objects.
class NNActivationCurveSampler {
public:
	NNActivationCurveSampler() = default;
	explicit NNActivationCurveSampler(const Ref<Resource> &p_curve) :
			_curve(p_curve), _response_curve(p_curve) {}

	float sample(float p_value) const {
		if (_curve.is_valid()) {
			return _curve->sample(p_value);
		}
		if (_response_curve.is_valid()) {
			return _response_curve->sample(p_value);
		}
		return p_value;
	}

private:
	Ref<Curve> _curve;
	Ref<NNResponseCurve> _response_curve;
};

} //namespace godot

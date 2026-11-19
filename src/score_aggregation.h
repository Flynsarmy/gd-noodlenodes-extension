#pragma once

#include "noodle_nodes.h"

namespace godot {

// Accumulates child scores with NoodleNodes::EvaluationMethod. add() reports
// when the accumulated value is final; further calls keep that value and
// return true so the caller can stop evaluating children or keep feeding them.
class ScoreAggregation {
public:
	explicit ScoreAggregation(NoodleNodes::EvaluationMethod p_evaluation_method) :
			_evaluation_method(p_evaluation_method), _result(0.0f), _count(0), _final(false) {}

	bool add(float p_value) {
		if (_final) {
			return true;
		}
		switch (_evaluation_method) {
			case NoodleNodes::EVALUATION_MIN:
				if (_count == 0 || p_value < _result) {
					_result = p_value;
				}
				break;
			case NoodleNodes::EVALUATION_MAX:
				if (_count == 0 || p_value > _result) {
					_result = p_value;
				}
				break;
			case NoodleNodes::EVALUATION_MULTIPLY:
				_result = _count == 0 ? p_value : _result * p_value;
				_final = _result == 0.0f;
				break;
			case NoodleNodes::EVALUATION_FIRST_NON_ZERO:
				if (p_value > 0.0f) {
					_result = p_value;
					_final = true;
				}
				break;
			default:
				_result += p_value;
				break;
		}
		++_count;
		return _final;
	}

	float result() const {
		if (_evaluation_method == NoodleNodes::EVALUATION_MEAN && _count > 0) {
			return _result / (float)_count;
		}
		return _result;
	}

private:
	NoodleNodes::EvaluationMethod _evaluation_method;
	float _result;
	unsigned int _count;
	bool _final;
};

} // namespace godot

#pragma once

#include "activation_curve.h"

namespace godot {

// Every dot product criterion declares its own filtering rule enum, but they
// all share these enumerators, so the rule can be applied generically.
template <typename FilteringRuleT>
inline bool filter_dot_product(float p_dot_product, float p_filtering_value, int p_filtering_rule) {
	switch (p_filtering_rule) {
		case static_cast<int>(FilteringRuleT::LessThan):
			return p_dot_product < p_filtering_value;
		case static_cast<int>(FilteringRuleT::LessOrEqual):
			return p_dot_product <= p_filtering_value;
		case static_cast<int>(FilteringRuleT::Equal):
			return p_dot_product == p_filtering_value;
		case static_cast<int>(FilteringRuleT::MoreOrEqual):
			return p_dot_product >= p_filtering_value;
		default:
			return p_dot_product > p_filtering_value;
	}
}

inline float score_dot_product(float p_dot_product) {
	return p_dot_product * 0.5f + 0.5f;
}

template <typename FilteringRuleT>
inline void apply_dot_product(bool p_use_for_filtering, bool p_use_for_scoring, const NNActivationCurveSampler &p_activation_curve, float p_dot_product, float p_filtering_value, int p_filtering_rule, bool &r_filter_out, float &r_score) {
	bool is_filtered = false;
	float score = 1.0f;
	if (p_use_for_filtering) {
		is_filtered = filter_dot_product<FilteringRuleT>(p_dot_product, p_filtering_value, p_filtering_rule);
	}
	if (p_use_for_scoring) {
		score = p_activation_curve.sample(score_dot_product(p_dot_product));
	}
	r_filter_out = is_filtered;
	r_score = score;
}

} //namespace godot

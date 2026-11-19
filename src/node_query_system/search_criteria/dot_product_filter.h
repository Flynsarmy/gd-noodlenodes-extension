#pragma once

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

} //namespace godot

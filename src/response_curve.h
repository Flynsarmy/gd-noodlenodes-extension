#pragma once

#include <godot_cpp/classes/curve.hpp>
#include <godot_cpp/classes/resource.hpp>

namespace godot {

class NNResponseCurve : public Resource {
	GDCLASS(NNResponseCurve, Resource)

public:
	enum CurveType {
		CURVE_LINEAR = 0,
		CURVE_POLYNOMIAL = 1,
		CURVE_EXPONENTIAL = 2,
		CURVE_LOGISTIC = 3,
		CURVE_LOGIT = 4,
		CURVE_NORMAL = 5,
		CURVE_SINE = 6,
		CURVE_STEP = 7,
	};

private:
	CurveType _curve_type = CURVE_LINEAR;
	float _slope = 1.0f;
	float _exponent = 2.0f;
	float _x_shift = 0.0f;
	float _y_shift = 0.0f;
	bool _invert = false;
	mutable Ref<Curve> _preview;

	void _on_parameters_changed();
	void _bake_preview() const;

protected:
	static void _bind_methods();
	void _validate_property(PropertyInfo &p_property) const;

public:
	NNResponseCurve();
	~NNResponseCurve();

	void set_curve_type(CurveType p_curve_type);
	CurveType get_curve_type() const;
	void set_slope(float p_slope);
	float get_slope() const;
	void set_exponent(float p_exponent);
	float get_exponent() const;
	void set_x_shift(float p_x_shift);
	float get_x_shift() const;
	void set_y_shift(float p_y_shift);
	float get_y_shift() const;
	void set_invert(bool p_invert);
	bool get_invert() const;
	Ref<Curve> get_preview() const;

	float sample(float p_x) const;

	static bool is_activation_curve(const Ref<Resource> &p_resource);
	static float sample_activation_curve(const Ref<Resource> &p_resource, float p_x, float p_fallback);
};

} //namespace godot

VARIANT_ENUM_CAST(NNResponseCurve::CurveType);

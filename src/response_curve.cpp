#include "response_curve.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

namespace {
constexpr int PREVIEW_POINT_COUNT = 65;
}

void NNResponseCurve::_bind_methods() {
	BIND_ENUM_CONSTANT(CURVE_LINEAR);
	BIND_ENUM_CONSTANT(CURVE_POLYNOMIAL);
	BIND_ENUM_CONSTANT(CURVE_EXPONENTIAL);
	BIND_ENUM_CONSTANT(CURVE_LOGISTIC);
	BIND_ENUM_CONSTANT(CURVE_LOGIT);
	BIND_ENUM_CONSTANT(CURVE_NORMAL);
	BIND_ENUM_CONSTANT(CURVE_SINE);
	BIND_ENUM_CONSTANT(CURVE_STEP);

	ClassDB::bind_method(D_METHOD("set_curve_type", "curve_type"), &NNResponseCurve::set_curve_type);
	ClassDB::bind_method(D_METHOD("get_curve_type"), &NNResponseCurve::get_curve_type);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "curve_type", PROPERTY_HINT_ENUM, "Linear,Polynomial,Exponential,Logistic,Logit,Normal,Sine,Step", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NNResponseCurve.CurveType"), "set_curve_type", "get_curve_type");

	ClassDB::bind_method(D_METHOD("set_slope", "slope"), &NNResponseCurve::set_slope);
	ClassDB::bind_method(D_METHOD("get_slope"), &NNResponseCurve::get_slope);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "slope", PROPERTY_HINT_RANGE, "-2,2,0.01,or_less,or_greater"), "set_slope", "get_slope");

	ClassDB::bind_method(D_METHOD("set_exponent", "exponent"), &NNResponseCurve::set_exponent);
	ClassDB::bind_method(D_METHOD("get_exponent"), &NNResponseCurve::get_exponent);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "exponent", PROPERTY_HINT_RANGE, "-10,10,0.01,or_less,or_greater"), "set_exponent", "get_exponent");

	ClassDB::bind_method(D_METHOD("set_x_shift", "x_shift"), &NNResponseCurve::set_x_shift);
	ClassDB::bind_method(D_METHOD("get_x_shift"), &NNResponseCurve::get_x_shift);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "x_shift", PROPERTY_HINT_RANGE, "-1,1,0.01,or_less,or_greater"), "set_x_shift", "get_x_shift");

	ClassDB::bind_method(D_METHOD("set_y_shift", "y_shift"), &NNResponseCurve::set_y_shift);
	ClassDB::bind_method(D_METHOD("get_y_shift"), &NNResponseCurve::get_y_shift);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "y_shift", PROPERTY_HINT_RANGE, "-1,1,0.01,or_less,or_greater"), "set_y_shift", "get_y_shift");

	ClassDB::bind_method(D_METHOD("set_invert", "invert"), &NNResponseCurve::set_invert);
	ClassDB::bind_method(D_METHOD("get_invert"), &NNResponseCurve::get_invert);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "invert", PROPERTY_HINT_NONE), "set_invert", "get_invert");

	ClassDB::bind_method(D_METHOD("get_preview"), &NNResponseCurve::get_preview);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "preview", PROPERTY_HINT_RESOURCE_TYPE, "Curve", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY), "", "get_preview");

	ClassDB::bind_method(D_METHOD("sample", "x"), &NNResponseCurve::sample);
}

// Constructor and destructor.

NNResponseCurve::NNResponseCurve() {
}

NNResponseCurve::~NNResponseCurve() {
}

// Getters and setters.

void NNResponseCurve::set_curve_type(CurveType p_curve_type) {
	if (_curve_type == p_curve_type) {
		return;
	}
	_curve_type = p_curve_type;
	notify_property_list_changed();
	_on_parameters_changed();
}

NNResponseCurve::CurveType NNResponseCurve::get_curve_type() const {
	return _curve_type;
}

void NNResponseCurve::set_slope(float p_slope) {
	if (_slope == p_slope) {
		return;
	}
	_slope = p_slope;
	_on_parameters_changed();
}

float NNResponseCurve::get_slope() const {
	return _slope;
}

void NNResponseCurve::set_exponent(float p_exponent) {
	if (_exponent == p_exponent) {
		return;
	}
	_exponent = p_exponent;
	_on_parameters_changed();
}

float NNResponseCurve::get_exponent() const {
	return _exponent;
}

void NNResponseCurve::set_x_shift(float p_x_shift) {
	if (_x_shift == p_x_shift) {
		return;
	}
	_x_shift = p_x_shift;
	_on_parameters_changed();
}

float NNResponseCurve::get_x_shift() const {
	return _x_shift;
}

void NNResponseCurve::set_y_shift(float p_y_shift) {
	if (_y_shift == p_y_shift) {
		return;
	}
	_y_shift = p_y_shift;
	_on_parameters_changed();
}

float NNResponseCurve::get_y_shift() const {
	return _y_shift;
}

void NNResponseCurve::set_invert(bool p_invert) {
	if (_invert == p_invert) {
		return;
	}
	_invert = p_invert;
	_on_parameters_changed();
}

bool NNResponseCurve::get_invert() const {
	return _invert;
}

Ref<Curve> NNResponseCurve::get_preview() const {
	if (_preview.is_null()) {
		_preview.instantiate();
		_bake_preview();
	}
	return _preview;
}

void NNResponseCurve::_on_parameters_changed() {
	// A new Curve rather than an in-place rebake: the inspector caches the preview per Curve object.
	_preview.unref();
	emit_changed();
}

void NNResponseCurve::_bake_preview() const {
	_preview->clear_points();
	for (int i = 0; i < PREVIEW_POINT_COUNT; i++) {
		const float x = (float)i / (float)(PREVIEW_POINT_COUNT - 1);
		_preview->add_point(Vector2(x, sample(x)), 0.0f, 0.0f, Curve::TANGENT_LINEAR, Curve::TANGENT_LINEAR);
	}
}

// Godot virtuals.

void NNResponseCurve::_validate_property(PropertyInfo &p_property) const {
	// Hidden values are kept, so switching curve types back restores them.
	const bool ignored = _curve_type == CURVE_LINEAR || _curve_type == CURVE_STEP;
	if (ignored && p_property.name == StringName("exponent")) {
		p_property.usage &= ~PROPERTY_USAGE_EDITOR;
	}
}

// Handling methods.

float NNResponseCurve::sample(float p_x) const {
	const float x = CLAMP(p_x, 0.0f, 1.0f);
	const float u = x - _x_shift;
	float y = 0.0f;

	switch (_curve_type) {
		case CURVE_LINEAR:
			y = _slope * u + _y_shift;
			break;
		case CURVE_POLYNOMIAL:
			y = _slope * Math::pow(u, _exponent) + _y_shift;
			break;
		case CURVE_EXPONENTIAL:
			if (Math::abs(_exponent) < 1e-4f) {
				y = _slope * u + _y_shift;
			} else {
				y = _slope * (Math::exp(_exponent * u) - 1.0f) / (Math::exp(_exponent) - 1.0f) + _y_shift;
			}
			break;
		case CURVE_LOGISTIC:
			y = _slope / (1.0f + Math::exp(-5.0f * _exponent * (u - 0.5f))) + _y_shift;
			break;
		case CURVE_LOGIT: {
			const float v = CLAMP(u, 1e-4f, 1.0f - 1e-4f);
			y = _slope * (0.5f + Math::log(v / (1.0f - v)) / (5.0f * _exponent)) + _y_shift;
			break;
		}
		case CURVE_NORMAL: {
			const float d = u - 0.5f;
			y = _slope * Math::exp(-10.0f * _exponent * d * d) + _y_shift;
			break;
		}
		case CURVE_SINE:
			y = _slope * 0.5f * (1.0f - Math::cos(Math::PI * _exponent * u)) + _y_shift;
			break;
		case CURVE_STEP:
			y = (u >= 0.5f ? _slope : 0.0f) + _y_shift;
			break;
	}

	if (!Math::is_finite(y)) {
		y = 0.0f;
	}
	y = CLAMP(y, 0.0f, 1.0f);
	if (_invert) {
		y = 1.0f - y;
	}
	return y;
}

bool NNResponseCurve::is_activation_curve(const Ref<Resource> &p_resource) {
	if (p_resource.is_null()) {
		return false;
	}
	return Object::cast_to<Curve>(p_resource.ptr()) != nullptr || Object::cast_to<NNResponseCurve>(p_resource.ptr()) != nullptr;
}

float NNResponseCurve::sample_activation_curve(const Ref<Resource> &p_resource, float p_x, float p_fallback) {
	if (p_resource.is_null()) {
		return p_fallback;
	}
	if (Curve *curve = Object::cast_to<Curve>(p_resource.ptr())) {
		return curve->sample(p_x);
	}
	if (NNResponseCurve *response_curve = Object::cast_to<NNResponseCurve>(p_resource.ptr())) {
		return response_curve->sample(p_x);
	}
	return p_fallback;
}

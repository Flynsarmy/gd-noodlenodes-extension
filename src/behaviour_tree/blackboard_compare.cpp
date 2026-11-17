#include "blackboard_compare.h"

#include "blackboard.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

namespace {

Variant::Operator _to_variant_operator(int p_operator) {
	switch (p_operator) {
		case NNBTBlackboardCompare::NOT_EQUAL:
			return Variant::OP_NOT_EQUAL;
		case NNBTBlackboardCompare::GREATER:
			return Variant::OP_GREATER;
		case NNBTBlackboardCompare::LESS:
			return Variant::OP_LESS;
		case NNBTBlackboardCompare::GREATER_EQUAL:
			return Variant::OP_GREATER_EQUAL;
		case NNBTBlackboardCompare::LESS_EQUAL:
			return Variant::OP_LESS_EQUAL;
		case NNBTBlackboardCompare::EQUAL:
		default:
			return Variant::OP_EQUAL;
	}
}

} // namespace

// Method binds.

void NNBTBlackboardCompare::_bind_methods() {
	BIND_ENUM_CONSTANT(EQUAL);
	BIND_ENUM_CONSTANT(NOT_EQUAL);
	BIND_ENUM_CONSTANT(GREATER);
	BIND_ENUM_CONSTANT(LESS);
	BIND_ENUM_CONSTANT(GREATER_EQUAL);
	BIND_ENUM_CONSTANT(LESS_EQUAL);

	ClassDB::bind_method(D_METHOD("set_key", "key"), &NNBTBlackboardCompare::set_key);
	ClassDB::bind_method(D_METHOD("get_key"), &NNBTBlackboardCompare::get_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "key"), "set_key", "get_key");

	ClassDB::bind_method(D_METHOD("set_value", "value"), &NNBTBlackboardCompare::set_value);
	ClassDB::bind_method(D_METHOD("get_value"), &NNBTBlackboardCompare::get_value);
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "value", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_NIL_IS_VARIANT), "set_value", "get_value");

	ClassDB::bind_method(D_METHOD("set_operator", "operator"), &NNBTBlackboardCompare::set_operator);
	ClassDB::bind_method(D_METHOD("get_operator"), &NNBTBlackboardCompare::get_operator);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "operator", PROPERTY_HINT_ENUM, "Equal:0,NotEqual:1,Greater:2,Less:3,GreaterEqual:4,LessEqual:5"), "set_operator", "get_operator");
}

// Constructor and destructor.

NNBTBlackboardCompare::NNBTBlackboardCompare() {
	_key = "";
	_operator = Operator::EQUAL;
	_has_reported_configuration_error = false;
}

NNBTBlackboardCompare::~NNBTBlackboardCompare() {
}

// Getters and Setters.

void NNBTBlackboardCompare::set_key(const String &p_key) {
	_key = p_key;
}

String NNBTBlackboardCompare::get_key() const {
	return _key;
}

void NNBTBlackboardCompare::set_value(const Variant &p_value) {
	_value = p_value;
}

Variant NNBTBlackboardCompare::get_value() const {
	return _value;
}

void NNBTBlackboardCompare::set_operator(int p_operator) {
	if (p_operator < Operator::EQUAL || p_operator > Operator::LESS_EQUAL) {
		ERR_PRINT(vformat("NNBTBlackboardCompare::set_operator(): received %d; the valid range is %d to %d. Keeping the previous operator.", p_operator, (int)Operator::EQUAL, (int)Operator::LESS_EQUAL));
		return;
	}
	_operator = p_operator;
}

int NNBTBlackboardCompare::get_operator() const {
	return _operator;
}

// Handling methods.

void NNBTBlackboardCompare::_report_configuration_error(const String &p_reason) {
	if (_has_reported_configuration_error) {
		return;
	}
	_has_reported_configuration_error = true;
	String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
	ERR_PRINT(vformat("%s node '%s' (%s) %s; returning FAILURE.", get_class(), get_name(), node_location, p_reason));
}

NNBTNodes::Status NNBTBlackboardCompare::tick(Variant blackboard, float delta) {
	set_internal_status(BT_INTERNAL_STATUS_TICKED);

	Status result = Status::FAILURE;
	NNBlackboard *board = get_blackboard_resource();
	if (_key.is_empty()) {
		_report_configuration_error("requires a non-empty blackboard key");
	} else if (board == nullptr) {
		_report_configuration_error("has no NNBTRoot ancestor with a blackboard");
	} else if (!board->has_value(_key)) {
		// A missing key (or a null-valued key) simply fails the comparison.
		result = Status::FAILURE;
	} else {
		Variant comparison_result;
		bool comparison_valid = false;
		Variant::evaluate(_to_variant_operator(_operator), board->get_value(_key, Variant()), _value, comparison_result, comparison_valid);
		if (comparison_valid && comparison_result.booleanize()) {
			result = Status::SUCCESS;
		}
	}

	set_tick_result(result);
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	return result;
}

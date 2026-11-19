#include "fixed_result.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTFixedResult::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_fixed_result", "fixed_result"), &NNBTFixedResult::set_fixed_result);
	ClassDB::bind_method(D_METHOD("get_fixed_result"), &NNBTFixedResult::get_fixed_result);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "fixed_result", PROPERTY_HINT_ENUM, "Running:0,Success:1,Failure:-1"), "set_fixed_result", "get_fixed_result");
}

// Constructor and destructor.

NNBTFixedResult::NNBTFixedResult() {
	_fixed_result = Status::SUCCESS;
}

NNBTFixedResult::~NNBTFixedResult() {
}

// Getters and Setters.

void NNBTFixedResult::set_fixed_result(Status fixed_result) {
	_fixed_result = fixed_result;
}

NNBTNodes::Status NNBTFixedResult::get_fixed_result() const {
	return _fixed_result;
}

// Handling methods.

NNBTNodes::Status NNBTFixedResult::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}
		btnode->tick(delta);
		break;
	}
	return _fixed_result;
}

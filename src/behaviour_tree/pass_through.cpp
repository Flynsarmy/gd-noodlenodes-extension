#include "pass_through.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTPassThrough::_bind_methods() {
	GDVIRTUAL_BIND(on_tick, "delta");
}

// Constructor and destructor.

NNBTPassThrough::NNBTPassThrough() {
}

NNBTPassThrough::~NNBTPassThrough() {
}

// Handling methods.

NNBTNodes::Status NNBTPassThrough::_tick(float delta) {
	_report_extra_enabled_child_btnodes();

	GDVIRTUAL_CALL(on_tick, delta);

	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}

		Status child_result = btnode->tick(delta);
		return child_result;
	} //endfor child ndoes

	Status fallback_result = get_tick_result();
	return fallback_result;
}

#include "selector.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTSelector::_bind_methods() {
	// godot-cpp binds a method under the class that declares it, and the shared
	// accessors live in an unregistered base, so bind them through this class.
	ClassDB::bind_method(D_METHOD("set_reactive", "reactive"), static_cast<void (NNBTSelector::*)(bool)>(&NNBTSelector::set_reactive));
	ClassDB::bind_method(D_METHOD("get_reactive"), static_cast<bool (NNBTSelector::*)() const>(&NNBTSelector::get_reactive));
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "reactive", PROPERTY_HINT_NONE), "set_reactive", "get_reactive");
}

// Constructor and destructor.

NNBTSelector::NNBTSelector() :
		NNBTOrderedComposite(Status::SUCCESS, Status::FAILURE) {
}

NNBTSelector::~NNBTSelector() {
}

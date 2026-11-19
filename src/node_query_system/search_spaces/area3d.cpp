#include "area3d.h"
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

void NNArea3DSearchSpace::_bind_methods() {
	ADD_SUBGROUP("Configuration", "");

	ClassDB::bind_method(D_METHOD("set_area3d", "area3d"), &NNArea3DSearchSpace::set_area3d);
	ClassDB::bind_method(D_METHOD("get_area3d"), &NNArea3DSearchSpace::get_area3d);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "area3d", PROPERTY_HINT_NODE_TYPE, "Area3D"), "set_area3d", "get_area3d");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_intersecting_areas", "intersecting_areas"), &NNArea3DSearchSpace::set_intersecting_areas);
	ClassDB::bind_method(D_METHOD("get_intersecting_areas"), &NNArea3DSearchSpace::get_intersecting_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Area3D")), "set_intersecting_areas", "get_intersecting_areas");
}

void NNArea3DSearchSpace::on_area_entered(Area3D *area) {
	_core.on_area_entered(area);
}

void NNArea3DSearchSpace::on_area_exited(Area3D *area) {
	_core.on_area_exited(area);
}

// Getters and setters for attributes.

void NNArea3DSearchSpace::set_area3d(Area3D *area3d) {
	_core.set_area(area3d);
}

Area3D *NNArea3DSearchSpace::get_area3d() const {
	return _core.get_area();
}

void NNArea3DSearchSpace::set_intersecting_areas(TypedArray<Area3D> intersecting_areas) {
	_core.set_intersecting_areas(intersecting_areas);
}

TypedArray<Area3D> NNArea3DSearchSpace::get_intersecting_areas() const {
	return _core.get_intersecting_areas();
}

// Handling methods.

TypedArray<Node> NNArea3DSearchSpace::get_searchspace_nodes() const {
	return _core.get_searchspace_nodes();
}

void NNArea3DSearchSpace::_initialize_search_space() {
	_core.initialize("NNArea3DSearchSpace::_initialize_search_space() - Error, the node for the Area3D has not been set.",
			callable_mp(this, &NNArea3DSearchSpace::on_area_entered),
			callable_mp(this, &NNArea3DSearchSpace::on_area_exited));
}

void NNArea3DSearchSpace::_uninitialize_search_space() {
	_core.uninitialize(callable_mp(this, &NNArea3DSearchSpace::on_area_entered),
			callable_mp(this, &NNArea3DSearchSpace::on_area_exited));
}

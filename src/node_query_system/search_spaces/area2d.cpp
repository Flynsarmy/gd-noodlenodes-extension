#include "area2d.h"
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

void NNArea2DSearchSpace::_bind_methods() {
	ADD_SUBGROUP("Configuration", "");

	ClassDB::bind_method(D_METHOD("set_area2d", "area2D"), &NNArea2DSearchSpace::set_area2d);
	ClassDB::bind_method(D_METHOD("get_area2d"), &NNArea2DSearchSpace::get_area2d);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "area2d", PROPERTY_HINT_NODE_TYPE, "Area2D"), "set_area2d", "get_area2d");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_intersecting_areas", "intersecting_areas"), &NNArea2DSearchSpace::set_intersecting_areas);
	ClassDB::bind_method(D_METHOD("get_intersecting_areas"), &NNArea2DSearchSpace::get_intersecting_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Area2D")), "set_intersecting_areas", "get_intersecting_areas");
}

void NNArea2DSearchSpace::on_area_entered(Area2D *area) {
	_core.on_area_entered(area);
}

void NNArea2DSearchSpace::on_area_exited(Area2D *area) {
	_core.on_area_exited(area);
}

// Getters and setters for attributes.

void NNArea2DSearchSpace::set_area2d(Area2D *area2d) {
	_core.set_area(area2d);
}

Area2D *NNArea2DSearchSpace::get_area2d() const {
	return _core.get_area();
}

void NNArea2DSearchSpace::set_intersecting_areas(TypedArray<Area2D> intersecting_areas) {
	_core.set_intersecting_areas(intersecting_areas);
}

TypedArray<Area2D> NNArea2DSearchSpace::get_intersecting_areas() const {
	return _core.get_intersecting_areas();
}

// Handling methods.

TypedArray<Node> NNArea2DSearchSpace::get_searchspace_nodes() const {
	return _core.get_searchspace_nodes();
}

void NNArea2DSearchSpace::_initialize_search_space() {
	_core.initialize("NNArea2DSearchSpace::_initialize_search_space() - Error, the node for the Area2D has not been set.",
			callable_mp(this, &NNArea2DSearchSpace::on_area_entered),
			callable_mp(this, &NNArea2DSearchSpace::on_area_exited));
}

void NNArea2DSearchSpace::_uninitialize_search_space() {
	_core.uninitialize(callable_mp(this, &NNArea2DSearchSpace::on_area_entered),
			callable_mp(this, &NNArea2DSearchSpace::on_area_exited));
}

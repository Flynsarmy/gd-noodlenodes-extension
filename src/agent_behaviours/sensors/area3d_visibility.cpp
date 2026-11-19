#include "area3d_visibility.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// Method binds.

void NNArea3DVisibilitySensor::_bind_methods() {
	ADD_GROUP("Configuration", "");

	ClassDB::bind_method(D_METHOD("set_use_owner_global_position", "use_owner_global_position"), &NNArea3DVisibilitySensor::set_use_owner_global_position);
	ClassDB::bind_method(D_METHOD("get_use_owner_global_position"), &NNArea3DVisibilitySensor::get_use_owner_global_position);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_owner_global_position", PROPERTY_HINT_NONE), "set_use_owner_global_position", "get_use_owner_global_position");

	ClassDB::bind_method(D_METHOD("set_offset_vector", "offset_vector"), &NNArea3DVisibilitySensor::set_offset_vector3);
	ClassDB::bind_method(D_METHOD("get_offset_vector"), &NNArea3DVisibilitySensor::get_offset_vector3);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "offset_vector", PROPERTY_HINT_NONE), "set_offset_vector", "get_offset_vector");

	ClassDB::bind_method(D_METHOD("set_visibility_volume", "visibility_volume"), &NNArea3DVisibilitySensor::set_visibility_volume);
	ClassDB::bind_method(D_METHOD("get_visibility_volume"), &NNArea3DVisibilitySensor::get_visibility_volume);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "visibility_volume", PROPERTY_HINT_NODE_TYPE, "Area3D"), "set_visibility_volume", "get_visibility_volume");

	ClassDB::bind_method(D_METHOD("set_max_expected_entities_found", "max_expected_entities_found"), &NNArea3DVisibilitySensor::set_max_expected_entities_found);
	ClassDB::bind_method(D_METHOD("get_max_expected_entities_found"), &NNArea3DVisibilitySensor::get_max_expected_entities_found);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_expected_entities_found", PROPERTY_HINT_RANGE, "1,32,or_greater"), "set_max_expected_entities_found", "get_max_expected_entities_found");

	ADD_GROUP("Occlusion", "");

	ClassDB::bind_method(D_METHOD("set_do_occlusion_test", "do_occlusion_test"), &NNArea3DVisibilitySensor::set_do_occlusion_test);
	ClassDB::bind_method(D_METHOD("get_do_occlusion_test"), &NNArea3DVisibilitySensor::get_do_occlusion_test);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "do_occlusion_test", PROPERTY_HINT_NONE), "set_do_occlusion_test", "get_do_occlusion_test");

	ClassDB::bind_method(D_METHOD("set_collision_mask", "collision_mask"), &NNArea3DVisibilitySensor::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &NNArea3DVisibilitySensor::get_collision_mask);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");

	ClassDB::bind_method(D_METHOD("set_occlusion_test_exclusion_list", "occlusion_test_exclusion_list"), &NNArea3DVisibilitySensor::set_occlusion_test_exclusion_list);
	ClassDB::bind_method(D_METHOD("get_occlusion_test_exclusion_list"), &NNArea3DVisibilitySensor::get_occlusion_test_exclusion_list);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "occlusion_test_exclusion_list", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "RID")), "set_occlusion_test_exclusion_list", "get_occlusion_test_exclusion_list");

	ADD_GROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_from_vector", "from_vector"), &NNArea3DVisibilitySensor::set_from_vector3);
	ClassDB::bind_method(D_METHOD("get_from_vector"), &NNArea3DVisibilitySensor::get_from_vector3);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "from_vector", PROPERTY_HINT_NONE), "set_from_vector", "get_from_vector");

	ClassDB::bind_method(D_METHOD("set_num_entities_found", "num_entities_found"), &NNArea3DVisibilitySensor::set_num_entities_found);
	ClassDB::bind_method(D_METHOD("get_num_entities_found"), &NNArea3DVisibilitySensor::get_num_entities_found);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "num_entities_found", PROPERTY_HINT_RANGE, "0,32,or_greater"), "set_num_entities_found", "get_num_entities_found");

	ADD_SUBGROUP("Areas", "");

	ClassDB::bind_method(D_METHOD("set_closest_intersecting_area_index", "closest_intersecting_area_index"), &NNArea3DVisibilitySensor::set_closest_intersecting_area_index);
	ClassDB::bind_method(D_METHOD("get_closest_intersecting_area_index"), &NNArea3DVisibilitySensor::get_closest_intersecting_area_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "closest_intersecting_area_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_intersecting_area_index", "get_closest_intersecting_area_index");

	ClassDB::bind_method(D_METHOD("set_intersecting_areas", "intersecting_areas"), &NNArea3DVisibilitySensor::set_intersecting_areas);
	ClassDB::bind_method(D_METHOD("get_intersecting_areas"), &NNArea3DVisibilitySensor::get_intersecting_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Area3D")), "set_intersecting_areas", "get_intersecting_areas");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_intersecting_areas", "squared_distances_to_intersecting_areas"), &NNArea3DVisibilitySensor::set_squared_distances_to_intersecting_areas);
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_intersecting_areas"), &NNArea3DVisibilitySensor::get_squared_distances_to_intersecting_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "squared_distances_to_intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_intersecting_areas", "get_squared_distances_to_intersecting_areas");

	ClassDB::bind_method(D_METHOD("set_closest_unoccluded_area_index", "closest_unoccluded_area_index"), &NNArea3DVisibilitySensor::set_closest_unoccluded_area_index);
	ClassDB::bind_method(D_METHOD("get_closest_unoccluded_area_index"), &NNArea3DVisibilitySensor::get_closest_unoccluded_area_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "closest_unoccluded_area_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_unoccluded_area_index", "get_closest_unoccluded_area_index");

	ClassDB::bind_method(D_METHOD("set_unoccluded_areas", "unoccluded_areas"), &NNArea3DVisibilitySensor::set_unoccluded_areas);
	ClassDB::bind_method(D_METHOD("get_unoccluded_areas"), &NNArea3DVisibilitySensor::get_unoccluded_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "unoccluded_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Area3D")), "set_unoccluded_areas", "get_unoccluded_areas");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_unoccluded_areas", "squared_distances_to_unoccluded_areas"), &NNArea3DVisibilitySensor::set_squared_distances_to_unoccluded_areas);
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_unoccluded_areas"), &NNArea3DVisibilitySensor::get_squared_distances_to_unoccluded_areas);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "squared_distances_to_unoccluded_areas", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_unoccluded_areas", "get_squared_distances_to_unoccluded_areas");

	ADD_SUBGROUP("Bodies", "");

	ClassDB::bind_method(D_METHOD("set_closest_intersecting_body_index", "closest_intersecting_body_index"), &NNArea3DVisibilitySensor::set_closest_intersecting_body_index);
	ClassDB::bind_method(D_METHOD("get_closest_intersecting_body_index"), &NNArea3DVisibilitySensor::get_closest_intersecting_body_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "closest_intersecting_body_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_intersecting_body_index", "get_closest_intersecting_body_index");

	ClassDB::bind_method(D_METHOD("set_intersecting_bodies", "intersecting_bodies"), &NNArea3DVisibilitySensor::set_intersecting_bodies);
	ClassDB::bind_method(D_METHOD("get_intersecting_bodies"), &NNArea3DVisibilitySensor::get_intersecting_bodies);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "intersecting_bodies", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Node3D")), "set_intersecting_bodies", "get_intersecting_bodies");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_intersecting_bodies", "squared_distances_to_intersecting_bodies"), &NNArea3DVisibilitySensor::set_squared_distances_to_intersecting_bodies);
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_intersecting_bodies"), &NNArea3DVisibilitySensor::get_squared_distances_to_intersecting_bodies);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "squared_distances_to_intersecting_bodies", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_intersecting_bodies", "get_squared_distances_to_intersecting_bodies");

	ClassDB::bind_method(D_METHOD("set_closest_unoccluded_body_index", "closest_unoccluded_body_index"), &NNArea3DVisibilitySensor::set_closest_unoccluded_body_index);
	ClassDB::bind_method(D_METHOD("get_closest_unoccluded_body_index"), &NNArea3DVisibilitySensor::get_closest_unoccluded_body_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "closest_unoccluded_body_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_unoccluded_body_index", "get_closest_unoccluded_body_index");

	ClassDB::bind_method(D_METHOD("set_unoccluded_bodies", "unoccluded_bodies"), &NNArea3DVisibilitySensor::set_unoccluded_bodies);
	ClassDB::bind_method(D_METHOD("get_unoccluded_bodies"), &NNArea3DVisibilitySensor::get_unoccluded_bodies);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "unoccluded_bodies", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Node3D")), "set_unoccluded_bodies", "get_unoccluded_bodies");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_unoccluded_bodies", "squared_distances_to_unoccluded_bodies"), &NNArea3DVisibilitySensor::set_squared_distances_to_unoccluded_bodies);
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_unoccluded_bodies"), &NNArea3DVisibilitySensor::get_squared_distances_to_unoccluded_bodies);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "squared_distances_to_unoccluded_bodies", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_unoccluded_bodies", "get_squared_distances_to_unoccluded_bodies");
}

// Constructor and destructor.

NNArea3DVisibilitySensor::NNArea3DVisibilitySensor() {
	_visibility_volume = nullptr;
}

NNArea3DVisibilitySensor::~NNArea3DVisibilitySensor() {
}

// Godot virtuals.

// Handling functions.

void NNArea3DVisibilitySensor::_update_cache() {
	_cache = ObjectID();
	if (_visibility_volume != nullptr) {
		_cache = _visibility_volume->get_instance_id();
	}
}

void NNArea3DVisibilitySensor::initialize_sensor() {
	if (Engine::get_singleton()->is_editor_hint())
		return;

	ERR_FAIL_COND_MSG(_visibility_volume == nullptr, "NNArea3DVisibilitySensor::initialize_sensor() - Error, the visibility volume is not set.");

	// Connect to the area entered and exited signals.
	Error error_visibility_volume_on_area_entered = _visibility_volume->connect("area_entered", callable_mp(this, &NNArea3DVisibilitySensor::on_area_entered));
	Error error_visibility_volume_on_area_exited = _visibility_volume->connect("area_exited", callable_mp(this, &NNArea3DVisibilitySensor::on_area_exited));
	Error error_visibility_volume_on_body_entered = _visibility_volume->connect("body_entered", callable_mp(this, &NNArea3DVisibilitySensor::on_body_entered));
	Error error_visibility_volume_on_body_exited = _visibility_volume->connect("body_exited", callable_mp(this, &NNArea3DVisibilitySensor::on_body_exited));
}

void NNArea3DVisibilitySensor::uninitialize_sensor() {
	if (Engine::get_singleton()->is_editor_hint())
		return;
	if (_visibility_volume != nullptr) {
		_visibility_volume->disconnect("area_entered", callable_mp(this, &NNArea3DVisibilitySensor::on_area_entered));
		_visibility_volume->disconnect("area_exited", callable_mp(this, &NNArea3DVisibilitySensor::on_area_exited));
		_visibility_volume->disconnect("body_entered", callable_mp(this, &NNArea3DVisibilitySensor::on_body_entered));
		_visibility_volume->disconnect("body_exited", callable_mp(this, &NNArea3DVisibilitySensor::on_body_exited));
		_visibility_volume = nullptr;
	}
}

float NNArea3DVisibilitySensor::evaluate_sensor_value() {
	if (_visibility_volume == nullptr) {
		return get_sensor_value();
	}
	if (!UtilityFunctions::is_instance_id_valid(_cache)) {
		_visibility_volume = nullptr;
		return get_sensor_value();
	}

	if (!_core.evaluate(_visibility_volume, get_owner())) {
		return get_sensor_value();
	}

	set_sensor_value(((float)_core.num_entities_found) * _core.one_over_max_expected_entities_found);
	return get_sensor_value();
}

void NNArea3DVisibilitySensor::on_area_entered(Area3D *area) {
	_core.on_area_entered(area, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::on_area_exited(Area3D *area) {
	_core.on_area_exited(area, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::on_body_entered(Node3D *body) {
	_core.on_body_entered(body, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::on_body_exited(Node3D *body) {
	_core.on_body_exited(body, _has_sensor_value_changed);
}

// Getters and Setters.

// Configuration values.

void NNArea3DVisibilitySensor::set_use_owner_global_position(bool use_owner_global_position) {
	set_value_if_different(_core.use_owner_global_position, use_owner_global_position, _has_sensor_value_changed);
}

bool NNArea3DVisibilitySensor::get_use_owner_global_position() const {
	return _core.use_owner_global_position;
}

void NNArea3DVisibilitySensor::set_from_vector3(Vector3 from) {
	set_value_if_different(_core.from_vector, from, _has_sensor_value_changed);
}

Vector3 NNArea3DVisibilitySensor::get_from_vector3() const {
	return _core.from_vector;
}

void NNArea3DVisibilitySensor::set_offset_vector3(Vector3 offset) {
	set_value_if_different(_core.offset_vector, offset, _has_sensor_value_changed);
}

Vector3 NNArea3DVisibilitySensor::get_offset_vector3() const {
	return _core.offset_vector;
}

void NNArea3DVisibilitySensor::set_visibility_volume(Area3D *visibility_volume) {
	_has_sensor_value_changed = _has_sensor_value_changed || (_visibility_volume != visibility_volume);
	_visibility_volume = visibility_volume;
	_update_cache();
}

Area3D *NNArea3DVisibilitySensor::get_visibility_volume() const {
	return _visibility_volume;
}

void NNArea3DVisibilitySensor::set_do_occlusion_test(bool do_occlusion_test) {
	set_value_if_different(_core.do_occlusion_test, do_occlusion_test, _has_sensor_value_changed);
}

bool NNArea3DVisibilitySensor::get_do_occlusion_test() const {
	return _core.do_occlusion_test;
}

void NNArea3DVisibilitySensor::set_collision_mask(uint32_t collision_mask) {
	set_value_if_different(_core.collision_mask, collision_mask, _has_sensor_value_changed);
}

uint32_t NNArea3DVisibilitySensor::get_collision_mask() const {
	return _core.collision_mask;
}

void NNArea3DVisibilitySensor::set_max_expected_entities_found(int max_expected_entities_found) {
	if (max_expected_entities_found <= 0) {
		return;
	}
	set_value_if_different(_core.max_expected_entities_found, max_expected_entities_found, _has_sensor_value_changed);
	_core.one_over_max_expected_entities_found = 1.0f / ((float)_core.max_expected_entities_found);
}

int NNArea3DVisibilitySensor::get_max_expected_entities_found() const {
	return _core.max_expected_entities_found;
}

void NNArea3DVisibilitySensor::set_occlusion_test_exclusion_list(TypedArray<RID> occlusion_test_exclusion_list) {
	set_value_if_different(_core.occlusion_test_exclusion_list, occlusion_test_exclusion_list, _has_sensor_value_changed);
}

TypedArray<RID> NNArea3DVisibilitySensor::get_occlusion_test_exclusion_list() const {
	return _core.occlusion_test_exclusion_list;
}

// Debugging / current values.

void NNArea3DVisibilitySensor::set_num_entities_found(int num_entities_found) {
	set_value_if_different(_core.num_entities_found, num_entities_found, _has_sensor_value_changed);
}

int NNArea3DVisibilitySensor::get_num_entities_found() const {
	return _core.num_entities_found;
}

void NNArea3DVisibilitySensor::set_closest_intersecting_area_index(int closest_intersecting_area_index) {
	set_value_if_different(_core.closest_intersecting_area_index, closest_intersecting_area_index, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_closest_intersecting_body_index(int closest_intersecting_body_index) {
	set_value_if_different(_core.closest_intersecting_body_index, closest_intersecting_body_index, _has_sensor_value_changed);
}

int NNArea3DVisibilitySensor::get_closest_intersecting_area_index() const {
	return _core.closest_intersecting_area_index;
}

int NNArea3DVisibilitySensor::get_closest_intersecting_body_index() const {
	return _core.closest_intersecting_body_index;
}

void NNArea3DVisibilitySensor::set_closest_unoccluded_area_index(int closest_unoccluded_area_index) {
	set_value_if_different(_core.closest_unoccluded_area_index, closest_unoccluded_area_index, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_closest_unoccluded_body_index(int closest_unoccluded_body_index) {
	set_value_if_different(_core.closest_unoccluded_body_index, closest_unoccluded_body_index, _has_sensor_value_changed);
}

int NNArea3DVisibilitySensor::get_closest_unoccluded_area_index() const {
	return _core.closest_unoccluded_area_index;
}

int NNArea3DVisibilitySensor::get_closest_unoccluded_body_index() const {
	return _core.closest_unoccluded_body_index;
}

void NNArea3DVisibilitySensor::set_intersecting_areas(TypedArray<Area3D> intersecting_areas) {
	set_value_if_different(_core.intersecting_areas, intersecting_areas, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_intersecting_bodies(TypedArray<Node3D> intersecting_bodies) {
	set_value_if_different(_core.intersecting_bodies, intersecting_bodies, _has_sensor_value_changed);
}

TypedArray<Area3D> NNArea3DVisibilitySensor::get_intersecting_areas() const {
	return _core.intersecting_areas;
}

TypedArray<Node3D> NNArea3DVisibilitySensor::get_intersecting_bodies() const {
	return _core.intersecting_bodies;
}

void NNArea3DVisibilitySensor::set_unoccluded_areas(TypedArray<Area3D> unoccluded_areas) {
	set_value_if_different(_core.unoccluded_areas, unoccluded_areas, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_unoccluded_bodies(TypedArray<Node3D> unoccluded_bodies) {
	set_value_if_different(_core.unoccluded_bodies, unoccluded_bodies, _has_sensor_value_changed);
}

TypedArray<Area3D> NNArea3DVisibilitySensor::get_unoccluded_areas() const {
	return _core.unoccluded_areas;
}

TypedArray<Node3D> NNArea3DVisibilitySensor::get_unoccluded_bodies() const {
	return _core.unoccluded_bodies;
}

void NNArea3DVisibilitySensor::set_squared_distances_to_intersecting_areas(TypedArray<float> squared_distances_to_intersecting_areas) {
	set_value_if_different(_core.squared_distances_to_intersecting_areas, squared_distances_to_intersecting_areas, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_squared_distances_to_intersecting_bodies(TypedArray<float> squared_distances_to_intersecting_bodies) {
	set_value_if_different(_core.squared_distances_to_intersecting_bodies, squared_distances_to_intersecting_bodies, _has_sensor_value_changed);
}

TypedArray<float> NNArea3DVisibilitySensor::get_squared_distances_to_intersecting_areas() const {
	return _core.squared_distances_to_intersecting_areas;
}

TypedArray<float> NNArea3DVisibilitySensor::get_squared_distances_to_intersecting_bodies() const {
	return _core.squared_distances_to_intersecting_bodies;
}

void NNArea3DVisibilitySensor::set_squared_distances_to_unoccluded_areas(TypedArray<float> squared_distances_to_unoccluded_areas) {
	set_value_if_different(_core.squared_distances_to_unoccluded_areas, squared_distances_to_unoccluded_areas, _has_sensor_value_changed);
}

void NNArea3DVisibilitySensor::set_squared_distances_to_unoccluded_bodies(TypedArray<float> squared_distances_to_unoccluded_bodies) {
	set_value_if_different(_core.squared_distances_to_unoccluded_bodies, squared_distances_to_unoccluded_bodies, _has_sensor_value_changed);
}

TypedArray<float> NNArea3DVisibilitySensor::get_squared_distances_to_unoccluded_areas() const {
	return _core.squared_distances_to_unoccluded_areas;
}

TypedArray<float> NNArea3DVisibilitySensor::get_squared_distances_to_unoccluded_bodies() const {
	return _core.squared_distances_to_unoccluded_bodies;
}

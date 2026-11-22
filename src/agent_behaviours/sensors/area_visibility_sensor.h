#pragma once

#include "../sensor.h"
#include <godot_cpp/classes/area2d.hpp>
#include <godot_cpp/classes/area3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state2d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters2d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_server2d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/property_info.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

template <typename T>
void set_value_if_different(T &field, const T &value, bool &changed) {
	changed = changed || field != value;
	field = value;
}

struct AreaVisibilitySensor2D {
	using Vec = Vector2;
	using Area = Area2D;
	using Body = Node2D;
	using RayQuery = PhysicsRayQueryParameters2D;
	using SpaceState = PhysicsDirectSpaceState2D;
	using Server = PhysicsServer2D;

	static constexpr Variant::Type VEC_TYPE = Variant::VECTOR2;
	static constexpr PropertyHint COLLISION_MASK_HINT = PROPERTY_HINT_LAYERS_2D_PHYSICS;
	static constexpr const char *AREA_TYPE_NAME = "Area2D";
	static constexpr const char *BODY_TYPE_NAME = "Node2D";

	static bool try_get_global_position(Node *node, Vec &r_position) {
		Node2D *node_2d = Object::cast_to<Node2D>(node);
		if (node_2d == nullptr) {
			return false;
		}
		r_position = node_2d->get_global_position();
		return true;
	}
};

struct AreaVisibilitySensor3D {
	using Vec = Vector3;
	using Area = Area3D;
	using Body = Node3D;
	using RayQuery = PhysicsRayQueryParameters3D;
	using SpaceState = PhysicsDirectSpaceState3D;
	using Server = PhysicsServer3D;

	static constexpr Variant::Type VEC_TYPE = Variant::VECTOR3;
	static constexpr PropertyHint COLLISION_MASK_HINT = PROPERTY_HINT_LAYERS_3D_PHYSICS;
	static constexpr const char *AREA_TYPE_NAME = "Area3D";
	static constexpr const char *BODY_TYPE_NAME = "Node3D";

	static bool try_get_global_position(Node *node, Vec &r_position) {
		Node3D *node_3d = Object::cast_to<Node3D>(node);
		if (node_3d == nullptr) {
			return false;
		}
		r_position = node_3d->get_global_position();
		return true;
	}
};

template <typename TTypes>
class AreaVisibilitySensorCore {
public:
	using Vec = typename TTypes::Vec;
	using Area = typename TTypes::Area;
	using Body = typename TTypes::Body;
	using RayQuery = typename TTypes::RayQuery;
	using SpaceState = typename TTypes::SpaceState;
	using Server = typename TTypes::Server;

	AreaVisibilitySensorCore() {
		do_occlusion_test = true;
		collision_mask = 1;
		num_entities_found = 0;
		max_expected_entities_found = 16;
		one_over_max_expected_entities_found = 1.0f / ((float)max_expected_entities_found);
		closest_intersecting_area_index = -1;
		closest_unoccluded_area_index = -1;
		closest_intersecting_body_index = -1;
		closest_unoccluded_body_index = -1;
		use_owner_global_position = false;
	}

	Vec from_vector;
	Vec offset_vector;
	bool use_owner_global_position;
	bool do_occlusion_test;
	uint32_t collision_mask;

	TypedArray<RID> occlusion_test_exclusion_list;
	TypedArray<Area> intersecting_areas;
	TypedArray<Body> intersecting_bodies;
	TypedArray<Area> unoccluded_areas;
	TypedArray<Body> unoccluded_bodies;
	TypedArray<float> squared_distances_to_intersecting_areas;
	TypedArray<float> squared_distances_to_unoccluded_areas;
	TypedArray<float> squared_distances_to_intersecting_bodies;
	TypedArray<float> squared_distances_to_unoccluded_bodies;

	int num_entities_found;
	int max_expected_entities_found;
	float one_over_max_expected_entities_found;
	int closest_intersecting_area_index;
	int closest_unoccluded_area_index;
	int closest_intersecting_body_index;
	int closest_unoccluded_body_index;

	bool evaluate(const Area *visibility_volume, Node *owner) {
		if (use_owner_global_position && owner != nullptr) {
			Vec owner_position;
			if (TTypes::try_get_global_position(owner, owner_position)) {
				from_vector = owner_position;
			}
		}

		SpaceState *space_state = nullptr;
		if (do_occlusion_test) {
			Server *server = Server::get_singleton();
			space_state = server->space_get_direct_state(server->area_get_space(visibility_volume->get_rid()));
			if (space_state == nullptr) {
				return false;
			}
			RayQuery *ray_query = ensure_ray_query();
			ray_query->set_collision_mask(collision_mask);
			ray_query->set_exclude(occlusion_test_exclusion_list);
			ray_query->set_collide_with_bodies(true);
		}

		Vec offset_from_vector = from_vector + offset_vector;
		num_entities_found = 0;
		unoccluded_areas.clear();
		unoccluded_bodies.clear();
		squared_distances_to_unoccluded_areas.clear();
		squared_distances_to_unoccluded_bodies.clear();
		squared_distances_to_intersecting_areas.clear();
		squared_distances_to_intersecting_bodies.clear();

		evaluate_entities(intersecting_areas, unoccluded_areas, squared_distances_to_intersecting_areas,
				squared_distances_to_unoccluded_areas, closest_intersecting_area_index, closest_unoccluded_area_index,
				true, offset_from_vector, space_state);
		evaluate_entities(intersecting_bodies, unoccluded_bodies, squared_distances_to_intersecting_bodies,
				squared_distances_to_unoccluded_bodies, closest_intersecting_body_index, closest_unoccluded_body_index,
				false, offset_from_vector, space_state);
		return true;
	}

	void on_area_entered(Area *area, bool &changed) {
		on_entity_entered(intersecting_areas, area, changed);
	}

	void on_area_exited(Area *area, bool &changed) {
		on_entity_exited(intersecting_areas, area, changed);
	}

	void on_body_entered(Body *body, bool &changed) {
		on_entity_entered(intersecting_bodies, body, changed);
	}

	void on_body_exited(Body *body, bool &changed) {
		on_entity_exited(intersecting_bodies, body, changed);
	}

private:
	template <typename TEntity>
	void evaluate_entities(TypedArray<TEntity> &entities, TypedArray<TEntity> &unoccluded, TypedArray<float> &intersecting_distances,
			TypedArray<float> &unoccluded_distances, int &closest_intersecting_index, int &closest_unoccluded_index,
			bool collide_with_areas, const Vec &offset_from_vector, SpaceState *space_state) {
		closest_intersecting_index = -1;
		closest_unoccluded_index = -1;
		float closest_intersecting_distance = 0.0f;
		float closest_unoccluded_distance = 0.0f;

		if (!_ray_query.is_null()) {
			_ray_query->set_collide_with_areas(collide_with_areas);
		}

		for (int i = 0; i < entities.size();) {
			TEntity *entity = Object::cast_to<TEntity>(entities[i].get_validated_object());
			if (entity == nullptr) {
				entities.remove_at(i);
				continue;
			}

			Vec entity_position = entity->get_global_position();
			float distance_squared = (entity_position - offset_from_vector).length_squared();
			intersecting_distances.push_back(distance_squared);
			if (closest_intersecting_index == -1 || distance_squared < closest_intersecting_distance) {
				closest_intersecting_index = i;
				closest_intersecting_distance = distance_squared;
			}

			if (!do_occlusion_test) {
				++num_entities_found;
			} else if (is_unoccluded(entity_position, entities[i], offset_from_vector, space_state)) {
				unoccluded.push_back(entity);
				unoccluded_distances.push_back(distance_squared);
				if (closest_unoccluded_index == -1 || distance_squared < closest_unoccluded_distance) {
					closest_unoccluded_index = (int)unoccluded.size() - 1;
					closest_unoccluded_distance = distance_squared;
				}
				++num_entities_found;
			}
			++i;
		}
	}

	bool is_unoccluded(const Vec &position, const Variant &target, const Vec &offset_from_vector, SpaceState *space_state) {
		_ray_query->set_from(offset_from_vector);
		_ray_query->set_to(position);
		Dictionary results = space_state->intersect_ray(_ray_query);
		return results.is_empty() || results.get("collider", nullptr) == target;
	}

	template <typename TEntity>
	void on_entity_entered(TypedArray<TEntity> &entities, TEntity *entity, bool &changed) {
		if (entity == nullptr) {
			return;
		}
		if (entities.has(entity)) {
			return;
		}
		changed = true;
		entities.push_back(entity);
	}

	template <typename TEntity>
	void on_entity_exited(TypedArray<TEntity> &entities, TEntity *entity, bool &changed) {
		if (entity == nullptr) {
			return;
		}
		int index = entities.find(entity);
		if (index < 0) {
			return;
		}
		changed = true;
		entities.remove_at(index);
	}

	Ref<RayQuery> _ray_query;

	RayQuery *ensure_ray_query() {
		if (_ray_query.is_null()) {
			_ray_query = RayQuery::create(Vec(), Vec());
		}
		return _ray_query.ptr();
	}
};

// Shared node behaviour for NNArea2DVisibilitySensor and NNArea3DVisibilitySensor.
// Not registered with ClassDB, so each subclass names its nearest registered ancestor.
template <typename TDerived, typename TTypes>
class AreaVisibilitySensor : public NNSensor {
public:
	using Vec = typename TTypes::Vec;
	using Area = typename TTypes::Area;
	using Body = typename TTypes::Body;

	void initialize_sensor() override {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}

		Area *visibility_volume = get_visibility_volume();
		ERR_FAIL_COND_MSG(visibility_volume == nullptr, String(TDerived::get_class_static()) + "::initialize_sensor() - Error, the visibility volume is not set.");

		visibility_volume->connect("area_entered", _area_entered_callable());
		visibility_volume->connect("area_exited", _area_exited_callable());
		visibility_volume->connect("body_entered", _body_entered_callable());
		visibility_volume->connect("body_exited", _body_exited_callable());
	}

	void uninitialize_sensor() override {
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}
		Area *visibility_volume = get_visibility_volume();
		if (visibility_volume != nullptr) {
			visibility_volume->disconnect("area_entered", _area_entered_callable());
			visibility_volume->disconnect("area_exited", _area_exited_callable());
			visibility_volume->disconnect("body_entered", _body_entered_callable());
			visibility_volume->disconnect("body_exited", _body_exited_callable());
		}
		_visibility_volume_id = ObjectID();
	}

	float evaluate_sensor_value() override {
		Area *visibility_volume = get_visibility_volume();
		if (visibility_volume == nullptr) {
			_visibility_volume_id = ObjectID();
			return get_sensor_value();
		}

		if (!_core.evaluate(visibility_volume, get_owner())) {
			return get_sensor_value();
		}

		set_sensor_value(((float)_core.num_entities_found) * _core.one_over_max_expected_entities_found);
		return get_sensor_value();
	}

	void on_area_entered(Area *area) {
		_core.on_area_entered(area, _has_sensor_value_changed);
	}

	void on_area_exited(Area *area) {
		_core.on_area_exited(area, _has_sensor_value_changed);
	}

	void on_body_entered(Body *body) {
		_core.on_body_entered(body, _has_sensor_value_changed);
	}

	void on_body_exited(Body *body) {
		_core.on_body_exited(body, _has_sensor_value_changed);
	}

	void set_use_owner_global_position(bool use_owner_global_position) {
		set_value_if_different(_core.use_owner_global_position, use_owner_global_position, _has_sensor_value_changed);
	}

	bool get_use_owner_global_position() const {
		return _core.use_owner_global_position;
	}

	void set_from_vector(Vec from) {
		set_value_if_different(_core.from_vector, from, _has_sensor_value_changed);
	}

	Vec get_from_vector() const {
		return _core.from_vector;
	}

	void set_offset_vector(Vec offset) {
		set_value_if_different(_core.offset_vector, offset, _has_sensor_value_changed);
	}

	Vec get_offset_vector() const {
		return _core.offset_vector;
	}

	void set_visibility_volume(Area *visibility_volume) {
		ObjectID visibility_volume_id = visibility_volume != nullptr ? ObjectID(visibility_volume->get_instance_id()) : ObjectID();
		set_value_if_different(_visibility_volume_id, visibility_volume_id, _has_sensor_value_changed);
	}

	Area *get_visibility_volume() const {
		return Object::cast_to<Area>(ObjectDB::get_instance(_visibility_volume_id));
	}

	void set_do_occlusion_test(bool do_occlusion_test) {
		set_value_if_different(_core.do_occlusion_test, do_occlusion_test, _has_sensor_value_changed);
	}

	bool get_do_occlusion_test() const {
		return _core.do_occlusion_test;
	}

	void set_collision_mask(uint32_t collision_mask) {
		set_value_if_different(_core.collision_mask, collision_mask, _has_sensor_value_changed);
	}

	uint32_t get_collision_mask() const {
		return _core.collision_mask;
	}

	void set_max_expected_entities_found(int max_expected_entities_found) {
		if (max_expected_entities_found <= 0) {
			return;
		}
		set_value_if_different(_core.max_expected_entities_found, max_expected_entities_found, _has_sensor_value_changed);
		_core.one_over_max_expected_entities_found = 1.0f / ((float)_core.max_expected_entities_found);
	}

	int get_max_expected_entities_found() const {
		return _core.max_expected_entities_found;
	}

	void set_occlusion_test_exclusion_list(TypedArray<RID> occlusion_test_exclusion_list) {
		set_value_if_different(_core.occlusion_test_exclusion_list, occlusion_test_exclusion_list, _has_sensor_value_changed);
	}

	TypedArray<RID> get_occlusion_test_exclusion_list() const {
		return _core.occlusion_test_exclusion_list;
	}

	void set_num_entities_found(int num_entities_found) {
		set_value_if_different(_core.num_entities_found, num_entities_found, _has_sensor_value_changed);
	}

	int get_num_entities_found() const {
		return _core.num_entities_found;
	}

	void set_closest_intersecting_area_index(int closest_intersecting_area_index) {
		set_value_if_different(_core.closest_intersecting_area_index, closest_intersecting_area_index, _has_sensor_value_changed);
	}

	int get_closest_intersecting_area_index() const {
		return _core.closest_intersecting_area_index;
	}

	void set_closest_intersecting_body_index(int closest_intersecting_body_index) {
		set_value_if_different(_core.closest_intersecting_body_index, closest_intersecting_body_index, _has_sensor_value_changed);
	}

	int get_closest_intersecting_body_index() const {
		return _core.closest_intersecting_body_index;
	}

	void set_closest_unoccluded_area_index(int closest_unoccluded_area_index) {
		set_value_if_different(_core.closest_unoccluded_area_index, closest_unoccluded_area_index, _has_sensor_value_changed);
	}

	int get_closest_unoccluded_area_index() const {
		return _core.closest_unoccluded_area_index;
	}

	void set_closest_unoccluded_body_index(int closest_unoccluded_body_index) {
		set_value_if_different(_core.closest_unoccluded_body_index, closest_unoccluded_body_index, _has_sensor_value_changed);
	}

	int get_closest_unoccluded_body_index() const {
		return _core.closest_unoccluded_body_index;
	}

	void set_intersecting_areas(TypedArray<Area> intersecting_areas) {
		set_value_if_different(_core.intersecting_areas, intersecting_areas, _has_sensor_value_changed);
	}

	TypedArray<Area> get_intersecting_areas() const {
		return _core.intersecting_areas;
	}

	void set_intersecting_bodies(TypedArray<Body> intersecting_bodies) {
		set_value_if_different(_core.intersecting_bodies, intersecting_bodies, _has_sensor_value_changed);
	}

	TypedArray<Body> get_intersecting_bodies() const {
		return _core.intersecting_bodies;
	}

	void set_unoccluded_areas(TypedArray<Area> unoccluded_areas) {
		set_value_if_different(_core.unoccluded_areas, unoccluded_areas, _has_sensor_value_changed);
	}

	TypedArray<Area> get_unoccluded_areas() const {
		return _core.unoccluded_areas;
	}

	void set_unoccluded_bodies(TypedArray<Body> unoccluded_bodies) {
		set_value_if_different(_core.unoccluded_bodies, unoccluded_bodies, _has_sensor_value_changed);
	}

	TypedArray<Body> get_unoccluded_bodies() const {
		return _core.unoccluded_bodies;
	}

	void set_squared_distances_to_intersecting_areas(TypedArray<float> squared_distances_to_intersecting_areas) {
		set_value_if_different(_core.squared_distances_to_intersecting_areas, squared_distances_to_intersecting_areas, _has_sensor_value_changed);
	}

	TypedArray<float> get_squared_distances_to_intersecting_areas() const {
		return _core.squared_distances_to_intersecting_areas;
	}

	void set_squared_distances_to_intersecting_bodies(TypedArray<float> squared_distances_to_intersecting_bodies) {
		set_value_if_different(_core.squared_distances_to_intersecting_bodies, squared_distances_to_intersecting_bodies, _has_sensor_value_changed);
	}

	TypedArray<float> get_squared_distances_to_intersecting_bodies() const {
		return _core.squared_distances_to_intersecting_bodies;
	}

	void set_squared_distances_to_unoccluded_areas(TypedArray<float> squared_distances_to_unoccluded_areas) {
		set_value_if_different(_core.squared_distances_to_unoccluded_areas, squared_distances_to_unoccluded_areas, _has_sensor_value_changed);
	}

	TypedArray<float> get_squared_distances_to_unoccluded_areas() const {
		return _core.squared_distances_to_unoccluded_areas;
	}

	void set_squared_distances_to_unoccluded_bodies(TypedArray<float> squared_distances_to_unoccluded_bodies) {
		set_value_if_different(_core.squared_distances_to_unoccluded_bodies, squared_distances_to_unoccluded_bodies, _has_sensor_value_changed);
	}

	TypedArray<float> get_squared_distances_to_unoccluded_bodies() const {
		return _core.squared_distances_to_unoccluded_bodies;
	}

private:
	Callable _area_entered_callable() {
		return callable_mp(static_cast<TDerived *>(this), static_cast<void (TDerived::*)(Area *)>(&AreaVisibilitySensor::on_area_entered));
	}

	Callable _area_exited_callable() {
		return callable_mp(static_cast<TDerived *>(this), static_cast<void (TDerived::*)(Area *)>(&AreaVisibilitySensor::on_area_exited));
	}

	Callable _body_entered_callable() {
		return callable_mp(static_cast<TDerived *>(this), static_cast<void (TDerived::*)(Body *)>(&AreaVisibilitySensor::on_body_entered));
	}

	Callable _body_exited_callable() {
		return callable_mp(static_cast<TDerived *>(this), static_cast<void (TDerived::*)(Body *)>(&AreaVisibilitySensor::on_body_exited));
	}

	AreaVisibilitySensorCore<TTypes> _core;
	// An ObjectID, not a pointer: the volume may be freed before this sensor.
	ObjectID _visibility_volume_id;
};

template <typename TClass, typename TTypes>
void bind_area_visibility_sensor_methods() {
	using Vec = typename TTypes::Vec;
	using Area = typename TTypes::Area;
	using Body = typename TTypes::Body;

	// godot-cpp binds a method under the class that declares it, and the shared
	// accessors live in an unregistered base, so bind them through this class.
	const StringName &class_name = TClass::get_class_static();

	ClassDB::add_property_group(class_name, "Configuration", "");

	ClassDB::bind_method(D_METHOD("set_use_owner_global_position", "use_owner_global_position"), static_cast<void (TClass::*)(bool)>(&TClass::set_use_owner_global_position));
	ClassDB::bind_method(D_METHOD("get_use_owner_global_position"), static_cast<bool (TClass::*)() const>(&TClass::get_use_owner_global_position));
	ClassDB::add_property(class_name, PropertyInfo(Variant::BOOL, "use_owner_global_position", PROPERTY_HINT_NONE), "set_use_owner_global_position", "get_use_owner_global_position");

	ClassDB::bind_method(D_METHOD("set_offset_vector", "offset_vector"), static_cast<void (TClass::*)(Vec)>(&TClass::set_offset_vector));
	ClassDB::bind_method(D_METHOD("get_offset_vector"), static_cast<Vec (TClass::*)() const>(&TClass::get_offset_vector));
	ClassDB::add_property(class_name, PropertyInfo(TTypes::VEC_TYPE, "offset_vector", PROPERTY_HINT_NONE), "set_offset_vector", "get_offset_vector");

	ClassDB::bind_method(D_METHOD("set_visibility_volume", "visibility_volume"), static_cast<void (TClass::*)(Area *)>(&TClass::set_visibility_volume));
	ClassDB::bind_method(D_METHOD("get_visibility_volume"), static_cast<Area *(TClass::*)() const>(&TClass::get_visibility_volume));
	ClassDB::add_property(class_name, PropertyInfo(Variant::OBJECT, "visibility_volume", PROPERTY_HINT_NODE_TYPE, TTypes::AREA_TYPE_NAME), "set_visibility_volume", "get_visibility_volume");

	ClassDB::bind_method(D_METHOD("set_max_expected_entities_found", "max_expected_entities_found"), static_cast<void (TClass::*)(int)>(&TClass::set_max_expected_entities_found));
	ClassDB::bind_method(D_METHOD("get_max_expected_entities_found"), static_cast<int (TClass::*)() const>(&TClass::get_max_expected_entities_found));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "max_expected_entities_found", PROPERTY_HINT_RANGE, "1,32,or_greater"), "set_max_expected_entities_found", "get_max_expected_entities_found");

	ClassDB::add_property_group(class_name, "Occlusion", "");

	ClassDB::bind_method(D_METHOD("set_do_occlusion_test", "do_occlusion_test"), static_cast<void (TClass::*)(bool)>(&TClass::set_do_occlusion_test));
	ClassDB::bind_method(D_METHOD("get_do_occlusion_test"), static_cast<bool (TClass::*)() const>(&TClass::get_do_occlusion_test));
	ClassDB::add_property(class_name, PropertyInfo(Variant::BOOL, "do_occlusion_test", PROPERTY_HINT_NONE), "set_do_occlusion_test", "get_do_occlusion_test");

	ClassDB::bind_method(D_METHOD("set_collision_mask", "collision_mask"), static_cast<void (TClass::*)(uint32_t)>(&TClass::set_collision_mask));
	ClassDB::bind_method(D_METHOD("get_collision_mask"), static_cast<uint32_t (TClass::*)() const>(&TClass::get_collision_mask));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "collision_mask", TTypes::COLLISION_MASK_HINT), "set_collision_mask", "get_collision_mask");

	ClassDB::bind_method(D_METHOD("set_occlusion_test_exclusion_list", "occlusion_test_exclusion_list"), static_cast<void (TClass::*)(TypedArray<RID>)>(&TClass::set_occlusion_test_exclusion_list));
	ClassDB::bind_method(D_METHOD("get_occlusion_test_exclusion_list"), static_cast<TypedArray<RID> (TClass::*)() const>(&TClass::get_occlusion_test_exclusion_list));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "occlusion_test_exclusion_list", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "RID")), "set_occlusion_test_exclusion_list", "get_occlusion_test_exclusion_list");

	ClassDB::add_property_group(class_name, "Debugging", "");

	ClassDB::bind_method(D_METHOD("set_from_vector", "from_vector"), static_cast<void (TClass::*)(Vec)>(&TClass::set_from_vector));
	ClassDB::bind_method(D_METHOD("get_from_vector"), static_cast<Vec (TClass::*)() const>(&TClass::get_from_vector));
	ClassDB::add_property(class_name, PropertyInfo(TTypes::VEC_TYPE, "from_vector", PROPERTY_HINT_NONE), "set_from_vector", "get_from_vector");

	ClassDB::bind_method(D_METHOD("set_num_entities_found", "num_entities_found"), static_cast<void (TClass::*)(int)>(&TClass::set_num_entities_found));
	ClassDB::bind_method(D_METHOD("get_num_entities_found"), static_cast<int (TClass::*)() const>(&TClass::get_num_entities_found));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "num_entities_found", PROPERTY_HINT_RANGE, "0,32,or_greater"), "set_num_entities_found", "get_num_entities_found");

	ClassDB::add_property_subgroup(class_name, "Areas", "");

	ClassDB::bind_method(D_METHOD("set_closest_intersecting_area_index", "closest_intersecting_area_index"), static_cast<void (TClass::*)(int)>(&TClass::set_closest_intersecting_area_index));
	ClassDB::bind_method(D_METHOD("get_closest_intersecting_area_index"), static_cast<int (TClass::*)() const>(&TClass::get_closest_intersecting_area_index));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "closest_intersecting_area_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_intersecting_area_index", "get_closest_intersecting_area_index");

	ClassDB::bind_method(D_METHOD("set_intersecting_areas", "intersecting_areas"), static_cast<void (TClass::*)(TypedArray<Area>)>(&TClass::set_intersecting_areas));
	ClassDB::bind_method(D_METHOD("get_intersecting_areas"), static_cast<TypedArray<Area> (TClass::*)() const>(&TClass::get_intersecting_areas));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, TTypes::AREA_TYPE_NAME)), "set_intersecting_areas", "get_intersecting_areas");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_intersecting_areas", "squared_distances_to_intersecting_areas"), static_cast<void (TClass::*)(TypedArray<float>)>(&TClass::set_squared_distances_to_intersecting_areas));
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_intersecting_areas"), static_cast<TypedArray<float> (TClass::*)() const>(&TClass::get_squared_distances_to_intersecting_areas));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "squared_distances_to_intersecting_areas", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_intersecting_areas", "get_squared_distances_to_intersecting_areas");

	ClassDB::bind_method(D_METHOD("set_closest_unoccluded_area_index", "closest_unoccluded_area_index"), static_cast<void (TClass::*)(int)>(&TClass::set_closest_unoccluded_area_index));
	ClassDB::bind_method(D_METHOD("get_closest_unoccluded_area_index"), static_cast<int (TClass::*)() const>(&TClass::get_closest_unoccluded_area_index));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "closest_unoccluded_area_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_unoccluded_area_index", "get_closest_unoccluded_area_index");

	ClassDB::bind_method(D_METHOD("set_unoccluded_areas", "unoccluded_areas"), static_cast<void (TClass::*)(TypedArray<Area>)>(&TClass::set_unoccluded_areas));
	ClassDB::bind_method(D_METHOD("get_unoccluded_areas"), static_cast<TypedArray<Area> (TClass::*)() const>(&TClass::get_unoccluded_areas));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "unoccluded_areas", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, TTypes::AREA_TYPE_NAME)), "set_unoccluded_areas", "get_unoccluded_areas");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_unoccluded_areas", "squared_distances_to_unoccluded_areas"), static_cast<void (TClass::*)(TypedArray<float>)>(&TClass::set_squared_distances_to_unoccluded_areas));
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_unoccluded_areas"), static_cast<TypedArray<float> (TClass::*)() const>(&TClass::get_squared_distances_to_unoccluded_areas));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "squared_distances_to_unoccluded_areas", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_unoccluded_areas", "get_squared_distances_to_unoccluded_areas");

	ClassDB::add_property_subgroup(class_name, "Bodies", "");

	ClassDB::bind_method(D_METHOD("set_closest_intersecting_body_index", "closest_intersecting_body_index"), static_cast<void (TClass::*)(int)>(&TClass::set_closest_intersecting_body_index));
	ClassDB::bind_method(D_METHOD("get_closest_intersecting_body_index"), static_cast<int (TClass::*)() const>(&TClass::get_closest_intersecting_body_index));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "closest_intersecting_body_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_intersecting_body_index", "get_closest_intersecting_body_index");

	ClassDB::bind_method(D_METHOD("set_intersecting_bodies", "intersecting_bodies"), static_cast<void (TClass::*)(TypedArray<Body>)>(&TClass::set_intersecting_bodies));
	ClassDB::bind_method(D_METHOD("get_intersecting_bodies"), static_cast<TypedArray<Body> (TClass::*)() const>(&TClass::get_intersecting_bodies));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "intersecting_bodies", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, TTypes::BODY_TYPE_NAME)), "set_intersecting_bodies", "get_intersecting_bodies");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_intersecting_bodies", "squared_distances_to_intersecting_bodies"), static_cast<void (TClass::*)(TypedArray<float>)>(&TClass::set_squared_distances_to_intersecting_bodies));
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_intersecting_bodies"), static_cast<TypedArray<float> (TClass::*)() const>(&TClass::get_squared_distances_to_intersecting_bodies));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "squared_distances_to_intersecting_bodies", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_intersecting_bodies", "get_squared_distances_to_intersecting_bodies");

	ClassDB::bind_method(D_METHOD("set_closest_unoccluded_body_index", "closest_unoccluded_body_index"), static_cast<void (TClass::*)(int)>(&TClass::set_closest_unoccluded_body_index));
	ClassDB::bind_method(D_METHOD("get_closest_unoccluded_body_index"), static_cast<int (TClass::*)() const>(&TClass::get_closest_unoccluded_body_index));
	ClassDB::add_property(class_name, PropertyInfo(Variant::INT, "closest_unoccluded_body_index", PROPERTY_HINT_RANGE, "-1,32,or_greater"), "set_closest_unoccluded_body_index", "get_closest_unoccluded_body_index");

	ClassDB::bind_method(D_METHOD("set_unoccluded_bodies", "unoccluded_bodies"), static_cast<void (TClass::*)(TypedArray<Body>)>(&TClass::set_unoccluded_bodies));
	ClassDB::bind_method(D_METHOD("get_unoccluded_bodies"), static_cast<TypedArray<Body> (TClass::*)() const>(&TClass::get_unoccluded_bodies));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "unoccluded_bodies", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, TTypes::BODY_TYPE_NAME)), "set_unoccluded_bodies", "get_unoccluded_bodies");

	ClassDB::bind_method(D_METHOD("set_squared_distances_to_unoccluded_bodies", "squared_distances_to_unoccluded_bodies"), static_cast<void (TClass::*)(TypedArray<float>)>(&TClass::set_squared_distances_to_unoccluded_bodies));
	ClassDB::bind_method(D_METHOD("get_squared_distances_to_unoccluded_bodies"), static_cast<TypedArray<float> (TClass::*)() const>(&TClass::get_squared_distances_to_unoccluded_bodies));
	ClassDB::add_property(class_name, PropertyInfo(Variant::ARRAY, "squared_distances_to_unoccluded_bodies", PROPERTY_HINT_ARRAY_TYPE, "float"), "set_squared_distances_to_unoccluded_bodies", "get_squared_distances_to_unoccluded_bodies");
}

} //namespace godot

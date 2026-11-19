#pragma once

#include <godot_cpp/classes/area2d.hpp>
#include <godot_cpp/classes/area3d.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state2d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters2d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_server2d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

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
			TEntity *entity = Object::cast_to<TEntity>(entities[i]);
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

} //namespace godot

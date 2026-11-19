#pragma once

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>

namespace godot {

// NNPointGrid2DSearchSpace and NNPointGrid3DSearchSpace differ only in their
// vector and node types; generation and lifetime handling live here.

template <typename VectorT>
struct NNPointGridLatticePreset {
	VectorT spacing;
	VectorT lattice_vector;
};

inline bool point_grid_spacing_is_valid(const Vector2 &p_spacing) {
	return p_spacing.is_finite() && p_spacing.x > 0.0f && p_spacing.y > 0.0f;
}

inline bool point_grid_spacing_is_valid(const Vector3 &p_spacing) {
	return p_spacing.is_finite() && p_spacing.x > 0.0f && p_spacing.y > 0.0f && p_spacing.z > 0.0f;
}

template <typename VectorT>
inline void point_grid_apply_lattice(int p_lattice_type, const NNPointGridLatticePreset<VectorT> (&p_presets)[4], VectorT &r_spacing, VectorT &r_lattice_vector) {
	if (p_lattice_type < 0 || p_lattice_type >= 4) {
		return;
	}
	r_spacing = p_presets[p_lattice_type].spacing;
	r_lattice_vector = p_presets[p_lattice_type].lattice_vector;
}

template <typename VectorT>
inline void point_grid_generate_positions_along_axis(int p_depth, const int *p_axis_order, int p_axis_count, VectorT &r_point, std::vector<VectorT> &r_positions, const VectorT &p_grid_size, const VectorT &p_spacing, const VectorT &p_lattice_vector) {
	const int axis = p_axis_order[p_depth];
	const float half_size = 0.5f * p_grid_size[axis];
	for (float value = -half_size; value <= half_size; value += p_spacing[axis]) {
		r_point[axis] = value;
		if (p_depth + 1 == p_axis_count) {
			r_positions.push_back(r_point);
			r_positions.push_back(r_point + p_lattice_vector);
		} else {
			point_grid_generate_positions_along_axis(p_depth + 1, p_axis_order, p_axis_count, r_point, r_positions, p_grid_size, p_spacing, p_lattice_vector);
		}
	}
}

template <typename VectorT>
inline void point_grid_generate_rectangular_positions(std::vector<VectorT> &r_positions, const VectorT &p_grid_size, const VectorT &p_spacing, const VectorT &p_lattice_vector, const int *p_axis_order, int p_axis_count) {
	r_positions.clear();
	VectorT point;
	point_grid_generate_positions_along_axis(0, p_axis_order, p_axis_count, point, r_positions, p_grid_size, p_spacing, p_lattice_vector);
}

template <typename NodeT>
inline NodeT *point_grid_find_template_node(Node *p_owner) {
	for (int i = 0; i < p_owner->get_child_count(); i++) {
		NodeT *node = Object::cast_to<NodeT>(p_owner->get_child(i));
		if (node != nullptr && node->get_name() == StringName("DEBUG")) {
			return node;
		}
	}
	return nullptr;
}

template <typename NodeT, typename VectorT>
inline void point_grid_create_nodes(const char *p_owner_name, NodeT *p_parent, NodeT *p_template_node, const std::vector<VectorT> &p_positions, const VectorT &p_offset, TypedArray<NodeT> &r_point_grid, std::vector<uint64_t> &r_generated_node_ids) {
	for (size_t i = 0; i < p_positions.size(); i++) {
		NodeT *new_node = Object::cast_to<NodeT>(p_template_node->duplicate(15));
		if (new_node == nullptr) {
			ERR_FAIL_MSG(String(p_owner_name) + "::create_point_grid_nodes(): Error, could not duplicate template node. Out of memory?");
			return;
		}
		p_parent->add_child(new_node);
		new_node->set_position(p_positions[i] + p_offset);
		r_point_grid.push_back(new_node);
		r_generated_node_ids.push_back(static_cast<uint64_t>(new_node->get_instance_id()));
	}
}

template <typename NodeT, typename VectorT>
inline void point_grid_create(Node *p_owner, const char *p_owner_name, NodeT *p_parent, const std::vector<VectorT> &p_positions, const VectorT &p_offset, TypedArray<NodeT> &r_point_grid, std::vector<uint64_t> &r_generated_node_ids) {
	// If there is a debug child under the search space node, make duplicates of it
	// under the search space parent node.
	NodeT *template_node = point_grid_find_template_node<NodeT>(p_owner);
	const bool owns_template_node = template_node == nullptr;
	if (owns_template_node) {
		template_node = memnew(NodeT);
	}

	// Ensure that score and is_filtered are available for debug.
	template_node->set("score", 0.0f);
	template_node->set("is_filtered", false);

	point_grid_create_nodes(p_owner_name, p_parent, template_node, p_positions, p_offset, r_point_grid, r_generated_node_ids);

	if (owns_template_node) {
		memdelete(template_node);
	}
}

template <typename NodeT>
inline void point_grid_destroy_nodes(std::vector<uint64_t> &r_generated_node_ids, TypedArray<NodeT> &r_point_grid, ObjectID &r_parent_id) {
	// Swap the ids into a local vector so a reentrant call (for example from a
	// node being deleted) finds an empty list and cannot free anything twice.
	std::vector<uint64_t> generated_node_ids;
	generated_node_ids.swap(r_generated_node_ids);

	for (size_t i = 0; i < generated_node_ids.size(); i++) {
		// The node may legitimately be gone already: the point grid parent node
		// can be freed before this search space, and user code may free points
		// individually. Looking the id up is safe, using the object is not.
		Object *object = ObjectDB::get_instance(generated_node_ids[i]);
		if (object == nullptr) {
			continue;
		}
		NodeT *node = Object::cast_to<NodeT>(object);
		if (node == nullptr) {
			continue;
		}
		// memdelete() is the Godot object destructor: it notifies the node, which
		// removes it from the point grid parent node. Never memfree() a Godot object.
		memdelete(node);
	}

	// The point grid may hold user supplied nodes; drop the references without
	// deleting them, and never dereference the (possibly stale) parent.
	r_point_grid.clear();
	r_parent_id = ObjectID();
}

template <typename VectorT, typename NodeT, typename NavigationServerT>
inline bool point_grid_snap_to_navigation(unsigned int &r_current_index, const TypedArray<NodeT> &p_point_grid, const std::vector<VectorT> &p_positions, const VectorT &p_offset, NodeT *p_parent, RID p_navigation_map, NavigationServerT *p_nav_server, uint64_t p_time_limit_timestamp_usec) {
	// The point grid is assignable, so it may not match the generated positions one to one.
	const unsigned int num_points = MIN((unsigned int)p_point_grid.size(), (unsigned int)p_positions.size());
	while (r_current_index < num_points) {
		NodeT *node = Object::cast_to<NodeT>(p_point_grid[r_current_index]);
		if (node != nullptr) {
			const VectorT local_position = p_positions[r_current_index] + p_offset;
			node->set_global_position(p_nav_server->map_get_closest_point(p_navigation_map, p_parent->get_global_transform().xform(local_position)));
		}
		++r_current_index;
		if (Time::get_singleton()->get_ticks_usec() >= p_time_limit_timestamp_usec) {
			return false;
		}
	}
	return true;
}

} //namespace godot

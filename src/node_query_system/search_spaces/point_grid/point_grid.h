#pragma once

#include "../../nqs_threading.h"
#include <functional>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <utility>
#include <vector>

namespace godot {

// NNPointGrid2DSearchSpace and NNPointGrid3DSearchSpace differ only in their
// vector and node types; generation and lifetime handling live here.

template <typename VectorT>
struct NNPointGridLatticePreset {
	VectorT spacing;
	VectorT lattice_vector;
};

template <typename VectorT>
struct NNPointGridTransformType;
template <>
struct NNPointGridTransformType<Vector2> {
	using type = Transform2D;
};
template <>
struct NNPointGridTransformType<Vector3> {
	using type = Transform3D;
};

// Serial snapping costs about 12 usec per point, so below this many the group task does not pay.
constexpr unsigned int POINT_GRID_AUTO_MIN_POINTS = 32;
constexpr unsigned int POINT_GRID_SNAP_CHUNK_SIZE = 32;
// Batching the clock read bounds a budget overrun to a full batch of points.
constexpr unsigned int POINT_GRID_TIME_CHECK_INTERVAL_POINTS = 64;

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
		NodeT *node = Object::cast_to<NodeT>(p_point_grid[r_current_index].get_validated_object());
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

// Workers read only the captured buffers below and never touch a node, so points may be freed mid-job.
template <typename VectorT, typename NodeT, typename NavigationServerT>
class NNPointGridSnapper {
public:
	bool snap(const TypedArray<NodeT> &p_point_grid, const std::vector<VectorT> &p_positions, const VectorT &p_offset, NodeT *p_parent, RID p_navigation_map, NavigationServerT *p_nav_server, uint64_t p_time_limit_timestamp_usec) {
		if (_stage == STAGE_IDLE) {
			_stage = STAGE_CAPTURE;
			_num_points = MIN((unsigned int)p_point_grid.size(), (unsigned int)p_positions.size());
			_local_positions.resize(_num_points);
			_snapped_positions.resize(_num_points);
			_node_ids.resize(_num_points);
			_navigation_map = p_navigation_map;
			_parent_transform = p_parent->get_global_transform();
			_capture_index = 0;
			_apply_index = 0;
		}

		if (_stage == STAGE_CAPTURE) {
			unsigned int points_since_time_check = POINT_GRID_TIME_CHECK_INTERVAL_POINTS;
			while (_capture_index < _num_points) {
				const NodeT *node = Object::cast_to<NodeT>(p_point_grid[_capture_index]);
				_node_ids[_capture_index] = node != nullptr ? static_cast<uint64_t>(node->get_instance_id()) : 0;
				_local_positions[_capture_index] = p_positions[_capture_index] + p_offset;
				++_capture_index;
				if (--points_since_time_check == 0) {
					points_since_time_check = POINT_GRID_TIME_CHECK_INTERVAL_POINTS;
					if (Time::get_singleton()->get_ticks_usec() >= p_time_limit_timestamp_usec) {
						return false;
					}
				}
			}
			_stage = STAGE_SNAP;
			const RID navigation_map = _navigation_map;
			const TransformT parent_transform = _parent_transform;
			std::function<void(uint32_t, uint32_t)> work = [this, p_nav_server, navigation_map, parent_transform](uint32_t p_begin, uint32_t p_end) {
				for (uint32_t i = p_begin; i < p_end; ++i) {
					_snapped_positions[i] = p_nav_server->map_get_closest_point(navigation_map, parent_transform.xform(_local_positions[i]));
				}
			};
			_job.start(_num_points, POINT_GRID_SNAP_CHUNK_SIZE, std::move(work), "Point grid navmesh snapping");
		}

		if (_stage == STAGE_SNAP) {
			if (!_job.poll()) {
				return false;
			}
			_stage = STAGE_APPLY;
		}

		unsigned int points_since_time_check = POINT_GRID_TIME_CHECK_INTERVAL_POINTS;
		while (_apply_index < _num_points) {
			// A point may be freed while the job runs, so write only ids that still resolve.
			const uint64_t node_id = _node_ids[_apply_index];
			NodeT *node = node_id != 0 ? Object::cast_to<NodeT>(ObjectDB::get_instance(node_id)) : nullptr;
			if (node != nullptr) {
				node->set_global_position(_snapped_positions[_apply_index]);
			}
			++_apply_index;
			if (--points_since_time_check == 0) {
				points_since_time_check = POINT_GRID_TIME_CHECK_INTERVAL_POINTS;
				if (Time::get_singleton()->get_ticks_usec() >= p_time_limit_timestamp_usec) {
					return false;
				}
			}
		}

		cancel();
		return true;
	}

	bool is_active() const {
		return _stage != STAGE_IDLE;
	}

	bool is_waiting_for_job() const {
		return _stage == STAGE_SNAP;
	}

	void cancel() {
		_job.wait();
		_local_positions.clear();
		_snapped_positions.clear();
		_node_ids.clear();
		_capture_index = 0;
		_apply_index = 0;
		_num_points = 0;
		_stage = STAGE_IDLE;
	}

private:
	enum Stage {
		STAGE_IDLE,
		STAGE_CAPTURE,
		STAGE_SNAP,
		STAGE_APPLY,
	};

	using TransformT = typename NNPointGridTransformType<VectorT>::type;

	// Members are destroyed in reverse order, so the job must stay last.
	std::vector<VectorT> _local_positions;
	std::vector<VectorT> _snapped_positions;
	std::vector<uint64_t> _node_ids;
	TransformT _parent_transform;
	RID _navigation_map;
	NNNQSWorkerJob _job;
	unsigned int _num_points = 0;
	unsigned int _capture_index = 0;
	unsigned int _apply_index = 0;
	Stage _stage = STAGE_IDLE;
};

template <typename VectorT, typename NodeT, typename NavigationServerT>
inline bool point_grid_preprocess(NNPointGridSnapper<VectorT, NodeT, NavigationServerT> &r_snapper, bool p_use_threads, unsigned int &r_current_index, bool &r_is_waiting_for_worker, const TypedArray<NodeT> &p_point_grid, const std::vector<VectorT> &p_positions, const VectorT &p_offset, NodeT *p_parent, RID p_navigation_map, NavigationServerT *p_nav_server, uint64_t p_time_limit_timestamp_usec) {
	if (p_use_threads) {
		const bool is_complete = r_snapper.snap(p_point_grid, p_positions, p_offset, p_parent, p_navigation_map, p_nav_server, p_time_limit_timestamp_usec);
		r_is_waiting_for_worker = !is_complete && r_snapper.is_waiting_for_job();
		return is_complete;
	}

	if (r_snapper.is_active()) {
		// Threading was switched off mid-query, so the serial pass restarts rather than skips unapplied points.
		r_snapper.cancel();
		r_current_index = 0;
	}
	return point_grid_snap_to_navigation(r_current_index, p_point_grid, p_positions, p_offset, p_parent, p_navigation_map, p_nav_server, p_time_limit_timestamp_usec);
}

} //namespace godot

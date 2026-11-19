#include "point_grid_2d.h"
#include <godot_cpp/classes/navigation_server2d.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/world2d.hpp>

using namespace godot;

namespace {
const NNPointGridLatticePreset<Vector2> POINT_GRID_LATTICE_PRESETS[4] = {
	{ Vector2(20.0f, 10.0f), Vector2(10.0f, 0.0f) },
	{ Vector2(10.0f, 20.0f), Vector2(-5.0f, 10.0f) },
	{ Vector2(20.0f, 10.0f), Vector2(10.0f, 5.0f) },
	{ Vector2(20.0f, 5.0f), Vector2(10.0f, 0.0f) },
};
} //namespace

NNPointGrid2DSearchSpace::NNPointGrid2DSearchSpace() {
	_offset_vector = Vector2(0.0, 0.0);
	_grid_size = Vector2(150.0f, 150.0f);
	_use_navigation_mesh_positions = true;
	_navigation_map_rid = RID();
	_point_grid_base_spacing_vector = Vector2(20.0f, 10.0f);
	set_point_grid_lattice_type(NNPointGrid2DSearchSpaceLatticeType::SQUARE);
	_point_grid_type = NNPointGrid2DSearchSpaceType::RECTANGLE;
}

NNPointGrid2DSearchSpace::~NNPointGrid2DSearchSpace() {
	destroy_generated_point_grid_nodes();
}

void NNPointGrid2DSearchSpace::destroy_generated_point_grid_nodes() {
	point_grid_destroy_nodes(_generated_point_grid_node_ids, _point_grid, _point_grid_parent_node_id);
}

void NNPointGrid2DSearchSpace::_bind_methods() {
	ADD_SUBGROUP("Configuration", "");

	ClassDB::bind_method(D_METHOD("set_point_grid_parent_node", "point_grid_parent_node"), &NNPointGrid2DSearchSpace::set_point_grid_parent_node);
	ClassDB::bind_method(D_METHOD("get_point_grid_parent_node"), &NNPointGrid2DSearchSpace::get_point_grid_parent_node);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "point_grid_parent_node", PROPERTY_HINT_NODE_TYPE, "Node2D"), "set_point_grid_parent_node", "get_point_grid_parent_node");

	ClassDB::bind_method(D_METHOD("set_point_grid_type", "point_grid_type"), &NNPointGrid2DSearchSpace::set_point_grid_type);
	ClassDB::bind_method(D_METHOD("get_point_grid_type"), &NNPointGrid2DSearchSpace::get_point_grid_type);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "point_grid_type", PROPERTY_HINT_ENUM, "Rectangle:0"), "set_point_grid_type", "get_point_grid_type");

	ClassDB::bind_method(D_METHOD("set_grid_size", "grid_size"), &NNPointGrid2DSearchSpace::set_grid_size);
	ClassDB::bind_method(D_METHOD("get_grid_size"), &NNPointGrid2DSearchSpace::get_grid_size);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "grid_size", PROPERTY_HINT_NONE), "set_grid_size", "get_grid_size");

	ClassDB::bind_method(D_METHOD("set_point_grid_lattice_type", "point_grid_lattice_type"), &NNPointGrid2DSearchSpace::set_point_grid_lattice_type);
	ClassDB::bind_method(D_METHOD("get_point_grid_lattice_type"), &NNPointGrid2DSearchSpace::get_point_grid_lattice_type);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "point_grid_lattice_type", PROPERTY_HINT_ENUM, "Square:0,Triangular:1,CenteredRectangular:2,Rectangular:3,Custom:4"), "set_point_grid_lattice_type", "get_point_grid_lattice_type");

	ClassDB::bind_method(D_METHOD("set_point_grid_base_spacing_vector", "point_grid_base_spacing_vector"), &NNPointGrid2DSearchSpace::set_point_grid_base_spacing_vector2);
	ClassDB::bind_method(D_METHOD("get_point_grid_base_spacing_vector"), &NNPointGrid2DSearchSpace::get_point_grid_base_spacing_vector2);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "point_grid_base_spacing_vector", PROPERTY_HINT_NONE), "set_point_grid_base_spacing_vector", "get_point_grid_base_spacing_vector");

	ClassDB::bind_method(D_METHOD("set_point_grid_lattice_vector", "point_grid_lattice_vector"), &NNPointGrid2DSearchSpace::set_point_grid_lattice_vector2);
	ClassDB::bind_method(D_METHOD("get_point_grid_lattice_vector"), &NNPointGrid2DSearchSpace::get_point_grid_lattice_vector2);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "point_grid_lattice_vector", PROPERTY_HINT_NONE), "set_point_grid_lattice_vector", "get_point_grid_lattice_vector");

	ClassDB::bind_method(D_METHOD("set_offset_vector", "offset_vector"), &NNPointGrid2DSearchSpace::set_offset_vector2);
	ClassDB::bind_method(D_METHOD("get_offset_vector"), &NNPointGrid2DSearchSpace::get_offset_vector2);
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR2, "offset_vector", PROPERTY_HINT_NONE), "set_offset_vector", "get_offset_vector");

	ClassDB::bind_method(D_METHOD("set_use_navigation_mesh_positions", "use_navigation_mesh_positions"), &NNPointGrid2DSearchSpace::set_use_navigation_mesh_positions);
	ClassDB::bind_method(D_METHOD("get_use_navigation_mesh_positions"), &NNPointGrid2DSearchSpace::get_use_navigation_mesh_positions);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_navigation_mesh_positions", PROPERTY_HINT_NONE), "set_use_navigation_mesh_positions", "get_use_navigation_mesh_positions");

	ClassDB::bind_method(D_METHOD("set_navigation_map_rid", "navigation_map_rid"), &NNPointGrid2DSearchSpace::set_navigation_map_rid);
	ClassDB::bind_method(D_METHOD("get_navigation_map_rid"), &NNPointGrid2DSearchSpace::get_navigation_map_rid);
	ADD_PROPERTY(PropertyInfo(Variant::RID, "navigation_map_rid", PROPERTY_HINT_NONE), "set_navigation_map_rid", "get_navigation_map_rid");

	ADD_SUBGROUP("Debugging", "");

	ClassDB::bind_method(D_METHOD("set_point_grid", "point_grid"), &NNPointGrid2DSearchSpace::set_point_grid);
	ClassDB::bind_method(D_METHOD("get_point_grid"), &NNPointGrid2DSearchSpace::get_point_grid);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "point_grid", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_NODE_TYPE, "Node2D")), "set_point_grid", "get_point_grid");
}

// Getters and setters.

void NNPointGrid2DSearchSpace::set_point_grid_type(int point_grid_type) {
	_point_grid_type = point_grid_type;
}

int NNPointGrid2DSearchSpace::get_point_grid_type() const {
	return _point_grid_type;
}

void NNPointGrid2DSearchSpace::set_point_grid_lattice_type(int point_grid_lattice_type) {
	_point_grid_lattice_type = point_grid_lattice_type;
	point_grid_apply_lattice(point_grid_lattice_type, POINT_GRID_LATTICE_PRESETS, _point_grid_base_spacing_vector, _point_grid_lattice_vector);
}

int NNPointGrid2DSearchSpace::get_point_grid_lattice_type() const {
	return _point_grid_lattice_type;
}

void NNPointGrid2DSearchSpace::set_point_grid_base_spacing_vector2(Vector2 point_grid_base_spacing_vector) {
	// Only accept a finite, strictly positive spacing on both axes. An invalid
	// value must not replace the previous one, otherwise later valid
	// assignments would be rejected because of the corrupted stored state.
	if (!point_grid_spacing_is_valid(point_grid_base_spacing_vector)) {
		return;
	}
	_point_grid_base_spacing_vector = point_grid_base_spacing_vector;
}

Vector2 NNPointGrid2DSearchSpace::get_point_grid_base_spacing_vector2() const {
	return _point_grid_base_spacing_vector;
}

void NNPointGrid2DSearchSpace::set_point_grid_lattice_vector2(Vector2 point_grid_lattice_vector) {
	_point_grid_lattice_vector = point_grid_lattice_vector;
}

Vector2 NNPointGrid2DSearchSpace::get_point_grid_lattice_vector2() const {
	return _point_grid_lattice_vector;
}

void NNPointGrid2DSearchSpace::set_grid_size(Vector2 grid_size) {
	_grid_size = grid_size;
}

Vector2 NNPointGrid2DSearchSpace::get_grid_size() const {
	return _grid_size;
}

void NNPointGrid2DSearchSpace::set_navigation_map_rid(RID navigation_map_rid) {
	_navigation_map_rid = navigation_map_rid;
}

RID NNPointGrid2DSearchSpace::get_navigation_map_rid() const {
	return _navigation_map_rid;
}

void NNPointGrid2DSearchSpace::set_use_navigation_mesh_positions(bool use_navigation_mesh_positions) {
	_use_navigation_mesh_positions = use_navigation_mesh_positions;
}

bool NNPointGrid2DSearchSpace::get_use_navigation_mesh_positions() const {
	return _use_navigation_mesh_positions;
}

TypedArray<Node> NNPointGrid2DSearchSpace::get_searchspace_nodes() const {
	return _point_grid;
}

void NNPointGrid2DSearchSpace::set_offset_vector2(Vector2 offset) {
	_offset_vector = offset;
}

Vector2 NNPointGrid2DSearchSpace::get_offset_vector2() const {
	return _offset_vector;
}

Node2D *NNPointGrid2DSearchSpace::_resolve_point_grid_parent_node() const {
	return Object::cast_to<Node2D>(ObjectDB::get_instance(_point_grid_parent_node_id));
}

void NNPointGrid2DSearchSpace::set_point_grid_parent_node(Node2D *point_grid_parent_node) {
	_point_grid_parent_node_id = point_grid_parent_node != nullptr ? ObjectID(point_grid_parent_node->get_instance_id()) : ObjectID();
}

Node2D *NNPointGrid2DSearchSpace::get_point_grid_parent_node() const {
	return _resolve_point_grid_parent_node();
}

void NNPointGrid2DSearchSpace::set_point_grid(TypedArray<Node2D> point_grid) {
	_point_grid = point_grid;
}

TypedArray<Node2D> NNPointGrid2DSearchSpace::get_point_grid() const {
	return _point_grid;
}

// Handling methods.

void NNPointGrid2DSearchSpace::create_point_grid() {
	// This creates the Node2D nodes as hidden child nodes.

	Node2D *point_grid_parent_node = _resolve_point_grid_parent_node();
	if (point_grid_parent_node == nullptr) {
		return;
	}

	// First create the Vector array for the ideal grid.
	_point_grid_default_positions.clear();
	switch (_point_grid_type) {
		case NNPointGrid2DSearchSpaceType::CIRCLE: {
		} break;
		default: {
			// Rectangle.
			create_rectangular_point_grid();
		}
	} //end switch point grid type

	point_grid_create(this, "NNPointGrid2DSearchSpace", point_grid_parent_node, _point_grid_default_positions, _offset_vector, _point_grid, _generated_point_grid_node_ids);
}

void NNPointGrid2DSearchSpace::create_point_grid_nodes(Node2D *template_node) {
	Node2D *point_grid_parent_node = _resolve_point_grid_parent_node();
	if (point_grid_parent_node == nullptr) {
		return;
	}
	point_grid_create_nodes("NNPointGrid2DSearchSpace", point_grid_parent_node, template_node, _point_grid_default_positions, _offset_vector, _point_grid, _generated_point_grid_node_ids);
}

void NNPointGrid2DSearchSpace::create_rectangular_point_grid() {
	_point_grid_default_positions.clear();
	// Defensive progress check: the spacing drives the loop increments, so a
	// non-finite or non-positive value would never terminate the loops below.
	if (!point_grid_spacing_is_valid(_point_grid_base_spacing_vector)) {
		ERR_FAIL_MSG("NNPointGrid2DSearchSpace::create_rectangular_point_grid(): Error, point_grid_base_spacing_vector must be finite and greater than zero on all required axes (x and y).");
		return;
	}
	static const int axis_order[2] = { 1, 0 };
	point_grid_generate_rectangular_positions(_point_grid_default_positions, _grid_size, _point_grid_base_spacing_vector, _point_grid_lattice_vector, axis_order, 2);
}

void NNPointGrid2DSearchSpace::_initialize_search_space() {
	if (_resolve_point_grid_parent_node() == nullptr)
		return;

	// Create the node3d's for the grid.
	create_point_grid();
	_navigation_map_rid = get_viewport()->get_world_2d()->get_navigation_map();
}

bool NNPointGrid2DSearchSpace::preprocess_search_space(uint64_t time_limit_timestamp_usec) {
	Node2D *point_grid_parent_node = _resolve_point_grid_parent_node();
	if (!_use_navigation_mesh_positions || !_navigation_map_rid.is_valid() || point_grid_parent_node == nullptr) {
		return true;
	}
	return point_grid_snap_to_navigation(_current_preprocessing_node_index, _point_grid, _point_grid_default_positions, _offset_vector, point_grid_parent_node, _navigation_map_rid, NavigationServer2D::get_singleton(), time_limit_timestamp_usec);
}

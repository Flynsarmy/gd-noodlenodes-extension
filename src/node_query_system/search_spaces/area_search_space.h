#pragma once

#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// NNArea2DSearchSpace and NNArea3DSearchSpace differ only in their area type;
// the signal callables must be bound to the GDCLASS, so they are passed in.

template <typename TArea>
class AreaSearchSpaceCore {
public:
	void on_area_entered(TArea *p_area) {
		if (p_area == nullptr) {
			return;
		}
		if (_intersecting_areas.has(p_area)) {
			return;
		}
		_intersecting_areas.push_back(p_area);
	}

	void on_area_exited(TArea *p_area) {
		if (p_area == nullptr) {
			return;
		}
		int index = _intersecting_areas.find(p_area);
		if (index < 0) {
			return;
		}
		_intersecting_areas.remove_at(index);
	}

	TArea *get_area() const {
		return Object::cast_to<TArea>(ObjectDB::get_instance(_area_id));
	}

	void set_area(TArea *p_area) {
		_area_id = p_area != nullptr ? ObjectID(p_area->get_instance_id()) : ObjectID();
	}

	TypedArray<TArea> get_intersecting_areas() const {
		return _intersecting_areas;
	}

	void set_intersecting_areas(TypedArray<TArea> p_intersecting_areas) {
		_intersecting_areas = p_intersecting_areas;
	}

	TypedArray<Node> get_searchspace_nodes() const {
		return _intersecting_areas;
	}

	void initialize(const char *p_not_set_error, const Callable &p_on_area_entered, const Callable &p_on_area_exited) {
		TArea *area = get_area();
		ERR_FAIL_COND_MSG(area == nullptr, p_not_set_error);
		area->connect("area_entered", p_on_area_entered);
		area->connect("area_exited", p_on_area_exited);
	}

	void uninitialize(const Callable &p_on_area_entered, const Callable &p_on_area_exited) {
		TArea *area = get_area();
		if (area != nullptr) {
			area->disconnect("area_entered", p_on_area_entered);
			area->disconnect("area_exited", p_on_area_exited);
		}
		_area_id = ObjectID();
	}

private:
	ObjectID _area_id;
	TypedArray<TArea> _intersecting_areas;
};

} //namespace godot

#pragma once

#include "spatial_action_leaf.h"
#include <godot_cpp/classes/character_body2d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/navigation_agent2d.hpp>
#include <godot_cpp/classes/navigation_agent3d.hpp>
#include <godot_cpp/classes/navigation_server2d.hpp>
#include <godot_cpp/classes/navigation_server3d.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/property_info.hpp>

namespace godot {

struct SpatialTypes2D {
	using Vec = Vector2;
	using SpatialNode = Node2D;
	using NavigationAgent = NavigationAgent2D;
	using CharacterBody = CharacterBody2D;
	using NavigationServer = NavigationServer2D;

	static constexpr Variant::Type VEC_TYPE = Variant::VECTOR2;
	static constexpr const char *SPATIAL_NODE_TYPE_NAME = "Node2D";
	static constexpr const char *NAVIGATION_AGENT_TYPE_NAME = "NavigationAgent2D";
};

struct SpatialTypes3D {
	using Vec = Vector3;
	using SpatialNode = Node3D;
	using NavigationAgent = NavigationAgent3D;
	using CharacterBody = CharacterBody3D;
	using NavigationServer = NavigationServer3D;

	static constexpr Variant::Type VEC_TYPE = Variant::VECTOR3;
	static constexpr const char *SPATIAL_NODE_TYPE_NAME = "Node3D";
	static constexpr const char *NAVIGATION_AGENT_TYPE_NAME = "NavigationAgent3D";
};

enum class SpatialTargetLookup {
	FOUND,
	// The target is gone at runtime: a freed node or a missing blackboard value.
	LOST,
	// The leaf is misconfigured; the error has been reported.
	INVALID,
};

// Shared 2D/3D target handling. Not registered with ClassDB, so each concrete
// leaf names NNBTSpatialActionLeaf as its parent in GDCLASS.
template <typename TTypes>
class SpatialActionLeaf : public NNBTSpatialActionLeaf {
public:
	using Vec = typename TTypes::Vec;
	using SpatialNode = typename TTypes::SpatialNode;

	void set_target_position(Vec p_target_position) { _target_position = p_target_position; }
	Vec get_target_position() const { return _target_position; }

protected:
	SpatialTargetLookup _resolve_target(Vec &r_target) {
		switch (get_target_source()) {
			case TARGET_POSITION:
				r_target = _target_position;
				return SpatialTargetLookup::FOUND;
			case TARGET_NODE: {
				ObjectID target_id = _get_target_node_id();
				if (target_id.is_null()) {
					_report_configuration_error("uses TARGET_NODE but has no target_node");
					return SpatialTargetLookup::INVALID;
				}
				return _resolve_target_object(ObjectDB::get_instance(target_id), r_target, "target_node");
			}
			case TARGET_BLACKBOARD: {
				String key = get_target_key();
				if (key.is_empty()) {
					_report_configuration_error("uses TARGET_BLACKBOARD but has an empty target_key");
					return SpatialTargetLookup::INVALID;
				}
				Variant value = get_blackboard(key);
				if (value.get_type() == TTypes::VEC_TYPE) {
					r_target = value;
					return SpatialTargetLookup::FOUND;
				}
				if (value.get_type() == Variant::NIL) {
					return SpatialTargetLookup::LOST;
				}
				if (value.get_type() != Variant::OBJECT) {
					_report_configuration_error(vformat("reads blackboard key '%s' holding a %s, not a %s or %s", key,
							Variant::get_type_name(value.get_type()), Variant::get_type_name(TTypes::VEC_TYPE), TTypes::SPATIAL_NODE_TYPE_NAME));
					return SpatialTargetLookup::INVALID;
				}
				// A freed object reads back as null, which is a lost target.
				return _resolve_target_object(value.get_validated_object(), r_target, vformat("blackboard key '%s'", key));
			}
		}
		return SpatialTargetLookup::INVALID;
	}

	// Hides the target properties the current target_source does not use and
	// narrows the target_node picker to this leaf's dimension.
	void _validate_property(PropertyInfo &p_property) const {
		TargetSource source = get_target_source();
		if (p_property.name == StringName("target_node")) {
			p_property.hint_string = TTypes::SPATIAL_NODE_TYPE_NAME;
			if (source != TARGET_NODE) {
				p_property.usage &= ~PROPERTY_USAGE_EDITOR;
			}
		} else if ((p_property.name == StringName("target_position") && source != TARGET_POSITION) ||
				(p_property.name == StringName("target_key") && source != TARGET_BLACKBOARD)) {
			p_property.usage &= ~PROPERTY_USAGE_EDITOR;
		}
	}

private:
	Vec _target_position;

	SpatialTargetLookup _resolve_target_object(Object *p_object, Vec &r_target, const String &p_origin) {
		if (p_object == nullptr) {
			return SpatialTargetLookup::LOST;
		}
		SpatialNode *node = Object::cast_to<SpatialNode>(p_object);
		if (node == nullptr) {
			_report_configuration_error(vformat("targets %s, which is a %s, not a %s", p_origin, p_object->get_class(), TTypes::SPATIAL_NODE_TYPE_NAME));
			return SpatialTargetLookup::INVALID;
		}
		r_target = node->get_global_position();
		return SpatialTargetLookup::FOUND;
	}
};

// Binds target_position on a concrete leaf. godot-cpp binds a method under the
// class that declares it, and the accessors live in an unregistered base.
template <typename TClass, typename TTypes>
void bind_spatial_target_methods() {
	using Vec = typename TTypes::Vec;
	const StringName &class_name = TClass::get_class_static();
	ClassDB::bind_method(D_METHOD("set_target_position", "target_position"), static_cast<void (TClass::*)(Vec)>(&TClass::set_target_position));
	ClassDB::bind_method(D_METHOD("get_target_position"), static_cast<Vec (TClass::*)() const>(&TClass::get_target_position));
	ClassDB::add_property(class_name, PropertyInfo(TTypes::VEC_TYPE, "target_position"), "set_target_position", "get_target_position");
}

} //namespace godot

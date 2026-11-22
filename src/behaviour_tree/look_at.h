#pragma once

#include "spatial_target.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/core/property_info.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <type_traits>

namespace godot {

// Shared facing behaviour for NNBTLookAt2D and NNBTLookAt3D. Not registered
// with ClassDB, so each concrete leaf names NNBTSpatialActionLeaf as its parent.
template <typename TDerived, typename TTypes>
class LookAtLeaf : public SpatialActionLeaf<TTypes> {
public:
	using Vec = typename TTypes::Vec;
	using SpatialNode = typename TTypes::SpatialNode;
	// Named here because lookup does not reach into the dependent base class.
	using Status = NNBTActionLeaf::Status;

	LookAtLeaf() {
		_turn_rate = Math::TAU;
		_angle_tolerance = Math::deg_to_rad(5.0f);
	}

	void set_rotated_node(SpatialNode *p_rotated_node) {
		_rotated_node_id = p_rotated_node != nullptr ? ObjectID(p_rotated_node->get_instance_id()) : ObjectID();
	}

	SpatialNode *get_rotated_node() const {
		return Object::cast_to<SpatialNode>(ObjectDB::get_instance(_rotated_node_id));
	}

	void set_turn_rate(float p_turn_rate) {
		_turn_rate = MAX(p_turn_rate, 0.0f);
	}

	float get_turn_rate() const {
		return _turn_rate;
	}

	void set_angle_tolerance(float p_angle_tolerance) {
		_angle_tolerance = CLAMP(p_angle_tolerance, 0.0f, Math::PI);
	}

	float get_angle_tolerance() const {
		return _angle_tolerance;
	}

protected:
	Status _tick(float p_delta) override {
		if (Engine::get_singleton()->is_editor_hint()) {
			return Status::FAILURE;
		}

		SpatialNode *rotated_node = _resolve_rotated_node();
		if (rotated_node == nullptr) {
			return Status::FAILURE;
		}

		Vec target;
		if (this->_resolve_target(target) != SpatialTargetLookup::FOUND) {
			return Status::FAILURE;
		}

		Vec direction = target - rotated_node->get_global_position();
		if (direction.length_squared() <= DEGENERATE_DIRECTION_SQUARED) {
			return Status::SUCCESS;
		}

		if constexpr (std::is_same_v<TTypes, SpatialTypes2D>) {
			return _tick_2d(rotated_node, direction, p_delta);
		} else {
			return _tick_3d(rotated_node, direction, p_delta);
		}
	}

private:
	static constexpr float DEGENERATE_DIRECTION_SQUARED = 1e-12f;

	ObjectID _rotated_node_id;
	float _turn_rate;
	float _angle_tolerance;

	SpatialNode *_resolve_rotated_node() {
		if (!_rotated_node_id.is_null()) {
			// A freed rotated node is a runtime loss, not a configuration error.
			Object *object = ObjectDB::get_instance(_rotated_node_id);
			if (object == nullptr) {
				return nullptr;
			}
			SpatialNode *rotated_node = Object::cast_to<SpatialNode>(object);
			if (rotated_node == nullptr) {
				this->_report_configuration_error(vformat("rotates a %s, which is not a %s", object->get_class(), TTypes::SPATIAL_NODE_TYPE_NAME));
			}
			return rotated_node;
		}

		Node *actor = this->get_actor();
		if (actor == nullptr) {
			this->_report_configuration_error("has no rotated_node and no actor to rotate");
			return nullptr;
		}
		SpatialNode *rotated_node = Object::cast_to<SpatialNode>(actor);
		if (rotated_node == nullptr) {
			this->_report_configuration_error(vformat("has an actor that is a %s, not a %s", actor->get_class(), TTypes::SPATIAL_NODE_TYPE_NAME));
		}
		return rotated_node;
	}

	float _turn_step(float p_remaining, float p_delta) const {
		return _turn_rate <= 0.0f ? p_remaining : MIN(_turn_rate * p_delta, p_remaining);
	}

	Status _tick_2d(SpatialNode *p_rotated_node, const Vec &p_direction, float p_delta) {
		float current = p_rotated_node->get_global_rotation();
		float difference = Math::angle_difference(current, p_direction.angle());
		float remaining = Math::abs(difference);
		if (remaining <= _angle_tolerance) {
			return Status::SUCCESS;
		}
		float step = _turn_step(remaining, p_delta);
		p_rotated_node->set_global_rotation(current + (difference > 0.0f ? step : -step));
		return remaining - step <= _angle_tolerance ? Status::SUCCESS : Status::RUNNING;
	}

	Status _tick_3d(SpatialNode *p_rotated_node, const Vec &p_direction, float p_delta) {
		const TDerived *derived = static_cast<const TDerived *>(this);
		Basis basis = p_rotated_node->get_global_basis();
		if (derived->get_yaw_only()) {
			return _tick_yaw_only(p_rotated_node, basis, p_direction, p_delta);
		}

		if (Math::abs(p_direction.normalized().dot(Vector3::UP)) >= 1.0f - 1e-6f) {
			return Status::SUCCESS;
		}

		Quaternion current = basis.get_rotation_quaternion();
		Quaternion desired = Basis::looking_at(p_direction, Vector3::UP, derived->get_use_model_front()).get_rotation_quaternion();
		float remaining = current.angle_to(desired);
		if (remaining <= _angle_tolerance) {
			return Status::SUCCESS;
		}
		float step = _turn_step(remaining, p_delta);
		// Pre-multiplying a global rotation preserves the node's scale.
		Quaternion turn = current.slerp(desired, step / remaining) * current.inverse();
		p_rotated_node->set_global_basis(Basis(turn) * basis);
		return remaining - step <= _angle_tolerance ? Status::SUCCESS : Status::RUNNING;
	}

	Status _tick_yaw_only(SpatialNode *p_rotated_node, const Basis &p_basis, const Vec &p_direction, float p_delta) {
		Vector2 flat_direction(p_direction.x, p_direction.z);
		if (flat_direction.length_squared() <= DEGENERATE_DIRECTION_SQUARED) {
			return Status::SUCCESS;
		}

		float model_front = static_cast<const TDerived *>(this)->get_use_model_front() ? 1.0f : -1.0f;
		Vector2 z_axis(p_basis.get_column(2).x, p_basis.get_column(2).z);
		float current = z_axis.length_squared() > DEGENERATE_DIRECTION_SQUARED ? Math::atan2(z_axis.x, z_axis.y) : p_rotated_node->get_global_rotation().y;
		float desired = Math::atan2(flat_direction.x * model_front, flat_direction.y * model_front);
		float difference = Math::angle_difference(current, desired);
		float remaining = Math::abs(difference);
		if (remaining <= _angle_tolerance) {
			return Status::SUCCESS;
		}
		// Pre-multiplying the global rotation leaves the node's pitch and roll untouched.
		float step = _turn_step(remaining, p_delta);
		p_rotated_node->set_global_basis(Basis(Vector3::UP, difference > 0.0f ? step : -step) * p_basis);
		return remaining - step <= _angle_tolerance ? Status::SUCCESS : Status::RUNNING;
	}
};

template <typename TClass, typename TTypes>
void bind_look_at_methods() {
	using SpatialNode = typename TTypes::SpatialNode;
	const StringName &class_name = TClass::get_class_static();

	ClassDB::bind_method(D_METHOD("set_rotated_node", "rotated_node"), static_cast<void (TClass::*)(SpatialNode *)>(&TClass::set_rotated_node));
	ClassDB::bind_method(D_METHOD("get_rotated_node"), static_cast<SpatialNode *(TClass::*)() const>(&TClass::get_rotated_node));
	ClassDB::add_property(class_name, PropertyInfo(Variant::OBJECT, "rotated_node", PROPERTY_HINT_NODE_TYPE, TTypes::SPATIAL_NODE_TYPE_NAME), "set_rotated_node", "get_rotated_node");

	ClassDB::bind_method(D_METHOD("set_turn_rate", "turn_rate"), static_cast<void (TClass::*)(float)>(&TClass::set_turn_rate));
	ClassDB::bind_method(D_METHOD("get_turn_rate"), static_cast<float (TClass::*)() const>(&TClass::get_turn_rate));
	ClassDB::add_property(class_name, PropertyInfo(Variant::FLOAT, "turn_rate", PROPERTY_HINT_RANGE, "0,1440,0.1,or_greater,radians_as_degrees,suffix:°/s"), "set_turn_rate", "get_turn_rate");

	ClassDB::bind_method(D_METHOD("set_angle_tolerance", "angle_tolerance"), static_cast<void (TClass::*)(float)>(&TClass::set_angle_tolerance));
	ClassDB::bind_method(D_METHOD("get_angle_tolerance"), static_cast<float (TClass::*)() const>(&TClass::get_angle_tolerance));
	ClassDB::add_property(class_name, PropertyInfo(Variant::FLOAT, "angle_tolerance", PROPERTY_HINT_RANGE, "0,180,0.1,radians_as_degrees"), "set_angle_tolerance", "get_angle_tolerance");
}

} //namespace godot

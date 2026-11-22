#pragma once

#include "spatial_target.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/navigation_agent2d.hpp>
#include <godot_cpp/classes/navigation_agent3d.hpp>
#include <godot_cpp/classes/navigation_server2d.hpp>
#include <godot_cpp/classes/navigation_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/core/property_info.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <type_traits>

namespace godot {

// Shared logic for the 2D and 3D move-to leaves. Not registered with ClassDB,
// so each concrete leaf names NNBTSpatialActionLeaf as its parent in GDCLASS.
template <typename TDerived, typename TTypes>
class MoveToLeaf : public SpatialActionLeaf<TTypes> {
public:
	using Vec = typename TTypes::Vec;
	using SpatialNode = typename TTypes::SpatialNode;
	using NavigationAgent = typename TTypes::NavigationAgent;
	using CharacterBody = typename TTypes::CharacterBody;
	using NavigationServer = typename TTypes::NavigationServer;
	using Status = NNBTTaskNodes::Status;

	MoveToLeaf() {
		_speed = 0.0f;
		_arrival_distance = 0.0f;
		_repath_distance = 0.0f;
		_velocity_key = String();
		_apply_movement = false;
		_is_run_active = false;
		_has_submitted_target = false;
		_is_velocity_computed_connected = false;
	}

	~MoveToLeaf() {
		_disconnect_velocity_computed();
	}

	void set_navigation_agent(NavigationAgent *p_navigation_agent) {
		_navigation_agent_id = p_navigation_agent != nullptr ? ObjectID(p_navigation_agent->get_instance_id()) : ObjectID();
	}

	NavigationAgent *get_navigation_agent() const {
		return Object::cast_to<NavigationAgent>(ObjectDB::get_instance(_navigation_agent_id));
	}

	void set_speed(float p_speed) { _speed = p_speed; }
	float get_speed() const { return _speed; }

	void set_arrival_distance(float p_arrival_distance) { _arrival_distance = p_arrival_distance; }
	float get_arrival_distance() const { return _arrival_distance; }

	void set_repath_distance(float p_repath_distance) { _repath_distance = p_repath_distance; }
	float get_repath_distance() const { return _repath_distance; }

	void set_velocity_key(const String &p_velocity_key) { _velocity_key = p_velocity_key; }
	String get_velocity_key() const { return _velocity_key; }

	void set_apply_movement(bool p_apply_movement) { _apply_movement = p_apply_movement; }
	bool get_apply_movement() const { return _apply_movement; }

protected:
	void _set_defaults(float p_speed, float p_arrival_distance, float p_repath_distance) {
		_speed = p_speed;
		_arrival_distance = p_arrival_distance;
		_repath_distance = p_repath_distance;
	}

	// Concrete leaves override _exit_tree themselves: godot-cpp cannot bind a
	// virtual that an unregistered template base declares.
	void _on_exit_tree() { _cleanup_run(); }

	virtual NNBTTaskNodes::Status _tick(float delta) override {
		if (Engine::get_singleton()->is_editor_hint()) {
			return Status::FAILURE;
		}

		NavigationAgent *agent = _resolve_agent();
		if (agent == nullptr) {
			return Status::FAILURE;
		}
		SpatialNode *body = Object::cast_to<SpatialNode>(agent->get_parent());
		if (body == nullptr) {
			this->_report_configuration_error(vformat("has a %s that is not a child of a %s", TTypes::NAVIGATION_AGENT_TYPE_NAME, TTypes::SPATIAL_NODE_TYPE_NAME));
			return Status::FAILURE;
		}
		if (!_is_run_active) {
			_is_run_active = true;
			_run_agent_id = agent->get_instance_id();
			_run_body_id = body->get_instance_id();
		}

		Vec target;
		if (this->_resolve_target(target) != SpatialTargetLookup::FOUND) {
			return Status::FAILURE;
		}

		Vec body_position = body->get_global_position();
		if (body_position.distance_to(target) <= _arrival_distance) {
			return Status::SUCCESS;
		}

		RID map = agent->get_navigation_map();
		uint32_t map_iteration = NavigationServer::get_singleton()->map_get_iteration_id(map);
		if (!_has_submitted_target || _submitted_target.distance_to(target) > _repath_distance) {
			agent->set_target_position(target);
			_submitted_target = target;
			_has_submitted_target = true;
		}
		// A map that has never synchronized cannot answer a path query yet.
		if (map_iteration == 0) {
			_stop_agent(agent);
			return Status::RUNNING;
		}

		// The query result is applied lazily by get_next_path_position(), so it
		// must run before the path can be inspected. An empty path then means
		// the query is still pending, not that the target is unreachable.
		Vec next_path_position = agent->get_next_path_position();
		if (agent->get_current_navigation_path().is_empty()) {
			_stop_agent(agent);
			return Status::RUNNING;
		}

		if (agent->get_final_position().distance_to(_submitted_target) > _arrival_distance) {
			return Status::FAILURE;
		}

		Vec steering_point = agent->is_navigation_finished() ? target : next_path_position;
		Vec desired_velocity = steering_point - body_position;
		if (desired_velocity.length_squared() > 0.0f) {
			desired_velocity = desired_velocity.normalized() * _speed;
		} else {
			desired_velocity = Vec();
		}

		agent->set_velocity(desired_velocity);
		_write_velocity(desired_velocity);
		_sync_avoidance(agent);
		if (_apply_movement && !agent->get_avoidance_enabled()) {
			_apply_velocity(body, desired_velocity, delta);
		}
		return Status::RUNNING;
	}

	virtual void _on_after_run(float delta) override {
		_cleanup_run();
		NNBTTaskNodes::_on_after_run(delta);
	}

	virtual void _on_interrupt(float delta) override {
		_cleanup_run();
		NNBTTaskNodes::_on_interrupt(delta);
	}

private:
	ObjectID _navigation_agent_id;
	ObjectID _run_agent_id;
	ObjectID _run_body_id;

	float _speed;
	float _arrival_distance;
	float _repath_distance;
	String _velocity_key;
	bool _apply_movement;

	bool _is_run_active;
	bool _has_submitted_target;
	Vec _submitted_target;

	bool _is_velocity_computed_connected;
	ObjectID _velocity_computed_agent_id;

	NavigationAgent *_resolve_agent() {
		if (!_navigation_agent_id.is_null()) {
			// A freed agent is a runtime loss, not a cue to fall back to the actor's agent.
			return Object::cast_to<NavigationAgent>(ObjectDB::get_instance(_navigation_agent_id));
		}

		Node *actor = this->get_actor();
		if (actor == nullptr) {
			this->_report_configuration_error(vformat("has no navigation_agent and no actor with a direct %s child", TTypes::NAVIGATION_AGENT_TYPE_NAME));
			return nullptr;
		}
		for (int i = 0; i < actor->get_child_count(); ++i) {
			NavigationAgent *child_agent = Object::cast_to<NavigationAgent>(actor->get_child(i));
			if (child_agent != nullptr) {
				return child_agent;
			}
		}
		this->_report_configuration_error(vformat("has no navigation_agent and its actor has no direct %s child", TTypes::NAVIGATION_AGENT_TYPE_NAME));
		return nullptr;
	}

	void _apply_velocity(SpatialNode *p_body, Vec p_velocity, float p_delta) {
		CharacterBody *character_body = Object::cast_to<CharacterBody>(p_body);
		if (character_body == nullptr) {
			p_body->set_global_position(p_body->get_global_position() + p_velocity * p_delta);
			return;
		}

		if constexpr (std::is_same_v<TTypes, SpatialTypes3D>) {
			if (character_body->get_motion_mode() == CharacterBody3D::MOTION_MODE_GROUNDED) {
				// Keeps the full speed on slopes and an avoidance slow-down alike.
				Vec horizontal = Vec(p_velocity.x, 0.0f, p_velocity.z);
				if (horizontal.length_squared() > 0.0f) {
					horizontal = horizontal.normalized() * p_velocity.length();
				}
				// Gravity owns the vertical channel, so a ground move never fights it.
				p_velocity = Vec(horizontal.x, character_body->get_velocity().y, horizontal.z);
			}
		}

		character_body->set_velocity(p_velocity);
		character_body->move_and_slide();
	}

	void _on_velocity_computed(Vec p_safe_velocity) {
		if (!_apply_movement) {
			return;
		}
		SpatialNode *body = Object::cast_to<SpatialNode>(ObjectDB::get_instance(_run_body_id));
		if (body == nullptr) {
			return;
		}
		_apply_velocity(body, p_safe_velocity, static_cast<float>(this->get_physics_process_delta_time()));
	}

	Callable _velocity_computed_callable() {
		return callable_mp(this, &MoveToLeaf::_on_velocity_computed);
	}

	void _sync_avoidance(NavigationAgent *p_agent) {
		if (!_apply_movement || !p_agent->get_avoidance_enabled()) {
			_disconnect_velocity_computed();
			return;
		}
		if (_is_velocity_computed_connected && _velocity_computed_agent_id == ObjectID(p_agent->get_instance_id())) {
			return;
		}
		_disconnect_velocity_computed();
		p_agent->connect("velocity_computed", _velocity_computed_callable());
		_is_velocity_computed_connected = true;
		_velocity_computed_agent_id = p_agent->get_instance_id();
	}

	void _disconnect_velocity_computed() {
		if (!_is_velocity_computed_connected) {
			return;
		}
		NavigationAgent *agent = Object::cast_to<NavigationAgent>(ObjectDB::get_instance(_velocity_computed_agent_id));
		if (agent != nullptr) {
			Callable callable = _velocity_computed_callable();
			if (agent->is_connected("velocity_computed", callable)) {
				agent->disconnect("velocity_computed", callable);
			}
		}
		_is_velocity_computed_connected = false;
		_velocity_computed_agent_id = ObjectID();
	}

	void _stop_agent(NavigationAgent *p_agent) {
		p_agent->set_velocity(Vec());
		_write_velocity(Vec());
	}

	void _write_velocity(Vec p_velocity) {
		if (_velocity_key.is_empty() || this->get_blackboard_resource() == nullptr) {
			return;
		}
		this->set_blackboard(_velocity_key, p_velocity);
	}

	void _cleanup_run() {
		_disconnect_velocity_computed();
		if (!_is_run_active) {
			return;
		}

		NavigationAgent *agent = Object::cast_to<NavigationAgent>(ObjectDB::get_instance(_run_agent_id));
		SpatialNode *body = Object::cast_to<SpatialNode>(ObjectDB::get_instance(_run_body_id));
		if (agent != nullptr) {
			if (body != nullptr) {
				agent->set_target_position(body->get_global_position());
			}
			agent->set_velocity(Vec());
		}
		if (_apply_movement && body != nullptr) {
			_zero_body_velocity(body);
		}
		_write_velocity(Vec());

		_is_run_active = false;
		_has_submitted_target = false;
		_run_agent_id = ObjectID();
		_run_body_id = ObjectID();
	}

	void _zero_body_velocity(SpatialNode *p_body) {
		CharacterBody *character_body = Object::cast_to<CharacterBody>(p_body);
		if (character_body == nullptr) {
			return;
		}
		Vec velocity = Vec();
		if constexpr (std::is_same_v<TTypes, SpatialTypes3D>) {
			if (character_body->get_motion_mode() == CharacterBody3D::MOTION_MODE_GROUNDED) {
				velocity = character_body->get_velocity();
				velocity.x = 0.0f;
				velocity.z = 0.0f;
			}
		}
		character_body->set_velocity(velocity);
	}
};

template <typename TClass, typename TTypes>
void bind_move_to_methods(const char *p_speed_hint) {
	using NavigationAgent = typename TTypes::NavigationAgent;

	const StringName &class_name = TClass::get_class_static();

	ClassDB::bind_method(D_METHOD("set_navigation_agent", "navigation_agent"), static_cast<void (TClass::*)(NavigationAgent *)>(&TClass::set_navigation_agent));
	ClassDB::bind_method(D_METHOD("get_navigation_agent"), static_cast<NavigationAgent *(TClass::*)() const>(&TClass::get_navigation_agent));
	ClassDB::add_property(class_name, PropertyInfo(Variant::OBJECT, "navigation_agent", PROPERTY_HINT_NODE_TYPE, TTypes::NAVIGATION_AGENT_TYPE_NAME), "set_navigation_agent", "get_navigation_agent");

	ClassDB::bind_method(D_METHOD("set_speed", "speed"), static_cast<void (TClass::*)(float)>(&TClass::set_speed));
	ClassDB::bind_method(D_METHOD("get_speed"), static_cast<float (TClass::*)() const>(&TClass::get_speed));
	ClassDB::add_property(class_name, PropertyInfo(Variant::FLOAT, "speed", PROPERTY_HINT_RANGE, p_speed_hint), "set_speed", "get_speed");

	ClassDB::bind_method(D_METHOD("set_arrival_distance", "arrival_distance"), static_cast<void (TClass::*)(float)>(&TClass::set_arrival_distance));
	ClassDB::bind_method(D_METHOD("get_arrival_distance"), static_cast<float (TClass::*)() const>(&TClass::get_arrival_distance));
	ClassDB::add_property(class_name, PropertyInfo(Variant::FLOAT, "arrival_distance", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_arrival_distance", "get_arrival_distance");

	ClassDB::bind_method(D_METHOD("set_repath_distance", "repath_distance"), static_cast<void (TClass::*)(float)>(&TClass::set_repath_distance));
	ClassDB::bind_method(D_METHOD("get_repath_distance"), static_cast<float (TClass::*)() const>(&TClass::get_repath_distance));
	ClassDB::add_property(class_name, PropertyInfo(Variant::FLOAT, "repath_distance", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), "set_repath_distance", "get_repath_distance");

	ClassDB::bind_method(D_METHOD("set_velocity_key", "velocity_key"), static_cast<void (TClass::*)(const String &)>(&TClass::set_velocity_key));
	ClassDB::bind_method(D_METHOD("get_velocity_key"), static_cast<String (TClass::*)() const>(&TClass::get_velocity_key));
	ClassDB::add_property(class_name, PropertyInfo(Variant::STRING, "velocity_key"), "set_velocity_key", "get_velocity_key");

	ClassDB::bind_method(D_METHOD("set_apply_movement", "apply_movement"), static_cast<void (TClass::*)(bool)>(&TClass::set_apply_movement));
	ClassDB::bind_method(D_METHOD("get_apply_movement"), static_cast<bool (TClass::*)() const>(&TClass::get_apply_movement));
	ClassDB::add_property(class_name, PropertyInfo(Variant::BOOL, "apply_movement"), "set_apply_movement", "get_apply_movement");
}

} //namespace godot

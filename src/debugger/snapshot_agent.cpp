#ifdef DEBUG_ENABLED

#include "../agent_behaviours/action.h"
#include "../agent_behaviours/action_group.h"
#include "../agent_behaviours/agent.h"
#include "../agent_behaviours/behaviour.h"
#include "../agent_behaviours/behaviour_group.h"
#include "../agent_behaviours/consideration.h"
#include "../agent_behaviours/consideration_group.h"
#include "../agent_behaviours/sensor_group.h"
#include "../agent_behaviours/sensors.h"
#include "../agent_behaviours/sensors/nqs_query.h"
#include "../blackboard.h"
#include "../response_curve.h"
#include "debug_root.h"
#include "snapshot_common.h"

using namespace godot;

namespace {

constexpr int CURVE_SAMPLES = 32;

String _evaluation_method_name(NoodleNodes::EvaluationMethod p_method) {
	switch (p_method) {
		case NoodleNodes::EVALUATION_SUM:
			return "sum";
		case NoodleNodes::EVALUATION_MIN:
			return "min";
		case NoodleNodes::EVALUATION_MAX:
			return "max";
		case NoodleNodes::EVALUATION_MEAN:
			return "mean";
		case NoodleNodes::EVALUATION_MULTIPLY:
			return "multiply";
		case NoodleNodes::EVALUATION_FIRST_NON_ZERO:
			return "first_non_zero";
	}
	return "sum";
}

PackedVector2Array _curve_samples(const Ref<Resource> &p_curve) {
	PackedVector2Array points;
	if (p_curve.is_null()) {
		return points;
	}
	for (int i = 0; i < CURVE_SAMPLES; i++) {
		const float x = (float)i / (float)(CURVE_SAMPLES - 1);
		points.push_back(Vector2(x, NNResponseCurve::sample_activation_curve(p_curve, x, 0.0f)));
	}
	return points;
}

Dictionary _behaviour_extras(NNBehaviours *p_behaviour, const ObjectID &p_current_behaviour_id, const ObjectID &p_current_group_id) {
	Dictionary extras;
	const bool group = p_behaviour->is_behaviour_group();
	extras["kind"] = group ? "behaviour_group" : "behaviour";
	extras["score"] = p_behaviour->get_score();
	const ObjectID node_id = ObjectID(p_behaviour->get_instance_id());
	extras["selected"] = node_id == (group ? p_current_group_id : p_current_behaviour_id);

	// NNBehaviour and NNBehaviourGroup each keep their own evaluation stamp.
	uint64_t evaluated_usec = 0;
	if (NNBehaviour *behaviour = Object::cast_to<NNBehaviour>(p_behaviour)) {
		evaluated_usec = behaviour->get_last_evaluated_timestamp();
	} else if (NNBehaviourGroup *behaviour_group = Object::cast_to<NNBehaviourGroup>(p_behaviour)) {
		evaluated_usec = behaviour_group->get_last_evaluated_timestamp();
	}
	extras["last_evaluated_usec"] = (int64_t)evaluated_usec;

	if (NNBehaviour *behaviour = Object::cast_to<NNBehaviour>(p_behaviour)) {
		extras["cooldown_remaining"] = behaviour->get_debug_cooldown_remaining();
		extras["cooldown_turns_remaining"] = behaviour->get_debug_cooldown_turns_remaining();
	} else {
		extras["cooldown_remaining"] = 0.0;
		extras["cooldown_turns_remaining"] = 0;
	}
	return extras;
}

Dictionary _consideration_extras(NNConsiderations *p_consideration) {
	Dictionary extras;
	extras["kind"] = Object::cast_to<NNConsiderationGroup>(p_consideration) != nullptr ? "consideration_group" : "consideration";
	extras["score"] = p_consideration->get_score();
	if (NNConsideration *consideration = Object::cast_to<NNConsideration>(p_consideration)) {
		extras["input"] = consideration->get_activation_input_value();
		extras["curve"] = _curve_samples(consideration->get_activation_curve());
	} else {
		extras["input"] = 0.0;
		extras["curve"] = PackedVector2Array();
	}
	if (NNConsiderationGroup *group = Object::cast_to<NNConsiderationGroup>(p_consideration)) {
		extras["aggregation"] = _evaluation_method_name(group->get_evaluation_method());
	}
	return extras;
}

Dictionary _sensor_extras(NNSensors *p_sensor) {
	Dictionary extras;
	extras["kind"] = Object::cast_to<NNSensorGroup>(p_sensor) != nullptr ? "sensor_group" : "sensor";
	extras["value"] = NNBlackboard::sanitize_debug_value(p_sensor->get_sensor_value());
	extras["last_evaluated_usec"] = (int64_t)p_sensor->get_last_evaluated_timestamp();
	if (NNNQSQuerySensor *query_sensor = Object::cast_to<NNNQSQuerySensor>(p_sensor)) {
		extras["nqs_search_space"] = nn_debug_id(query_sensor->get_nqs_search_space());
	}
	return extras;
}

Dictionary _action_extras(NNActions *p_action, NNAction *p_current_action) {
	Dictionary extras;
	extras["kind"] = Object::cast_to<NNActionGroup>(p_action) != nullptr ? "action_group" : "action";
	const bool active = p_current_action != nullptr && (p_action == p_current_action || p_action->is_ancestor_of(p_current_action));
	extras["active"] = active;
	extras["finished"] = p_action->get_is_finished();
	return extras;
}

Dictionary _node_extras(const Node *p_node, NNAction *p_current_action, const ObjectID &p_current_behaviour_id, const ObjectID &p_current_group_id) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(const_cast<Node *>(p_node));
	if (noodle == nullptr) {
		Dictionary extras;
		extras["kind"] = "other";
		return extras;
	}

	if (NNBehaviours *behaviour = Object::cast_to<NNBehaviours>(noodle)) {
		return _behaviour_extras(behaviour, p_current_behaviour_id, p_current_group_id);
	}
	if (NNConsiderations *consideration = Object::cast_to<NNConsiderations>(noodle)) {
		return _consideration_extras(consideration);
	}
	if (NNSensors *sensor = Object::cast_to<NNSensors>(noodle)) {
		return _sensor_extras(sensor);
	}
	if (NNActions *action = Object::cast_to<NNActions>(noodle)) {
		return _action_extras(action, p_current_action);
	}

	Dictionary extras;
	extras["kind"] = "other";
	return extras;
}

void _append_target_path(NoodleNodes *p_target, NoodleNodes *p_root, std::vector<int64_t> &r_path) {
	NoodleNodes *node = p_target;
	while (node != nullptr) {
		r_path.push_back((int64_t)node->get_instance_id());
		if (node == p_root) {
			break;
		}
		node = Object::cast_to<NoodleNodes>(node->get_parent());
	}
}

} //namespace

Dictionary NNAgent::get_debug_snapshot() const {
	NNAgent *agent = const_cast<NNAgent *>(this);
	Dictionary snapshot = nn_debug_envelope(agent, &_debug_root, "agent");

	NNBehaviour *current_behaviour = agent->peek_current_behaviour();
	NNBehaviourGroup *current_behaviour_group = agent->peek_current_behaviour_group();
	NNAction *current_action = agent->peek_current_action();
	snapshot["current_behaviour"] = nn_debug_id(current_behaviour);
	snapshot["last_behaviour"] = nn_debug_id(agent->peek_last_behaviour());
	snapshot["current_behaviour_group"] = nn_debug_id(current_behaviour_group);
	snapshot["current_action"] = nn_debug_id(current_action);
	snapshot["top_scoring"] = agent->get_debug_top_scoring();
	snapshot["current_behaviour_bias"] = agent->get_current_behaviour_bias();
	snapshot["num_behaviours_to_select"] = agent->get_num_behaviours_to_select();

	const ObjectID current_behaviour_id = current_behaviour != nullptr ? ObjectID(current_behaviour->get_instance_id()) : ObjectID();
	const ObjectID current_group_id = current_behaviour_group != nullptr ? ObjectID(current_behaviour_group->get_instance_id()) : ObjectID();
	Array nodes;
	Dictionary root_entry = nn_debug_node_entry(agent, 0);
	root_entry.merge(_node_extras(agent, current_action, current_behaviour_id, current_group_id));
	nodes.push_back(root_entry);
	std::vector<NNDebugPortal> portals;
	nn_debug_append_descendants(agent, (int64_t)agent->get_instance_id(), nodes, [current_action, current_behaviour_id, current_group_id](const Node *p_node) -> Dictionary { return _node_extras(p_node, current_action, current_behaviour_id, current_group_id); }, portals);
	snapshot["nodes"] = nodes;

	std::vector<int64_t> active_path;
	active_path.push_back((int64_t)agent->get_instance_id());
	if (current_behaviour != nullptr) {
		_append_target_path(current_behaviour, agent, active_path);
	}
	if (current_action != nullptr) {
		_append_target_path(current_action, agent, active_path);
	}
	snapshot["active_hosted_root"] = nn_debug_active_hosted_root(active_path, portals);
	return snapshot;
}

#endif

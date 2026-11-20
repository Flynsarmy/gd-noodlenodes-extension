#ifdef DEBUG_ENABLED

#include "snapshot_st.h"

#include "../state_tree/guard.h"
#include "../state_tree/history.h"
#include "../state_tree/node.h"
#include "../state_tree/parallel.h"
#include "../state_tree/root.h"
#include "../state_tree/transition.h"
#include "debug_root.h"
#include "snapshot_common.h"

using namespace godot;

namespace {

Array _trigger_names(int p_trigger_types) {
	Array names;
	const int ordered[] = { NNSTRoot::TriggerType::EVENT, NNSTRoot::TriggerType::STATE_ENTER, NNSTRoot::TriggerType::PROPERTY_CHANGE, NNSTRoot::TriggerType::STATE_CHANGE };
	for (int trigger : ordered) {
		if ((p_trigger_types & trigger) != 0) {
			names.push_back(String(nn_debug_trigger_name(trigger)));
		}
	}
	return names;
}

int64_t _initial_state_id(NoodleNodes *p_node) {
	if (NNSTNode *state = Object::cast_to<NNSTNode>(p_node)) {
		const NodePath initial_state = state->get_initial_state();
		if (!initial_state.is_empty()) {
			Node *target = state->get_node_or_null(initial_state);
			if (NNSTTickedNodes *target_state = Object::cast_to<NNSTTickedNodes>(target)) {
				return (int64_t)target_state->get_instance_id();
			}
			if (NNSTHistory *history = Object::cast_to<NNSTHistory>(target)) {
				const std::vector<NNSTHistoryStateSnapshot> snapshot = history->_get_restore_snapshot();
				if (!snapshot.empty()) {
					return (int64_t)snapshot[0].state_id;
				}
			}
			return 0;
		}
	}

	for (int i = 0; i < p_node->get_child_count(); i++) {
		if (NNSTTickedNodes *child = Object::cast_to<NNSTTickedNodes>(p_node->get_child(i))) {
			return (int64_t)child->get_instance_id();
		}
	}
	return 0;
}

int64_t _transition_target_id(NNSTTransition *p_transition) {
	Node *target = p_transition->get_node_or_null(p_transition->get_to());
	if (NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(target)) {
		return (int64_t)state->get_instance_id();
	}
	if (NNSTHistory *history = Object::cast_to<NNSTHistory>(target)) {
		const std::vector<NNSTHistoryStateSnapshot> snapshot = history->_get_restore_snapshot();
		if (!snapshot.empty()) {
			return (int64_t)snapshot[0].state_id;
		}
	}
	return 0;
}

Dictionary _branch_extras(NNSTBranchNodes *p_branch) {
	Dictionary extras;
	if (Object::cast_to<NNSTRoot>(p_branch) != nullptr) {
		extras["kind"] = "root";
	} else if (Object::cast_to<NNSTParallel>(p_branch) != nullptr) {
		extras["kind"] = "parallel";
	} else {
		extras["kind"] = "state";
	}

	extras["active"] = p_branch->get_is_active();
	extras["initial"] = _initial_state_id(p_branch);

	NNSTTickedNodes *ticked = Object::cast_to<NNSTTickedNodes>(p_branch);
	if (ticked == nullptr) {
		extras["final"] = false;
		extras["score"] = 0.0;
		extras["last_visited_usec"] = (int64_t)0;
		extras["last_evaluated_usec"] = (int64_t)0;
		extras["pending_transition"] = Variant();
		return extras;
	}

	extras["final"] = ticked->get_is_final();
	extras["score"] = ticked->get_score();
	extras["last_visited_usec"] = (int64_t)ticked->get_last_visited_timestamp();
	extras["last_evaluated_usec"] = (int64_t)ticked->get_last_evaluated_timestamp();

	const ObjectID pending_id = ticked->get_debug_pending_transition_id();
	if (!pending_id.is_null() && ObjectDB::get_instance(pending_id) != nullptr) {
		Dictionary pending;
		pending["transition"] = (int64_t)pending_id;
		pending["initial_delay"] = ticked->get_debug_pending_initial_delay();
		pending["remaining_delay"] = ticked->get_debug_pending_remaining_delay();
		extras["pending_transition"] = pending;
	} else {
		extras["pending_transition"] = Variant();
	}
	return extras;
}

Dictionary _node_extras(const Node *p_node) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(const_cast<Node *>(p_node));
	if (NNSTHistory *history = Object::cast_to<NNSTHistory>(noodle)) {
		Dictionary extras;
		extras["kind"] = "history";
		extras["deep"] = history->get_deep();
		extras["default_state"] = nn_debug_id(Object::cast_to<NNSTTickedNodes>(history->get_node_or_null(history->get_default_state())));
		extras["remembered"] = history->get_debug_remembered_ids();
		return extras;
	}

	if (NNSTTransition *transition = Object::cast_to<NNSTTransition>(noodle)) {
		Dictionary extras;
		extras["kind"] = "transition";
		extras["event"] = transition->get_event_name();
		extras["to"] = _transition_target_id(transition);
		extras["delay"] = transition->get_delay_in_seconds();
		const Ref<NNSTGuard> guard = transition->get_guard();
		extras["guard"] = guard.is_valid() ? guard->get_debug_description() : String();
		extras["triggers"] = _trigger_names(transition->get_supported_trigger_types());
		return extras;
	}

	if (NNSTBranchNodes *branch = Object::cast_to<NNSTBranchNodes>(noodle)) {
		return _branch_extras(branch);
	}

	Dictionary extras;
	extras["kind"] = "other";
	return extras;
}

void _collect_active_states(NNSTBranchNodes *p_branch, Array &r_active_states, std::vector<int64_t> &r_path) {
	const std::vector<ObjectID> active_ids = p_branch->_get_active_state_ids();
	for (const ObjectID &id : active_ids) {
		NNSTTickedNodes *state = Object::cast_to<NNSTTickedNodes>(ObjectDB::get_instance(id));
		if (state == nullptr) {
			continue;
		}
		const int64_t state_id = (int64_t)state->get_instance_id();
		r_active_states.push_back(state_id);
		r_path.push_back(state_id);
		_collect_active_states(state, r_active_states, r_path);
	}
}

} //namespace

namespace godot {

const char *nn_debug_trigger_name(int p_trigger_type) {
	switch (p_trigger_type) {
		case NNSTRoot::TriggerType::EVENT:
			return "event";
		case NNSTRoot::TriggerType::STATE_ENTER:
			return "state_enter";
		case NNSTRoot::TriggerType::PROPERTY_CHANGE:
			return "property_change";
		case NNSTRoot::TriggerType::STATE_CHANGE:
			return "state_change";
		default:
			return "";
	}
}

void nn_debug_record_guard(NNDebugRoot *p_debug_root, int64_t p_transition_id, const Ref<NNSTGuard> &p_guard, const char *p_trigger, bool p_result) {
	if (p_debug_root == nullptr) {
		return;
	}

	String detail;
	if (p_guard.is_valid()) {
		detail = p_guard->get_debug_detail();
		if (detail.is_empty()) {
			detail = p_guard->get_debug_description() + " => " + (p_result ? "true" : "false");
		}
	}

	Dictionary fields;
	fields["transition"] = p_transition_id;
	fields["trigger"] = String(p_trigger);
	fields["result"] = p_result;
	fields["detail"] = detail;
	p_debug_root->record("st_guard", fields);
}

} //namespace godot

Dictionary NNSTRoot::get_debug_snapshot() const {
	NNSTRoot *root = const_cast<NNSTRoot *>(this);
	Dictionary snapshot = nn_debug_envelope(root, &_debug_root, "st");

	Array active_states;
	std::vector<int64_t> active_path;
	if (root->get_is_active()) {
		active_states.push_back((int64_t)root->get_instance_id());
		active_path.push_back((int64_t)root->get_instance_id());
		_collect_active_states(root, active_states, active_path);
	}

	snapshot["active_states"] = active_states;
	snapshot["halted"] = root->get_is_event_processing_halted();
	snapshot["expression_properties"] = root->_debug_get_expression_properties();

	Array nodes;
	Dictionary root_entry = nn_debug_node_entry(root, 0);
	root_entry.merge(_node_extras(root));
	nodes.push_back(root_entry);
	std::vector<NNDebugPortal> portals;
	nn_debug_append_descendants(root, (int64_t)root->get_instance_id(), nodes, [](const Node *p_node) -> Dictionary { return _node_extras(p_node); }, portals);
	snapshot["nodes"] = nodes;
	snapshot["active_hosted_root"] = nn_debug_active_hosted_root(active_path, portals);
	return snapshot;
}

Dictionary NNSTRoot::_debug_get_expression_properties() const {
	Dictionary properties;
	NNBlackboard *board = get_blackboard_resource();
	if (board == nullptr) {
		return properties;
	}

	const Array initial_keys = _initial_expression_properties.keys();
	for (int i = 0; i < initial_keys.size(); i++) {
		const Variant &key = initial_keys[i];
		if (key.get_type() == Variant::STRING || key.get_type() == Variant::STRING_NAME) {
			const String name = String(key);
			properties[name] = NNBlackboard::sanitize_debug_value(board->get_value(name));
		}
	}

	for (const String &name : _debug_expression_property_names) {
		properties[name] = NNBlackboard::sanitize_debug_value(board->get_value(name));
	}
	return properties;
}

#endif

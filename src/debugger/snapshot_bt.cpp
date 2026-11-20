#ifdef DEBUG_ENABLED

#include "../behaviour_tree/cooldown.h"
#include "../behaviour_tree/cooldown_ticks.h"
#include "../behaviour_tree/delayer.h"
#include "../behaviour_tree/limiter.h"
#include "../behaviour_tree/repeater.h"
#include "../behaviour_tree/root.h"
#include "../behaviour_tree/run_nqs_query.h"
#include "../behaviour_tree/score_based_picker.h"
#include "../behaviour_tree/time_limiter.h"
#include "debug_root.h"
#include "snapshot_common.h"

using namespace godot;

namespace {

String _status_name(NNBTNodes::Status p_status) {
	switch (p_status) {
		case NNBTNodes::RUNNING:
			return "running";
		case NNBTNodes::SUCCESS:
			return "success";
		case NNBTNodes::FAILURE:
			return "failure";
		case NNBTNodes::SKIP:
			return "skip";
	}
	return "unvisited";
}

String _node_status(const NNBTNodes *p_node) {
	if (p_node->get_last_visited_timestamp() == 0) {
		return "unvisited";
	}
	if (p_node->get_debug_interrupted()) {
		return "interrupted";
	}
	if (p_node->get_is_running()) {
		return "running";
	}
	return _status_name(p_node->get_tick_result());
}

Dictionary _badges(NNBTNodes *p_node) {
	Dictionary badges;
	if (NNBTCooldown *cooldown = Object::cast_to<NNBTCooldown>(p_node)) {
		badges["cooldown_remaining"] = cooldown->get_remaining_cooldown();
	}
	if (NNBTCooldownTicks *cooldown_ticks = Object::cast_to<NNBTCooldownTicks>(p_node)) {
		badges["cooldown_ticks_remaining"] = cooldown_ticks->get_current_cooldown_ticks();
	}
	if (NNBTRepeater *repeater = Object::cast_to<NNBTRepeater>(p_node)) {
		badges["repeat_count"] = repeater->get_times_repeated();
		badges["repeat_limit"] = repeater->get_repeat_times();
	}
	if (NNBTLimiter *limiter = Object::cast_to<NNBTLimiter>(p_node)) {
		badges["limiter_uses"] = limiter->get_debug_current_repeat_times();
		badges["limiter_max"] = limiter->get_max_repeat_times();
	}
	if (NNBTDelayer *delayer = Object::cast_to<NNBTDelayer>(p_node)) {
		const float remaining = delayer->get_wait_time() - delayer->get_time_waited();
		badges["delay_remaining"] = remaining > 0.0f ? remaining : 0.0f;
	}
	if (NNBTTimeLimiter *time_limiter = Object::cast_to<NNBTTimeLimiter>(p_node)) {
		const float remaining = time_limiter->get_time_limit() - time_limiter->get_time_spent();
		badges["time_remaining"] = remaining > 0.0f ? remaining : 0.0f;
	}
	if (NNBTRunNQSQuery *query = Object::cast_to<NNBTRunNQSQuery>(p_node)) {
		badges["nqs_search_space"] = nn_debug_id(query->get_nqs_search_space());
	}
	if (NNBTScoreBasedPicker *picker = Object::cast_to<NNBTScoreBasedPicker>(p_node)) {
		badges["picker_choice"] = picker->get_debug_selected_child_id();
	}
	return badges;
}

Dictionary _node_extras(const Node *p_node) {
	Dictionary extras;
	NNBTNodes *node = Object::cast_to<NNBTNodes>(const_cast<Node *>(p_node));
	if (node == nullptr) {
		extras["status"] = "unvisited";
		extras["is_running"] = false;
		extras["last_visited_usec"] = (int64_t)0;
		extras["last_evaluated_usec"] = (int64_t)0;
		extras["score"] = 0.0;
		extras["badges"] = Dictionary();
		return extras;
	}

	extras["status"] = _node_status(node);
	extras["is_running"] = node->get_is_running();
	extras["last_visited_usec"] = (int64_t)node->get_last_visited_timestamp();
	extras["last_evaluated_usec"] = (int64_t)node->get_last_evaluated_timestamp();
	extras["score"] = node->get_score();
	extras["badges"] = _badges(node);
	return extras;
}

} //namespace

Dictionary NNBTRoot::get_debug_snapshot() const {
	NNBTRoot *root = const_cast<NNBTRoot *>(this);
	Dictionary snapshot = nn_debug_envelope(root, &_debug_root, "bt");

	NNBTNodes *running_node = root->get_running_action();
	snapshot["running_node"] = nn_debug_id(running_node);
	snapshot["tick_count"] = (int64_t)root->get_debug_tick_count();
	snapshot["elapsed_time"] = root->get_elapsed_time();
	snapshot["last_result"] = _node_status(root);

	Array nodes;
	Dictionary root_entry = nn_debug_node_entry(root, 0);
	root_entry.merge(_node_extras(root));
	nodes.push_back(root_entry);
	std::vector<NNDebugPortal> portals;
	nn_debug_append_descendants(root, (int64_t)root->get_instance_id(), nodes, [](const Node *p_node) -> Dictionary { return _node_extras(p_node); }, portals);
	snapshot["nodes"] = nodes;

	std::vector<int64_t> active_path;
	NNBTNodes *active = running_node;
	while (active != nullptr) {
		active_path.push_back((int64_t)active->get_instance_id());
		if (active == root) {
			break;
		}
		active = Object::cast_to<NNBTNodes>(active->get_parent());
	}
	snapshot["active_hosted_root"] = nn_debug_active_hosted_root(active_path, portals);
	return snapshot;
}

#endif

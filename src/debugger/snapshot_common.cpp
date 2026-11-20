#ifdef DEBUG_ENABLED

#include "snapshot_common.h"

#include "../blackboard.h"
#include "../host.h"
#include "../noodle_nodes.h"
#include "debug_root.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <unordered_map>

using namespace godot;

namespace {

// Collects one snapshot's flat node list. Hosted subtrees are portals, so the
// walk stops at a nested root and records it against the node that owns it.
class SubtreeCollector {
public:
	SubtreeCollector(const Node *p_root, Array &r_nodes, const std::function<Dictionary(const Node *)> &p_extras, std::vector<NNDebugPortal> &r_portals, int p_root_entry_index) :
			_root(p_root), _nodes(r_nodes), _extras(p_extras), _portals(r_portals), _root_entry_index(p_root_entry_index) {
	}

	void collect(const Node *p_parent, int64_t p_parent_id) {
		for (int i = 0; i < p_parent->get_child_count(); i++) {
			Node *child = p_parent->get_child(i);
			NoodleNodes *noodle = Object::cast_to<NoodleNodes>(child);
			if (noodle != nullptr && noodle->is_root()) {
				_add_portal(noodle);
				continue;
			}

			Dictionary entry = nn_debug_node_entry(child, p_parent_id);
			entry.merge(_extras(child));
			_index_by_id[(int64_t)child->get_instance_id()] = (int)_entries.size();
			_entries.push_back(entry);
			collect(child, (int64_t)child->get_instance_id());
		}
	}

	void flush() {
		for (const Dictionary &entry : _entries) {
			_nodes.push_back(entry);
		}
	}

private:
	void _add_portal(NoodleNodes *p_hosted) {
		// A nested root that is not formally hosted (a root parent stops
		// nn_find_host_ancestor) still belongs to the nearest ancestor node; the
		// fixtures report the NNAgent under an NNSTRoot this way.
		NoodleNodes *host = nn_find_host_ancestor(p_hosted);
		if (host == nullptr) {
			for (Node *ancestor = p_hosted->get_parent(); ancestor != nullptr; ancestor = ancestor->get_parent()) {
				host = Object::cast_to<NoodleNodes>(ancestor);
				if (host != nullptr || ancestor == _root) {
					break;
				}
			}
		}
		if (host == nullptr) {
			return;
		}

		const int64_t host_id = (int64_t)host->get_instance_id();
		std::unordered_map<int64_t, int>::const_iterator found = _index_by_id.find(host_id);

		const int64_t hosted_id = (int64_t)p_hosted->get_instance_id();
		for (const NNDebugPortal &portal : _portals) {
			if (portal.host_id == host_id) {
				// One portal per host node; extra nested roots stay reachable
				// through the root registry.
				return;
			}
		}

		int depth = 0;
		for (const Node *node = host; node != nullptr && node != _root; node = node->get_parent()) {
			depth++;
		}

		if (found != _index_by_id.end()) {
			Dictionary entry = _entries[(size_t)found->second];
			entry["hosted_root"] = hosted_id;
			_entries[(size_t)found->second] = entry;
		} else if (host == _root && _root_entry_index >= 0) {
			Dictionary entry = _nodes[_root_entry_index];
			entry["hosted_root"] = hosted_id;
			_nodes.set(_root_entry_index, entry);
		} else {
			return;
		}
		_portals.push_back({ host_id, hosted_id, depth });
	}

	const Node *_root;
	Array &_nodes;
	const std::function<Dictionary(const Node *)> &_extras;
	std::vector<NNDebugPortal> &_portals;
	int _root_entry_index;
	std::vector<Dictionary> _entries;
	std::unordered_map<int64_t, int> _index_by_id;
};

bool _is_root_active(NoodleNodes *p_root) {
	NNHostedRoot *hosted_root = p_root->get_hosted_root();
	if (hosted_root != nullptr && hosted_root->is_hosted()) {
		return hosted_root->is_active();
	}
	return p_root->get_is_enabled() && p_root->is_inside_tree();
}

} //namespace

namespace godot {

Dictionary nn_debug_envelope(NoodleNodes *p_root, const NNDebugRoot *p_debug_root, const char *p_type) {
	Dictionary snapshot;
	snapshot["id"] = (int64_t)p_root->get_instance_id();
	snapshot["type"] = String(p_type);
	snapshot["class"] = String(p_root->get_class());
	snapshot["name"] = String(p_root->get_name());
	snapshot["time_usec"] = (int64_t)Time::get_singleton()->get_ticks_usec();
	snapshot["frame"] = (int64_t)Engine::get_singleton()->get_process_frames();
	snapshot["enabled"] = p_root->get_is_enabled();
	snapshot["active"] = _is_root_active(p_root);
	snapshot["last_seq"] = p_debug_root->get_last_seq();
	snapshot["blackboard"] = nn_debug_blackboard(p_root);
	snapshot["active_hosted_root"] = (int64_t)0;
	return snapshot;
}

Dictionary nn_debug_node_entry(const Node *p_node, int64_t p_parent_id) {
	Dictionary entry;
	entry["id"] = (int64_t)p_node->get_instance_id();
	entry["parent"] = p_parent_id;
	entry["name"] = String(p_node->get_name());
	entry["class"] = String(p_node->get_class());
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(const_cast<Node *>(p_node));
	entry["enabled"] = noodle != nullptr ? noodle->get_is_enabled() : true;
	return entry;
}

Variant nn_debug_blackboard(NoodleNodes *p_root) {
	NNBlackboard *board = p_root->get_blackboard_resource();
	if (board == nullptr) {
		return Variant();
	}

	Dictionary data;
	data["id"] = (int64_t)board->get_instance_id();
	data["values"] = board->get_debug_data();
	return data;
}

void nn_debug_append_descendants(const Node *p_parent, int64_t p_parent_id, Array &r_nodes,
		const std::function<Dictionary(const Node *)> &p_extras, std::vector<NNDebugPortal> &r_portals, int p_root_entry_index) {
	SubtreeCollector collector(p_parent, r_nodes, p_extras, r_portals, p_root_entry_index);
	collector.collect(p_parent, p_parent_id);
	collector.flush();
}

int64_t nn_debug_active_hosted_root(const std::vector<int64_t> &p_active_path, const std::vector<NNDebugPortal> &p_portals) {
	int64_t active_root_id = 0;
	int best_depth = -1;
	for (const NNDebugPortal &portal : p_portals) {
		if (portal.depth <= best_depth) {
			continue;
		}
		bool on_path = false;
		for (const int64_t &id : p_active_path) {
			if (id == portal.host_id) {
				on_path = true;
				break;
			}
		}
		if (!on_path) {
			continue;
		}

		NoodleNodes *hosted = Object::cast_to<NoodleNodes>(ObjectDB::get_instance((uint64_t)portal.root_id));
		if (hosted == nullptr || !_is_root_active(hosted)) {
			continue;
		}
		active_root_id = portal.root_id;
		best_depth = portal.depth;
	}
	return active_root_id;
}

NNDebugRoot *nn_debug_watched_root(NoodleNodes *p_node) {
	if (p_node == nullptr) {
		return nullptr;
	}

	NNDebugRoot *debug_root = p_node->get_debug_root();
	if (debug_root == nullptr) {
		NoodleNodes *ancestor = p_node->get_ancestor_root();
		if (ancestor != nullptr) {
			debug_root = ancestor->get_debug_root();
		}
	}
	return debug_root != nullptr && debug_root->is_watched() ? debug_root : nullptr;
}

} //namespace godot

#endif

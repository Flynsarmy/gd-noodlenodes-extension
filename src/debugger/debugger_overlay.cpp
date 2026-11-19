#ifdef DEBUG_ENABLED
#include "debugger_overlay.h"
#include <godot_cpp/classes/h_slider.hpp>
#include <godot_cpp/classes/packed_scene.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/timer.hpp>

#include "../agent_behaviours/agent.h"
#include "../agent_behaviours/behaviour.h"
#include "../agent_behaviours/behaviours.h"
#include "../agent_behaviours/considerations.h"
#include "../agent_behaviours/sensors.h"
#include "../behaviour_tree/root.h"
#include "../host.h"
#include "../htn/parallel_task.h"
#include "../htn/root.h"
#include "../htn/task.h"
#include "../noodle_nodes.h"
#include "../state_tree/root.h"
#include "../state_tree/ticked_nodes.h"

using namespace godot;

static const char *const NN_DEBUGGER_OVERLAY_SCENE_PATH = "res://addons/noodle_nodes/debugger/noodle_nodes_debugger_overlay.tscn";

NNDebuggerOverlay *NNDebuggerOverlay::_singleton = nullptr;

NNDebuggerOverlay *NNDebuggerOverlay::get_singleton() {
	return _singleton;
}

NNDebuggerOverlay::NNDebuggerOverlay() {
	_singleton = this;
	_type_selection = nullptr;
	_root_selection = nullptr;
	_debug_messages = nullptr;
	_selected_tree = nullptr;
	_current_type_selection = -1;
	_current_root_selection = -1;
	_registry_revision = 0;
	_rendered_type_selection = -2;
	_rendered_registry_revision = 0;
}

NNDebuggerOverlay::~NNDebuggerOverlay() {
	_clear_view();
	_overlay_scene_id = ObjectID();
	if (_singleton == this) {
		_singleton = nullptr;
	}
}

void NNDebuggerOverlay::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_as_child_of", "debugger_parent_node"), &NNDebuggerOverlay::add_as_child_of);

	// UI Handling methods.
	ClassDB::bind_method(D_METHOD("on_type_item_selected", "item"), &NNDebuggerOverlay::on_type_item_selected);
	ClassDB::bind_method(D_METHOD("on_root_item_selected", "item"), &NNDebuggerOverlay::on_root_item_selected);
	ClassDB::bind_method(D_METHOD("on_exit_tree"), &NNDebuggerOverlay::on_exit_tree);
	ClassDB::bind_method(D_METHOD("update_ui"), &NNDebuggerOverlay::update_ui);
}

// Godot virtuals.

// Handling methods.

int NNDebuggerOverlay::_register_object(std::vector<ObjectID> &registry, uint64_t instance_id) {
	ERR_FAIL_COND_V_MSG(instance_id == 0, -1, "NNDebuggerOverlay: Cannot register an invalid instance ID.");

	ObjectID object_id(instance_id);
	for (unsigned int i = 0; i < registry.size(); i++) {
		if (registry[i] == object_id) {
			return (int)i;
		}
	}

	int index = (int)registry.size();
	registry.push_back(object_id);
	_registry_revision++;
	return index;
}

void NNDebuggerOverlay::_deregister_object(std::vector<ObjectID> &registry, uint64_t instance_id) {
	ObjectID object_id(instance_id);
	for (std::vector<ObjectID>::iterator it = registry.begin(); it != registry.end(); ++it) {
		if (*it == object_id) {
			registry.erase(it);
			_registry_revision++;
			return;
		}
	}
}

int NNDebuggerOverlay::register_behaviour_tree(uint64_t instance_id) {
	return _register_object(_behaviour_trees, instance_id);
}

int NNDebuggerOverlay::register_state_tree(uint64_t instance_id) {
	return _register_object(_state_trees, instance_id);
}

int NNDebuggerOverlay::register_ai_agent(uint64_t instance_id) {
	return _register_object(_agents, instance_id);
}

int NNDebuggerOverlay::register_htn_root(uint64_t instance_id) {
	return _register_object(_htn_roots, instance_id);
}

void NNDebuggerOverlay::deregister_behaviour_tree(uint64_t instance_id) {
	_deregister_object(_behaviour_trees, instance_id);
}

void NNDebuggerOverlay::deregister_state_tree(uint64_t instance_id) {
	_deregister_object(_state_trees, instance_id);
}

void NNDebuggerOverlay::deregister_ai_agent(uint64_t instance_id) {
	_deregister_object(_agents, instance_id);
}

void NNDebuggerOverlay::deregister_htn_root(uint64_t instance_id) {
	_deregister_object(_htn_roots, instance_id);
}

Control *NNDebuggerOverlay::_get_overlay_scene() const {
	if (_overlay_scene_id.is_null()) {
		return nullptr;
	}
	return Object::cast_to<Control>(ObjectDB::get_instance((uint64_t)_overlay_scene_id));
}

void NNDebuggerOverlay::_clear_view() {
	_type_selection = nullptr;
	_root_selection = nullptr;
	_debug_messages = nullptr;
	_selected_tree = nullptr;
	// The selection survives so a reparented overlay resumes where it was. The
	// rendered type is invalidated so the root list is rebuilt on the next refresh.
	_rendered_type_selection = -2;
	_rendered_registry_revision = 0;
}

void NNDebuggerOverlay::_clear_selected_tree() {
	if (_selected_tree != nullptr) {
		_selected_tree->clear();
	}
}

bool NNDebuggerOverlay::_bind_overlay_view(Control *overlay) {
	ERR_FAIL_NULL_V_MSG(overlay, false, "NNDebuggerOverlay::_bind_overlay_view(): The overlay scene is null.");

	OptionButton *type_selection = Object::cast_to<OptionButton>(overlay->get_node_or_null("HBoxContainer/VBoxContainer/SelectType"));
	ERR_FAIL_NULL_V_MSG(type_selection, false, "NNDebuggerOverlay::_bind_overlay_view(): Missing 'HBoxContainer/VBoxContainer/SelectType' OptionButton in the overlay scene.");

	OptionButton *root_selection = Object::cast_to<OptionButton>(overlay->get_node_or_null("HBoxContainer/VBoxContainer/SelectTree"));
	ERR_FAIL_NULL_V_MSG(root_selection, false, "NNDebuggerOverlay::_bind_overlay_view(): Missing 'HBoxContainer/VBoxContainer/SelectTree' OptionButton in the overlay scene.");

	RichTextLabel *debug_messages = Object::cast_to<RichTextLabel>(overlay->get_node_or_null("HBoxContainer/TextVBoxContainer/DebugTextArea"));
	ERR_FAIL_NULL_V_MSG(debug_messages, false, "NNDebuggerOverlay::_bind_overlay_view(): Missing 'HBoxContainer/TextVBoxContainer/DebugTextArea' RichTextLabel in the overlay scene.");

	Tree *selected_tree = Object::cast_to<Tree>(overlay->get_node_or_null("SelectedTree"));
	ERR_FAIL_NULL_V_MSG(selected_tree, false, "NNDebuggerOverlay::_bind_overlay_view(): Missing 'SelectedTree' Tree in the overlay scene.");

	Timer *refresh_timer = Object::cast_to<Timer>(overlay->get_node_or_null("RefreshTimer"));
	ERR_FAIL_NULL_V_MSG(refresh_timer, false, "NNDebuggerOverlay::_bind_overlay_view(): Missing 'RefreshTimer' Timer in the overlay scene.");

	// Connections are checked before use so reopening a detached overlay does not
	// attach duplicate callbacks.
	const Callable exit_callable(this, "on_exit_tree");
	if (!overlay->is_connected("tree_exited", exit_callable)) {
		overlay->connect("tree_exited", exit_callable);
	}

	const Callable type_selected_callable(this, "on_type_item_selected");
	if (!type_selection->is_connected("item_selected", type_selected_callable)) {
		type_selection->connect("item_selected", type_selected_callable);
	}

	const Callable root_selected_callable(this, "on_root_item_selected");
	if (!root_selection->is_connected("item_selected", root_selected_callable)) {
		root_selection->connect("item_selected", root_selected_callable);
	}

	const Callable update_callable(this, "update_ui");
	if (!refresh_timer->is_connected("timeout", update_callable)) {
		refresh_timer->connect("timeout", update_callable);
	}

	_type_selection = type_selection;
	_root_selection = root_selection;
	_debug_messages = debug_messages;
	_selected_tree = selected_tree;
	return true;
}

void NNDebuggerOverlay::add_as_child_of(Node *debugger_parent_node) {
	ERR_FAIL_NULL_MSG(debugger_parent_node, "NNDebuggerOverlay::add_as_child_of(): The debugger parent node must not be null.");
	ERR_FAIL_COND_MSG(debugger_parent_node->is_queued_for_deletion(), "NNDebuggerOverlay::add_as_child_of(): The debugger parent node is queued for deletion.");

	Control *overlay = _get_overlay_scene();
	if (overlay != nullptr && overlay->is_queued_for_deletion()) {
		// Detach the dying overlay immediately so a reopen in the same frame can
		// reuse the expected node name and does not create two live siblings.
		Node *old_parent = overlay->get_parent();
		if (old_parent != nullptr) {
			old_parent->remove_child(overlay);
		}
		_overlay_scene_id = ObjectID();
		overlay = nullptr;
	}

	if (overlay != nullptr && overlay->get_parent() != nullptr) {
		if (overlay->get_parent() != debugger_parent_node) {
			ERR_FAIL_MSG("NNDebuggerOverlay::add_as_child_of(): The debugger overlay is already attached to another parent.");
		}

		// Already attached. Rebind defensively (the view may have been cleared by
		// a tree exit) but never add a second overlay or duplicate connections.
		if (!_bind_overlay_view(overlay)) {
			_clear_view();
			return;
		}
		update_ui();
		return;
	}

	if (overlay == nullptr) {
		Ref<PackedScene> scene_template = ResourceLoader::get_singleton()->load(NN_DEBUGGER_OVERLAY_SCENE_PATH);
		ERR_FAIL_COND_MSG(scene_template.is_null(), String("NNDebuggerOverlay::add_as_child_of(): Failed to load '") + String(NN_DEBUGGER_OVERLAY_SCENE_PATH) + "'.");

		Node *instance = scene_template->instantiate();
		ERR_FAIL_NULL_MSG(instance, "NNDebuggerOverlay::add_as_child_of(): Failed to instantiate the debugger overlay scene.");

		Control *new_overlay = Object::cast_to<Control>(instance);
		if (new_overlay == nullptr) {
			memdelete(instance);
			ERR_FAIL_MSG("NNDebuggerOverlay::add_as_child_of(): The debugger overlay scene root must be a Control.");
		}

		_overlay_scene_id = new_overlay->get_instance_id();
		if (!_bind_overlay_view(new_overlay)) {
			_overlay_scene_id = ObjectID();
			_clear_view();
			memdelete(new_overlay);
			return;
		}

		debugger_parent_node->add_child(new_overlay);
		on_type_item_selected(0);
		update_ui();
		return;
	}

	// The overlay is alive but detached. Reuse it instead of creating a second
	// overlay, which also keeps its connections singular.
	if (!_bind_overlay_view(overlay)) {
		_overlay_scene_id = ObjectID();
		_clear_view();
		memdelete(overlay);
		return;
	}

	debugger_parent_node->add_child(overlay);
	on_type_item_selected(0);
	update_ui();
}

// UI Handling methods.

const std::vector<ObjectID> *NNDebuggerOverlay::_get_registry_for_type(int type) const {
	switch (type) {
		case 1: {
			return &_agents;
		} break;
		case 2: {
			return &_behaviour_trees;
		} break;
		case 3: {
			return &_state_trees;
		} break;
		case 4: {
			return &_htn_roots;
		} break;
		default: {
		} break;
	}
	return nullptr;
}

Node *NNDebuggerOverlay::_resolve_root_for_type(int type, ObjectID instance_id) const {
	if (instance_id.is_null()) {
		return nullptr;
	}

	Object *object = ObjectDB::get_instance((uint64_t)instance_id);
	if (object == nullptr) {
		return nullptr;
	}

	switch (type) {
		case 1: {
			return Object::cast_to<NNAgent>(object);
		} break;
		case 2: {
			return Object::cast_to<NNBTRoot>(object);
		} break;
		case 3: {
			return Object::cast_to<NNSTRoot>(object);
		} break;
		case 4: {
			return Object::cast_to<NNHTNRoot>(object);
		} break;
		default: {
		} break;
	}
	return nullptr;
}

String NNDebuggerOverlay::_host_path(const NoodleNodes *host) {
	std::vector<String> names;
	for (const NoodleNodes *node = host; node != nullptr; node = Object::cast_to<NoodleNodes>(node->get_parent())) {
		names.push_back(String(node->get_name()));
		if (node->is_root()) {
			break;
		}
	}

	String path;
	for (int i = (int)names.size() - 1; i >= 0; i--) {
		if (!path.is_empty()) {
			path += "/";
		}
		path += names[(size_t)i];
	}
	return path;
}

String NNDebuggerOverlay::_root_label(Node *root) const {
	ERR_FAIL_NULL_V(root, String());

	Node *owner = root->get_owner();
	String label;
	if (owner != nullptr) {
		label = String(owner->get_name()) + ": " + String(root->get_name());
	} else {
		label = String(root->get_name()) + " (no owner)";
	}

	NoodleNodes *host = nn_find_host_ancestor(root);
	if (host != nullptr) {
		label += String(" (hosted in ") + _host_path(host) + ")";
	}
	return label;
}

String NNDebuggerOverlay::_root_status_text(Node *root) {
	String type_name;
	if (Object::cast_to<NNAgent>(root) != nullptr) {
		type_name = "Agent";
	} else if (Object::cast_to<NNBTRoot>(root) != nullptr) {
		type_name = "Behaviour Tree";
	} else if (Object::cast_to<NNSTRoot>(root) != nullptr) {
		type_name = "State Tree";
	} else if (Object::cast_to<NNHTNRoot>(root) != nullptr) {
		type_name = "HTN";
	}

	if (type_name.is_empty()) {
		return type_name;
	}
	if (nn_find_host_ancestor(root) != nullptr) {
		type_name += " (hosted)";
	}
	return type_name;
}

String NNDebuggerOverlay::_active_path_status(Node *node) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(node);
	if (noodle == nullptr) {
		return String();
	}

	NoodleNodes *ancestor_root = noodle->get_ancestor_root();
	if (Object::cast_to<NNBTRoot>(ancestor_root) != nullptr || Object::cast_to<NNHTNRoot>(ancestor_root) != nullptr) {
		return "running";
	}
	if (Object::cast_to<NNSTRoot>(ancestor_root) != nullptr) {
		return "active";
	}
	if (Object::cast_to<NNAgent>(ancestor_root) != nullptr) {
		return "current";
	}
	return String();
}

NNHostedRoot *NNDebuggerOverlay::_hosted_root_of(Node *root) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(root);
	if (noodle == nullptr) {
		return nullptr;
	}

	NNHostedRoot *hosted_root = noodle->get_hosted_root();
	if (hosted_root == nullptr || !hosted_root->is_hosted()) {
		return nullptr;
	}
	return hosted_root;
}

bool NNDebuggerOverlay::_is_on_path_to(Node *node, const ObjectID &target_id) {
	if (node == nullptr || target_id.is_null()) {
		return false;
	}

	Node *target = Object::cast_to<Node>(ObjectDB::get_instance((uint64_t)target_id));
	if (target == nullptr) {
		return false;
	}
	return node == target || node->is_ancestor_of(target);
}

void NNDebuggerOverlay::_cache_agent_selections(Node *root) {
	_agent_selections.clear();
	if (root == nullptr) {
		return;
	}

	// Collecting runs no user code, so these child pointers stay valid here.
	std::vector<ObjectID> agent_ids;
	std::vector<Node *> pending;
	pending.push_back(root);
	while (!pending.empty()) {
		Node *node = pending.back();
		pending.pop_back();
		if (Object::cast_to<NNAgent>(node) != nullptr) {
			agent_ids.push_back(ObjectID(node->get_instance_id()));
		}
		for (int i = 0; i < node->get_child_count(); i++) {
			Node *child = node->get_child(i);
			if (child != nullptr) {
				pending.push_back(child);
			}
		}
	}

	for (unsigned int i = 0; i < agent_ids.size(); i++) {
		AgentSelection selection;
		selection.agent_id = agent_ids[i];

		NNAgent *agent = Object::cast_to<NNAgent>(ObjectDB::get_instance((uint64_t)agent_ids[i]));
		if (agent == nullptr) {
			continue;
		}

		if (NNBehaviour *behaviour = agent->peek_current_behaviour()) {
			selection.behaviour_id = ObjectID(behaviour->get_instance_id());
		}
		if (NNAction *action = agent->peek_current_action()) {
			selection.action_id = ObjectID(action->get_instance_id());
		}

		_agent_selections.push_back(selection);
	}
}

bool NNDebuggerOverlay::_node_is_on_active_path(Node *node) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(node);
	if (noodle == nullptr) {
		return false;
	}

	NoodleNodes *ancestor_root = noodle->get_ancestor_root();
	if (ancestor_root == nullptr) {
		return false;
	}

	if (NNBTRoot *bt_root = Object::cast_to<NNBTRoot>(ancestor_root)) {
		NNBTNodes *running_action = bt_root->get_running_action();
		if (running_action == nullptr) {
			return false;
		}
		return node == running_action || node->is_ancestor_of(running_action);
	}

	if (Object::cast_to<NNSTRoot>(ancestor_root) != nullptr) {
		NNSTTickedNodes *ticked_node = Object::cast_to<NNSTTickedNodes>(node);
		return ticked_node != nullptr && ticked_node->get_is_active();
	}

	if (NNHTNRoot *htn_root = Object::cast_to<NNHTNRoot>(ancestor_root)) {
		const TypedArray<NNHTNPlanStep> plan = htn_root->get_plan();
		for (int i = 0; i < plan.size(); i++) {
			const Ref<NNHTNPlanStep> step = plan[i];
			const int state = step->get_state();
			if (state != NNHTNPlanStep::RUNNING && state != NNHTNPlanStep::VERIFYING && state != NNHTNPlanStep::STAGED) {
				continue;
			}
			NNHTNTask *task = step->get_task();
			NNHTNParallelTask *group = step->get_parallel_group();
			if ((task != nullptr && (node == task || node->is_ancestor_of(task))) || (group != nullptr && (node == group || node->is_ancestor_of(group)))) {
				return true;
			}
		}
		return false;
	}

	if (Object::cast_to<NNAgent>(ancestor_root) != nullptr) {
		ObjectID agent_id(ancestor_root->get_instance_id());
		for (unsigned int i = 0; i < _agent_selections.size(); i++) {
			const AgentSelection &selection = _agent_selections[i];
			if (selection.agent_id != agent_id) {
				continue;
			}
			return _is_on_path_to(node, selection.behaviour_id) || _is_on_path_to(node, selection.action_id);
		}
	}

	return false;
}

void NNDebuggerOverlay::_apply_htn_step_state(TreeItem *item, Node *node) {
	NNHTNNodes *htn_node = Object::cast_to<NNHTNNodes>(node);
	if (htn_node == nullptr || (Object::cast_to<NNHTNTask>(htn_node) == nullptr && Object::cast_to<NNHTNParallelTask>(htn_node) == nullptr)) {
		return;
	}
	NNHTNRoot *htn_root = htn_node->get_htn_root();
	const int state = htn_root != nullptr ? htn_root->get_debug_node_state(htn_node) : -1;
	if (state < 0) {
		item->set_custom_color(0, Color(0.5f, 0.5f, 0.5f));
		return;
	}
	const char *const state_names[] = { "planned", "running", "verifying", "staged", "succeeded", "failed", "cancelled" };
	const Color state_colors[] = { Color(1.0f, 1.0f, 1.0f), Color(1.0f, 0.85f, 0.2f), Color(0.4f, 0.7f, 1.0f), Color(0.6f, 0.9f, 0.6f), Color(0.3f, 0.9f, 0.3f), Color(1.0f, 0.3f, 0.3f), Color(0.6f, 0.6f, 0.6f) };
	item->set_text(1, state_names[state]);
	item->set_custom_color(0, state_colors[state]);
	item->set_custom_color(1, state_colors[state]);
}

void NNDebuggerOverlay::_rebuild_root_items() {
	if (_root_selection == nullptr) {
		return;
	}

	_root_selection->clear();
	_root_selection->add_item("Select a root node");
	_root_selection->set_item_metadata(0, Variant((int64_t)0));

	const std::vector<ObjectID> *registry = _get_registry_for_type(_current_type_selection);
	if (registry != nullptr) {
		for (unsigned int i = 0; i < registry->size(); i++) {
			ObjectID instance_id = (*registry)[i];
			Node *root = _resolve_root_for_type(_current_type_selection, instance_id);
			if (root == nullptr) {
				continue;
			}

			int item_index = _root_selection->get_item_count();
			_root_selection->add_item(_root_label(root));
			_root_selection->set_item_metadata(item_index, Variant((int64_t)(uint64_t)instance_id));
		}
	}

	// Preserve the selected root by instance ID while the list is rebuilt. This
	// also keeps selection correct when roots before it are freed.
	int selected_index = 0;
	if (_selected_root_id.is_valid()) {
		for (int i = 1; i < _root_selection->get_item_count(); i++) {
			Variant metadata = _root_selection->get_item_metadata(i);
			if (metadata.get_type() != Variant::INT) {
				continue;
			}
			ObjectID item_id((uint64_t)(int64_t)metadata);
			if (item_id == _selected_root_id) {
				selected_index = i;
				break;
			}
		}

		if (selected_index == 0) {
			// The selected root was removed or freed.
			_selected_root_id = ObjectID();
			_current_root_selection = -1;
			_clear_selected_tree();
		}
	}

	_root_selection->select(selected_index);
	_current_root_selection = selected_index;
	_rendered_type_selection = _current_type_selection;
	_rendered_registry_revision = _registry_revision;
}

void NNDebuggerOverlay::_ensure_root_items() {
	if (_root_selection == nullptr) {
		return;
	}
	if (_rendered_type_selection == _current_type_selection && _rendered_registry_revision == _registry_revision) {
		return;
	}
	_rebuild_root_items();
}

void NNDebuggerOverlay::on_type_item_selected(int item) {
	if (_get_overlay_scene() == nullptr) {
		_clear_view();
		return;
	}
	if (_type_selection == nullptr || _root_selection == nullptr) {
		return;
	}
	if (item < 0 || item >= _type_selection->get_item_count()) {
		return;
	}

	_current_type_selection = item;
	_current_root_selection = -1;
	_selected_root_id = ObjectID();
	_type_selection->select(item);
	_clear_selected_tree();
	_rebuild_root_items();
}

void NNDebuggerOverlay::_refresh_selected_root_view() {
	if (_selected_tree == nullptr) {
		return;
	}

	Node *root = _resolve_root_for_type(_current_type_selection, _selected_root_id);
	_cache_agent_selections(root);

	if (root == nullptr) {
		if (_selected_root_id.is_valid()) {
			_selected_root_id = ObjectID();
			_current_root_selection = -1;
			if (_root_selection != nullptr && _root_selection->get_item_count() > 0) {
				_root_selection->select(0);
				_current_root_selection = 0;
			}
		}
		_clear_selected_tree();
		return;
	}

	_selected_tree->clear();
	TreeItem *root_item = _selected_tree->create_item();
	if (root_item == nullptr) {
		return;
	}

	root_item->set_custom_font_size(0, 10);
	root_item->set_custom_font_size(1, 10);
	root_item->set_custom_font_size(2, 10);
	root_item->set_text(0, root->get_name());
	root_item->set_text(1, _root_status_text(root));
	NNHostedRoot *hosted_root = _hosted_root_of(root);
	tree_add_child_nodes(_selected_tree, root_item, root, hosted_root == nullptr || hosted_root->is_active());
}

void NNDebuggerOverlay::on_root_item_selected(int item) {
	if (_get_overlay_scene() == nullptr) {
		_clear_view();
		return;
	}
	if (_root_selection == nullptr || _selected_tree == nullptr) {
		return;
	}
	if (item < 0 || item >= _root_selection->get_item_count()) {
		return;
	}

	if (item == 0) { // The 0th item is the "Select a root node" placeholder.
		_current_root_selection = 0;
		_selected_root_id = ObjectID();
		_root_selection->select(0);
		_clear_selected_tree();
		return;
	}

	Variant metadata = _root_selection->get_item_metadata(item);
	if (metadata.get_type() != Variant::INT) {
		_current_root_selection = 0;
		_selected_root_id = ObjectID();
		_root_selection->select(0);
		_clear_selected_tree();
		return;
	}

	ObjectID instance_id((uint64_t)(int64_t)metadata);
	Node *root = _resolve_root_for_type(_current_type_selection, instance_id);
	if (root == nullptr) {
		// The item outlived its root. Drop the selection rather than indexing the
		// unfiltered registry.
		_current_root_selection = 0;
		_selected_root_id = ObjectID();
		_root_selection->select(0);
		_clear_selected_tree();
		return;
	}

	_current_root_selection = item;
	_selected_root_id = instance_id;
	_root_selection->select(item);
	_refresh_selected_root_view();
}

void NNDebuggerOverlay::on_exit_tree() {
	// The overlay view is gone (closed, detached or freed). Clear only view
	// state; registered AI roots may still be alive and are kept for reopening.
	_clear_view();
}

// Handling methods.

void NNDebuggerOverlay::update_ui() {
	Control *overlay = _get_overlay_scene();
	if (overlay == nullptr || !overlay->is_inside_tree()) {
		return;
	}
	if (_debug_messages == nullptr || _root_selection == nullptr || _selected_tree == nullptr) {
		// A re-entered overlay keeps its connections but lost its view on exit.
		if (!_bind_overlay_view(overlay)) {
			_clear_view();
			return;
		}
	}

	_ensure_root_items();
	_refresh_selected_root_view();

	int agent_count = 0;
	for (unsigned int i = 0; i < _agents.size(); i++) {
		if (_resolve_root_for_type(1, _agents[i]) != nullptr) {
			agent_count++;
		}
	}
	int behaviour_tree_count = 0;
	for (unsigned int i = 0; i < _behaviour_trees.size(); i++) {
		if (_resolve_root_for_type(2, _behaviour_trees[i]) != nullptr) {
			behaviour_tree_count++;
		}
	}
	int state_tree_count = 0;
	for (unsigned int i = 0; i < _state_trees.size(); i++) {
		if (_resolve_root_for_type(3, _state_trees[i]) != nullptr) {
			state_tree_count++;
		}
	}

	int htn_root_count = 0;
	for (unsigned int i = 0; i < _htn_roots.size(); i++) {
		if (_resolve_root_for_type(4, _htn_roots[i]) != nullptr) {
			htn_root_count++;
		}
	}

	godot::String msg = godot::String("Agents: ") + godot::String::num_int64(agent_count) + godot::String(" | BTrees: ") + godot::String::num_int64(behaviour_tree_count) + godot::String(" | STrees: ") + godot::String::num_int64(state_tree_count) + godot::String(" | HTNs: ") + godot::String::num_int64(htn_root_count) + godot::String(".\n");

	Node *selected_root = _resolve_root_for_type(_current_type_selection, _selected_root_id);
	if (selected_root != nullptr) {
		Node *root_owner = selected_root->get_owner();
		if (root_owner != nullptr) {
			msg = msg + godot::String("Currently inspecting: [b][color=green]") + root_owner->get_name() + godot::String("[/color][/b]\n");
		} else {
			msg = msg + godot::String("Currently inspecting: [b][color=gray]No owner[/color][/b] ") + selected_root->get_name() + godot::String("\n");
		}
		if (NNHTNRoot *htn_root = Object::cast_to<NNHTNRoot>(selected_root)) {
			static const char *const status_names[] = { "FOUND", "NO_PLAN", "BUDGET_EXHAUSTED", "INVALID_DOMAIN" };
			msg += vformat("Last search: %s, %d expansions. Plan: %d steps left, %d done.\n", status_names[htn_root->get_last_search_status()], htn_root->get_last_expansion_count(), htn_root->get_plan().size(), htn_root->get_completed_steps().size());
		}
	}

	_debug_messages->set_text(msg);
}

void NNDebuggerOverlay::tree_add_child_nodes(Tree *tree, TreeItem *parent_node, Node *parent_ai_node, bool p_path_open) {
	if (tree == nullptr || parent_ai_node == nullptr || parent_node == nullptr) {
		return;
	}
	uint64_t current_timestamp = godot::Time::get_singleton()->get_ticks_usec();

	for (int i = 0; i < parent_ai_node->get_child_count(); i++) {
		Node *next_ai_node = parent_ai_node->get_child(i);
		if (!next_ai_node)
			continue;

		TreeItem *child_tree_item = tree->create_item(parent_node);
		if (!child_tree_item)
			return;
		child_tree_item->set_custom_font_size(0, 10);
		child_tree_item->set_custom_font_size(1, 10);
		child_tree_item->set_custom_font_size(2, 10);
		float score = 0.0f;
		uint64_t tick_timestamp = 0;
		uint64_t eval_timestamp = 0;
		if (NNAgent *agent = godot::Object::cast_to<NNAgent>(next_ai_node)) {
			tick_timestamp = agent->get_last_evaluated_timestamp(); // Visited only updates when signals are used.
			eval_timestamp = agent->get_last_evaluated_timestamp();
		} else if (NNConsiderations *cons = godot::Object::cast_to<NNConsiderations>(next_ai_node)) {
			tick_timestamp = cons->get_last_evaluated_timestamp();
			eval_timestamp = cons->get_last_evaluated_timestamp();
			score = cons->get_score();
		} else if (NNBehaviours *beh = godot::Object::cast_to<NNBehaviours>(next_ai_node)) {
			tick_timestamp = beh->get_last_evaluated_timestamp();
			eval_timestamp = beh->get_last_evaluated_timestamp();
			score = beh->get_score();
		} else if (NNSensors *sensors = godot::Object::cast_to<NNSensors>(next_ai_node)) {
			tick_timestamp = sensors->get_last_evaluated_timestamp();
			eval_timestamp = sensors->get_last_evaluated_timestamp();
		} else if (NNBTNodes *btnode = godot::Object::cast_to<NNBTNodes>(next_ai_node)) {
			tick_timestamp = btnode->get_last_visited_timestamp();
			eval_timestamp = btnode->get_last_evaluated_timestamp();
			score = btnode->get_score();
		} else if (NNSTBranchNodes *stnode = godot::Object::cast_to<NNSTBranchNodes>(next_ai_node)) {
			tick_timestamp = stnode->get_last_visited_timestamp();
			eval_timestamp = stnode->get_last_evaluated_timestamp();
			if (NNSTTickedNodes *ticked_node = godot::Object::cast_to<NNSTTickedNodes>(next_ai_node)) {
				score = ticked_node->get_score();
			}
		}

		NoodleNodes *noodle = Object::cast_to<NoodleNodes>(next_ai_node);
		bool child_path_open = false;
		String status_text;
		if (noodle != nullptr && noodle->is_root()) {
			NNHostedRoot *hosted_root = _hosted_root_of(noodle);
			child_path_open = p_path_open && hosted_root != nullptr && hosted_root->is_active();
			status_text = _root_status_text(noodle);
		} else if (p_path_open && _node_is_on_active_path(noodle)) {
			child_path_open = true;
			status_text = _active_path_status(noodle);
		}

		child_tree_item->set_text(0, next_ai_node->get_name());
		child_tree_item->set_text(1, status_text);
		child_tree_item->set_text(2, String::num((double)score, 2));

		uint64_t tick_time_diff = current_timestamp - tick_timestamp;
		if (tick_time_diff > 1000000) {
			tick_time_diff = 1000000;
		}
		uint64_t eval_time_diff = current_timestamp - eval_timestamp;
		if (eval_time_diff > 1000000) {
			eval_time_diff = 1000000;
		}
		float tick_color = 1.0f - (float)tick_time_diff * 0.000001f * 0.7f;
		float eval_color = 1.0f - (float)eval_time_diff * 0.000001f * 0.7f;

		child_tree_item->set_custom_color(0, Color(tick_color, tick_color, tick_color));
		child_tree_item->set_custom_color(2, Color(eval_color * 0.8f, eval_color * 0.8f, eval_color));

		if (p_path_open) {
			_apply_htn_step_state(child_tree_item, next_ai_node);
		}

		tree_add_child_nodes(tree, child_tree_item, next_ai_node, child_path_open);

	} //endfor child nodes.
}

#endif

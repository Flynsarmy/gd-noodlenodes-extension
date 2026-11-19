#pragma once

#ifdef DEBUG_ENABLED

#include <godot_cpp/classes/control.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/option_button.hpp>
#include <godot_cpp/classes/rich_text_label.hpp>
#include <godot_cpp/classes/tree.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/string.hpp>
#include <vector>

namespace godot {

class NNHostedRoot;
class NoodleNodes;

class NNDebuggerOverlay : public Object {
	GDCLASS(NNDebuggerOverlay, Object)

private:
	// Values are part of the bound on_type_item_selected() API.
	enum RootType {
		ROOT_TYPE_AGENT = 1,
		ROOT_TYPE_BEHAVIOUR_TREE = 2,
		ROOT_TYPE_STATE_TREE = 3,
		ROOT_TYPE_HTN = 4,
	};

	struct RootTypeInfo {
		std::vector<ObjectID> *registry;
		Node *(*resolve)(Object *object);
		const char *label;
		const char *count_label;
		const char *active_path_label;
	};

	// Registries hold instance IDs so freed roots are never dereferenced.
	std::vector<ObjectID> _behaviour_trees;
	std::vector<ObjectID> _state_trees;
	std::vector<ObjectID> _agents;
	std::vector<ObjectID> _htn_roots;
	RootTypeInfo _root_types[4];

	static NNDebuggerOverlay *_singleton;

	// The overlay scene is resolved through its ObjectID on every use. This lets
	// a detached overlay be reattached and makes a freed overlay harmless.
	ObjectID _overlay_scene_id;
	OptionButton *_type_selection;
	OptionButton *_root_selection;
	RichTextLabel *_debug_messages;
	Tree *_selected_tree;

	int _current_type_selection;
	int _current_root_selection;
	ObjectID _selected_root_id;

	uint64_t _registry_revision;
	int _rendered_type_selection;
	uint64_t _rendered_registry_revision;

	Control *_get_overlay_scene() const;
	bool _bind_overlay_view(Control *overlay);
	void _clear_view();
	void _clear_selected_tree();
	void _clear_root_selection();

	const RootTypeInfo *_root_type_info(int type) const;
	const std::vector<ObjectID> *_get_registry_for_type(int type) const;
	Node *_resolve_root_for_type(int type, ObjectID instance_id) const;
	static int _count_live_roots(const std::vector<ObjectID> &registry, Node *(*resolve)(Object *object));
	void _register_object(std::vector<ObjectID> &registry, uint64_t instance_id);
	void _deregister_object(std::vector<ObjectID> &registry, uint64_t instance_id);
	String _root_label(Node *root) const;
	static String _host_path(const NoodleNodes *host);
	String _root_status_text(Node *root) const;
	String _active_path_status(Node *node) const;
	static NNHostedRoot *_hosted_root_of(Node *root);
	static void _collect_active_targets(Node *root, std::vector<Node *> &r_targets);
	static bool _is_on_active_path(Node *node, const std::vector<Node *> &targets);
	static void _apply_htn_step_state(TreeItem *item, Node *node);
	bool _apply_node_row(TreeItem *item, Node *node, bool p_path_open, const std::vector<Node *> &targets);
	void _refresh_item_children(TreeItem *parent_item, Node *parent_node, bool p_path_open, const std::vector<Node *> &targets);

	void _rebuild_root_items();
	void _ensure_root_items();
	void _refresh_selected_root_view();

protected:
	static void _bind_methods();

public:
	NNDebuggerOverlay();
	~NNDebuggerOverlay();

	static NNDebuggerOverlay *get_singleton();

	// Handling methods.
	void register_behaviour_tree(uint64_t instance_id);
	void register_state_tree(uint64_t instance_id);
	void register_ai_agent(uint64_t instance_id);
	void register_htn_root(uint64_t instance_id);

	void deregister_behaviour_tree(uint64_t instance_id);
	void deregister_state_tree(uint64_t instance_id);
	void deregister_ai_agent(uint64_t instance_id);
	void deregister_htn_root(uint64_t instance_id);

	void add_as_child_of(Node *debugger_parent_node);

	// UI handling methods.
	void on_type_item_selected(int item);
	void on_root_item_selected(int item);
	void on_exit_tree();

	void update_ui();
};

} //namespace godot

#endif //debug enabled

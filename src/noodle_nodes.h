#pragma once

#include "blackboard.h"
#include "debugger/debug_root.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class NNRootHost;
class NNHostedRoot;
class NNBlackboardDebugWatch;

class NoodleNodes : public Node {
	GDCLASS(NoodleNodes, Node)

private:
	bool _is_enabled;
	// A reparented ancestor notifies no descendants, but it does move them out
	// of and back into the tree, so the cache is only trusted while in-tree.
	mutable ObjectID _ancestor_root_id;
	mutable bool _has_cached_ancestor_root;

	NoodleNodes *_find_ancestor_root() const;

protected:
	static void _bind_methods();

	void _notification(int p_what);

	// Called after get_is_enabled() changes. Subclasses override this to react
	// to being disabled or re-enabled.
	virtual void _on_is_enabled_changed(bool p_is_enabled);

public:
	enum EvaluationMethod {
		EVALUATION_SUM = 0,
		EVALUATION_MIN = 1,
		EVALUATION_MAX = 2,
		EVALUATION_MEAN = 3,
		EVALUATION_MULTIPLY = 4,
		EVALUATION_FIRST_NON_ZERO = 5,
	};

	NoodleNodes();
	~NoodleNodes();

	// Getters and setters for attributes.
	void set_is_enabled(bool is_enabled);
	bool get_is_enabled() const;

	// True for the node that owns a blackboard / actor scope.
	virtual bool is_root() const { return false; }

	// Starts at the parent, so a root never resolves itself.
	NoodleNodes *get_ancestor_root() const;

	// Hosts a root nested below this node when it returns a host.
	virtual NNRootHost *get_root_host() { return nullptr; }
	// Non-null for a root that can be driven by an ancestor host.
	virtual NNHostedRoot *get_hosted_root() { return nullptr; }
#ifdef DEBUG_ENABLED
	// Non-null for a root the debugger can register and watch.
	virtual NNDebugRoot *get_debug_root() { return nullptr; }
	// Schema in tutorial/Debugger_reference.md. Empty for non-roots.
	virtual Dictionary get_debug_snapshot() const { return Dictionary(); }
	// Non-null for a root whose blackboard signals feed the debugger.
	virtual NNBlackboardDebugWatch *get_debug_blackboard_watch() { return nullptr; }

	// Blackboard signal relays. Connected by the root's debug watch, so the
	// events reach the root's own NNDebugRoot without self-connecting.
	void _on_debug_blackboard_value_changed(const String &p_key, const Variant &p_value);
	void _on_debug_blackboard_value_erased(const String &p_key);
	void _on_debug_blackboard_cleared();
#endif
	// Called when a root this node hosts reports it finished.
	virtual void _on_hosted_root_finished(bool p_succeeded, Node *p_root);

	virtual NNBlackboard *get_blackboard_resource() const;
	// Ref-returning wrapper bound under the GDScript name
	// "get_blackboard_resource". Returning the raw pointer to GDScript would
	// leave the RefCounted resource unowned by the returned Variant.
	Ref<NNBlackboard> get_blackboard_resource_ref() const;
	Variant get_blackboard(const String &key, const Variant &default_value = Variant()) const;
	bool set_blackboard(const String &key, const Variant &value);
	bool has_blackboard(const String &key) const;
	bool erase_blackboard(const String &key);
	virtual Node *get_actor() const;
};

} //namespace godot

VARIANT_ENUM_CAST(NoodleNodes::EvaluationMethod)

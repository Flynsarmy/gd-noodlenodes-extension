#pragma once

#include "action_leaf.h"
#include <godot_cpp/core/object_id.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Shared target configuration for the 2D and 3D movement leaves. The
// dimension-specific target position and resolution live in SpatialActionLeaf.
class NNBTSpatialActionLeaf : public NNBTActionLeaf {
	GDCLASS(NNBTSpatialActionLeaf, NNBTActionLeaf)

public:
	enum TargetSource {
		TARGET_POSITION = 0,
		TARGET_NODE = 1,
		TARGET_BLACKBOARD = 2,
	};

private:
	TargetSource _target_source;
	ObjectID _target_node_id;
	String _target_key;
	bool _has_reported_configuration_error;

protected:
	static void _bind_methods();

	// The assigned target node's ID, null when none was assigned. A non-null ID
	// whose instance is gone means the target was freed.
	ObjectID _get_target_node_id() const { return _target_node_id; }

	void _report_configuration_error(const String &p_reason);

public:
	NNBTSpatialActionLeaf();

	void set_target_source(TargetSource p_target_source);
	TargetSource get_target_source() const;

	void set_target_node(Node *p_target_node);
	Node *get_target_node() const;

	void set_target_key(const String &p_target_key);
	String get_target_key() const;
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTSpatialActionLeaf::TargetSource)

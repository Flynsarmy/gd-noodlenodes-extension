#pragma once

#include <functional>
#include <godot_cpp/core/object_id.hpp>
#include <vector>

namespace godot {

class Node;
class NoodleNodes;

// Owned by a host node. Drives every NNHostedRoot registered with it.
class NNRootHost {
public:
	NNRootHost();

	// The owner outlives the host.
	void configure(Node *p_owner);

	void register_root(Node *p_root);
	void unregister_root(Node *p_root);

	bool is_active() const;
	void activate();
	void deactivate();
	void tick(double p_delta);

private:
	Node *_owner;
	std::vector<ObjectID> _root_ids;
	bool _is_active;
};

// Owned by a root. Follows the nearest NNRootHost ancestor.
class NNHostedRoot {
public:
	using HostChangedCallback = std::function<void(bool p_hosted)>;
	using ActivateCallback = std::function<void()>;
	using TickCallback = std::function<void(double p_delta)>;
	using DeactivateCallback = std::function<void()>;

	NNHostedRoot();

	// The owner outlives the client.
	void configure(Node *p_owner, HostChangedCallback p_host_changed, ActivateCallback p_activate, TickCallback p_tick, DeactivateCallback p_deactivate);

	bool resolve_host();
	void release_host();

	bool is_hosted() const;
	bool is_active() const;

	void activate();
	void tick(double p_delta);
	void deactivate();

private:
	// The owner and the hosting node are stored by ID because the callbacks
	// below can free either of them.
	ObjectID _owner_id;
	ObjectID _host_id;
	Node *_owner;
	HostChangedCallback _host_changed;
	ActivateCallback _activate;
	TickCallback _tick;
	DeactivateCallback _deactivate;
	bool _is_active;
};

} //namespace godot

// Walks the parent chain from p_start, excluding it, for the nearest NoodleNodes that is a host.
// The nearest ancestor root stops the walk: the root owns its subtree.
godot::NoodleNodes *nn_find_host_ancestor(const godot::Node *p_start);

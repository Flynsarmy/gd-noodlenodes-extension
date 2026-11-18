#include "host.h"

#include "noodle_nodes.h"

#include <algorithm>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>

using namespace godot;

// The finished signal carries only the result, so the root is bound behind it.
// Both sides of is_connected()/disconnect() must build the same bound callable.
static Callable _finished_callable(Node *p_owner, Node *p_root) {
	NoodleNodes *owner_as_noodle = Object::cast_to<NoodleNodes>(p_owner);
	if (owner_as_noodle == nullptr) {
		return Callable();
	}
	return callable_mp(owner_as_noodle, &NoodleNodes::_on_hosted_root_finished).bind(p_root);
}

static NNHostedRoot *_resolve_hosted_root(const ObjectID &p_root_id) {
	NoodleNodes *noodle = Object::cast_to<NoodleNodes>(ObjectDB::get_instance(p_root_id));
	return noodle != nullptr ? noodle->get_hosted_root() : nullptr;
}

NNRootHost::NNRootHost() {
	_owner = nullptr;
	_is_active = false;
}

void NNRootHost::configure(Node *p_owner) {
	_owner = p_owner;
}

void NNRootHost::register_root(Node *p_root) {
	if (p_root == nullptr) {
		return;
	}

	const ObjectID root_id = ObjectID(p_root->get_instance_id());
	if (std::find(_root_ids.begin(), _root_ids.end(), root_id) == _root_ids.end()) {
		_root_ids.push_back(root_id);
	}

	if (_owner == nullptr || !p_root->has_signal("finished")) {
		return;
	}
	const Callable finished_callable = _finished_callable(_owner, p_root);
	if (finished_callable.is_null()) {
		return;
	}
	if (!p_root->is_connected("finished", finished_callable)) {
		p_root->connect("finished", finished_callable);
	}
}

void NNRootHost::unregister_root(Node *p_root) {
	if (p_root == nullptr) {
		return;
	}

	if (_owner != nullptr && p_root->has_signal("finished")) {
		const Callable finished_callable = _finished_callable(_owner, p_root);
		if (!finished_callable.is_null() && p_root->is_connected("finished", finished_callable)) {
			p_root->disconnect("finished", finished_callable);
		}
	}

	const ObjectID root_id = ObjectID(p_root->get_instance_id());
	std::vector<ObjectID>::iterator root_it = std::find(_root_ids.begin(), _root_ids.end(), root_id);
	if (root_it != _root_ids.end()) {
		_root_ids.erase(root_it);
	}
}

bool NNRootHost::is_active() const {
	return _is_active;
}

void NNRootHost::activate() {
	if (_is_active) {
		return;
	}
	_is_active = true;

	const std::vector<ObjectID> root_ids = _root_ids;
	for (unsigned int i = 0; i < root_ids.size(); i++) {
		NNHostedRoot *hosted_root = _resolve_hosted_root(root_ids[i]);
		if (hosted_root != nullptr) {
			hosted_root->activate();
		}
	}
}

void NNRootHost::deactivate() {
	if (!_is_active) {
		return;
	}
	_is_active = false;

	const std::vector<ObjectID> root_ids = _root_ids;
	for (unsigned int i = 0; i < root_ids.size(); i++) {
		NNHostedRoot *hosted_root = _resolve_hosted_root(root_ids[i]);
		if (hosted_root != nullptr) {
			hosted_root->deactivate();
		}
	}
}

void NNRootHost::tick(double p_delta) {
	if (!_is_active) {
		return;
	}

	const std::vector<ObjectID> root_ids = _root_ids;
	for (unsigned int i = 0; i < root_ids.size(); i++) {
		NNHostedRoot *hosted_root = _resolve_hosted_root(root_ids[i]);
		if (hosted_root != nullptr) {
			hosted_root->tick(p_delta);
		}
	}
}

NNHostedRoot::NNHostedRoot() {
	_owner = nullptr;
	_is_active = false;
}

void NNHostedRoot::configure(Node *p_owner, HostChangedCallback p_host_changed, ActivateCallback p_activate, TickCallback p_tick, DeactivateCallback p_deactivate) {
	_owner = p_owner;
	_owner_id = p_owner != nullptr ? ObjectID(p_owner->get_instance_id()) : ObjectID();
	_host_changed = p_host_changed;
	_activate = p_activate;
	_tick = p_tick;
	_deactivate = p_deactivate;
}

bool NNHostedRoot::is_hosted() const {
	return !_host_id.is_null();
}

bool NNHostedRoot::is_active() const {
	return _is_active;
}

bool NNHostedRoot::resolve_host() {
	release_host();

	// Releasing above may have run an interrupt callback that freed the owner.
	Node *owner = godot::Object::cast_to<Node>(ObjectDB::get_instance(_owner_id));
	if (owner == nullptr) {
		return false;
	}

	NoodleNodes *host_node = nn_find_host_ancestor(owner);
	if (host_node == nullptr) {
		return false;
	}
	NNRootHost *host = host_node->get_root_host();
	if (host == nullptr) {
		return false;
	}

	// Registering runs no user code, but the activation below does, so the
	// host is only reached through the stored ID from here on.
	const bool host_is_active = host->is_active();
	_host_id = ObjectID(host_node->get_instance_id());
	host->register_root(owner);

	_host_changed(true);

	if (host_is_active) {
		activate();
	}
	return true;
}

void NNHostedRoot::release_host() {
	if (_host_id.is_null()) {
		return;
	}

	const ObjectID host_id = _host_id;
	_host_id = ObjectID();

	NoodleNodes *host_node = Object::cast_to<NoodleNodes>(ObjectDB::get_instance(host_id));
	if (host_node != nullptr) {
		NNRootHost *host = host_node->get_root_host();
		if (host != nullptr) {
			host->unregister_root(_owner);
		}
	}

	_host_changed(false);
	deactivate();
}

void NNHostedRoot::activate() {
	if (_host_id.is_null() || _is_active) {
		return;
	}
	_is_active = true;
	_activate();
}

void NNHostedRoot::tick(double p_delta) {
	if (_host_id.is_null() || !_is_active) {
		return;
	}
	_tick(p_delta);
}

void NNHostedRoot::deactivate() {
	if (!_is_active) {
		return;
	}
	_is_active = false;
	_deactivate();
}

NoodleNodes *nn_find_host_ancestor(const Node *p_start) {
	if (p_start == nullptr) {
		return nullptr;
	}

	for (Node *node = p_start->get_parent(); node != nullptr; node = node->get_parent()) {
		NoodleNodes *noodle = Object::cast_to<NoodleNodes>(node);
		if (noodle == nullptr) {
			continue;
		}
		// A root owns its subtree, so a root nested below it is never hosted across it.
		if (noodle->is_root()) {
			return nullptr;
		}
		if (noodle->get_root_host() != nullptr) {
			return noodle;
		}
	}
	return nullptr;
}

#include "node_children.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

void NNNodeChildrenSearchSpace::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_parent_node", "parent_node"), &NNNodeChildrenSearchSpace::set_parent_node);
	ClassDB::bind_method(D_METHOD("get_parent_node"), &NNNodeChildrenSearchSpace::get_parent_node);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "parent_node", PROPERTY_HINT_NODE_TYPE, "Node"), "set_parent_node", "get_parent_node");
}

void NNNodeChildrenSearchSpace::_initialize_search_space() {
}

void NNNodeChildrenSearchSpace::_uninitialize_search_space() {
	_parent_node_id = ObjectID();
}

// Getters and setters.

void NNNodeChildrenSearchSpace::set_parent_node(Node *parent_node) {
	_parent_node_id = parent_node != nullptr ? ObjectID(parent_node->get_instance_id()) : ObjectID();
}

Node *NNNodeChildrenSearchSpace::get_parent_node() const {
	return Object::cast_to<Node>(ObjectDB::get_instance(_parent_node_id));
}

TypedArray<Node> NNNodeChildrenSearchSpace::get_searchspace_nodes() const {
	Node *parent_node = get_parent_node();
	if (parent_node == nullptr) {
		TypedArray<Node> emptyarray;
		return emptyarray;
	}
	return parent_node->get_children();
}

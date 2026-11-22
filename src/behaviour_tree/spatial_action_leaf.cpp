#include "spatial_action_leaf.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void NNBTSpatialActionLeaf::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_target_source", "target_source"), &NNBTSpatialActionLeaf::set_target_source);
	ClassDB::bind_method(D_METHOD("get_target_source"), &NNBTSpatialActionLeaf::get_target_source);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "target_source", PROPERTY_HINT_ENUM, "Position,Node,Blackboard"), "set_target_source", "get_target_source");

	ClassDB::bind_method(D_METHOD("set_target_node", "target_node"), &NNBTSpatialActionLeaf::set_target_node);
	ClassDB::bind_method(D_METHOD("get_target_node"), &NNBTSpatialActionLeaf::get_target_node);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "target_node", PROPERTY_HINT_NODE_TYPE, "Node"), "set_target_node", "get_target_node");

	ClassDB::bind_method(D_METHOD("set_target_key", "target_key"), &NNBTSpatialActionLeaf::set_target_key);
	ClassDB::bind_method(D_METHOD("get_target_key"), &NNBTSpatialActionLeaf::get_target_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "target_key"), "set_target_key", "get_target_key");

	BIND_ENUM_CONSTANT(TARGET_POSITION);
	BIND_ENUM_CONSTANT(TARGET_NODE);
	BIND_ENUM_CONSTANT(TARGET_BLACKBOARD);
}

NNBTSpatialActionLeaf::NNBTSpatialActionLeaf() {
	_target_source = TARGET_POSITION;
	_has_reported_configuration_error = false;
}

void NNBTSpatialActionLeaf::set_target_source(TargetSource p_target_source) {
	_target_source = p_target_source;
	notify_property_list_changed();
}

NNBTSpatialActionLeaf::TargetSource NNBTSpatialActionLeaf::get_target_source() const {
	return _target_source;
}

void NNBTSpatialActionLeaf::set_target_node(Node *p_target_node) {
	_target_node_id = p_target_node != nullptr ? ObjectID(p_target_node->get_instance_id()) : ObjectID();
}

Node *NNBTSpatialActionLeaf::get_target_node() const {
	return Object::cast_to<Node>(ObjectDB::get_instance(_target_node_id));
}

void NNBTSpatialActionLeaf::set_target_key(const String &p_target_key) {
	_target_key = p_target_key;
}

String NNBTSpatialActionLeaf::get_target_key() const {
	return _target_key;
}

void NNBTSpatialActionLeaf::_report_configuration_error(const String &p_reason) {
	if (_has_reported_configuration_error) {
		return;
	}
	_has_reported_configuration_error = true;
	String node_location = is_inside_tree() ? String(get_path()) : get_name() + String(" (not in tree)");
	ERR_PRINT(vformat("%s node '%s' (%s) %s; returning FAILURE.", get_class(), get_name(), node_location, p_reason));
}

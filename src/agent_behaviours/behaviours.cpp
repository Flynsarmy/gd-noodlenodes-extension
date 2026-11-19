#include "behaviours.h"

#include <godot_cpp/core/object.hpp>

using namespace godot;

void NNBehaviours::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNBehaviours::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNBehaviours::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum,Min,Max,Mean,Multiply,First Non Zero", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NoodleNodes.EvaluationMethod"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("set_score", "score"), &NNBehaviours::set_score);
	ClassDB::bind_method(D_METHOD("get_score"), &NNBehaviours::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_RANGE, "-100.0,100.0"), "set_score", "get_score");
}

// Godot virtuals.

void NNBehaviours::_notification(int p_what) {
	if (p_what == NOTIFICATION_CHILD_ORDER_CHANGED) {
		_child_considerations.clear();
		_child_behaviour_ids.clear();
		int num_children = get_child_count();
		for (int i = 0; i < num_children; i++) {
			if (NNConsiderations *cons = godot::Object::cast_to<NNConsiderations>(get_child(i))) {
				_child_considerations.push_back(cons);
			} else if (NNBehaviours *beh = godot::Object::cast_to<NNBehaviours>(get_child(i))) {
				_child_behaviour_ids.push_back(ObjectID(beh->get_instance_id()));
			}
		} //endfor child nodes
		_num_child_considerations = (unsigned int)_child_considerations.size();
		_num_child_behaviours = (unsigned int)_child_behaviour_ids.size();
	}
}

// Getters and setters.

ObjectID NNBehaviours::get_child_behaviour_id(unsigned int index) const {
	if (index >= _child_behaviour_ids.size()) {
		return ObjectID();
	}
	return _child_behaviour_ids[index];
}

NNBehaviours *NNBehaviours::get_child_behaviour(unsigned int index) const {
	// The cached list can be stale while user callbacks run. Resolve the ID and
	// verify the node is still a child of this behaviour before returning it.
	NNBehaviours *behaviour = godot::Object::cast_to<NNBehaviours>(ObjectDB::get_instance(get_child_behaviour_id(index)));
	if (behaviour == nullptr || behaviour->get_parent() != this) {
		return nullptr;
	}
	return behaviour;
}

void NNBehaviours::set_evaluation_method(EvaluationMethod evaluation_method) {
	_evaluation_method = evaluation_method;
}

NoodleNodes::EvaluationMethod NNBehaviours::get_evaluation_method() const {
	return _evaluation_method;
}

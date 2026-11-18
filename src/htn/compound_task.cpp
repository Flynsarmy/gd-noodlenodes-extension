#include "compound_task.h"

#include "method.h"

using namespace godot;

void NNHTNCompoundTask::_bind_methods() {
}

std::vector<NNHTNMethod *> NNHTNCompoundTask::get_enabled_methods() const {
	std::vector<NNHTNMethod *> methods;
	for (int i = 0; i < get_child_count(); i++) {
		NNHTNMethod *method = Object::cast_to<NNHTNMethod>(get_child(i));
		if (method != nullptr && method->get_is_enabled()) {
			methods.push_back(method);
		}
	}
	return methods;
}

PackedStringArray NNHTNCompoundTask::_get_configuration_warnings() const {
	PackedStringArray warnings = NNHTNNodes::_get_configuration_warnings();
	bool has_method = false;
	for (int i = 0; i < get_child_count(); i++) {
		if (Object::cast_to<NNHTNMethod>(get_child(i)) != nullptr) {
			has_method = true;
		} else if (Object::cast_to<NNHTNNodes>(get_child(i)) != nullptr) {
			warnings.push_back(vformat("'%s' is not an NNHTNMethod; a compound task's children are its methods and anything else is ignored.", get_child(i)->get_name()));
		}
	}
	if (!has_method) {
		warnings.push_back("A compound task needs at least one NNHTNMethod child.");
	}
	return warnings;
}

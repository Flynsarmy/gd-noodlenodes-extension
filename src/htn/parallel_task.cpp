#include "parallel_task.h"

#include "compound_task.h"
#include "method.h"
#include "subtask_call.h"
#include "task.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

void NNHTNParallelTask::_bind_methods() {
	BIND_ENUM_CONSTANT(REJECT);
	BIND_ENUM_CONSTANT(SERIALIZE);

	ClassDB::bind_method(D_METHOD("set_effects", "effects"), &NNHTNParallelTask::set_effects);
	ClassDB::bind_method(D_METHOD("get_effects"), &NNHTNParallelTask::get_effects);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "effects", PROPERTY_HINT_DICTIONARY_TYPE, vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")), "set_effects", "get_effects");

	ClassDB::bind_method(D_METHOD("set_unsafe_policy", "unsafe_policy"), &NNHTNParallelTask::set_unsafe_policy);
	ClassDB::bind_method(D_METHOD("get_unsafe_policy"), &NNHTNParallelTask::get_unsafe_policy);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "unsafe_policy", PROPERTY_HINT_ENUM, "Reject,Serialize"), "set_unsafe_policy", "get_unsafe_policy");
}

NNHTNParallelTask::NNHTNParallelTask() {
	_unsafe_policy = REJECT;
}

void NNHTNParallelTask::set_effects(const Dictionary &p_effects) {
	_effects = p_effects;
}

Dictionary NNHTNParallelTask::get_effects() const {
	return _effects;
}

void NNHTNParallelTask::set_unsafe_policy(UnsafePolicy p_unsafe_policy) {
	_unsafe_policy = p_unsafe_policy;
	update_configuration_warnings();
}

NNHTNParallelTask::UnsafePolicy NNHTNParallelTask::get_unsafe_policy() const {
	return _unsafe_policy;
}

String NNHTNParallelTask::_get_branch_error(const Node *p_child) const {
	if (Object::cast_to<NNHTNTask>(p_child) != nullptr) {
		return String();
	}
	if (const NNHTNSubtaskCall *call = Object::cast_to<NNHTNSubtaskCall>(p_child)) {
		const NNHTNNodes *target = call->get_task();
		if (target == nullptr) {
			return vformat("Call '%s' has no template.", call->get_name());
		}
		if (Object::cast_to<NNHTNTask>(target) == nullptr) {
			return vformat("Call '%s' targets '%s', which is not a primitive NNHTNTask.", call->get_name(), target->get_name());
		}
		return String();
	}
	if (Object::cast_to<NNHTNCompoundTask>(p_child) != nullptr) {
		return vformat("'%s' is a compound task; decompose it outside the group and run its primitives as branches.", p_child->get_name());
	}
	if (Object::cast_to<NNHTNParallelTask>(p_child) != nullptr) {
		return vformat("'%s' is a nested parallel group, which is not supported.", p_child->get_name());
	}
	return vformat("'%s' is not a primitive NNHTNTask or an NNHTNSubtaskCall to one.", p_child->get_name());
}

String NNHTNParallelTask::resolve_branches(std::vector<NNHTNNodes *> &r_branches) const {
	if (_unsafe_policy != REJECT && _unsafe_policy != SERIALIZE) {
		return vformat("unsafe_policy %d is invalid.", (int)_unsafe_policy);
	}
	for (int i = 0; i < get_child_count(); i++) {
		NNHTNNodes *child = Object::cast_to<NNHTNNodes>(get_child(i));
		if (child == nullptr || !child->get_is_enabled()) {
			continue;
		}
		const String error = _get_branch_error(child);
		if (!error.is_empty()) {
			return error;
		}
		r_branches.push_back(child);
	}
	if (r_branches.empty()) {
		return "The group has no enabled branches.";
	}
	return String();
}

void NNHTNParallelTask::report_serialization(const String &p_message) const {
	if (p_message == _reported_serialization) {
		return;
	}
	_reported_serialization = p_message;
	if (!p_message.is_empty()) {
		WARN_PRINT(vformat("%s: %s", _describe(), p_message));
	}
}

PackedStringArray NNHTNParallelTask::_get_configuration_warnings() const {
	PackedStringArray warnings = NNHTNNodes::_get_configuration_warnings();
	if (Object::cast_to<NNHTNMethod>(get_parent()) == nullptr) {
		warnings.push_back("A parallel group must be a child of an NNHTNMethod.");
	}
	if (_unsafe_policy != REJECT && _unsafe_policy != SERIALIZE) {
		warnings.push_back(vformat("unsafe_policy %d is invalid.", (int)_unsafe_policy));
	}
	bool has_branch = false;
	for (int i = 0; i < get_child_count(); i++) {
		const NNHTNNodes *child = Object::cast_to<NNHTNNodes>(get_child(i));
		if (child == nullptr || !child->get_is_enabled()) {
			continue;
		}
		has_branch = true;
		const String error = _get_branch_error(child);
		if (!error.is_empty()) {
			warnings.push_back(error + String(" The group is rejected while planning."));
		}
		if (!child->get_predecessors().is_empty()) {
			warnings.push_back(vformat("The predecessors of '%s' are ignored; predecessors order method children, not parallel branches.", child->get_name()));
		}
	}
	if (!has_branch) {
		warnings.push_back("A parallel group needs at least one enabled NNHTNTask or NNHTNSubtaskCall branch.");
	}
	return warnings;
}

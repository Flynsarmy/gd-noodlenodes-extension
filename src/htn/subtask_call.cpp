#include "subtask_call.h"

#include "compound_task.h"
#include "task.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void NNHTNSubtaskCall::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_task", "task"), &NNHTNSubtaskCall::set_task);
	ClassDB::bind_method(D_METHOD("get_task"), &NNHTNSubtaskCall::get_task);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "task", PROPERTY_HINT_NODE_TYPE, "NNHTNTask,NNHTNCompoundTask"), "set_task", "get_task");

	ClassDB::bind_method(D_METHOD("set_args", "args"), &NNHTNSubtaskCall::set_args);
	ClassDB::bind_method(D_METHOD("get_args"), &NNHTNSubtaskCall::get_args);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "args"), "set_args", "get_args");

	ClassDB::bind_method(D_METHOD("set_argument_bindings", "argument_bindings"), &NNHTNSubtaskCall::set_argument_bindings);
	ClassDB::bind_method(D_METHOD("get_argument_bindings"), &NNHTNSubtaskCall::get_argument_bindings);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "argument_bindings", PROPERTY_HINT_DICTIONARY_TYPE, "String;NNHTNArgumentReference"), "set_argument_bindings", "get_argument_bindings");
}

static PackedStringArray _sorted_keys(const Dictionary &p_dictionary) {
	PackedStringArray keys;
	const Array raw = p_dictionary.keys();
	for (int i = 0; i < raw.size(); i++) {
		keys.push_back(raw[i]);
	}
	keys.sort();
	return keys;
}

void NNHTNSubtaskCall::set_task(NNHTNNodes *p_task) {
	_task_id = p_task != nullptr ? ObjectID(p_task->get_instance_id()) : ObjectID();
	update_configuration_warnings();
}

NNHTNNodes *NNHTNSubtaskCall::get_task() const {
	return Object::cast_to<NNHTNNodes>(ObjectDB::get_instance(_task_id));
}

void NNHTNSubtaskCall::set_args(const Dictionary &p_args) {
	_args = p_args;
}

Dictionary NNHTNSubtaskCall::get_args() const {
	return _args;
}

NNHTNNodes *NNHTNSubtaskCall::get_template() const {
	NNHTNNodes *task = get_task();
	if (Object::cast_to<NNHTNTask>(task) != nullptr || Object::cast_to<NNHTNCompoundTask>(task) != nullptr) {
		return task;
	}
	return nullptr;
}

void NNHTNSubtaskCall::set_argument_bindings(const TypedDictionary<String, NNHTNArgumentReference> &p_argument_bindings) {
	_argument_bindings = p_argument_bindings;
	update_configuration_warnings();
}

TypedDictionary<String, NNHTNArgumentReference> NNHTNSubtaskCall::get_argument_bindings() const {
	return _argument_bindings;
}

PackedStringArray NNHTNSubtaskCall::get_argument_binding_errors() const {
	PackedStringArray errors;
	for (const String &name : _sorted_keys(_argument_bindings)) {
		Ref<NNHTNArgumentReference> reference = _argument_bindings[name];
		if (name.is_empty()) {
			errors.push_back("argument_bindings has an entry with an empty name.");
		} else if (reference.is_null()) {
			errors.push_back(vformat("argument_bindings['%s'] is empty.", name));
		} else {
			for (const String &error : reference->get_validation_errors()) {
				errors.push_back(vformat("argument_bindings['%s']: %s", name, error));
			}
		}
	}
	return errors;
}

bool NNHTNSubtaskCall::resolve_args(const NNHTNStateView &p_state, const Dictionary &p_inherited, Dictionary &r_args) const {
	const PackedStringArray errors = get_argument_binding_errors();
	report_configuration_error(errors.is_empty() ? String() : String(" ").join(errors) + " The call is rejected.");
	if (!errors.is_empty()) {
		return false;
	}
	Dictionary resolved = p_inherited.duplicate(true);
	resolved.merge(_args.duplicate(true), true);
	for (const String &name : _sorted_keys(_argument_bindings)) {
		Ref<NNHTNArgumentReference> reference = _argument_bindings[name];
		Variant value;
		if (!reference->resolve(p_state.get_values(), resolved, value)) {
			return false;
		}
		resolved[name] = value.duplicate(true);
	}
	resolved.make_read_only();
	r_args = resolved;
	return true;
}

void NNHTNSubtaskCall::collect_dependency_keys(HashSet<String> &r_keys) const {
	NNHTNNodes::collect_dependency_keys(r_keys);
	const Array references = _argument_bindings.values();
	for (int i = 0; i < references.size(); i++) {
		Ref<NNHTNArgumentReference> reference = references[i];
		if (reference.is_valid() && reference->get_source() == NNHTNArgumentReference::WORLD_STATE && !reference->get_key().is_empty()) {
			r_keys.insert(reference->get_key());
		}
	}
}

PackedStringArray NNHTNSubtaskCall::_get_configuration_warnings() const {
	PackedStringArray warnings = NNHTNNodes::_get_configuration_warnings();
	if (get_child_count() > 0) {
		warnings.push_back("A subtask call references a template and must not have children.");
	}
	NNHTNNodes *task = get_template();
	if (task == nullptr) {
		warnings.push_back("The call has no template. Assign an NNHTNTask or NNHTNCompoundTask to task.");
	} else if (task->is_ancestor_of(const_cast<NNHTNSubtaskCall *>(this))) {
		warnings.push_back("The call references a compound task that contains it, which recursion makes unplannable.");
	}
	warnings.append_array(get_argument_binding_errors());
	return warnings;
}

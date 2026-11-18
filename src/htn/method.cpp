#include "method.h"

#include "compound_task.h"

#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/templates/hash_map.hpp>

using namespace godot;

void NNHTNMethod::_bind_methods() {
	BIND_ENUM_CONSTANT(SEQUENTIAL);
	BIND_ENUM_CONSTANT(PARTIAL_ORDER);

	ClassDB::bind_method(D_METHOD("set_priority", "priority"), &NNHTNMethod::set_priority);
	ClassDB::bind_method(D_METHOD("get_priority"), &NNHTNMethod::get_priority);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "priority", PROPERTY_HINT_RANGE, "0,1000000,0.001,or_greater"), "set_priority", "get_priority");

	ClassDB::bind_method(D_METHOD("set_ordering_mode", "ordering_mode"), &NNHTNMethod::set_ordering_mode);
	ClassDB::bind_method(D_METHOD("get_ordering_mode"), &NNHTNMethod::get_ordering_mode);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "ordering_mode", PROPERTY_HINT_ENUM, "Sequential,Partial Order"), "set_ordering_mode", "get_ordering_mode");

	ClassDB::bind_method(D_METHOD("set_bindings", "bindings"), &NNHTNMethod::set_bindings);
	ClassDB::bind_method(D_METHOD("get_bindings"), &NNHTNMethod::get_bindings);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "bindings", PROPERTY_HINT_ARRAY_TYPE, "NNHTNBinding"), "set_bindings", "get_bindings");

	ClassDB::bind_method(D_METHOD("get_ordering_errors"), &NNHTNMethod::get_ordering_errors);
	ClassDB::bind_method(D_METHOD("get_ordering_warnings"), &NNHTNMethod::get_ordering_warnings);

	GDVIRTUAL_BIND(on_get_priority, "state", "args");
	GDVIRTUAL_BIND(on_resolve_arguments, "state", "args");
}

NNHTNMethod::NNHTNMethod() {
	_priority = 0.0;
	_ordering_mode = SEQUENTIAL;
}

void NNHTNMethod::set_priority(double p_priority) {
	_priority = p_priority;
	update_configuration_warnings();
}

double NNHTNMethod::get_priority() const {
	return _priority;
}

void NNHTNMethod::set_ordering_mode(OrderingMode p_ordering_mode) {
	_ordering_mode = p_ordering_mode;
	update_configuration_warnings();
}

NNHTNMethod::OrderingMode NNHTNMethod::get_ordering_mode() const {
	return _ordering_mode;
}

void NNHTNMethod::set_bindings(const TypedArray<NNHTNBinding> &p_bindings) {
	_bindings = p_bindings;
	update_configuration_warnings();
}

TypedArray<NNHTNBinding> NNHTNMethod::get_bindings() const {
	return _bindings;
}

bool NNHTNMethod::compute_priority(const NNHTNStateView &p_state, const Dictionary &p_args, double &r_priority) const {
	Variant result = _priority;
	if (_has_hook(_gdvirtual_on_get_priority_sn)) {
		const Variant args[2] = { p_state.get_hook_state(), p_args };
		const Variant *arg_ptrs[2] = { &args[0], &args[1] };
		if (!_call_hook(_gdvirtual_on_get_priority_sn, arg_ptrs, 2, result) || (result.get_type() != Variant::INT && result.get_type() != Variant::FLOAT)) {
			ERR_PRINT(vformat("%s: on_get_priority() must return a number; got %s. The method is skipped.", _describe(), Variant::get_type_name(result.get_type())));
			return false;
		}
	}
	const double priority = result;
	if (!Math::is_finite(priority) || priority < 0.0) {
		ERR_PRINT(vformat("%s: priority must be finite and non-negative; got %s. The method is skipped.", _describe(), result));
		return false;
	}
	r_priority = priority;
	return true;
}

bool NNHTNMethod::resolve_argument_candidates(const NNHTNStateView &p_state, const Dictionary &p_args, int p_cap, std::vector<Dictionary> &r_candidates, bool &r_truncated) const {
	r_truncated = false;
	if (!_has_hook(_gdvirtual_on_resolve_arguments_sn)) {
		r_candidates.push_back(p_args);
		return true;
	}

	const Variant args[2] = { p_state.get_hook_state(), p_args };
	const Variant *arg_ptrs[2] = { &args[0], &args[1] };
	Variant result;
	if (!_call_hook(_gdvirtual_on_resolve_arguments_sn, arg_ptrs, 2, result) || result.get_type() != Variant::ARRAY) {
		ERR_PRINT(vformat("%s: on_resolve_arguments() must return an Array of Dictionaries; got %s. The method is skipped.", _describe(), Variant::get_type_name(result.get_type())));
		return false;
	}

	const Array candidates = result;
	for (int i = 0; i < candidates.size(); i++) {
		if (candidates[i].get_type() != Variant::DICTIONARY) {
			ERR_PRINT(vformat("%s: on_resolve_arguments() candidate %d is a %s, not a Dictionary; it is skipped.", _describe(), i, Variant::get_type_name(candidates[i].get_type())));
			continue;
		}
		if ((int)r_candidates.size() >= p_cap) {
			r_truncated = true;
			break;
		}
		Dictionary candidate = Dictionary(candidates[i]).duplicate(true);
		candidate.make_read_only();
		r_candidates.push_back(candidate);
	}
	return true;
}

bool NNHTNMethod::get_schedulable_children(std::vector<NNHTNNodes *> &r_children) const {
	for (int i = 0; i < get_child_count(); i++) {
		NNHTNNodes *child = Object::cast_to<NNHTNNodes>(get_child(i));
		if (child == nullptr || !child->get_is_enabled()) {
			continue;
		}
		if (Object::cast_to<NNHTNMethod>(child) != nullptr) {
			return false;
		}
		r_children.push_back(child);
	}
	return true;
}

bool NNHTNMethod::build_predecessor_graph(const std::vector<NNHTNNodes *> &p_children, std::vector<std::vector<int>> &r_predecessors, PackedStringArray &r_errors) const {
	HashMap<const NNHTNNodes *, int> indices;
	for (size_t i = 0; i < p_children.size(); i++) {
		indices.insert(p_children[i], (int)i);
	}

	r_predecessors.assign(p_children.size(), std::vector<int>());
	const int64_t initial_errors = r_errors.size();
	for (size_t i = 0; i < p_children.size(); i++) {
		const NNHTNNodes *child = p_children[i];
		const TypedArray<NNHTNNodes> predecessors = child->get_predecessors();
		for (int j = 0; j < predecessors.size(); j++) {
			const Variant &entry = predecessors[j];
			// Read the stored ID instead of dereferencing: the node may already be freed.
			const NNHTNNodes *predecessor = entry.get_type() == Variant::OBJECT ? Object::cast_to<NNHTNNodes>(ObjectDB::get_instance(entry.operator ObjectID())) : nullptr;
			if (predecessor == nullptr) {
				r_errors.push_back(vformat("'%s' has a null or freed predecessor.", child->get_name()));
			} else if (predecessor == child) {
				r_errors.push_back(vformat("'%s' lists itself as a predecessor.", child->get_name()));
			} else if (predecessor->get_parent() != this) {
				r_errors.push_back(vformat("'%s' lists '%s', which is not a direct child of this method.", child->get_name(), predecessor->get_name()));
			} else if (!indices.has(predecessor)) {
				r_errors.push_back(vformat("'%s' lists '%s', which is disabled or cannot be scheduled.", child->get_name(), predecessor->get_name()));
			} else if (std::find(r_predecessors[i].begin(), r_predecessors[i].end(), indices[predecessor]) != r_predecessors[i].end()) {
				r_errors.push_back(vformat("'%s' lists '%s' more than once.", child->get_name(), predecessor->get_name()));
			} else {
				r_predecessors[i].push_back(indices[predecessor]);
			}
		}
	}

	// Kahn's algorithm: children left with unscheduled predecessors are on a cycle.
	std::vector<int> pending_counts(p_children.size());
	std::vector<std::vector<int>> successors(p_children.size());
	std::vector<int> ready;
	for (size_t i = 0; i < p_children.size(); i++) {
		pending_counts[i] = (int)r_predecessors[i].size();
		for (int predecessor : r_predecessors[i]) {
			successors[predecessor].push_back((int)i);
		}
		if (pending_counts[i] == 0) {
			ready.push_back((int)i);
		}
	}
	while (!ready.empty()) {
		const int index = ready.back();
		ready.pop_back();
		for (int successor : successors[index]) {
			if (--pending_counts[successor] == 0) {
				ready.push_back(successor);
			}
		}
	}
	PackedStringArray cycle;
	for (size_t i = 0; i < p_children.size(); i++) {
		if (pending_counts[i] > 0) {
			cycle.push_back(p_children[i]->get_name());
		}
	}
	if (!cycle.is_empty()) {
		r_errors.push_back(vformat("The predecessors form a cycle through %s.", String(", ").join(cycle)));
	}
	return r_errors.size() == initial_errors;
}

PackedStringArray NNHTNMethod::get_ordering_errors() const {
	PackedStringArray errors;
	if (_ordering_mode == SEQUENTIAL) {
		return errors;
	}
	if (_ordering_mode != PARTIAL_ORDER) {
		errors.push_back(vformat("ordering_mode %d is invalid.", (int)_ordering_mode));
		return errors;
	}
	std::vector<NNHTNNodes *> children;
	get_schedulable_children(children);
	std::vector<std::vector<int>> predecessors;
	build_predecessor_graph(children, predecessors, errors);
	return errors;
}

PackedStringArray NNHTNMethod::get_ordering_warnings() const {
	PackedStringArray warnings;
	if (_ordering_mode != SEQUENTIAL) {
		return warnings;
	}
	for (int i = 0; i < get_child_count(); i++) {
		NNHTNNodes *child = Object::cast_to<NNHTNNodes>(get_child(i));
		if (child != nullptr && !child->get_predecessors().is_empty()) {
			warnings.push_back(vformat("The predecessors of '%s' are ignored because ordering_mode is SEQUENTIAL. Set PARTIAL_ORDER to use them.", child->get_name()));
		}
	}
	return warnings;
}

PackedStringArray NNHTNMethod::get_binding_errors() const {
	PackedStringArray errors;
	for (int i = 0; i < _bindings.size(); i++) {
		Ref<NNHTNBinding> binding = _bindings[i];
		if (binding.is_null()) {
			errors.push_back(vformat("bindings[%d] is empty.", i));
			continue;
		}
		for (const String &error : binding->get_validation_errors()) {
			errors.push_back(vformat("bindings[%d]: %s", i, error));
		}
	}
	return errors;
}

void NNHTNMethod::collect_dependency_keys(HashSet<String> &r_keys) const {
	NNHTNNodes::collect_dependency_keys(r_keys);
	for (int i = 0; i < _bindings.size(); i++) {
		Ref<NNHTNBinding> binding = _bindings[i];
		if (binding.is_valid()) {
			binding->collect_dependency_keys(r_keys);
		}
	}
}

PackedStringArray NNHTNMethod::_get_configuration_warnings() const {
	PackedStringArray warnings = NNHTNNodes::_get_configuration_warnings();
	if (Object::cast_to<NNHTNCompoundTask>(get_parent()) == nullptr) {
		warnings.push_back("A method must be a child of an NNHTNCompoundTask.");
	}
	bool has_task = false;
	for (int i = 0; i < get_child_count(); i++) {
		NNHTNNodes *child = Object::cast_to<NNHTNNodes>(get_child(i));
		if (child == nullptr) {
			continue;
		}
		if (Object::cast_to<NNHTNMethod>(child) != nullptr) {
			warnings.push_back(vformat("'%s' is a method; a method's children must be tasks, compound tasks, subtask calls or parallel groups.", child->get_name()));
		} else {
			has_task = true;
		}
	}
	if (!has_task) {
		warnings.push_back("A method needs at least one task, compound task, subtask call or parallel group child; an empty method never decomposes.");
	}
	if (!Math::is_finite(_priority) || _priority < 0.0) {
		warnings.push_back("priority must be finite and non-negative.");
	}
	warnings.append_array(get_binding_errors());
	warnings.append_array(get_ordering_warnings());
	warnings.append_array(get_ordering_errors());
	return warnings;
}

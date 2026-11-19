#include "nodes.h"

#include "../expression_util.h"
#include "root.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

static bool _fail_precondition(Dictionary *r_failure, const String &p_condition, int p_index) {
	if (r_failure != nullptr) {
		(*r_failure)["condition"] = p_condition;
		(*r_failure)["condition_index"] = p_index;
	}
	return false;
}

// NNHTNStateView.

NNHTNStateView::NNHTNStateView(const Dictionary &p_values) :
		_values(p_values) {
}

const Dictionary &NNHTNStateView::get_values() const {
	return _values;
}

Variant NNHTNStateView::get_read_only_value(const String &p_key) const {
	Variant value = _read_only_values.get_or_add(p_key, Variant());
	// A cached NIL is rebuilt, which only costs another NIL copy.
	if (value.get_type() == Variant::NIL) {
		value = NNExpressionUtil::read_only_copy(_values.get(p_key, Variant()));
		_read_only_values[p_key] = value;
	}
	return value;
}

const Dictionary &NNHTNStateView::get_hook_state() const {
	if (!_hook_state_valid) {
		// The previous state was sealed, so it is replaced rather than rewritten.
		_hook_state = Dictionary();
		const Array keys = _values.keys();
		for (int i = 0; i < keys.size(); i++) {
			_hook_state[keys[i]] = get_read_only_value(keys[i]);
		}
		_hook_state.make_read_only();
		_hook_state_valid = true;
	}
	_hook_state_reads++;
	return _hook_state;
}

uint64_t NNHTNStateView::get_hook_state_reads() const {
	return _hook_state_reads;
}

void NNHTNStateView::set_value(const String &p_key, const Variant &p_value) {
	Change change;
	change.key = p_key;
	change.existed = _values.has(p_key);
	if (change.existed) {
		change.previous = _values.get(p_key, Variant());
	}
	_trail.push_back(std::move(change));
	// A null value means the key is absent, as on NNBlackboard.
	if (p_value.get_type() == Variant::NIL) {
		_values.erase(p_key);
	} else {
		_values[p_key] = p_value;
	}
	_read_only_values.erase(p_key);
	_hook_state_valid = false;
}

void NNHTNStateView::reset(const Dictionary &p_values) {
	_values = p_values;
	_read_only_values.clear();
	_hook_state_valid = false;
	_trail.clear();
}

size_t NNHTNStateView::get_trail_mark() const {
	return _trail.size();
}

void NNHTNStateView::restore_trail(size_t p_mark) {
	if (_trail.size() <= p_mark) {
		return;
	}
	while (_trail.size() > p_mark) {
		const Change &change = _trail.back();
		if (change.existed) {
			_values[change.key] = change.previous;
		} else {
			_values.erase(change.key);
		}
		_read_only_values.erase(change.key);
		_trail.pop_back();
	}
	_hook_state_valid = false;
}

// NNHTNNodes.

void NNHTNNodes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_conditions", "conditions"), &NNHTNNodes::set_conditions);
	ClassDB::bind_method(D_METHOD("get_conditions"), &NNHTNNodes::get_conditions);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "conditions", PROPERTY_HINT_ARRAY_TYPE, "NNHTNCondition"), "set_conditions", "get_conditions");

	ClassDB::bind_method(D_METHOD("set_dependency_keys", "dependency_keys"), &NNHTNNodes::set_dependency_keys);
	ClassDB::bind_method(D_METHOD("get_dependency_keys"), &NNHTNNodes::get_dependency_keys);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "dependency_keys"), "set_dependency_keys", "get_dependency_keys");

	ClassDB::bind_method(D_METHOD("set_dependencies_complete", "dependencies_complete"), &NNHTNNodes::set_dependencies_complete);
	ClassDB::bind_method(D_METHOD("get_dependencies_complete"), &NNHTNNodes::get_dependencies_complete);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "dependencies_complete"), "set_dependencies_complete", "get_dependencies_complete");

	ClassDB::bind_method(D_METHOD("set_predecessors", "predecessors"), &NNHTNNodes::set_predecessors);
	ClassDB::bind_method(D_METHOD("get_predecessors"), &NNHTNNodes::get_predecessors);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "predecessors", PROPERTY_HINT_TYPE_STRING, vformat("%d/%d:NNHTNNodes", Variant::OBJECT, PROPERTY_HINT_NODE_TYPE)), "set_predecessors", "get_predecessors");

	ClassDB::bind_method(D_METHOD("get_htn_root"), &NNHTNNodes::get_htn_root);

	GDVIRTUAL_BIND(on_check_preconditions, "state", "args");
}

NNHTNNodes::NNHTNNodes() {
	_dependencies_complete = false;
}

void NNHTNNodes::set_conditions(const TypedArray<NNHTNCondition> &p_conditions) {
	_conditions = p_conditions;
	update_configuration_warnings();
}

TypedArray<NNHTNCondition> NNHTNNodes::get_conditions() const {
	return _conditions;
}

void NNHTNNodes::set_dependency_keys(const PackedStringArray &p_dependency_keys) {
	_dependency_keys = p_dependency_keys;
	update_configuration_warnings();
}

PackedStringArray NNHTNNodes::get_dependency_keys() const {
	return _dependency_keys;
}

void NNHTNNodes::set_dependencies_complete(bool p_dependencies_complete) {
	_dependencies_complete = p_dependencies_complete;
}

bool NNHTNNodes::get_dependencies_complete() const {
	return _dependencies_complete;
}

void NNHTNNodes::set_predecessors(const TypedArray<NNHTNNodes> &p_predecessors) {
	_predecessors = p_predecessors;
	// The ordering graph is validated by the parent method.
	if (Node *parent = get_parent()) {
		parent->update_configuration_warnings();
	}
}

TypedArray<NNHTNNodes> NNHTNNodes::get_predecessors() const {
	return _predecessors;
}

bool NNHTNNodes::_has_hook(const StringName &p_name) const {
	return gdextension_interface::object_has_script_method(_owner, &p_name);
}

bool NNHTNNodes::_call_hook(const StringName &p_name, const Variant **p_args, int p_argc, Variant &r_result) const {
	if (!_has_hook(p_name)) {
		return false;
	}
	GDExtensionCallError call_error;
	gdextension_interface::object_call_script_method(_owner, &p_name, (const GDExtensionConstVariantPtr *)p_args, p_argc, &r_result, &call_error);
	return call_error.error == GDEXTENSION_CALL_OK;
}

String NNHTNNodes::_describe() const {
	return vformat("%s '%s'", get_class(), NNExpressionUtil::path_of(this));
}

Dictionary NNHTNNodes::_condition_args(const Dictionary &p_args) const {
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_valid() && condition->get_reads_args()) {
			return NNExpressionUtil::read_only_copy(p_args);
		}
	}
	Dictionary unread;
	unread.make_read_only();
	return unread;
}

bool NNHTNNodes::check_preconditions(const NNHTNStateView &p_state, const Dictionary &p_args, Dictionary *r_failure) const {
	if (!_conditions.is_empty()) {
		const Dictionary args = _condition_args(p_args);
		for (int i = 0; i < _conditions.size(); i++) {
			Ref<NNHTNCondition> condition = _conditions[i];
			if (condition.is_null()) {
				ERR_PRINT(vformat("%s: conditions[%d] is empty; the node is unavailable.", _describe(), i));
				return _fail_precondition(r_failure, String(), i);
			}
			if (!condition->evaluate_read_only(p_state, args)) {
				return _fail_precondition(r_failure, condition->get_expression(), i);
			}
		}
	}

	if (!_has_hook(_gdvirtual_on_check_preconditions_sn)) {
		return true;
	}
	const Variant args[2] = { p_state.get_hook_state(), p_args };
	const Variant *arg_ptrs[2] = { &args[0], &args[1] };
	Variant result;
	if (!_call_hook(_gdvirtual_on_check_preconditions_sn, arg_ptrs, 2, result) || result.get_type() != Variant::BOOL) {
		ERR_PRINT(vformat("%s: on_check_preconditions() must return a bool; got %s. Treating it as false.", _describe(), Variant::get_type_name(result.get_type())));
		return _fail_precondition(r_failure, "on_check_preconditions()", -1);
	}
	return bool(result) || _fail_precondition(r_failure, "on_check_preconditions()", -1);
}

void NNHTNNodes::report_configuration_error(const String &p_message) const {
	if (p_message == _reported_configuration_error) {
		return;
	}
	_reported_configuration_error = p_message;
	if (!p_message.is_empty()) {
		ERR_PRINT(vformat("%s: %s", _describe(), p_message));
	}
}

void NNHTNNodes::collect_dependency_keys(HashSet<String> &r_keys) const {
	for (const String &key : _dependency_keys) {
		if (!key.is_empty()) {
			r_keys.insert(key);
		}
	}
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_valid()) {
			for (const String &key : condition->get_read_keys()) {
				r_keys.insert(key);
			}
		}
	}
}

NNHTNRoot *NNHTNNodes::get_htn_root() const {
	for (Node *node = get_parent(); node != nullptr; node = node->get_parent()) {
		if (NNHTNRoot *root = Object::cast_to<NNHTNRoot>(node)) {
			return root;
		}
	}
	return nullptr;
}

PackedStringArray NNHTNNodes::_get_configuration_warnings() const {
	PackedStringArray warnings;
	for (int i = 0; i < _conditions.size(); i++) {
		Ref<NNHTNCondition> condition = _conditions[i];
		if (condition.is_null()) {
			warnings.push_back(vformat("conditions[%d] is empty, which makes this node unavailable.", i));
			continue;
		}
		const String error = condition->get_parse_error();
		if (!error.is_empty()) {
			warnings.push_back(vformat("conditions[%d] does not parse: %s", i, error));
		}
	}
	for (const String &key : _dependency_keys) {
		if (key.is_empty()) {
			warnings.push_back("dependency_keys contains an empty entry.");
			break;
		}
	}
	return warnings;
}

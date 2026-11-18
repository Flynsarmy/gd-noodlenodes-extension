#include "task.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

void NNHTNTask::_bind_methods() {
	BIND_ENUM_CONSTANT(FAILURE);
	BIND_ENUM_CONSTANT(RUNNING);
	BIND_ENUM_CONSTANT(SUCCESS);
	BIND_ENUM_CONSTANT(TRUST_SUCCESS);
	BIND_ENUM_CONSTANT(VERIFY);
	BIND_ENUM_CONSTANT(ALL);
	BIND_ENUM_CONSTANT(NONE);
	BIND_ENUM_CONSTANT(ALLOWLIST);

	ClassDB::bind_method(D_METHOD("set_effects", "effects"), &NNHTNTask::set_effects);
	ClassDB::bind_method(D_METHOD("get_effects"), &NNHTNTask::get_effects);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "effects", PROPERTY_HINT_DICTIONARY_TYPE, vformat("%s;%s", Variant::get_type_name(Variant::STRING), "Variant")), "set_effects", "get_effects");

	ClassDB::bind_method(D_METHOD("set_estimated_cost", "estimated_cost"), &NNHTNTask::set_estimated_cost);
	ClassDB::bind_method(D_METHOD("get_estimated_cost"), &NNHTNTask::get_estimated_cost);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "estimated_cost", PROPERTY_HINT_RANGE, "0,1000000,0.001,or_greater"), "set_estimated_cost", "get_estimated_cost");

	ClassDB::bind_method(D_METHOD("set_resumable", "resumable"), &NNHTNTask::set_resumable);
	ClassDB::bind_method(D_METHOD("get_resumable"), &NNHTNTask::get_resumable);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "resumable"), "set_resumable", "get_resumable");

	ADD_GROUP("Verification", "");
	ClassDB::bind_method(D_METHOD("set_verification_mode", "verification_mode"), &NNHTNTask::set_verification_mode);
	ClassDB::bind_method(D_METHOD("get_verification_mode"), &NNHTNTask::get_verification_mode);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "verification_mode", PROPERTY_HINT_ENUM, "Trust Success,Verify"), "set_verification_mode", "get_verification_mode");

	ClassDB::bind_method(D_METHOD("set_postconditions", "postconditions"), &NNHTNTask::set_postconditions);
	ClassDB::bind_method(D_METHOD("get_postconditions"), &NNHTNTask::get_postconditions);
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "postconditions", PROPERTY_HINT_ARRAY_TYPE, "NNHTNCondition"), "set_postconditions", "get_postconditions");

	ClassDB::bind_method(D_METHOD("set_verification_timeout", "verification_timeout"), &NNHTNTask::set_verification_timeout);
	ClassDB::bind_method(D_METHOD("get_verification_timeout"), &NNHTNTask::get_verification_timeout);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "verification_timeout", PROPERTY_HINT_RANGE, "0,3600,0.01,or_greater,suffix:s"), "set_verification_timeout", "get_verification_timeout");

	ADD_GROUP("Runtime Effects", "");
	ClassDB::bind_method(D_METHOD("set_runtime_effect_commit_mode", "runtime_effect_commit_mode"), &NNHTNTask::set_runtime_effect_commit_mode);
	ClassDB::bind_method(D_METHOD("get_runtime_effect_commit_mode"), &NNHTNTask::get_runtime_effect_commit_mode);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "runtime_effect_commit_mode", PROPERTY_HINT_ENUM, "All,None,Allowlist"), "set_runtime_effect_commit_mode", "get_runtime_effect_commit_mode");

	ClassDB::bind_method(D_METHOD("set_runtime_commit_effect_keys", "runtime_commit_effect_keys"), &NNHTNTask::set_runtime_commit_effect_keys);
	ClassDB::bind_method(D_METHOD("get_runtime_commit_effect_keys"), &NNHTNTask::get_runtime_commit_effect_keys);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "runtime_commit_effect_keys"), "set_runtime_commit_effect_keys", "get_runtime_commit_effect_keys");

	ADD_GROUP("Parallel Safety", "");
	ClassDB::bind_method(D_METHOD("set_actor_resources", "actor_resources"), &NNHTNTask::set_actor_resources);
	ClassDB::bind_method(D_METHOD("get_actor_resources"), &NNHTNTask::get_actor_resources);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "actor_resources"), "set_actor_resources", "get_actor_resources");

	ClassDB::bind_method(D_METHOD("set_concurrency_read_keys", "concurrency_read_keys"), &NNHTNTask::set_concurrency_read_keys);
	ClassDB::bind_method(D_METHOD("get_concurrency_read_keys"), &NNHTNTask::get_concurrency_read_keys);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "concurrency_read_keys"), "set_concurrency_read_keys", "get_concurrency_read_keys");

	ClassDB::bind_method(D_METHOD("set_concurrency_write_keys", "concurrency_write_keys"), &NNHTNTask::set_concurrency_write_keys);
	ClassDB::bind_method(D_METHOD("get_concurrency_write_keys"), &NNHTNTask::get_concurrency_write_keys);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "concurrency_write_keys"), "set_concurrency_write_keys", "get_concurrency_write_keys");

	ClassDB::bind_method(D_METHOD("set_concurrency_contract_complete", "concurrency_contract_complete"), &NNHTNTask::set_concurrency_contract_complete);
	ClassDB::bind_method(D_METHOD("get_concurrency_contract_complete"), &NNHTNTask::get_concurrency_contract_complete);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "concurrency_contract_complete"), "set_concurrency_contract_complete", "get_concurrency_contract_complete");

	ADD_SIGNAL(MethodInfo("started"));
	ADD_SIGNAL(MethodInfo("succeeded"));
	ADD_SIGNAL(MethodInfo("failed"));

	GDVIRTUAL_BIND(on_get_effects, "state", "args");
	GDVIRTUAL_BIND(on_get_estimated_cost, "state", "args");
	// Bound by hand: GDVIRTUAL cannot name an enum declared in the same class.
	MethodInfo on_execute("on_execute", PropertyInfo(Variant::FLOAT, "delta"), PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep"));
	on_execute.flags = METHOD_FLAG_VIRTUAL;
	on_execute.return_val = PropertyInfo(Variant::INT, "", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NNHTNTask.Status");
	on_execute.arguments_metadata.push_back(GDEXTENSION_METHOD_ARGUMENT_METADATA_REAL_IS_DOUBLE);
	on_execute.arguments_metadata.push_back(GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
	ClassDB::add_virtual_method(get_class_static(), on_execute, { "delta", "step" });
	MethodInfo on_verify("on_verify", PropertyInfo(Variant::OBJECT, "step", PROPERTY_HINT_RESOURCE_TYPE, "NNHTNPlanStep"));
	on_verify.flags = METHOD_FLAG_VIRTUAL;
	on_verify.return_val = on_execute.return_val;
	on_verify.arguments_metadata.push_back(GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE);
	ClassDB::add_virtual_method(get_class_static(), on_verify, { "step" });
	GDVIRTUAL_BIND(on_can_continue_verification, "step");
	GDVIRTUAL_BIND(on_cancel, "step");
}

NNHTNTask::NNHTNTask() {
	_estimated_cost = 0.0;
	_resumable = false;
	_verification_mode = TRUST_SUCCESS;
	_verification_timeout = 0.0;
	_runtime_effect_commit_mode = ALL;
	_concurrency_contract_complete = false;
	_missing_on_execute_reported = false;
	_root_host.configure(this);
	_hosted_result = RUNNING;
	_on_execute_sn = "on_execute";
	_on_verify_sn = "on_verify";
}

void NNHTNTask::set_effects(const Dictionary &p_effects) {
	_effects = p_effects;
}

Dictionary NNHTNTask::get_effects() const {
	return _effects;
}

void NNHTNTask::set_estimated_cost(double p_estimated_cost) {
	_estimated_cost = p_estimated_cost;
	update_configuration_warnings();
}

double NNHTNTask::get_estimated_cost() const {
	return _estimated_cost;
}

void NNHTNTask::set_resumable(bool p_resumable) {
	_resumable = p_resumable;
}

bool NNHTNTask::get_resumable() const {
	return _resumable;
}

void NNHTNTask::set_verification_mode(VerificationMode p_verification_mode) {
	_verification_mode = p_verification_mode;
	notify_property_list_changed();
	update_configuration_warnings();
}

NNHTNTask::VerificationMode NNHTNTask::get_verification_mode() const {
	return _verification_mode;
}

void NNHTNTask::set_postconditions(const TypedArray<NNHTNCondition> &p_postconditions) {
	_postconditions = p_postconditions;
	update_configuration_warnings();
}

TypedArray<NNHTNCondition> NNHTNTask::get_postconditions() const {
	return _postconditions;
}

void NNHTNTask::set_verification_timeout(double p_verification_timeout) {
	_verification_timeout = p_verification_timeout;
	update_configuration_warnings();
}

double NNHTNTask::get_verification_timeout() const {
	return _verification_timeout;
}

void NNHTNTask::set_runtime_effect_commit_mode(RuntimeEffectCommitMode p_runtime_effect_commit_mode) {
	_runtime_effect_commit_mode = p_runtime_effect_commit_mode;
	notify_property_list_changed();
	update_configuration_warnings();
}

NNHTNTask::RuntimeEffectCommitMode NNHTNTask::get_runtime_effect_commit_mode() const {
	return _runtime_effect_commit_mode;
}

void NNHTNTask::set_runtime_commit_effect_keys(const PackedStringArray &p_runtime_commit_effect_keys) {
	_runtime_commit_effect_keys = p_runtime_commit_effect_keys;
	update_configuration_warnings();
}

PackedStringArray NNHTNTask::get_runtime_commit_effect_keys() const {
	return _runtime_commit_effect_keys;
}

void NNHTNTask::set_actor_resources(const PackedStringArray &p_actor_resources) {
	_actor_resources = p_actor_resources;
	update_configuration_warnings();
}

PackedStringArray NNHTNTask::get_actor_resources() const {
	return _actor_resources;
}

void NNHTNTask::set_concurrency_read_keys(const PackedStringArray &p_concurrency_read_keys) {
	_concurrency_read_keys = p_concurrency_read_keys;
	update_configuration_warnings();
}

PackedStringArray NNHTNTask::get_concurrency_read_keys() const {
	return _concurrency_read_keys;
}

void NNHTNTask::set_concurrency_write_keys(const PackedStringArray &p_concurrency_write_keys) {
	_concurrency_write_keys = p_concurrency_write_keys;
	update_configuration_warnings();
}

PackedStringArray NNHTNTask::get_concurrency_write_keys() const {
	return _concurrency_write_keys;
}

void NNHTNTask::set_concurrency_contract_complete(bool p_concurrency_contract_complete) {
	_concurrency_contract_complete = p_concurrency_contract_complete;
}

bool NNHTNTask::get_concurrency_contract_complete() const {
	return _concurrency_contract_complete;
}

void NNHTNTask::collect_concurrency_reads(HashSet<String> &r_keys) const {
	collect_dependency_keys(r_keys);
	for (const String &key : _concurrency_read_keys) {
		r_keys.insert(key);
	}
	if (_verification_mode != VERIFY) {
		return;
	}
	for (int i = 0; i < _postconditions.size(); i++) {
		Ref<NNHTNCondition> condition = _postconditions[i];
		if (condition.is_valid()) {
			for (const String &key : condition->get_read_keys()) {
				r_keys.insert(key);
			}
		}
	}
}

static void _append_entry_warnings(const PackedStringArray &p_entries, const char *p_property, PackedStringArray &r_warnings) {
	HashSet<String> seen;
	for (const String &entry : p_entries) {
		if (entry.is_empty()) {
			r_warnings.push_back(vformat("%s contains an empty entry.", p_property));
		} else if (seen.has(entry)) {
			r_warnings.push_back(vformat("%s contains '%s' more than once.", p_property, entry));
		}
		seen.insert(entry);
	}
}

void NNHTNTask::_validate_property(PropertyInfo &p_property) const {
	// Hidden values are kept, so switching modes back restores them.
	const bool verify_only = p_property.name == StringName("postconditions") || p_property.name == StringName("verification_timeout");
	if ((verify_only && _verification_mode != VERIFY) || (p_property.name == StringName("runtime_commit_effect_keys") && _runtime_effect_commit_mode != ALLOWLIST)) {
		p_property.usage &= ~PROPERTY_USAGE_EDITOR;
	}
}

bool NNHTNTask::compute_effects(const NNHTNStateView &p_state, const Dictionary &p_args, Dictionary &r_effects) const {
	if (!_has_hook(_gdvirtual_on_get_effects_sn)) {
		r_effects = _effects.duplicate(true);
		return true;
	}
	const Variant args[2] = { p_state.get_hook_state(), p_args };
	const Variant *arg_ptrs[2] = { &args[0], &args[1] };
	Variant result;
	if (!_call_hook(_gdvirtual_on_get_effects_sn, arg_ptrs, 2, result) || result.get_type() != Variant::DICTIONARY) {
		ERR_PRINT(vformat("%s: on_get_effects() must return a Dictionary; got %s. The occurrence is rejected.", _describe(), Variant::get_type_name(result.get_type())));
		return false;
	}
	r_effects = Dictionary(result).duplicate(true);
	return true;
}

bool NNHTNTask::compute_estimated_cost(const NNHTNStateView &p_state, const Dictionary &p_args, double &r_cost) const {
	Variant result = _estimated_cost;
	if (_has_hook(_gdvirtual_on_get_estimated_cost_sn)) {
		const Variant args[2] = { p_state.get_hook_state(), p_args };
		const Variant *arg_ptrs[2] = { &args[0], &args[1] };
		if (!_call_hook(_gdvirtual_on_get_estimated_cost_sn, arg_ptrs, 2, result) || (result.get_type() != Variant::INT && result.get_type() != Variant::FLOAT)) {
			ERR_PRINT(vformat("%s: on_get_estimated_cost() must return a number; got %s. The occurrence is rejected.", _describe(), Variant::get_type_name(result.get_type())));
			return false;
		}
	}
	const double cost = result;
	if (!Math::is_finite(cost) || cost < 0.0) {
		ERR_PRINT(vformat("%s: estimated cost must be finite and non-negative; got %s. The occurrence is rejected.", _describe(), result));
		return false;
	}
	r_cost = cost;
	return true;
}

PackedStringArray NNHTNTask::get_committed_effect_keys(const Dictionary &p_effects) const {
	PackedStringArray keys;
	if (_runtime_effect_commit_mode == NONE) {
		return keys;
	}
	const Array effect_keys = p_effects.keys();
	for (int i = 0; i < effect_keys.size(); i++) {
		if (_runtime_effect_commit_mode == ALL || _runtime_commit_effect_keys.has(effect_keys[i])) {
			keys.push_back(effect_keys[i]);
		}
	}
	return keys;
}

PackedStringArray NNHTNTask::get_execution_errors() const {
	PackedStringArray errors;
	if (_verification_mode != TRUST_SUCCESS && _verification_mode != VERIFY) {
		errors.push_back(vformat("verification_mode %d is invalid.", (int)_verification_mode));
	}
	if (_verification_mode == VERIFY) {
		if (!Math::is_finite(_verification_timeout) || _verification_timeout < 0.0) {
			errors.push_back(vformat("verification_timeout must be finite and non-negative; got %s.", _verification_timeout));
		}
		for (int i = 0; i < _postconditions.size(); i++) {
			Ref<NNHTNCondition> condition = _postconditions[i];
			if (condition.is_null()) {
				errors.push_back(vformat("postconditions[%d] is empty.", i));
			} else if (!condition->get_parse_error().is_empty()) {
				errors.push_back(vformat("postconditions[%d] does not parse: %s", i, condition->get_parse_error()));
			}
		}
	}
	if (_runtime_effect_commit_mode != ALL && _runtime_effect_commit_mode != NONE && _runtime_effect_commit_mode != ALLOWLIST) {
		errors.push_back(vformat("runtime_effect_commit_mode %d is invalid.", (int)_runtime_effect_commit_mode));
	}
	return errors;
}

NNHTNTask::Status NNHTNTask::_call_status_hook(const StringName &p_name, const Variant **p_args, int p_argc) {
	Variant result;
	const bool called = _call_hook(p_name, p_args, p_argc, result);
	if (!called || result.get_type() != Variant::INT) {
		ERR_PRINT(vformat("%s: %s() returned a value of type '%s'; it must return RUNNING, SUCCESS or FAILURE. Treating the result as FAILURE.", _describe(), p_name, Variant::get_type_name(result.get_type())));
		return FAILURE;
	}
	const int64_t value = result;
	if (value != FAILURE && value != RUNNING && value != SUCCESS) {
		ERR_PRINT(vformat("%s: %s() returned '%d'; it must return RUNNING, SUCCESS or FAILURE. Treating the result as FAILURE.", _describe(), p_name, value));
		return FAILURE;
	}
	return (Status)value;
}

NNHTNTask::Status NNHTNTask::execute(double p_delta, const Ref<NNHTNPlanStep> &p_step) {
	const bool has_on_execute = _has_hook(_on_execute_sn);
	const bool hosts_roots = _root_host.has_roots();
	if (!has_on_execute && !hosts_roots) {
		if (!_missing_on_execute_reported) {
			_missing_on_execute_reported = true;
			ERR_PRINT(vformat("%s has no on_execute(delta: float, step: NNHTNPlanStep) -> Status override and hosts no root. Add on_execute to the node's script or a root under it; returning FAILURE.", _describe()));
		}
		return FAILURE;
	}

	const ObjectID step_id = ObjectID(p_step->get_instance_id());
	if (hosts_roots && _hosting_step_id != step_id) {
		if (!_hosting_step_id.is_null()) {
			ERR_PRINT(vformat("%s is already running its hosted roots for another occurrence; returning FAILURE.", _describe()));
			return FAILURE;
		}
		_hosting_step_id = step_id;
		_hosted_result = RUNNING;
		_root_host.activate();
	}

	Status result = RUNNING;
	if (has_on_execute) {
		const Variant args[2] = { p_delta, p_step };
		const Variant *arg_ptrs[2] = { &args[0], &args[1] };
		result = _call_status_hook(_on_execute_sn, arg_ptrs, 2);
	}
	if (result == RUNNING && _hosting_step_id == step_id) {
		_root_host.tick(p_delta);
		result = _hosted_result;
	}
	if (result != RUNNING) {
		_release_hosted_roots(step_id);
	}
	return result;
}

void NNHTNTask::_release_hosted_roots(const ObjectID &p_step_id) {
	if (_hosting_step_id != p_step_id) {
		return;
	}
	_hosting_step_id = ObjectID();
	_root_host.deactivate();
}

void NNHTNTask::_on_hosted_root_finished(bool p_succeeded, Node *p_root) {
	// Only the first report of the occurrence counts.
	if (!_hosting_step_id.is_null() && _hosted_result == RUNNING) {
		_hosted_result = p_succeeded ? SUCCESS : FAILURE;
	}
}

NNHTNTask::Status NNHTNTask::verify(const Dictionary &p_live_state, const Ref<NNHTNPlanStep> &p_step) {
	if (_has_hook(_on_verify_sn)) {
		const Variant arg = p_step;
		const Variant *arg_ptr = &arg;
		return _call_status_hook(_on_verify_sn, &arg_ptr, 1);
	}
	for (int i = 0; i < _postconditions.size(); i++) {
		Ref<NNHTNCondition> condition = _postconditions[i];
		if (condition.is_null()) {
			ERR_PRINT(vformat("%s: postconditions[%d] is empty; verification fails.", _describe(), i));
			return FAILURE;
		}
		if (!condition->evaluate(p_live_state, p_step->get_args())) {
			return RUNNING;
		}
	}
	return SUCCESS;
}

bool NNHTNTask::can_continue_verification(const Ref<NNHTNPlanStep> &p_step) const {
	if (!_has_hook(_gdvirtual_on_can_continue_verification_sn)) {
		return true;
	}
	const Variant arg = p_step;
	const Variant *arg_ptr = &arg;
	Variant result;
	if (!_call_hook(_gdvirtual_on_can_continue_verification_sn, &arg_ptr, 1, result) || result.get_type() != Variant::BOOL) {
		ERR_PRINT(vformat("%s: on_can_continue_verification() must return a bool; got %s. Treating it as false.", _describe(), Variant::get_type_name(result.get_type())));
		return false;
	}
	return result;
}

void NNHTNTask::cancel(const Ref<NNHTNPlanStep> &p_step) {
	_release_hosted_roots(ObjectID(p_step->get_instance_id()));
	GDVIRTUAL_CALL(on_cancel, p_step);
}

PackedStringArray NNHTNTask::_get_configuration_warnings() const {
	PackedStringArray warnings = NNHTNNodes::_get_configuration_warnings();
	for (int i = 0; i < get_child_count(); i++) {
		if (Object::cast_to<NNHTNNodes>(get_child(i)) != nullptr) {
			warnings.push_back(vformat("'%s' is never planned: a primitive task's children are only the roots it hosts.", get_child(i)->get_name()));
		}
	}
	if (!Math::is_finite(_estimated_cost) || _estimated_cost < 0.0) {
		warnings.push_back("estimated_cost must be finite and non-negative.");
	}
	for (const String &error : get_execution_errors()) {
		warnings.push_back(error + String(" Occurrences of this task are rejected while planning."));
	}
	if (_runtime_effect_commit_mode == ALLOWLIST && _runtime_commit_effect_keys.has(String())) {
		warnings.push_back("runtime_commit_effect_keys contains an empty entry.");
	}
	_append_entry_warnings(_actor_resources, "actor_resources", warnings);
	_append_entry_warnings(_concurrency_read_keys, "concurrency_read_keys", warnings);
	_append_entry_warnings(_concurrency_write_keys, "concurrency_write_keys", warnings);
	return warnings;
}

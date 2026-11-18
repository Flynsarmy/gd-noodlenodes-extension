#include "plan_step.h"

#include "parallel_task.h"
#include "task.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

static uint64_t next_occurrence_id = 1;

static bool _references_valid(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::OBJECT: {
			// Read the stored ID instead of dereferencing: the object may already be freed.
			Object *object = ObjectDB::get_instance(p_value.operator ObjectID());
			if (object == nullptr) {
				return false;
			}
			Node *node = Object::cast_to<Node>(object);
			return node == nullptr || !node->is_queued_for_deletion();
		}
		case Variant::ARRAY: {
			const Array array = p_value;
			for (int i = 0; i < array.size(); i++) {
				if (!_references_valid(array[i])) {
					return false;
				}
			}
			return true;
		}
		case Variant::DICTIONARY: {
			const Dictionary dictionary = p_value;
			const Array values = dictionary.values();
			for (int i = 0; i < values.size(); i++) {
				if (!_references_valid(values[i])) {
					return false;
				}
			}
			return true;
		}
		default:
			return true;
	}
}

void NNHTNPlanStep::_bind_methods() {
	BIND_ENUM_CONSTANT(PENDING);
	BIND_ENUM_CONSTANT(RUNNING);
	BIND_ENUM_CONSTANT(VERIFYING);
	BIND_ENUM_CONSTANT(STAGED);
	BIND_ENUM_CONSTANT(SUCCEEDED);
	BIND_ENUM_CONSTANT(FAILED);
	BIND_ENUM_CONSTANT(CANCELLED);

	ClassDB::bind_method(D_METHOD("get_task"), &NNHTNPlanStep::get_task);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "task", PROPERTY_HINT_NODE_TYPE, "NNHTNTask", PROPERTY_USAGE_NONE), "", "get_task");
	ClassDB::bind_method(D_METHOD("get_args"), &NNHTNPlanStep::get_args);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "args", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_args");
	ClassDB::bind_method(D_METHOD("get_effects"), &NNHTNPlanStep::get_effects);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "effects", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_effects");
	ClassDB::bind_method(D_METHOD("get_runtime"), &NNHTNPlanStep::get_runtime);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "runtime", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_runtime");
	ClassDB::bind_method(D_METHOD("get_call_path"), &NNHTNPlanStep::get_call_path);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "call_path", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_call_path");
	ClassDB::bind_method(D_METHOD("get_cost"), &NNHTNPlanStep::get_cost);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "cost", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_cost");
	ClassDB::bind_method(D_METHOD("get_occurrence_id"), &NNHTNPlanStep::get_occurrence_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "occurrence_id", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_occurrence_id");
	ClassDB::bind_method(D_METHOD("get_state"), &NNHTNPlanStep::get_state);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "state", PROPERTY_HINT_ENUM, "Pending,Running,Verifying,Staged,Succeeded,Failed,Cancelled", PROPERTY_USAGE_NONE), "", "get_state");

	ClassDB::bind_method(D_METHOD("get_verification_elapsed"), &NNHTNPlanStep::get_verification_elapsed);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "verification_elapsed", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_verification_elapsed");
	ClassDB::bind_method(D_METHOD("get_failure_reason"), &NNHTNPlanStep::get_failure_reason);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "failure_reason", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_failure_reason");

	ClassDB::bind_method(D_METHOD("get_parallel_group"), &NNHTNPlanStep::get_parallel_group);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "parallel_group", PROPERTY_HINT_NODE_TYPE, "NNHTNParallelTask", PROPERTY_USAGE_NONE), "", "get_parallel_group");
	ClassDB::bind_method(D_METHOD("get_parallel_group_id"), &NNHTNPlanStep::get_parallel_group_id);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "parallel_group_id", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_parallel_group_id");
	ClassDB::bind_method(D_METHOD("get_parallel_branch_index"), &NNHTNPlanStep::get_parallel_branch_index);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "parallel_branch_index", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_parallel_branch_index");
	ClassDB::bind_method(D_METHOD("get_parallel_branch_count"), &NNHTNPlanStep::get_parallel_branch_count);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "parallel_branch_count", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_parallel_branch_count");
	ClassDB::bind_method(D_METHOD("get_parallel_group_args"), &NNHTNPlanStep::get_parallel_group_args);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "parallel_group_args", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_parallel_group_args");
	ClassDB::bind_method(D_METHOD("get_parallel_group_effects"), &NNHTNPlanStep::get_parallel_group_effects);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "parallel_group_effects", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_parallel_group_effects");
	ClassDB::bind_method(D_METHOD("get_deferred_group_effects"), &NNHTNPlanStep::get_deferred_group_effects);
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "deferred_group_effects", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_deferred_group_effects");

	ClassDB::bind_method(D_METHOD("get_observed_effect_keys"), &NNHTNPlanStep::get_observed_effect_keys);
	ClassDB::bind_method(D_METHOD("get_provenance"), &NNHTNPlanStep::get_provenance);
	ClassDB::bind_method(D_METHOD("has_valid_references"), &NNHTNPlanStep::has_valid_references);
}

NNHTNPlanStep::NNHTNPlanStep() {
	_cost = 0.0;
	_occurrence_id = next_occurrence_id++;
	_state = PENDING;
	_verification_elapsed = 0.0;
	_parallel_group_id = 0;
	_parallel_branch_index = -1;
	_parallel_branch_count = 0;
}

void NNHTNPlanStep::setup(NNHTNTask *p_task, const Dictionary &p_args, const Dictionary &p_effects, const PackedStringArray &p_committed_effect_keys, double p_cost, const String &p_call_path, std::vector<NNHTNProvenanceFrame> &&p_provenance) {
	_task_id = p_task != nullptr ? ObjectID(p_task->get_instance_id()) : ObjectID();
	_args = p_args;
	_args.make_read_only();
	_effects = p_effects;
	_effects.make_read_only();
	_committed_effect_keys = p_committed_effect_keys;
	_cost = p_cost;
	_call_path = p_call_path;
	_provenance = std::move(p_provenance);
}

void NNHTNPlanStep::set_parallel_group(NNHTNParallelTask *p_group, uint64_t p_group_id, int p_branch_index, int p_branch_count, const Dictionary &p_group_args, const Dictionary &p_group_effects) {
	_parallel_group = p_group != nullptr ? ObjectID(p_group->get_instance_id()) : ObjectID();
	_parallel_group_id = p_group_id;
	_parallel_branch_index = p_branch_index;
	_parallel_branch_count = p_branch_count;
	_parallel_group_args = p_group_args;
	_parallel_group_args.make_read_only();
	_parallel_group_effects = p_group_effects;
	_parallel_group_effects.make_read_only();
}

void NNHTNPlanStep::set_deferred_group_effects(const Dictionary &p_effects) {
	_deferred_group_effects = p_effects;
	_deferred_group_effects.make_read_only();
}

NNHTNTask *NNHTNPlanStep::get_task() const {
	return Object::cast_to<NNHTNTask>(ObjectDB::get_instance(_task_id));
}

Dictionary NNHTNPlanStep::get_args() const {
	return _args;
}

Dictionary NNHTNPlanStep::get_effects() const {
	return _effects;
}

Dictionary NNHTNPlanStep::get_committed_effects() const {
	Dictionary committed;
	for (const String &key : _committed_effect_keys) {
		committed[key] = _effects[key];
	}
	committed.merge(_deferred_group_effects, true);
	return committed;
}

PackedStringArray NNHTNPlanStep::get_committed_effect_keys() const {
	return _committed_effect_keys;
}

PackedStringArray NNHTNPlanStep::get_observed_effect_keys() const {
	PackedStringArray observed;
	const Array keys = _effects.keys();
	for (int i = 0; i < keys.size(); i++) {
		if (!_committed_effect_keys.has(keys[i])) {
			observed.push_back(keys[i]);
		}
	}
	return observed;
}

Dictionary NNHTNPlanStep::get_runtime() const {
	return _runtime;
}

String NNHTNPlanStep::get_call_path() const {
	return _call_path;
}

double NNHTNPlanStep::get_cost() const {
	return _cost;
}

int64_t NNHTNPlanStep::get_occurrence_id() const {
	return (int64_t)_occurrence_id;
}

NNHTNPlanStep::State NNHTNPlanStep::get_state() const {
	return _state;
}

void NNHTNPlanStep::set_state(State p_state) {
	_state = p_state;
}

bool NNHTNPlanStep::is_started() const {
	return _state == RUNNING || _state == VERIFYING;
}

double NNHTNPlanStep::get_verification_elapsed() const {
	return _verification_elapsed;
}

void NNHTNPlanStep::add_verification_elapsed(double p_delta) {
	_verification_elapsed += p_delta;
}

String NNHTNPlanStep::get_failure_reason() const {
	return _failure_reason;
}

void NNHTNPlanStep::set_failure_reason(const String &p_failure_reason) {
	_failure_reason = p_failure_reason;
}

NNHTNParallelTask *NNHTNPlanStep::get_parallel_group() const {
	return Object::cast_to<NNHTNParallelTask>(ObjectDB::get_instance(_parallel_group));
}

int64_t NNHTNPlanStep::get_parallel_group_id() const {
	return (int64_t)_parallel_group_id;
}

int NNHTNPlanStep::get_parallel_branch_index() const {
	return _parallel_branch_index;
}

int NNHTNPlanStep::get_parallel_branch_count() const {
	return _parallel_branch_count;
}

Dictionary NNHTNPlanStep::get_parallel_group_args() const {
	return _parallel_group_args;
}

Dictionary NNHTNPlanStep::get_parallel_group_effects() const {
	return _parallel_group_effects;
}

Dictionary NNHTNPlanStep::get_deferred_group_effects() const {
	return _deferred_group_effects;
}

Array NNHTNPlanStep::get_provenance() const {
	Array frames;
	for (const NNHTNProvenanceFrame &frame : _provenance) {
		Dictionary entry;
		entry["frame_id"] = (int64_t)frame.frame_id;
		entry["compound"] = ObjectDB::get_instance(frame.compound_id);
		entry["method"] = ObjectDB::get_instance(frame.method_id);
		entry["args"] = frame.args;
		entry["method_path"] = frame.method_path;
		entry["child_index"] = frame.child_index;
		entry["span_start"] = frame.span_start;
		entry["span_end"] = frame.span_end;
		frames.push_back(entry);
	}
	return frames;
}

std::vector<NNHTNProvenanceFrame> &NNHTNPlanStep::provenance() {
	return _provenance;
}

const std::vector<NNHTNProvenanceFrame> &NNHTNPlanStep::provenance() const {
	return _provenance;
}

bool NNHTNPlanStep::has_valid_references() const {
	NNHTNTask *task = get_task();
	if (task == nullptr || !task->get_is_enabled() || task->is_queued_for_deletion()) {
		return false;
	}
	return _references_valid(_args);
}

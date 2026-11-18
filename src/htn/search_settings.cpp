#include "search_settings.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void NNHTNSearchSettings::_bind_methods() {
	BIND_ENUM_CONSTANT(ORDERED);
	BIND_ENUM_CONSTANT(RANKED);
	BIND_ENUM_CONSTANT(LOWEST_COST);

	ClassDB::bind_method(D_METHOD("set_policy", "policy"), &NNHTNSearchSettings::set_policy);
	ClassDB::bind_method(D_METHOD("get_policy"), &NNHTNSearchSettings::get_policy);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "policy", PROPERTY_HINT_ENUM, "Ordered,Ranked,Lowest Cost"), "set_policy", "get_policy");

	ClassDB::bind_method(D_METHOD("set_max_expansions", "max_expansions"), &NNHTNSearchSettings::set_max_expansions);
	ClassDB::bind_method(D_METHOD("get_max_expansions"), &NNHTNSearchSettings::get_max_expansions);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_expansions", PROPERTY_HINT_RANGE, "1,1000000,1,or_greater"), "set_max_expansions", "get_max_expansions");

	ClassDB::bind_method(D_METHOD("set_max_time_ms", "max_time_ms"), &NNHTNSearchSettings::set_max_time_ms);
	ClassDB::bind_method(D_METHOD("get_max_time_ms"), &NNHTNSearchSettings::get_max_time_ms);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_time_ms", PROPERTY_HINT_RANGE, "0,3600000,1,or_greater,suffix:ms"), "set_max_time_ms", "get_max_time_ms");

	ClassDB::bind_method(D_METHOD("set_max_binding_candidates", "max_binding_candidates"), &NNHTNSearchSettings::set_max_binding_candidates);
	ClassDB::bind_method(D_METHOD("get_max_binding_candidates"), &NNHTNSearchSettings::get_max_binding_candidates);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_binding_candidates", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_max_binding_candidates", "get_max_binding_candidates");

	ClassDB::bind_method(D_METHOD("set_max_history_attempts", "max_history_attempts"), &NNHTNSearchSettings::set_max_history_attempts);
	ClassDB::bind_method(D_METHOD("get_max_history_attempts"), &NNHTNSearchSettings::get_max_history_attempts);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_history_attempts", PROPERTY_HINT_RANGE, "1,10000,1,or_greater"), "set_max_history_attempts", "get_max_history_attempts");

	ClassDB::bind_method(D_METHOD("set_max_history_bytes", "max_history_bytes"), &NNHTNSearchSettings::set_max_history_bytes);
	ClassDB::bind_method(D_METHOD("get_max_history_bytes"), &NNHTNSearchSettings::get_max_history_bytes);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_history_bytes", PROPERTY_HINT_RANGE, "1024,67108864,1024,or_greater,suffix:B"), "set_max_history_bytes", "get_max_history_bytes");

	ClassDB::bind_method(D_METHOD("set_max_trace_events", "max_trace_events"), &NNHTNSearchSettings::set_max_trace_events);
	ClassDB::bind_method(D_METHOD("get_max_trace_events"), &NNHTNSearchSettings::get_max_trace_events);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_trace_events", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_max_trace_events", "get_max_trace_events");

	ClassDB::bind_method(D_METHOD("get_validation_errors"), &NNHTNSearchSettings::get_validation_errors);
}

void NNHTNSearchSettings::set_policy(Policy p_policy) {
	_policy = p_policy;
	emit_changed();
}

NNHTNSearchSettings::Policy NNHTNSearchSettings::get_policy() const {
	return _policy;
}

void NNHTNSearchSettings::set_max_expansions(int p_max_expansions) {
	_max_expansions = p_max_expansions;
	emit_changed();
}

int NNHTNSearchSettings::get_max_expansions() const {
	return _max_expansions;
}

void NNHTNSearchSettings::set_max_time_ms(int p_max_time_ms) {
	_max_time_ms = p_max_time_ms;
	emit_changed();
}

int NNHTNSearchSettings::get_max_time_ms() const {
	return _max_time_ms;
}

void NNHTNSearchSettings::set_max_binding_candidates(int p_max_binding_candidates) {
	_max_binding_candidates = p_max_binding_candidates;
	emit_changed();
}

int NNHTNSearchSettings::get_max_binding_candidates() const {
	return _max_binding_candidates;
}

void NNHTNSearchSettings::set_max_history_attempts(int p_max_history_attempts) {
	_max_history_attempts = p_max_history_attempts;
	emit_changed();
}

int NNHTNSearchSettings::get_max_history_attempts() const {
	return _max_history_attempts;
}

void NNHTNSearchSettings::set_max_history_bytes(int p_max_history_bytes) {
	_max_history_bytes = p_max_history_bytes;
	emit_changed();
}

int NNHTNSearchSettings::get_max_history_bytes() const {
	return _max_history_bytes;
}

void NNHTNSearchSettings::set_max_trace_events(int p_max_trace_events) {
	_max_trace_events = p_max_trace_events;
	emit_changed();
}

int NNHTNSearchSettings::get_max_trace_events() const {
	return _max_trace_events;
}

PackedStringArray NNHTNSearchSettings::get_validation_errors() const {
	PackedStringArray errors;
	if (_policy != ORDERED && _policy != RANKED && _policy != LOWEST_COST) {
		errors.push_back(vformat("Search policy %d is invalid.", (int)_policy));
	}
	if (_max_expansions < 1) {
		errors.push_back(vformat("max_expansions must be at least 1; got %d.", _max_expansions));
	}
	if (_max_time_ms < 0) {
		errors.push_back(vformat("max_time_ms must be 0 (no limit) or positive; got %d.", _max_time_ms));
	}
	if (_max_binding_candidates < 1) {
		errors.push_back(vformat("max_binding_candidates must be at least 1; got %d.", _max_binding_candidates));
	}
	if (_max_history_attempts < 1) {
		errors.push_back(vformat("max_history_attempts must be at least 1; got %d.", _max_history_attempts));
	}
	if (_max_history_bytes < 1024) {
		errors.push_back(vformat("max_history_bytes must be at least 1024; got %d.", _max_history_bytes));
	}
	if (_max_trace_events < 1) {
		errors.push_back(vformat("max_trace_events must be at least 1; got %d.", _max_trace_events));
	}
	return errors;
}

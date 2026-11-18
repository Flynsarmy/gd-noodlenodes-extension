#include "search_trace.h"

#include "../blackboard.h"
#include "search_settings.h"
#include "task.h"

#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

void NNHTNSearchTrace::begin(const NNHTNSearchSettings &p_settings, const Dictionary &p_state) {
	_max_events = p_settings.get_max_trace_events();
	_max_history_attempts = p_settings.get_max_history_attempts();
	_max_history_bytes = p_settings.get_max_history_bytes();
	_events.clear();
	_occurrence_events.clear();
	_event_bytes = 0;
	_events_closed = false;
	_truncated = false;
	_initial_state = NNBlackboard::sanitize_debug_value(p_state);
	_initial_state_bytes = _size_of(_initial_state);
	if (_initial_state_bytes > _max_history_bytes / 4) {
		_initial_state = Dictionary();
		_initial_state_bytes = _size_of(_initial_state);
		_truncated = true;
	}
	_started_usec = Time::get_singleton()->get_ticks_usec();
}

int NNHTNSearchTrace::record(int p_parent_id, const char *p_kind, const String &p_path, const char *p_outcome, const char *p_reason, const String &p_detail, const Dictionary &p_args, const Dictionary &p_state, const Dictionary &p_failure, int64_t p_occurrence_id) {
	if (_events_closed) {
		return NO_EVENT;
	}
	if ((int)_events.size() >= _max_events) {
		_close_events();
		return NO_EVENT;
	}

	const int id = (int)_events.size() + 1;
	const String outcome = p_outcome;
	Dictionary event;
	event["id"] = id;
	event["parent_id"] = p_parent_id;
	event["kind"] = p_kind;
	event["path"] = p_path;
	event["outcome"] = outcome;
	event["reason"] = p_reason;
	event["final"] = false;
	if (!p_detail.is_empty()) {
		event["detail"] = p_detail;
	}
	if (!p_args.is_empty()) {
		event["args"] = NNBlackboard::sanitize_debug_value(p_args);
	}
	if (!p_failure.is_empty()) {
		event["condition"] = p_failure.get("condition", String());
		event["condition_index"] = p_failure.get("condition_index", -1);
	}
	if (outcome == "rejected" || outcome == "pruned" || outcome == "cutoff") {
		event["state"] = NNBlackboard::sanitize_debug_value(p_state);
	}
	if (p_occurrence_id != 0) {
		event["occurrence_id"] = p_occurrence_id;
	}

	const int64_t bytes = _size_of(event);
	if (_initial_state_bytes + _event_bytes + bytes > _max_history_bytes / 2) {
		_close_events();
		return NO_EVENT;
	}
	_events.push_back(event);
	_event_bytes += bytes;
	if (p_occurrence_id != 0) {
		_occurrence_events[p_occurrence_id] = id;
	}
	return id;
}

const Dictionary &NNHTNSearchTrace::finish(const Dictionary &p_summary, const std::vector<Ref<NNHTNPlanStep>> &p_plan, bool p_installed) {
	const Array plan = _plan_entries(p_plan);
	_mark_final(plan);
	Array events;
	for (const Dictionary &event : _events) {
		events.push_back(event);
	}

	Dictionary attempt = p_summary.duplicate(true);
	attempt["id"] = _next_attempt_id++;
	attempt["timestamp"] = Time::get_singleton()->get_datetime_string_from_system(true);
	attempt["elapsed_usec"] = (int64_t)(Time::get_singleton()->get_ticks_usec() - _started_usec);
	attempt["installed"] = p_installed;
	attempt["initial_state"] = _initial_state;
	attempt["plan"] = plan;
	attempt["events"] = events;
	attempt["truncated"] = _truncated;
	_events.clear();
	_occurrence_events.clear();
	_initial_state = Dictionary();

	Attempt entry;
	entry.data = attempt;
	entry.bytes = _size_of(attempt);
	_history_bytes += entry.bytes;
	_history.push_back(std::move(entry));
	// The newest attempt is always kept; begin() and record() keep it within the byte limit.
	while (_history.size() > 1 && ((int)_history.size() > _max_history_attempts || _history_bytes > _max_history_bytes)) {
		_history_bytes -= _history.front().bytes;
		_history.pop_front();
	}
	return _history.back().data;
}

void NNHTNSearchTrace::clear() {
	_history.clear();
	_history_bytes = 0;
	_events.clear();
	_occurrence_events.clear();
	_initial_state = Dictionary();
}

TypedArray<Dictionary> NNHTNSearchTrace::get_history() const {
	TypedArray<Dictionary> history;
	for (const Attempt &attempt : _history) {
		history.push_back(attempt.data.duplicate(true));
	}
	return history;
}

Dictionary NNHTNSearchTrace::get_last_attempt() const {
	return _history.empty() ? Dictionary() : _history.back().data.duplicate(true);
}

void NNHTNSearchTrace::_close_events() {
	_events_closed = true;
	_truncated = true;
}

Array NNHTNSearchTrace::_plan_entries(const std::vector<Ref<NNHTNPlanStep>> &p_plan) {
	Array entries;
	int64_t bytes = 0;
	for (size_t i = 0; i < p_plan.size(); i++) {
		const Ref<NNHTNPlanStep> &step = p_plan[i];
		const NNHTNTask *task = step->get_task();
		const auto event = _occurrence_events.find(step->get_occurrence_id());
		Dictionary entry;
		entry["index"] = (int64_t)i;
		entry["task"] = task != nullptr ? String(task->get_name()) : String();
		entry["call_path"] = step->get_call_path();
		entry["args"] = NNBlackboard::sanitize_debug_value(step->get_args());
		entry["cost"] = step->get_cost();
		entry["occurrence_id"] = step->get_occurrence_id();
		entry["event_id"] = event != _occurrence_events.end() ? event->second : NO_EVENT;
		bytes += _size_of(entry);
		if (bytes > _max_history_bytes / 4) {
			_truncated = true;
			break;
		}
		entries.push_back(entry);
	}
	return entries;
}

void NNHTNSearchTrace::_mark_final(const Array &p_plan_entries) {
	for (int i = 0; i < p_plan_entries.size(); i++) {
		int id = Dictionary(p_plan_entries[i])["event_id"];
		while (id > 0 && id <= (int)_events.size()) {
			Dictionary event = _events[id - 1];
			if (event["final"]) {
				break;
			}
			event["final"] = true;
			id = event["parent_id"];
		}
	}
}

int64_t NNHTNSearchTrace::_size_of(const Variant &p_value) {
	return UtilityFunctions::var_to_bytes(p_value).size();
}

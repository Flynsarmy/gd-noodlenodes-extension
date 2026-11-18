#pragma once

#include "plan_step.h"

#include <deque>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <unordered_map>
#include <vector>

namespace godot {

class NNHTNSearchSettings;

// Bounded decision records for search attempts and a bounded history of attempts.
// Every recorded value is sanitised, so attempts never hold raw Objects.
class NNHTNSearchTrace {
public:
	static constexpr int NO_EVENT = -1;

	void begin(const NNHTNSearchSettings &p_settings, const Dictionary &p_state);
	// Returns the event's id, or NO_EVENT once a limit has dropped it. Rejected, pruned and cutoff
	// events also capture p_state. p_failure holds the failing condition, when known.
	int record(int p_parent_id, const char *p_kind, const String &p_path, const char *p_outcome, const char *p_reason, const String &p_detail, const Dictionary &p_args, const Dictionary &p_state, const Dictionary &p_failure = Dictionary(), int64_t p_occurrence_id = 0);
	// Closes the attempt begun last with the search metadata in p_summary and adds it to the history.
	const Dictionary &finish(const Dictionary &p_summary, const std::vector<Ref<NNHTNPlanStep>> &p_plan, bool p_installed);
	void clear();

	TypedArray<Dictionary> get_history() const;
	Dictionary get_last_attempt() const;

private:
	int _max_events = 0;
	int _max_history_attempts = 0;
	int64_t _max_history_bytes = 0;

	std::vector<Dictionary> _events;
	std::unordered_map<int64_t, int> _occurrence_events;
	int64_t _event_bytes = 0;
	// Once one event is dropped every later one is too, so an attempt's events are a prefix.
	bool _events_closed = false;
	Dictionary _initial_state;
	int64_t _initial_state_bytes = 0;
	bool _truncated = false;
	uint64_t _started_usec = 0;

	struct Attempt {
		Dictionary data;
		int64_t bytes = 0;
	};
	std::deque<Attempt> _history;
	int64_t _history_bytes = 0;
	int64_t _next_attempt_id = 1;

	void _close_events();
	Array _plan_entries(const std::vector<Ref<NNHTNPlanStep>> &p_plan);
	void _mark_final(const Array &p_plan_entries);
	static int64_t _size_of(const Variant &p_value);
};

} //namespace godot

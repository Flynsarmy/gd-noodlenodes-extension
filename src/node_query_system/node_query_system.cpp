#include "node_query_system.h"
#include <godot_cpp/classes/performance.hpp>
#include <godot_cpp/classes/time.hpp>
#include <vector>

using namespace godot;

NNNodeQuerySystem::NNNodeQuerySystem() {
	_current_high_priority_query_index = 0;
	_current_regular_query_index = 0;

	_time_allocation_pct_to_high_priority_queries = 0.8f;

	_run_queries_time_budget_per_frame = 1000;
	_run_queries_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * ((float)_run_queries_time_budget_per_frame));
	_run_queries_time_budget_per_frame_regular_queries = _run_queries_time_budget_per_frame - _run_queries_time_budget_per_frame_high_priority_queries;

	_post_query_time_budget_per_frame = 500;
	_post_query_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * (double)_post_query_time_budget_per_frame);
	_post_query_time_budget_per_frame_regular_queries = _post_query_time_budget_per_frame - _post_query_time_budget_per_frame_high_priority_queries;

	_post_high_priority_queries_time_elapsed_usec = 0;
	_post_regular_queries_time_elapsed_usec = 0;
	_run_queries_time_elapsed_usec = 0;
	_current_post_high_priority_queries_time_elapsed_usec = 0;
	_current_post_regular_queries_time_elapsed_usec = 0;

	_is_performance_counter_initialized = false;

	_num_active_high_priority_queries = 0;
	_num_active_regular_priority_queries = 0;

	_high_priority_query_per_frame_execute_query_time_budget_usec = 20;
	_regular_query_per_frame_execute_query_time_budget_usec = 10;
}

NNNodeQuerySystem::~NNNodeQuerySystem() {
}

void NNNodeQuerySystem::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_run_queries_time_budget_per_frame", "run_queries_time_budget_per_frame_usec"), &NNNodeQuerySystem::set_run_queries_time_budget_per_frame);
	ClassDB::bind_method(D_METHOD("get_run_queries_time_budget_per_frame"), &NNNodeQuerySystem::get_run_queries_time_budget_per_frame);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "run_queries_time_budget_per_frame_usec", PROPERTY_HINT_RANGE, "1,10000,or_greater"), "set_run_queries_time_budget_per_frame", "get_run_queries_time_budget_per_frame");

	ClassDB::bind_method(D_METHOD("set_high_priority_query_per_frame_execute_query_time_budget_usec", "high_priority_query_per_frame_execute_query_time_budget_usec"), &NNNodeQuerySystem::set_high_priority_query_per_frame_execute_query_time_budget_usec);
	ClassDB::bind_method(D_METHOD("get_high_priority_query_per_frame_execute_query_time_budget_usec"), &NNNodeQuerySystem::get_high_priority_query_per_frame_execute_query_time_budget_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "high_priority_query_per_frame_execute_query_time_budget_usec", PROPERTY_HINT_RANGE, "1,100,or_greater"), "set_high_priority_query_per_frame_execute_query_time_budget_usec", "get_high_priority_query_per_frame_execute_query_time_budget_usec");

	ClassDB::bind_method(D_METHOD("set_regular_query_per_frame_execute_query_time_budget_usec", "regular_query_per_frame_execute_query_time_budget_usec"), &NNNodeQuerySystem::set_regular_query_per_frame_execute_query_time_budget_usec);
	ClassDB::bind_method(D_METHOD("get_regular_query_per_frame_execute_query_time_budget_usec"), &NNNodeQuerySystem::get_regular_query_per_frame_execute_query_time_budget_usec);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "regular_query_per_frame_execute_query_time_budget_usec", PROPERTY_HINT_RANGE, "1,100,or_greater"), "set_regular_query_per_frame_execute_query_time_budget_usec", "get_regular_query_per_frame_execute_query_time_budget_usec");

	ClassDB::bind_method(D_METHOD("set_time_allocation_pct_to_high_priority_queries", "time_allocation_pct_to_high_priority_queries"), &NNNodeQuerySystem::set_time_allocation_pct_to_high_priority_queries);
	ClassDB::bind_method(D_METHOD("get_time_allocation_pct_to_high_priority_queries"), &NNNodeQuerySystem::get_time_allocation_pct_to_high_priority_queries);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "time_allocation_pct_to_high_priority_queries", PROPERTY_HINT_RANGE, "0.0,1.0"), "set_time_allocation_pct_to_high_priority_queries", "get_time_allocation_pct_to_high_priority_queries");

	ClassDB::bind_method(D_METHOD("post_query", "search_space", "is_high_priority"), &NNNodeQuerySystem::post_query);
	ClassDB::bind_method(D_METHOD("stop_query", "search_space"), &NNNodeQuerySystem::stop_query);
	ClassDB::bind_method(D_METHOD("run_queries"), &NNNodeQuerySystem::run_queries);
	ClassDB::bind_method(D_METHOD("clear_queries"), &NNNodeQuerySystem::clear_queries);
	ClassDB::bind_method(D_METHOD("initialize_performance_counters"), &NNNodeQuerySystem::initialize_performance_counters);
	ClassDB::bind_method(D_METHOD("get_run_queries_time_elapsed_usec"), &NNNodeQuerySystem::get_run_queries_time_elapsed_usec);
	ClassDB::bind_method(D_METHOD("get_post_queries_time_elapsed_usec"), &NNNodeQuerySystem::get_post_queries_time_elapsed_usec);
	ClassDB::bind_method(D_METHOD("get_num_active_high_priority_queries"), &NNNodeQuerySystem::get_num_active_high_priority_queries);
	ClassDB::bind_method(D_METHOD("get_num_active_regular_priority_queries"), &NNNodeQuerySystem::get_num_active_regular_priority_queries);
}

// Getters and setters.

void NNNodeQuerySystem::set_run_queries_time_budget_per_frame(uint64_t run_queries_time_budget_per_frame) {
	_run_queries_time_budget_per_frame = run_queries_time_budget_per_frame;
	_run_queries_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * (double)_run_queries_time_budget_per_frame);
}

uint64_t NNNodeQuerySystem::get_run_queries_time_budget_per_frame() const {
	return _run_queries_time_budget_per_frame;
}

void NNNodeQuerySystem::set_post_query_time_budget_per_frame(uint64_t post_query_time_budget_per_frame) {
	_post_query_time_budget_per_frame = post_query_time_budget_per_frame;
	_post_query_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * (double)_post_query_time_budget_per_frame);
	_post_query_time_budget_per_frame_regular_queries = _post_query_time_budget_per_frame - _post_query_time_budget_per_frame_high_priority_queries;
}

uint64_t NNNodeQuerySystem::get_post_query_time_budget_per_frame() const {
	return _post_query_time_budget_per_frame;
}

void NNNodeQuerySystem::set_time_allocation_pct_to_high_priority_queries(float time_allocation_pct_to_high_priority_queries) {
	_time_allocation_pct_to_high_priority_queries = time_allocation_pct_to_high_priority_queries;

	_run_queries_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * (double)_run_queries_time_budget_per_frame);
	_run_queries_time_budget_per_frame_regular_queries = _run_queries_time_budget_per_frame - _run_queries_time_budget_per_frame_high_priority_queries;

	_post_query_time_budget_per_frame_high_priority_queries = (uint64_t)(_time_allocation_pct_to_high_priority_queries * (double)_post_query_time_budget_per_frame);
	_post_query_time_budget_per_frame_regular_queries = _post_query_time_budget_per_frame - _post_query_time_budget_per_frame_high_priority_queries;
}

float NNNodeQuerySystem::get_time_allocation_pct_to_high_priority_queries() const {
	return _time_allocation_pct_to_high_priority_queries;
}

void NNNodeQuerySystem::set_high_priority_query_per_frame_execute_query_time_budget_usec(int high_priority_query_per_frame_execute_query_time_budget_usec) {
	_high_priority_query_per_frame_execute_query_time_budget_usec = high_priority_query_per_frame_execute_query_time_budget_usec;
}

int NNNodeQuerySystem::get_high_priority_query_per_frame_execute_query_time_budget_usec() const {
	return _high_priority_query_per_frame_execute_query_time_budget_usec;
}

void NNNodeQuerySystem::set_regular_query_per_frame_execute_query_time_budget_usec(int regular_query_per_frame_execute_query_time_budget_usec) {
	_regular_query_per_frame_execute_query_time_budget_usec = regular_query_per_frame_execute_query_time_budget_usec;
}

int NNNodeQuerySystem::get_regular_query_per_frame_execute_query_time_budget_usec() const {
	return _regular_query_per_frame_execute_query_time_budget_usec;
}

int NNNodeQuerySystem::get_run_queries_time_elapsed_usec() const {
	return _run_queries_time_elapsed_usec;
}

int NNNodeQuerySystem::get_post_queries_time_elapsed_usec() const {
	return (_post_high_priority_queries_time_elapsed_usec + _post_regular_queries_time_elapsed_usec);
}

int NNNodeQuerySystem::get_num_active_high_priority_queries() const {
	return (int)_num_active_high_priority_queries;
}

int NNNodeQuerySystem::get_num_active_regular_priority_queries() const {
	return (int)_num_active_regular_priority_queries;
}

// Handling methods.

void NNNodeQuerySystem::initialize_performance_counters() {
	if (_is_performance_counter_initialized)
		return;
	Performance *perf = godot::Performance::get_singleton();
	if (perf == nullptr)
		return;
	perf->add_custom_monitor("NodeQuerySystem/Run queries time usec", Callable(this, "get_run_queries_time_elapsed_usec"));
	perf->add_custom_monitor("NodeQuerySystem/Post queries time usec", Callable(this, "get_post_queries_time_elapsed_usec"));
	_is_performance_counter_initialized = true;
}

void NNNodeQuerySystem::run_queries() {
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();

	// Clear the post queries time measurement.
	_post_high_priority_queries_time_elapsed_usec = _current_post_high_priority_queries_time_elapsed_usec;
	_current_post_high_priority_queries_time_elapsed_usec = 0;

	_post_regular_queries_time_elapsed_usec = _current_post_regular_queries_time_elapsed_usec;
	_current_post_regular_queries_time_elapsed_usec = 0;

	// Then continue with the update.
	uint64_t frame_time_left = _run_queries_time_budget_per_frame;
	if (_high_priority_queries.size() == 0 && _regular_queries.size() == 0 ||
			_num_active_high_priority_queries == 0 && _num_active_regular_priority_queries == 0) {
		_run_queries_time_elapsed_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
		return;
	}

	if (_num_active_high_priority_queries > 0 && _high_priority_queries.size() > 0) {
		while (true) {
			if (_current_high_priority_query_index >= _high_priority_queries.size()) {
				_current_high_priority_query_index = 0;
			}
			// Remember which registration this execution call owns. A
			// "query_completed" callback may stop and/or re-post the query, so
			// the completion must not release whatever is registered later.
			const int high_priority_query_index = _current_high_priority_query_index;
			NNNQSSearchSpaces *current_query = godot::Object::cast_to<NNNQSSearchSpaces>(_high_priority_queries[_current_high_priority_query_index]);
			if (current_query != nullptr) {
				const uint64_t query_registration = current_query->get_nqs_query_registration();
				bool is_completed = current_query->execute_query(_high_priority_query_per_frame_execute_query_time_budget_usec);
				if (is_completed) {
					// Only release the exact registration that executed. The
					// registration token is the source of truth; a callback may
					// have changed the index without changing the running flag.
					_release_query_slot(current_query, true, high_priority_query_index, query_registration);
				}
			}

			++_current_high_priority_query_index;
			uint64_t time_used = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			if (time_used >= _run_queries_time_budget_per_frame_high_priority_queries || _num_active_high_priority_queries == 0) {
				break;
			}
		} //endwhile run queries
	} //endif high priority queries are running
	uint64_t regular_query_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();

	if (_num_active_regular_priority_queries > 0 && _regular_queries.size() > 0) {
		// Compare before subtracting to avoid unsigned wraparound after an overrun.
		uint64_t elapsed_before_regular_queries_usec = regular_query_start_time_usec - method_start_time_usec;
		if (elapsed_before_regular_queries_usec >= frame_time_left) {
			_run_queries_time_elapsed_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
			return; // Too bad, no time left for regular priority queries :(
		}
		frame_time_left -= elapsed_before_regular_queries_usec;

		while (true) {
			if (_current_regular_query_index >= _regular_queries.size()) {
				_current_regular_query_index = 0;
			}

			// See the high priority loop above: capture the registration before
			// executing so a callback cannot make this completion release a
			// newer registration.
			const int regular_query_index = _current_regular_query_index;
			NNNQSSearchSpaces *current_query = godot::Object::cast_to<NNNQSSearchSpaces>(_regular_queries[_current_regular_query_index]);
			if (current_query != nullptr) {
				const uint64_t query_registration = current_query->get_nqs_query_registration();
				bool is_completed = current_query->execute_query(_regular_query_per_frame_execute_query_time_budget_usec);
				if (is_completed) {
					_release_query_slot(current_query, false, regular_query_index, query_registration);
				}
			}

			++_current_regular_query_index;
			uint64_t time_used = godot::Time::get_singleton()->get_ticks_usec() - regular_query_start_time_usec;
			if (time_used >= frame_time_left || _num_active_regular_priority_queries == 0) {
				break;
			}
		} //endwhile run queries
	} //endif regular queries exist

	_run_queries_time_elapsed_usec = godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec;
}

int NNNodeQuerySystem::post_query(NNNQSSearchSpaces *search_space, bool is_high_priority) {
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();

	if (is_high_priority) {
		if (search_space == nullptr) { //|| _post_high_priority_queries_time_elapsed_usec >= _post_query_time_budget_per_frame_high_priority_queries ) {
			_current_post_high_priority_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
			return -1;
		}
		// Bail out if the search space is already being queried.
		if (search_space->get_nqs_query_index() > -1) { //_high_priority_queries.has( search_space ) ){
			_current_post_high_priority_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
			return -1;
		}
		search_space->start_query();
		search_space->set_nqs_query_is_high_priority(true);
		if (_available_high_priority_query_indexes.size() == 0) {
			search_space->set_nqs_query_index(_high_priority_queries.size());
			_high_priority_queries.push_back(search_space);
		} else {
			int free_index = _available_high_priority_query_indexes.back();
			_available_high_priority_query_indexes.pop_back();
			search_space->set_nqs_query_index(free_index);
			_high_priority_queries[free_index] = search_space;
		}
		++_num_active_high_priority_queries;
		// A registration token is bumped even when start_query() declined a
		// disabled query: the query is scheduled regardless, and its later
		// completion must be distinguishable from this registration.
		search_space->bump_nqs_query_registration();
		_current_post_high_priority_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
		return 1;
	}

	if (search_space == nullptr) { //} || _post_regular_queries_time_elapsed_usec >= _post_query_time_budget_per_frame_regular_queries ) {
		_current_post_regular_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
		return -1;
	}

	// Regular priority.

	// Bail out if the search space is already being queried.
	if (search_space->get_nqs_query_index() > -1) { ////_regular_queries.has( search_space ) ){
		_current_post_regular_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
		return -1;
	}
	search_space->start_query();
	search_space->set_nqs_query_is_high_priority(false);
	if (_available_regular_query_indexes.size() == 0) {
		search_space->set_nqs_query_index(_regular_queries.size());
		_regular_queries.push_back(search_space);
	} else {
		int free_index = _available_regular_query_indexes.back();
		_available_regular_query_indexes.pop_back();
		search_space->set_nqs_query_index(free_index);
		_regular_queries[free_index] = search_space;
	}
	++_num_active_regular_priority_queries;
	search_space->bump_nqs_query_registration();
	_current_post_regular_queries_time_elapsed_usec += (godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
	return 1;
}

bool NNNodeQuerySystem::_release_query_slot(NNNQSSearchSpaces *search_space,
		bool is_high_priority,
		int expected_query_index,
		uint64_t expected_registration) {
	if (search_space == nullptr) {
		return false;
	}

	const int query_index = search_space->get_nqs_query_index();
	if (query_index < 0) {
		return false; // Not in the scheduler.
	}

	// A completion owns only the registration it started with. A completion
	// callback may have stopped the query and re-posted it, possibly into the
	// same index at either priority. In that case this release is stale and
	// must leave the newer registration untouched.
	if (expected_query_index >= 0) {
		if (query_index != expected_query_index ||
				search_space->get_nqs_query_registration() != expected_registration) {
			return false;
		}
	}

	godot::TypedArray<NNNQSSearchSpaces> &queries = is_high_priority ? _high_priority_queries : _regular_queries;
	std::vector<int> &available_query_indexes = is_high_priority ? _available_high_priority_query_indexes : _available_regular_query_indexes;
	unsigned int &num_active_queries = is_high_priority ? _num_active_high_priority_queries : _num_active_regular_priority_queries;

	// The index can be stale if the query list was cleared while the query was
	// posted, or if the slot has already been reused by another query. Leave
	// the search space's index alone: it may belong to a live registration.
	if (query_index >= (int)queries.size() ||
			godot::Object::cast_to<NNNQSSearchSpaces>(queries[query_index]) != search_space) {
		return false;
	}

	ERR_FAIL_COND_V_MSG(num_active_queries == 0, false, "Cannot release an occupied query slot with no active queries.");
	queries[query_index] = nullptr;
	available_query_indexes.push_back(query_index);
	--num_active_queries;
	search_space->set_nqs_query_index(-1);
	search_space->set_is_query_still_running(false);
	// Invalidate any completion that captured the released registration.
	search_space->bump_nqs_query_registration();
	return true;
}

bool NNNodeQuerySystem::stop_query(NNNQSSearchSpaces *search_space) {
	if (search_space == nullptr) {
		return false; // Not stopped, nullptr.
	}
	if (search_space->get_nqs_query_index() < 0) {
		return false; // Not stopped, invalid index.
	}
	return _release_query_slot(search_space, search_space->get_nqs_query_is_high_priority());
}

void NNNodeQuerySystem::clear_queries() {
	// Unregister every posted search space before dropping the lists. The
	// search space stores its own query index, so leaving it behind would make
	// stop_query() (also called from _exit_tree()) index an empty list.
	for (int i = 0; i < _high_priority_queries.size(); ++i) {
		NNNQSSearchSpaces *search_space = godot::Object::cast_to<NNNQSSearchSpaces>(_high_priority_queries[i]);
		if (search_space == nullptr) {
			continue;
		}
		search_space->set_nqs_query_index(-1);
		search_space->set_is_query_still_running(false);
		// Invalidate any in-flight completion for this registration.
		search_space->bump_nqs_query_registration();
	}
	for (int i = 0; i < _regular_queries.size(); ++i) {
		NNNQSSearchSpaces *search_space = godot::Object::cast_to<NNNQSSearchSpaces>(_regular_queries[i]);
		if (search_space == nullptr) {
			continue;
		}
		search_space->set_nqs_query_index(-1);
		search_space->set_is_query_still_running(false);
		search_space->bump_nqs_query_registration();
	}

	_high_priority_queries.clear();
	_regular_queries.clear();
	_available_high_priority_query_indexes.clear();
	_available_regular_query_indexes.clear();
	_num_active_high_priority_queries = 0;
	_num_active_regular_priority_queries = 0;
	_current_high_priority_query_index = 0;
	_current_regular_query_index = 0;
}

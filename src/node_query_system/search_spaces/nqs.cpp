#include "nqs.h"
#include "../node_query_system.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node2d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/object.hpp>

#include <cstdint>
#include <utility>

using namespace godot;

NNNQSSearchSpaces::NNNQSSearchSpaces() {
	_top_n_to_find = 1;
	_nqs_query_index = -1;
	_nqs_query_is_high_priority = true;
	_nqs_query_registration = 0;
	_is_query_still_running = false;
	_is_search_space_fetched = false;
	_is_criteria_handled = false;
	_is_results_copied = false;
	_current_criterion_index = 0;
	_total_query_runtime_usec = 0;
	_work_in_progress_num_added_nodes = 0;
	_total_query_call_count = 0;
	_total_query_node_visits = 0;
	_current_query_call_count = 0;
	_current_query_node_visits = 0;
	_current_query_runtime_usec = 0;
	_average_call_runtime_usec = 0;
	_current_call_runtime_usec = 0;
	_search_space_fetch_time_usec = 0;
	_preprocessing_time_usec = 0;
	_completed_signal_time_usec = 0;
	_is_run_in_debug_mode = false;
	_threading_mode = THREADING_AUTO;
	_is_last_query_threaded = false;
	_is_waiting_for_worker = false;
	_is_threading_decision_made = false;
	_is_criteria_threaded = false;
	_threaded_snapshot_index = 0;
	_threaded_snapshot_completed = false;
	_threaded_job_started = false;
	_threaded_keep_all_candidates = false;
	_threaded_top_n = 1;
#ifdef DEBUG_ENABLED
	_debug_score_watch_count = 0;
#endif
	_is_filtered_property = StringName("is_filtered");
	_score_property = StringName("score");
}

NNNQSSearchSpaces::~NNNQSSearchSpaces() {
}

// Batching the clock read bounds a budget overrun to at most N - 1 node visits.
constexpr unsigned int TIME_CHECK_INTERVAL_NODES = 16;
// One worker chunk is also one top-N list during the criteria phase.
constexpr uint32_t CRITERIA_THREADING_CHUNK_SIZE = 256;
// Below this many candidates the snapshot and dispatch cost more than the scoring they replace.
constexpr unsigned int CRITERIA_THREADING_AUTO_MIN_NODES = 700;

static PropertyInfo _runtime_stat(PropertyInfo p_info) {
	p_info.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY;
	return p_info;
}

void NNNQSSearchSpaces::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_top_n_to_find", "top_n_to_find"), &NNNQSSearchSpaces::set_top_n_to_find);
	ClassDB::bind_method(D_METHOD("get_top_n_to_find"), &NNNQSSearchSpaces::get_top_n_to_find);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "top_n_to_find", PROPERTY_HINT_RANGE, "1,32,or_greater"), "set_top_n_to_find", "get_top_n_to_find");

	ClassDB::bind_method(D_METHOD("get_query_results"), &NNNQSSearchSpaces::get_query_results);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::ARRAY, "query_results", PROPERTY_HINT_ARRAY_TYPE, vformat("%s/%s:%s", Variant::OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Node"))), "", "get_query_results");

	ClassDB::bind_method(D_METHOD("get_query_result_scores"), &NNNQSSearchSpaces::get_query_result_scores);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::ARRAY, "query_result_scores", PROPERTY_HINT_NONE)), "", "get_query_result_scores");

	ADD_SUBGROUP("Debugging", "");

#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("watch_debug_scores"), &NNNQSSearchSpaces::watch_debug_scores);
	ClassDB::bind_method(D_METHOD("unwatch_debug_scores"), &NNNQSSearchSpaces::unwatch_debug_scores);
	ClassDB::bind_method(D_METHOD("get_debug_scored_nodes"), &NNNQSSearchSpaces::get_debug_scored_nodes);
	ClassDB::bind_method(D_METHOD("get_debug_scored_scores"), &NNNQSSearchSpaces::get_debug_scored_scores);
#endif

	ClassDB::bind_method(D_METHOD("set_is_run_in_debug_mode", "is_run_in_debug_mode"), &NNNQSSearchSpaces::set_is_run_in_debug_mode);
	ClassDB::bind_method(D_METHOD("get_is_run_in_debug_mode"), &NNNQSSearchSpaces::get_is_run_in_debug_mode);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_run_in_debug_mode", PROPERTY_HINT_NONE), "set_is_run_in_debug_mode", "get_is_run_in_debug_mode");

	ClassDB::bind_method(D_METHOD("set_threading_mode", "threading_mode"), &NNNQSSearchSpaces::set_threading_mode);
	ClassDB::bind_method(D_METHOD("get_threading_mode"), &NNNQSSearchSpaces::get_threading_mode);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "threading_mode", PROPERTY_HINT_ENUM, "Off,Auto,Always"), "set_threading_mode", "get_threading_mode");

	ClassDB::bind_method(D_METHOD("get_is_last_query_threaded"), &NNNQSSearchSpaces::get_is_last_query_threaded);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::BOOL, "is_last_query_threaded", PROPERTY_HINT_NONE)), "", "get_is_last_query_threaded");

	ClassDB::bind_method(D_METHOD("get_is_query_still_running"), &NNNQSSearchSpaces::get_is_query_still_running);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::BOOL, "is_query_still_running", PROPERTY_HINT_NONE)), "", "get_is_query_still_running");

	ClassDB::bind_method(D_METHOD("get_current_call_runtime_usec"), &NNNQSSearchSpaces::get_current_call_runtime_usec);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "current_call_runtime_usec", PROPERTY_HINT_NONE)), "", "get_current_call_runtime_usec");

	ClassDB::bind_method(D_METHOD("get_average_call_runtime_usec"), &NNNQSSearchSpaces::get_average_call_runtime_usec);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "average_call_runtime_usec", PROPERTY_HINT_NONE)), "", "get_average_call_runtime_usec");

	ClassDB::bind_method(D_METHOD("get_search_space_fetch_time_usec"), &NNNQSSearchSpaces::get_search_space_fetch_time_usec);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "search_space_fetch_time_usec", PROPERTY_HINT_NONE)), "", "get_search_space_fetch_time_usec");

	ClassDB::bind_method(D_METHOD("get_total_query_runtime_usec"), &NNNQSSearchSpaces::get_total_query_runtime_usec);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "total_query_runtime_usec", PROPERTY_HINT_NONE)), "", "get_total_query_runtime_usec");

	ClassDB::bind_method(D_METHOD("get_completed_signal_time_usec"), &NNNQSSearchSpaces::get_completed_signal_time_usec);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "completed_signal_time_usec", PROPERTY_HINT_NONE)), "", "get_completed_signal_time_usec");

	ClassDB::bind_method(D_METHOD("get_total_query_node_visits"), &NNNQSSearchSpaces::get_total_query_node_visits);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "total_query_node_visits", PROPERTY_HINT_NONE)), "", "get_total_query_node_visits");

	ClassDB::bind_method(D_METHOD("get_total_query_call_count"), &NNNQSSearchSpaces::get_total_query_call_count);
	ADD_PROPERTY(_runtime_stat(PropertyInfo(Variant::INT, "total_query_call_count", PROPERTY_HINT_NONE)), "", "get_total_query_call_count");

	ClassDB::bind_method(D_METHOD("initialize_search_space"), &NNNQSSearchSpaces::initialize_search_space);
	ClassDB::bind_method(D_METHOD("execute_query", "time_budget_usec"), &NNNQSSearchSpaces::execute_query);

	BIND_ENUM_CONSTANT(THREADING_OFF);
	BIND_ENUM_CONSTANT(THREADING_AUTO);
	BIND_ENUM_CONSTANT(THREADING_ALWAYS);

	ADD_SIGNAL(MethodInfo("query_completed", PropertyInfo(Variant::OBJECT, "search_space")));
}

void NNNQSSearchSpaces::_ready() {
	if (Engine::get_singleton()->is_editor_hint())
		return;
	initialize_search_space(); // Maybe not really needed? We'll see.

	// Get all the criterias to a vector to avoid slow type casting
	// during runtime.
	_filtering_criteria.clear();
	for (int i = 0; i < get_child_count(); i++) {
		if (NNNQSSearchCriteria *criterion = godot::Object::cast_to<NNNQSSearchCriteria>(get_child(i))) {
			_filtering_criteria.push_back(criterion);
		}
	}
	_num_filtering_criteria = (unsigned int)_filtering_criteria.size();
}

void NNNQSSearchSpaces::_exit_tree() {
	if (Engine::get_singleton()->is_editor_hint())
		return;
	_uninitialize_search_space();
	_leave_scheduler();
}

void NNNQSSearchSpaces::_notification(int p_what) {
	if (p_what == NOTIFICATION_PREDELETE) {
		// A space freed while outside the tree never reaches _exit_tree().
		_leave_scheduler();
	}
}

void NNNQSSearchSpaces::_leave_scheduler() {
	NNNodeQuerySystem *nqs = get_nqs_scheduler();
	if (nqs != nullptr) {
		nqs->stop_query(this);
	}
}

// Getters and setters.

void NNNQSSearchSpaces::set_is_run_in_debug_mode(bool is_run_in_debug_mode) {
	_is_run_in_debug_mode = is_run_in_debug_mode;
}

bool NNNQSSearchSpaces::get_is_run_in_debug_mode() const {
	return _is_run_in_debug_mode;
}

void NNNQSSearchSpaces::set_threading_mode(ThreadingMode threading_mode) {
	_threading_mode = threading_mode;
}

NNNQSSearchSpaces::ThreadingMode NNNQSSearchSpaces::get_threading_mode() const {
	return _threading_mode;
}

bool NNNQSSearchSpaces::get_is_last_query_threaded() const {
	return _is_last_query_threaded;
}

bool NNNQSSearchSpaces::is_waiting_for_worker() const {
	return _is_waiting_for_worker;
}

bool NNNQSSearchSpaces::uses_threads_for(unsigned int p_item_count, unsigned int p_auto_min_items) const {
	switch (_threading_mode) {
		case THREADING_ALWAYS:
			return p_item_count > 0;
		case THREADING_AUTO:
			return p_item_count >= p_auto_min_items;
		default:
			return false;
	}
}

void NNNQSSearchSpaces::set_nqs_query_index(int nqs_query_index) {
	_nqs_query_index = nqs_query_index;
}

int NNNQSSearchSpaces::get_nqs_query_index() const {
	return _nqs_query_index;
}

void NNNQSSearchSpaces::set_nqs_scheduler(NNNodeQuerySystem *nqs_scheduler) {
	_nqs_scheduler_id = nqs_scheduler != nullptr ? nqs_scheduler->get_instance_id() : ObjectID();
}

NNNodeQuerySystem *NNNQSSearchSpaces::get_nqs_scheduler() const {
	return godot::Object::cast_to<NNNodeQuerySystem>(godot::ObjectDB::get_instance(_nqs_scheduler_id));
}

void NNNQSSearchSpaces::set_nqs_query_is_high_priority(bool nqs_query_is_high_priority) {
	_nqs_query_is_high_priority = nqs_query_is_high_priority;
}

bool NNNQSSearchSpaces::get_nqs_query_is_high_priority() const {
	return _nqs_query_is_high_priority;
}

void NNNQSSearchSpaces::set_nqs_query_registration(uint64_t nqs_query_registration) {
	_nqs_query_registration = nqs_query_registration;
}

uint64_t NNNQSSearchSpaces::get_nqs_query_registration() const {
	return _nqs_query_registration;
}

void NNNQSSearchSpaces::bump_nqs_query_registration() {
	++_nqs_query_registration;
}

TypedArray<Node> NNNQSSearchSpaces::get_searchspace_nodes() const {
	TypedArray<Node> emptyarray;
	return emptyarray;
}

TypedArray<Node> NNNQSSearchSpaces::get_query_results() const {
	return _query_results;
}

PackedFloat64Array NNNQSSearchSpaces::get_query_result_scores() const {
	return _query_result_scores;
}

#ifdef DEBUG_ENABLED
void NNNQSSearchSpaces::watch_debug_scores() {
	++_debug_score_watch_count;
}

void NNNQSSearchSpaces::unwatch_debug_scores() {
	if (_debug_score_watch_count == 0) {
		return;
	}
	--_debug_score_watch_count;
	if (_debug_score_watch_count == 0) {
		_debug_scored_nodes.clear();
		_debug_scored_scores.clear();
	}
}

TypedArray<Node> NNNQSSearchSpaces::get_debug_scored_nodes() const {
	return _debug_scored_nodes;
}

PackedFloat64Array NNNQSSearchSpaces::get_debug_scored_scores() const {
	return _debug_scored_scores;
}
#endif

void NNNQSSearchSpaces::set_top_n_to_find(int top_n_to_find) {
	ERR_FAIL_COND_MSG(top_n_to_find < 1, "NNNQSSearchSpaces::set_top_n_to_find(): top_n_to_find must be at least 1.");
	_top_n_to_find = top_n_to_find;
}

int NNNQSSearchSpaces::get_top_n_to_find() const {
	return _top_n_to_find;
}

uint64_t NNNQSSearchSpaces::get_current_call_runtime_usec() const {
	return _current_call_runtime_usec;
}

uint64_t NNNQSSearchSpaces::get_search_space_fetch_time_usec() const {
	return _search_space_fetch_time_usec;
}

uint64_t NNNQSSearchSpaces::get_average_call_runtime_usec() const {
	return _average_call_runtime_usec;
}

uint64_t NNNQSSearchSpaces::get_total_query_runtime_usec() const {
	return _total_query_runtime_usec;
}

uint64_t NNNQSSearchSpaces::get_total_query_node_visits() const {
	return _total_query_node_visits;
}

uint64_t NNNQSSearchSpaces::get_total_query_call_count() const {
	return _total_query_call_count;
}

void NNNQSSearchSpaces::set_is_query_still_running(bool is_query_still_running) {
	_is_query_still_running = is_query_still_running;
}

bool NNNQSSearchSpaces::get_is_query_still_running() const {
	return _is_query_still_running;
}

uint64_t NNNQSSearchSpaces::get_completed_signal_time_usec() const {
	return _completed_signal_time_usec;
}

// Handling methods.

void NNNQSSearchSpaces::initialize_search_space() {
	_initialize_search_space();
}

void NNNQSSearchSpaces::reset_query_variables() {
	clear_threaded_query_data();
	_cancel_preprocessing();

	// Query was not running already, so initialize a new one.
	_current_query_runtime_usec = 0;
	_current_query_node_visits = 0;
	_current_query_call_count = 0;
	_average_call_runtime_usec = 0;
	_current_call_runtime_usec = 0;
	_search_space_fetch_time_usec = 0;
	_current_criterion_index = 0;
	_current_node_index = 0;
	_current_result_index = 0;
	_work_in_progress_num_added_nodes = 0;

	_preprocessing_time_usec = 0;
	_current_preprocessing_node_index = 0;

	_is_search_space_fetched = false;
	_is_preprocessing_completed = false;
	_is_criteria_handled = false;
	_is_results_copied = false;

	_is_query_still_running = true; // Set the query as running.
}

void NNNQSSearchSpaces::start_query() {
	if (!get_is_enabled())
		return;
	if (Engine::get_singleton()->is_editor_hint())
		return;
	if (get_child_count() < 1) {
		WARN_PRINT("NNNodeQuerySystem::start_query() - No search criteria nodes added.");
		return;
	}
	reset_query_variables();
}

bool NNNQSSearchSpaces::execute_query(uint64_t time_budget_usec) {
	uint64_t method_start_time_usec = godot::Time::get_singleton()->get_ticks_usec();
	_is_waiting_for_worker = false;
	const uint64_t deadline_usec = time_budget_usec > 0 ? method_start_time_usec + time_budget_usec : UINT64_MAX;

	if (!get_is_enabled()) {
		_is_query_still_running = false;
		_is_last_query_threaded = false;
		return true;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		_is_query_still_running = false;
		_is_last_query_threaded = false;
		return true;
	}
	if (get_child_count() < 1) {
		WARN_PRINT("NNNodeQuerySystem::execute_query() - No search criteria nodes added.");
		_is_query_still_running = false;
		_is_last_query_threaded = false;
		return true;
	}

	if (!_is_query_still_running) {
		reset_query_variables();
	} //endif query is not running
	++_current_query_call_count;

	if (!_is_search_space_fetched) {
		// Get the search space nodes and set the score to 1.0 for all of them.
		_search_space = get_searchspace_nodes();
		_num_search_space_nodes = _search_space.size();
		_scores.resize(_num_search_space_nodes);
		_scores.fill(1.0);

		// Create the work-in-progress search space we will be swapping with.
		_work_in_progress_search_space = _search_space.duplicate();
		_work_in_progress_scores = _scores.duplicate();
		_work_in_progress_num_added_nodes = 0;

		_ptr_current_search_space = &_search_space;
		_ptr_current_scores = &_scores;

		_ptr_current_work_in_progress_search_space = &_work_in_progress_search_space;
		_ptr_current_work_in_progress_scores = &_work_in_progress_scores;

		_is_search_space_fetched = true;

		uint64_t search_space_fetch_end_timestamp_usec = godot::Time::get_singleton()->get_ticks_usec();
		_search_space_fetch_time_usec = search_space_fetch_end_timestamp_usec - method_start_time_usec;
		if (search_space_fetch_end_timestamp_usec >= deadline_usec) {
			record_call_runtime(_search_space_fetch_time_usec);
			return false; // Search space fetching used the time budget.
		}

	} //endif is searchspace fetched

	// Do any preprocessing that's needed.
	if (!_is_preprocessing_completed) {
		uint64_t preprocessing_start_timestamp_usec = godot::Time::get_singleton()->get_ticks_usec();
		_is_preprocessing_completed = preprocess_search_space(deadline_usec);
		uint64_t preprocessing_end_timestamp_usec = godot::Time::get_singleton()->get_ticks_usec();
		_preprocessing_time_usec += (preprocessing_end_timestamp_usec - preprocessing_start_timestamp_usec);
		if (!_is_preprocessing_completed || preprocessing_end_timestamp_usec >= deadline_usec) {
			record_call_runtime(preprocessing_end_timestamp_usec - method_start_time_usec);
			return false; // Preprocessing used the time budget or waits on worker threads.
		}
	}

	// Handle the criteria.
	if (!_is_criteria_handled) {
		if (!_is_threading_decision_made) {
			_is_criteria_threaded = decide_threaded_criteria();
			_is_threading_decision_made = true;
		}
		if (_is_criteria_threaded) {
			if (!_threaded_snapshot_completed) {
				if (!snapshot_threaded_candidates(method_start_time_usec, deadline_usec)) {
					return false; // Snapshot used the time budget.
				}
				_threaded_snapshot_completed = true;
			}
			if (!_threaded_job_started) {
				dispatch_threaded_criteria();
				_threaded_job_started = true;
			}
			// An unlimited budget promises to finish the query in this call.
			if (time_budget_usec == 0) {
				_threaded_job.wait();
			} else if (!_threaded_job.poll()) {
				_is_waiting_for_worker = true;
				record_call_runtime(godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
				return false;
			}
			apply_threaded_criteria();
		} else {
			while (_current_criterion_index < (int)_num_filtering_criteria) {
				NNNQSSearchCriteria *criterion = _filtering_criteria[_current_criterion_index];
				if (!criterion->get_is_enabled()) {
					++_current_criterion_index;
					continue;
				}
				bool is_criterion_complete = apply_criterion_with_time_budget(criterion,
						method_start_time_usec,
						deadline_usec);
				if (!is_criterion_complete) {
					// Note: the runtime is already updated in the apply_criterion_with_time_budget() method.
					return false; // The criterion did not complete, so it timed out.
				}
				++_current_criterion_index;
			} //endwhile criterions left to process
			_is_criteria_handled = true;
			_current_query_results.clear();
			_current_query_result_scores.clear();
		}
	} //endif is criteria handled
	// Put all the remaining scores to the search results in order.
	if (!_is_results_copied) {
		unsigned int nodes_since_time_check = TIME_CHECK_INTERVAL_NODES;
		while (_current_result_index < _num_search_space_nodes) {
			if (nodes_since_time_check >= TIME_CHECK_INTERVAL_NODES) {
				uint64_t current_time_usec = godot::Time::get_singleton()->get_ticks_usec();
				if (current_time_usec >= deadline_usec) {
					record_call_runtime(current_time_usec - method_start_time_usec);
					return false;
				}
				nodes_since_time_check = 0;
			}

			Node *node = godot::Object::cast_to<Node>((*_ptr_current_search_space)[_current_result_index].get_validated_object());
			if (node != nullptr) {
				place_to_query_results_based_on_score(node, (*_ptr_current_scores)[_current_result_index]);
			}
			++_current_result_index;
			++nodes_since_time_check;
		}
		_query_results = _current_query_results;
		_query_result_scores = _current_query_result_scores;
		_is_results_copied = true;
#ifdef DEBUG_ENABLED
		// _query_results only keeps the top N; the debugger's viewport draw needs
		// every surviving candidate and its score.
		if (_debug_score_watch_count > 0) {
			_debug_scored_nodes.clear();
			_debug_scored_scores.clear();
			for (unsigned int i = 0; i < _num_search_space_nodes; ++i) {
				Node *node = godot::Object::cast_to<Node>((*_ptr_current_search_space)[i].get_validated_object());
				if (node == nullptr) {
					continue;
				}
				_debug_scored_nodes.push_back(node);
				_debug_scored_scores.push_back((*_ptr_current_scores)[i]);
			}
		}
#endif
	} //endif results are copied

	// Clear everything to be ready for the next query.
	_is_last_query_threaded = _is_criteria_threaded;
	clear_threaded_query_data();
	_current_criterion_index = 0;
	_current_node_index = 0;
	_current_result_index = 0;
	_work_in_progress_num_added_nodes = 0;
	_num_search_space_nodes = 0;
	_is_query_still_running = false;
	_total_query_call_count = _current_query_call_count;
	_total_query_node_visits = _current_query_node_visits;

	// Emit the signal that this query completed.
	uint64_t signal_start_timestamp = godot::Time::get_singleton()->get_ticks_usec();
	emit_signal("query_completed", this);
	_completed_signal_time_usec = godot::Time::get_singleton()->get_ticks_usec() - signal_start_timestamp;

	// All the criterions are processed and results sorted. Store the total time used for processing.
	record_call_runtime(godot::Time::get_singleton()->get_ticks_usec() - method_start_time_usec);
	_total_query_runtime_usec = _current_query_runtime_usec;

	// The query is done.
	return true;
}

void NNNQSSearchSpaces::record_call_runtime(uint64_t call_runtime_usec) {
	_current_call_runtime_usec = call_runtime_usec;
	_average_call_runtime_usec = _average_call_runtime_usec * 0.5 + 0.5 * _current_call_runtime_usec;
	_current_query_runtime_usec += _current_call_runtime_usec;
}

bool NNNQSSearchSpaces::apply_criterion_with_time_budget(NNNQSSearchCriteria *criterion,
		uint64_t start_time_usec,
		uint64_t deadline_usec) {
	unsigned int nodes_since_time_check = TIME_CHECK_INTERVAL_NODES;
	while (_current_node_index < _num_search_space_nodes) {
		if (nodes_since_time_check >= TIME_CHECK_INTERVAL_NODES) {
			uint64_t current_time_usec = godot::Time::get_singleton()->get_ticks_usec();
			if (current_time_usec >= deadline_usec) {
				record_call_runtime(current_time_usec - start_time_usec);
				return false;
			}
			nodes_since_time_check = 0;
		}

		// The raw Variant cast does not detect a freed node.
		Node *node = godot::Object::cast_to<Node>((*_ptr_current_search_space)[_current_node_index].get_validated_object());
		if (node == nullptr) {
			++_current_node_index;
			continue;
		}
		bool filter_out = false;
		float score = 1.0f;
		float previous_score = 1.0f;
		if (_current_node_index < (*_ptr_current_scores).size()) {
			previous_score = (*_ptr_current_scores)[_current_node_index];
		}
		++_current_query_node_visits;
		criterion->apply_criterion(node, filter_out, score);
		if (!filter_out) {
			(*_ptr_current_work_in_progress_search_space)[_work_in_progress_num_added_nodes] = node;
			(*_ptr_current_work_in_progress_scores)[_work_in_progress_num_added_nodes] = (previous_score * score);
			++_work_in_progress_num_added_nodes;
		}
		if (_is_run_in_debug_mode) {
			node->set(_is_filtered_property, filter_out);
			node->set(_score_property, (previous_score * score));
		}

		// Move to the next node.
		++_current_node_index;
		++nodes_since_time_check;
	} //endwhile nodes

	TypedArray<Node> *temparray = _ptr_current_search_space;
	PackedFloat64Array *tempscores = _ptr_current_scores;
	_ptr_current_search_space = _ptr_current_work_in_progress_search_space;
	_ptr_current_scores = _ptr_current_work_in_progress_scores;

	_ptr_current_work_in_progress_search_space = temparray;
	_ptr_current_work_in_progress_scores = tempscores;

	_num_search_space_nodes = _work_in_progress_num_added_nodes;

	_current_node_index = 0;
	_work_in_progress_num_added_nodes = 0;

	// All done!
	return true;
}

namespace {

// Descending; a tie goes after its equals, and a full list returns -1 for a worse score.
template <typename TScore>
int score_insert_position(const TScore *p_scores, int p_num_entries, float p_score, int p_top_n) {
	if (p_num_entries > 0 && p_num_entries == p_top_n && p_score < p_scores[p_top_n - 1]) {
		return -1;
	}
	int i = 0;
	while (i < p_num_entries && p_scores[i] >= p_score) {
		++i;
	}
	return i;
}

} //namespace

void NNNQSSearchSpaces::place_to_query_results_based_on_score(Node *node, float score) {
	const int num_entries = _current_query_result_scores.size();
	const int insertion_index = score_insert_position(_current_query_result_scores.ptr(), num_entries, score, _top_n_to_find);
	if (insertion_index < 0) {
		return;
	}
	_current_query_results.insert(insertion_index, node);
	_current_query_result_scores.insert(insertion_index, score);
	if (num_entries + 1 > _top_n_to_find) {
		_current_query_result_scores.remove_at(_top_n_to_find);
		_current_query_results.remove_at(_top_n_to_find);
	}
}

bool NNNQSSearchSpaces::decide_threaded_criteria() {
	if (!uses_threads_for(_num_search_space_nodes, CRITERIA_THREADING_AUTO_MIN_NODES)) {
		return false;
	}
	if (_is_run_in_debug_mode) {
		return false;
	}

	_threaded_criteria.clear();
	for (NNNQSSearchCriteria *criterion : _filtering_criteria) {
		if (!criterion->get_is_enabled()) {
			continue;
		}
		// A script can override apply_criterion(), so its kernel is not trustworthy.
		Object *script = criterion->get_script();
		if (script != nullptr) {
			_threaded_criteria.clear();
			return false;
		}
		std::unique_ptr<NNNQSThreadedCriterion> kernel = criterion->create_threaded_criterion();
		if (kernel == nullptr) {
			_threaded_criteria.clear();
			return false;
		}
		_threaded_criteria.push_back(std::move(kernel));
	}
	return !_threaded_criteria.empty();
}

bool NNNQSSearchSpaces::snapshot_threaded_candidates(uint64_t start_time_usec, uint64_t deadline_usec) {
	// Array::ptr() is private in godot-cpp, so take the address of the first element once.
	const Variant *search_space_nodes = _num_search_space_nodes > 0 ? &(*_ptr_current_search_space)[0] : nullptr;
	unsigned int nodes_since_time_check = TIME_CHECK_INTERVAL_NODES;
	while (_threaded_snapshot_index < _num_search_space_nodes) {
		if (nodes_since_time_check >= TIME_CHECK_INTERVAL_NODES) {
			const uint64_t current_time_usec = godot::Time::get_singleton()->get_ticks_usec();
			if (current_time_usec >= deadline_usec) {
				record_call_runtime(current_time_usec - start_time_usec);
				return false;
			}
			nodes_since_time_check = 0;
		}

		Node *node = godot::Object::cast_to<Node>(search_space_nodes[_threaded_snapshot_index]);
		if (node != nullptr) {
			NNNQSCandidate candidate;
			if (Node3D *node3d = godot::Object::cast_to<Node3D>(node)) {
				candidate.kind = NNNQSCandidate::NODE_3D;
				candidate.global_transform_3d = node3d->get_global_transform();
			} else if (Node2D *node2d = godot::Object::cast_to<Node2D>(node)) {
				candidate.kind = NNNQSCandidate::NODE_2D;
				candidate.global_transform_2d = node2d->get_global_transform();
			}
			_threaded_candidates.push_back(candidate);
			_threaded_candidate_ids.push_back(ObjectID(node->get_instance_id()));
		}
		++_threaded_snapshot_index;
		++nodes_since_time_check;
	}
	return true;
}

void NNNQSSearchSpaces::dispatch_threaded_criteria() {
	const uint32_t candidate_count = (uint32_t)_threaded_candidates.size();
	const uint32_t chunk_count = (candidate_count + CRITERIA_THREADING_CHUNK_SIZE - 1) / CRITERIA_THREADING_CHUNK_SIZE;
	_threaded_chunk_results.assign(chunk_count, CriteriaChunkResult());
	// Workers read this copy: top_n_to_find may be set while the job runs.
	_threaded_top_n = _top_n_to_find;
	const size_t chunk_list_capacity = MIN((size_t)_threaded_top_n, (size_t)CRITERIA_THREADING_CHUNK_SIZE);
	for (CriteriaChunkResult &chunk_result : _threaded_chunk_results) {
		chunk_result.candidate_indexes.reserve(chunk_list_capacity);
		chunk_result.scores.reserve(chunk_list_capacity);
	}

#ifdef DEBUG_ENABLED
	_threaded_keep_all_candidates = _debug_score_watch_count > 0;
#endif
	if (_threaded_keep_all_candidates) {
		_threaded_candidate_kept.assign(candidate_count, 0);
		_threaded_candidate_scores.assign(candidate_count, 0.0f);
	}

	if (candidate_count == 0) {
		return;
	}
	_threaded_job.start(candidate_count, CRITERIA_THREADING_CHUNK_SIZE, [this](uint32_t begin, uint32_t end) { run_threaded_criteria_chunk(begin, end); }, "NQS criteria");
}

void NNNQSSearchSpaces::run_threaded_criteria_chunk(uint32_t p_begin, uint32_t p_end) {
	CriteriaChunkResult &chunk_result = _threaded_chunk_results[p_begin / CRITERIA_THREADING_CHUNK_SIZE];
	unsigned int visits = 0;
	for (uint32_t i = p_begin; i < p_end; ++i) {
		float score = 1.0f;
		bool is_dropped = false;
		for (const std::unique_ptr<NNNQSThreadedCriterion> &criterion : _threaded_criteria) {
			bool filter_out = false;
			float criterion_score = 1.0f;
			criterion->evaluate(_threaded_candidates[i], filter_out, criterion_score);
			++visits;
			if (filter_out) {
				is_dropped = true;
				break;
			}
			score = score * criterion_score;
		}

		if (_threaded_keep_all_candidates) {
			_threaded_candidate_kept[i] = is_dropped ? 0 : 1;
			_threaded_candidate_scores[i] = score;
		}
		if (is_dropped) {
			continue;
		}

		const int insertion_index = score_insert_position(chunk_result.scores.data(), (int)chunk_result.scores.size(), score, _threaded_top_n);
		if (insertion_index < 0) {
			continue;
		}
		chunk_result.candidate_indexes.insert(chunk_result.candidate_indexes.begin() + insertion_index, i);
		chunk_result.scores.insert(chunk_result.scores.begin() + insertion_index, score);
		if ((int)chunk_result.scores.size() > _threaded_top_n) {
			chunk_result.candidate_indexes.pop_back();
			chunk_result.scores.pop_back();
		}
	}
	chunk_result.visits = visits;
}

void NNNQSSearchSpaces::apply_threaded_criteria() {
	_current_query_results.clear();
	_current_query_result_scores.clear();

	unsigned int visits = 0;
	for (const CriteriaChunkResult &chunk_result : _threaded_chunk_results) {
		visits += chunk_result.visits;
		for (size_t i = 0; i < chunk_result.candidate_indexes.size(); ++i) {
			const uint32_t candidate_index = chunk_result.candidate_indexes[i];
			Node *node = godot::Object::cast_to<Node>(ObjectDB::get_instance(_threaded_candidate_ids[candidate_index]));
			if (node != nullptr) {
				place_to_query_results_based_on_score(node, chunk_result.scores[i]);
			}
		}
	}
	_current_query_node_visits += visits;

	_query_results = _current_query_results;
	_query_result_scores = _current_query_result_scores;

#ifdef DEBUG_ENABLED
	if (_threaded_keep_all_candidates) {
		_debug_scored_nodes.clear();
		_debug_scored_scores.clear();
		for (size_t i = 0; i < _threaded_candidate_ids.size(); ++i) {
			if (_threaded_candidate_kept[i] == 0) {
				continue;
			}
			Node *node = godot::Object::cast_to<Node>(ObjectDB::get_instance(_threaded_candidate_ids[i]));
			if (node == nullptr) {
				continue;
			}
			_debug_scored_nodes.push_back(node);
			_debug_scored_scores.push_back(_threaded_candidate_scores[i]);
		}
	}
#endif

	_num_search_space_nodes = 0;
	_is_criteria_handled = true;
	_is_results_copied = true;
}

void NNNQSSearchSpaces::clear_threaded_query_data() {
	_threaded_job.wait();
	_threaded_candidate_ids.clear();
	_threaded_candidates.clear();
	_threaded_criteria.clear();
	_threaded_chunk_results.clear();
	_threaded_candidate_kept.clear();
	_threaded_candidate_scores.clear();
	_threaded_snapshot_index = 0;
	_threaded_snapshot_completed = false;
	_threaded_job_started = false;
	_threaded_keep_all_candidates = false;
	_is_threading_decision_made = false;
	_is_criteria_threaded = false;
}

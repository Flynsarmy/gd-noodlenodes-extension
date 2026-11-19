#include "nqs.h"
#include "../node_query_system.h"
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>

#include <cstdint>

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
	_is_filtered_property = StringName("is_filtered");
	_score_property = StringName("score");
}

NNNQSSearchSpaces::~NNNQSSearchSpaces() {
}

// Batching the clock read bounds a budget overrun to at most N - 1 node visits.
constexpr unsigned int TIME_CHECK_INTERVAL_NODES = 16;

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

	ClassDB::bind_method(D_METHOD("set_is_run_in_debug_mode", "is_run_in_debug_mode"), &NNNQSSearchSpaces::set_is_run_in_debug_mode);
	ClassDB::bind_method(D_METHOD("get_is_run_in_debug_mode"), &NNNQSSearchSpaces::get_is_run_in_debug_mode);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_run_in_debug_mode", PROPERTY_HINT_NONE), "set_is_run_in_debug_mode", "get_is_run_in_debug_mode");

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
	// If we don't remove this search space from the singleton, it'll cause a memory leak.
	NNNodeQuerySystem *nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
	if (nqs == nullptr)
		return;
	nqs->stop_query(this);
}

// Getters and setters.

void NNNQSSearchSpaces::set_is_run_in_debug_mode(bool is_run_in_debug_mode) {
	_is_run_in_debug_mode = is_run_in_debug_mode;
}

bool NNNQSSearchSpaces::get_is_run_in_debug_mode() const {
	return _is_run_in_debug_mode;
}

void NNNQSSearchSpaces::set_nqs_query_index(int nqs_query_index) {
	_nqs_query_index = nqs_query_index;
}

int NNNQSSearchSpaces::get_nqs_query_index() const {
	return _nqs_query_index;
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

void NNNQSSearchSpaces::set_top_n_to_find(int top_n_to_find) {
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
	const uint64_t deadline_usec = time_budget_usec > 0 ? method_start_time_usec + time_budget_usec : UINT64_MAX;

	if (!get_is_enabled()) {
		_is_query_still_running = false;
		return true;
	}
	if (Engine::get_singleton()->is_editor_hint()) {
		_is_query_still_running = false;
		return true;
	}
	if (get_child_count() < 1) {
		WARN_PRINT("NNNodeQuerySystem::execute_query() - No search criteria nodes added.");
		_is_query_still_running = false;
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
		if (preprocessing_end_timestamp_usec >= deadline_usec) {
			record_call_runtime(preprocessing_end_timestamp_usec - method_start_time_usec);
			return false; // Preprocessing used the time budget.
		}
	}

	// Handle the criteria.
	if (!_is_criteria_handled) {
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

			Node *node = godot::Object::cast_to<Node>((*_ptr_current_search_space)[_current_result_index]);
			place_to_query_results_based_on_score(node, (*_ptr_current_scores)[_current_result_index]);
			++_current_result_index;
			++nodes_since_time_check;
		}
		_query_results = _current_query_results;
		_query_result_scores = _current_query_result_scores;
		_is_results_copied = true;
	} //endif results are copied

	// Clear everything to be ready for the next query.
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

		Node *node = godot::Object::cast_to<Node>((*_ptr_current_search_space)[_current_node_index]);
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

void NNNQSSearchSpaces::place_to_query_results_based_on_score(Node *node, float score) {
	int num_entries = _current_query_result_scores.size();
	if (num_entries == 0) {
		_current_query_results.push_back(node);
		_current_query_result_scores.push_back(score);
		return;
	} else if (num_entries == _top_n_to_find) {
		if (score < _current_query_result_scores[_top_n_to_find - 1])
			return; // Worse than the worst on the list.
	}

	int i = 0;
	while (i < num_entries && _current_query_result_scores[i] >= score) {
		i++;
	}

	if (i < num_entries) {
		_current_query_results.insert(i, node);
		_current_query_result_scores.insert(i, score);
		if (num_entries + 1 > _top_n_to_find) {
			_current_query_result_scores.remove_at(_top_n_to_find);
			_current_query_results.remove_at(_top_n_to_find);
		}
		return;
	}
	if (i < _top_n_to_find) {
		_current_query_results.push_back(node);
		_current_query_result_scores.push_back(score);
	}
}

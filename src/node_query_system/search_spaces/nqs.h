#pragma once

#include "../noodle_nodes.h"
#include "../search_criteria/nqs.h"
#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNNQSSearchSpaces : public NoodleNodes {
	GDCLASS(NNNQSSearchSpaces, NoodleNodes)

private:
	bool _is_run_in_debug_mode;

	int _top_n_to_find;
	unsigned int _current_criterion_index;
	unsigned int _current_node_index;
	unsigned int _current_result_index;
	bool _is_search_space_fetched;
	bool _is_preprocessing_completed;
	bool _is_criteria_handled;
	bool _is_results_copied;
	bool _is_query_still_running;
	TypedArray<Node> _current_query_results;
	PackedFloat64Array _current_query_result_scores;
	TypedArray<Node> _query_results;
	PackedFloat64Array _query_result_scores;
	uint64_t _total_query_runtime_usec;
	uint64_t _current_query_runtime_usec;
	uint64_t _current_call_runtime_usec;
	uint64_t _average_call_runtime_usec;
	uint64_t _search_space_fetch_time_usec;
	uint64_t _preprocessing_time_usec;
	uint64_t _completed_signal_time_usec;
	unsigned int _current_query_node_visits;
	unsigned int _current_query_call_count;
	unsigned int _total_query_node_visits;
	unsigned int _total_query_call_count;
	TypedArray<Node> _search_space;
	PackedFloat64Array _scores;
	unsigned int _num_search_space_nodes;
	TypedArray<Node> _work_in_progress_search_space;
	PackedFloat64Array _work_in_progress_scores;
	unsigned int _work_in_progress_num_added_nodes;

	TypedArray<Node> *_ptr_current_search_space;
	TypedArray<Node> *_ptr_current_work_in_progress_search_space;
	PackedFloat64Array *_ptr_current_scores;
	PackedFloat64Array *_ptr_current_work_in_progress_scores;

	std::vector<NNNQSSearchCriteria *> _filtering_criteria;
	unsigned int _num_filtering_criteria;

	int _nqs_query_index; // Index of the query in the singleton.
	bool _nqs_query_is_high_priority;
	// Monotonic token identifying the current scheduler registration. A
	// completion may only release the registration it started with, even if a
	// callback stopped and re-posted the query into the same index.
	uint64_t _nqs_query_registration;

	void record_call_runtime(uint64_t call_runtime_usec);

protected:
	static void _bind_methods();
	virtual void _initialize_search_space() {}
	virtual void _uninitialize_search_space() {}

	bool apply_criterion_with_time_budget(NNNQSSearchCriteria *criterion,
			uint64_t start_time_usec,
			uint64_t deadline_usec);
	virtual bool preprocess_search_space(uint64_t time_limit_timestamp_usec) {
		_is_preprocessing_completed = true;
		return true;
	};
	void place_to_query_results_based_on_score(Node *node, float score);

	unsigned int _current_preprocessing_node_index;

public:
	NNNQSSearchSpaces();
	~NNNQSSearchSpaces();

	// Getters and setters.

	void set_is_run_in_debug_mode(bool is_run_in_debug_mode);
	bool get_is_run_in_debug_mode() const;

	void set_nqs_query_index(int nqs_query_index);
	int get_nqs_query_index() const;

	void set_nqs_query_is_high_priority(bool nqs_query_is_high_priority);
	bool get_nqs_query_is_high_priority() const;

	void set_nqs_query_registration(uint64_t nqs_query_registration);
	uint64_t get_nqs_query_registration() const;
	void bump_nqs_query_registration();

	virtual TypedArray<Node> get_searchspace_nodes() const;

	TypedArray<Node> get_query_results() const;
	PackedFloat64Array get_query_result_scores() const;

	void set_top_n_to_find(int top_n_to_find);
	int get_top_n_to_find() const;

	uint64_t get_average_call_runtime_usec() const;
	uint64_t get_current_call_runtime_usec() const;
	uint64_t get_search_space_fetch_time_usec() const;
	uint64_t get_total_query_runtime_usec() const;
	uint64_t get_completed_signal_time_usec() const;
	uint64_t get_total_query_node_visits() const;
	uint64_t get_total_query_call_count() const;

	void set_is_query_still_running(bool is_query_still_running);
	bool get_is_query_still_running() const;

	// Handling methods.

	void initialize_search_space();
	void reset_query_variables();

	virtual void start_query();
	virtual bool execute_query(uint64_t time_budget_usec = 0);

	// Godot virtuals.
	void _ready() override;
	void _exit_tree() override;
};

} //namespace godot

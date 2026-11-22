#pragma once

#include "../noodle_nodes.h"
#include "../nqs_threading.h"
#include "../search_criteria/nqs.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object_id.hpp>
#include <memory>
#include <vector>

namespace godot {

class NNNodeQuerySystem;

class NNNQSSearchSpaces : public NoodleNodes {
	GDCLASS(NNNQSSearchSpaces, NoodleNodes)

public:
	enum ThreadingMode {
		THREADING_OFF,
		THREADING_AUTO,
		THREADING_ALWAYS,
	};

private:
	// Members, not statics: static StringNames outlive the engine's StringName table.
	StringName _is_filtered_property;
	StringName _score_property;

	bool _is_run_in_debug_mode;
	ThreadingMode _threading_mode;
	bool _is_last_query_threaded;

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
#ifdef DEBUG_ENABLED
	unsigned int _debug_score_watch_count;
	TypedArray<Node> _debug_scored_nodes;
	PackedFloat64Array _debug_scored_scores;
#endif
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

	struct CriteriaChunkResult {
		std::vector<uint32_t> candidate_indexes;
		std::vector<float> scores;
		unsigned int visits = 0;
	};

	// Worker threads read and write only these buffers.
	bool _is_threading_decision_made;
	bool _is_criteria_threaded;
	unsigned int _threaded_snapshot_index;
	bool _threaded_snapshot_completed;
	bool _threaded_job_started;
	bool _threaded_keep_all_candidates;
	int _threaded_top_n;
	std::vector<ObjectID> _threaded_candidate_ids;
	std::vector<NNNQSCandidate> _threaded_candidates;
	std::vector<std::unique_ptr<NNNQSThreadedCriterion>> _threaded_criteria;
	std::vector<CriteriaChunkResult> _threaded_chunk_results;
	std::vector<uint8_t> _threaded_candidate_kept;
	std::vector<float> _threaded_candidate_scores;
	// After the buffers above: its destructor waits before they go away.
	NNNQSWorkerJob _threaded_job;

	int _nqs_query_index; // Index of the query in the scheduler.
	ObjectID _nqs_scheduler_id;
	bool _nqs_query_is_high_priority;
	// Monotonic token identifying the current scheduler registration. A
	// completion may only release the registration it started with, even if a
	// callback stopped and re-posted the query into the same index.
	uint64_t _nqs_query_registration;

	void record_call_runtime(uint64_t call_runtime_usec);
	void _leave_scheduler();

protected:
	static void _bind_methods();
	virtual void _initialize_search_space() {}
	virtual void _uninitialize_search_space() {}
	virtual void _cancel_preprocessing() {}

	bool apply_criterion_with_time_budget(NNNQSSearchCriteria *criterion,
			uint64_t start_time_usec,
			uint64_t deadline_usec);
	bool decide_threaded_criteria();
	bool snapshot_threaded_candidates(uint64_t start_time_usec, uint64_t deadline_usec);
	void dispatch_threaded_criteria();
	void run_threaded_criteria_chunk(uint32_t begin, uint32_t end);
	void apply_threaded_criteria();
	void clear_threaded_query_data();
	virtual bool preprocess_search_space(uint64_t time_limit_timestamp_usec) {
		_is_preprocessing_completed = true;
		return true;
	};
	void place_to_query_results_based_on_score(Node *node, float score);
	bool uses_threads_for(unsigned int p_item_count, unsigned int p_auto_min_items) const;
	bool _is_waiting_for_worker;

	unsigned int _current_preprocessing_node_index;

public:
	NNNQSSearchSpaces();
	~NNNQSSearchSpaces();

	// Getters and setters.

	void set_is_run_in_debug_mode(bool is_run_in_debug_mode);
	bool get_is_run_in_debug_mode() const;

	void set_threading_mode(ThreadingMode threading_mode);
	ThreadingMode get_threading_mode() const;

	bool get_is_last_query_threaded() const;
	bool is_waiting_for_worker() const;

	void set_nqs_query_index(int nqs_query_index);
	int get_nqs_query_index() const;

	void set_nqs_scheduler(NNNodeQuerySystem *nqs_scheduler);
	NNNodeQuerySystem *get_nqs_scheduler() const;

	void set_nqs_query_is_high_priority(bool nqs_query_is_high_priority);
	bool get_nqs_query_is_high_priority() const;

	void set_nqs_query_registration(uint64_t nqs_query_registration);
	uint64_t get_nqs_query_registration() const;
	void bump_nqs_query_registration();

	virtual TypedArray<Node> get_searchspace_nodes() const;

	TypedArray<Node> get_query_results() const;
	PackedFloat64Array get_query_result_scores() const;

#ifdef DEBUG_ENABLED
	void watch_debug_scores();
	void unwatch_debug_scores();
	TypedArray<Node> get_debug_scored_nodes() const;
	PackedFloat64Array get_debug_scored_scores() const;
#endif

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
	void _notification(int p_what);
};

} //namespace godot

VARIANT_ENUM_CAST(NNNQSSearchSpaces::ThreadingMode);

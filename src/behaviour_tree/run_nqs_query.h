#pragma once

#include "../node_query_system/node_query_system.h"
#include "../node_query_system/search_spaces/nqs.h"
#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object.hpp>

#define QS_IDLE 0
#define QS_RUNNING 1
#define QS_COMPLETED 2
// The query stopped without emitting "query_completed": it was cancelled through
// NodeQuerySystem.stop_query()/clear_queries(), or its posting was rejected.
#define QS_CANCELLED 3

namespace godot {

class NNBTRunNQSQuery : public NNBTTaskNodes {
	GDCLASS(NNBTRunNQSQuery, NNBTTaskNodes)

private:
	// Non-owning reference to the search space, tracked by instance ID. The node
	// can be freed at any time, so every use resolves the ID through ObjectDB.
	ObjectID _nqs_search_space_cache;
	NNNodeQuerySystem *_nqs;

	int _time_budget_usec;
	int _top_n_to_find;
	bool _is_high_priority;

	int _query_state;
	// True once the current query's "query_completed" signal has been observed.
	// That signal is only emitted on genuine completion, so it is what separates
	// completion from cancellation. Results length cannot be used for this.
	bool _has_query_completed;
	// True when this leaf posted the query represented by _query_state. A query
	// that failed to post belongs to another poster and must not be stopped or
	// reset by this leaf.
	bool _owns_query;
	// Scheduler registration token captured when our query was posted. A later
	// re-post (or an external stop) bumps it, so it also proves the scheduled
	// query is still ours when we clean up on reassignment/reset.
	uint64_t _posted_query_registration;
	// One-shot connection to the search space's completion signal, kept so it
	// can be disconnected when a run is abandoned. The callable binds the space
	// instance ID (and registration) so a stale callback cannot complete the
	// current run, and so the handler never dereferences the signal argument.
	Callable _query_completed_callable;

	NNNQSSearchSpaces *_resolve_nqs_search_space() const;
	bool _connect_query_completed(NNNQSSearchSpaces *p_search_space);
	void _disconnect_query_completed(NNNQSSearchSpaces *p_search_space);
	void _release_in_flight_query(NNNQSSearchSpaces *p_search_space);
	void _on_query_completed(Object *p_search_space, int64_t p_search_space_instance_id, int64_t p_query_registration);

protected:
	static void _bind_methods();

public:
	NNBTRunNQSQuery();
	~NNBTRunNQSQuery();

	// Getters and setters for attributes.

	void set_nqs_search_space(NNNQSSearchSpaces *nqs_search_space);
	NNNQSSearchSpaces *get_nqs_search_space() const;

	void set_time_budget_usec(int time_budget_usec);
	int get_time_budget_usec() const;

	void set_top_n_to_find(int top_n_to_find);
	int get_top_n_to_find() const;

	void set_is_high_priority(bool is_high_priority);
	bool get_is_high_priority() const;

	// Handling functions.
	virtual void reset_bt_node() override;
	virtual Status tick(Variant blackboard, float delta) override;

	// Godot virtuals.

	void _ready() override;
	void _physics_process(double delta) override;
};

} //namespace godot

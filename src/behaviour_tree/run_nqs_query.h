#pragma once

#include "../node_query_system/node_query_system.h"
#include "../node_query_system/search_spaces/nqs.h"
#include "task_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/object.hpp>

namespace godot {

class NNBTRunNQSQuery : public NNBTTaskNodes {
	GDCLASS(NNBTRunNQSQuery, NNBTTaskNodes)

private:
	enum class QueryState { IDLE,
		RUNNING,
		COMPLETED,
		CANCELLED };

	ObjectID _nqs_search_space_cache;

	int _time_budget_usec;
	int _top_n_to_find;
	bool _is_high_priority;

	QueryState _query_state;
	// A nonzero token identifies the registration this leaf posted.
	uint64_t _posted_query_registration;
	Callable _query_completed_callable;

	NNNQSSearchSpaces *_resolve_nqs_search_space() const;
	bool _connect_query_completed(NNNQSSearchSpaces *p_search_space);
	void _on_query_completed(Object *p_search_space, int64_t p_query_registration);

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

	void _exit_tree() override;
};

} //namespace godot

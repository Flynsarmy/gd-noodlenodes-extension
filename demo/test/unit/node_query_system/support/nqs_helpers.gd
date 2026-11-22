## Builders shared by the node query system tests. Preload with
## `const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")`.

extends RefCounted

const GENEROUS_BUDGET_USEC := 100000
const MAX_RUN_QUERIES_CALLS := 100


class CountingCriterion extends NNCustomSearchCriterion:
	var apply_count := 0

	func on_apply_criterion(_node) -> void:
		apply_count += 1


static func make_nqs(
		test: GutTest,
		run_budget_usec := GENEROUS_BUDGET_USEC,
		execute_budget_usec := GENEROUS_BUDGET_USEC) -> NNNodeQuerySystem:
	var nqs: NNNodeQuerySystem = test.autofree(NNNodeQuerySystem.new())
	nqs.run_queries_time_budget_per_frame_usec = run_budget_usec
	# Recompute the priority split after changing the frame budget.
	nqs.time_allocation_pct_to_high_priority_queries = 0.8
	nqs.high_priority_query_per_frame_execute_query_time_budget_usec = execute_budget_usec
	nqs.regular_query_per_frame_execute_query_time_budget_usec = execute_budget_usec
	return nqs


static func make_container(test: GutTest, child_count: int) -> Node:
	var container: Node = Node.new()
	for _i in range(child_count):
		container.add_child(Node.new())
	return test.add_child_autofree(container)


static func make_query(
		test: GutTest,
		container: Node,
		criterion_or_criteria,
		top_n: int = 1) -> NNNodeChildrenSearchSpace:
	var query: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	query.parent_node = container
	query.top_n_to_find = top_n
	if criterion_or_criteria is Array:
		for criterion in criterion_or_criteria:
			query.add_child(criterion)
	else:
		query.add_child(criterion_or_criteria)
	return test.add_child_autofree(query)


static func run_to_completion(test: GutTest, nqs: NNNodeQuerySystem, query: NNNQSSearchSpaces) -> void:
	test.assert_eq(nqs.post_query(query, true), 1, "The test query must be posted.")
	var calls: int = 0
	while query.is_query_still_running and calls < MAX_RUN_QUERIES_CALLS:
		nqs.run_queries()
		calls += 1
	test.assert_false(query.is_query_still_running, "The query must complete with a generous budget.")
	test.assert_lt(calls, MAX_RUN_QUERIES_CALLS, "The query must not spin across frames.")

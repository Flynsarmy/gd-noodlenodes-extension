# GdUnit generated TestSuite
extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const RESET_RULE_WHEN_TICKED := 0
const RESET_RULE_WHEN_COMPLETED := 1
const RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED := 2
const RESET_RULE_NEVER := 3

const INTERNAL_STATUS_COMPLETED := 2

func test_unset_search_space_fails_for_all_reset_rules() -> void:
	for reset_rule in [RESET_RULE_WHEN_TICKED, RESET_RULE_WHEN_COMPLETED, RESET_RULE_WHEN_TICKED_AFTER_BEING_COMPLETED, RESET_RULE_NEVER]:
		var _root: NNBTRoot = NNBTRoot.new()
		var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
		_child.reset_rule = reset_rule
		_root.add_child(_child)
		add_child(_root)

		for _tick_index in 3:
			assert_eq(_root.tick({}, 0.1), NNBTNodes.FAILURE)
			assert_eq(_child.tick_result, NNBTNodes.FAILURE)
			assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)

		_root.free()

func test_configured_search_space_still_runs_and_resets() -> void:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	var _root: NNBTRoot = NNBTRoot.new()
	var _child: NNBTRunNQSQuery = NNBTRunNQSQuery.new()
	_child.nqs_search_space = _search_space
	_child.reset_rule = RESET_RULE_WHEN_COMPLETED
	_root.add_child(_child)

	# Add to the scene tree so the query node resolves the NodeQuerySystem singleton.
	add_child_autofree(_search_space)
	add_child_autofree(_root)

	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	for _query_index in 2:
		assert_eq(_root.tick({}, 0.1), NNBTNodes.RUNNING)
		assert_true(_search_space.is_query_still_running)
		_nqs.run_queries()
		assert_false(_search_space.is_query_still_running)
		await wait_physics_frames(2)

		assert_eq(_root.tick({}, 0.1), NNBTNodes.SUCCESS)
		assert_eq(_child.internal_status, INTERNAL_STATUS_COMPLETED)
		# WHEN_COMPLETED resets the query variables before the next run.
		assert_true(_search_space.is_query_still_running)

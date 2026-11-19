extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")


func before_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()

func after_each() -> void:
	Engine.get_singleton("NodeQuerySystem").clear_queries()

# The singleton does not run by itself in headless GUT, so tests drive it.
func _complete_query(search_space: NNNQSSearchSpaces) -> void:
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	for _i in 128:
		if not search_space.is_query_still_running:
			return
		_nqs.run_queries()
	assert_false(search_space.is_query_still_running, "The query did not complete.")

func _make_search_space(parent_node: Node = null) -> NNNodeChildrenSearchSpace:
	var _search_space: NNNodeChildrenSearchSpace = NNNodeChildrenSearchSpace.new()
	_search_space.add_child(NNDistanceToVector2SearchCriterion.new())
	_search_space.parent_node = parent_node
	return _search_space

func _make_search_space_with_target(position := Vector2(50.0, 0.0)) -> NNNodeChildrenSearchSpace:
	var _container: Node2D = add_child_autofree(Node2D.new())
	var _best_node: Node2D = Node2D.new()
	_best_node.position = position
	_container.add_child(_best_node)
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space(_container)
	add_child_autofree(_search_space)
	return _search_space

func _make_sensor_with_root(search_space: NNNQSSearchSpaces) -> NNNQSQuerySensor:
	var _sensor: NNNQSQuerySensor = NNNQSQuerySensor.new()
	_sensor.nqs_search_space = search_space
	var _root := Fixtures.add_manual_st_root(self)
	_root.add_child(_sensor)
	return _sensor

func test_completed_query_sets_the_value_and_writes_the_best_node() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot

	_root.tick(0.1)

	assert_true(_search_space.is_query_still_running, "The tick posts the query.")
	assert_eq(_sensor.sensor_value, 0.0, "A posted query does not change the value yet.")

	_complete_query(_search_space)

	assert_almost_eq(_sensor.sensor_value, _search_space.query_result_scores[0], 0.0001)
	assert_eq(_root.get_blackboard("nqs_result"), _search_space.query_results[0])

func test_value_keeps_the_last_result_while_a_new_query_runs() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot
	var _best_node := _search_space.parent_node.get_child(0) as Node2D

	_root.tick(0.1)
	_complete_query(_search_space)
	var _previous_value: float = _sensor.sensor_value
	var _previous_node: Variant = _root.get_blackboard("nqs_result")
	assert_almost_eq(_previous_value, _search_space.query_result_scores[0], 0.0001)

	_best_node.position = Vector2(75.0, 0.0)
	_root.tick(0.1)

	assert_true(_search_space.is_query_still_running, "The tick posts a new query.")
	assert_almost_eq(_sensor.sensor_value, _previous_value, 0.0001)
	assert_eq(_root.get_blackboard("nqs_result"), _previous_node)

	_complete_query(_search_space)

	assert_almost_eq(_sensor.sensor_value, _search_space.query_result_scores[0], 0.0001)
	assert_ne(_sensor.sensor_value, _previous_value)

func test_no_result_sets_zero_and_erases_the_key() -> void:
	var _search_space: NNNodeChildrenSearchSpace = _make_search_space()
	add_child_autofree(_search_space)
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot
	assert_true(_root.set_blackboard("nqs_result", "stale"))

	_root.tick(0.1)
	_complete_query(_search_space)

	assert_eq(_sensor.sensor_value, 0.0)
	assert_false(_root.get_blackboard_resource().keys().has("nqs_result"), "An empty result erases the key.")

func test_a_custom_best_result_key_is_used() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	_sensor.best_result_key = "target"
	var _root := _sensor.get_parent() as NNSTRoot

	_root.tick(0.1)
	_complete_query(_search_space)

	assert_eq(_root.get_blackboard("target"), _search_space.query_results[0])
	assert_false(_root.has_blackboard("nqs_result"))

func test_cancelled_query_writes_nothing_and_keeps_the_last_result() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot

	_root.tick(0.1)
	_complete_query(_search_space)
	var _previous_value: float = _sensor.sensor_value
	var _previous_node: Variant = _root.get_blackboard("nqs_result")
	assert_not_null(_previous_node)

	_root.tick(0.1)
	assert_true(_search_space.is_query_still_running)
	var _nqs: NNNodeQuerySystem = Engine.get_singleton("NodeQuerySystem")
	assert_true(_nqs.stop_query(_search_space))

	_root.tick(0.1)

	assert_eq(_root.get_blackboard("nqs_result"), _previous_node)
	assert_almost_eq(_sensor.sensor_value, _previous_value, 0.0001)
	assert_false(_search_space.is_query_still_running)

func test_disabling_the_sensor_stops_its_query() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot

	_root.tick(0.1)
	assert_true(_search_space.is_query_still_running)

	_sensor.is_enabled = false

	assert_false(_search_space.is_query_still_running)

func test_freeing_the_sensor_stops_its_query() -> void:
	var _search_space := _make_search_space_with_target()
	var _sensor := _make_sensor_with_root(_search_space)
	var _root := _sensor.get_parent() as NNSTRoot

	_root.tick(0.1)
	assert_true(_search_space.is_query_still_running)

	_sensor.free()

	assert_false(_search_space.is_query_still_running)
	assert_false(_root.has_blackboard("nqs_result"))
	_complete_query(_search_space)
	assert_engine_error_count(0)

func test_agent_reads_the_sensor_key_from_its_blackboard() -> void:
	var _search_space := _make_search_space_with_target()

	var _agent: NNAgent = NNAgent.new()
	_agent.process_thread = NNAgent.MANUAL
	var _sensor: NNNQSQuerySensor = NNNQSQuerySensor.new()
	_sensor.nqs_search_space = _search_space
	_agent.add_child(_sensor)
	add_child_autofree(_agent)

	_agent.evaluate_options(0.1)
	_complete_query(_search_space)

	assert_eq(_agent.get_blackboard("nqs_result"), _search_space.query_results[0])
	assert_eq(_agent.get_blackboard("nqs_result"), _search_space.parent_node.get_child(0))
	assert_almost_eq(_sensor.sensor_value, _search_space.query_result_scores[0], 0.0001)

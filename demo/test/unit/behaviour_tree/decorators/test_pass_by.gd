extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const BT = preload("res://test/unit/behaviour_tree/support/bt_helpers.gd")

const PASS_BY_SCRIPT := "res://test/unit/behaviour_tree/decorators/scripts/counting_pass_by.gd"


func test_off_tree_tick_runs_the_script_hook() -> void:
	var node = load(PASS_BY_SCRIPT).new()
	var root: NNBTRoot = BT.build_root(node)

	assert_eq(root.tick(0.25), NNBTNodes.SUCCESS)
	assert_eq(node.tick_count, 1, "on_tick must run when the root is not in the SceneTree")
	assert_almost_eq(node.last_delta, 0.25, 0.0001)

	root.free()


func test_script_attached_after_entering_the_tree_runs_the_hook() -> void:
	var node: NNBTPassBy = NNBTPassBy.new()
	var root: NNBTRoot = BT.build_root(node)
	add_child_autofree(root)

	node.set_script(load(PASS_BY_SCRIPT))

	assert_eq(root.tick(0.1), NNBTNodes.SUCCESS)
	assert_eq(node.get("tick_count"), 1, "on_tick must be detected when the node ticks, not only on tree entry")

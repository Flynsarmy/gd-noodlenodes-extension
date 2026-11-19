extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

const Fixtures = preload("res://test/support/fixtures.gd")
const STHelpers = preload("res://test/unit/state_tree/support/st_helpers.gd")


func test_highest_scoring_child_is_entered_at_every_level() -> void:
	var _root: NNSTRoot = NNSTRoot.new()
	var _low: NNSTNode = NNSTNode.new()
	var _high: NNSTNode = NNSTNode.new()
	var _grandchild_low: NNSTNode = NNSTNode.new()
	var _grandchild_high: NNSTNode = NNSTNode.new()

	_root.child_state_selection_rule = STHelpers.UTILITY_SCORING
	_high.child_state_selection_rule = STHelpers.UTILITY_SCORING
	_root.add_child(_low)
	_root.add_child(_high)
	_high.add_child(_grandchild_low)
	_high.add_child(_grandchild_high)
	for node in [_high, _grandchild_high]:
		node.add_child(Fixtures.consideration(0.5))
	# Selection happens on entering the tree, so the hierarchy must be complete first.
	Fixtures.add_manual_st_root(self, _root)

	assert_false(_low.get_is_active())
	assert_true(_high.get_is_active())
	assert_eq(_high.score, 0.5)
	assert_false(_grandchild_low.get_is_active())
	assert_true(_grandchild_high.get_is_active())

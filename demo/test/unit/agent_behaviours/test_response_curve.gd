extends GutTest

const Fixtures = preload("res://test/support/fixtures.gd")
const NqsHelpers = preload("res://test/unit/node_query_system/support/nqs_helpers.gd")
const NON_CURVE_ERROR := "NNConsideration::set_activation_curve(): activation_curve must be a Curve or an NNResponseCurve."


func _curve(type: NNResponseCurve.CurveType, parameters := {}) -> NNResponseCurve:
	var curve := NNResponseCurve.new()
	curve.curve_type = type
	for property in parameters:
		curve.set(property, parameters[property])
	return curve


func test_each_type_gives_its_canonical_shape_with_default_parameters() -> void:
	var cases := [
		{"type": NNResponseCurve.CURVE_LINEAR, "expected": [0.0, 0.5, 1.0, 0.25]},
		{"type": NNResponseCurve.CURVE_POLYNOMIAL, "expected": [0.0, 0.25, 1.0, 0.0625]},
		{"type": NNResponseCurve.CURVE_EXPONENTIAL, "expected": [0.0, 0.26894, 1.0, 0.10154]},
		{"type": NNResponseCurve.CURVE_LOGISTIC, "expected": [0.00669, 0.5, 0.99331, 0.07586]},
		{"type": NNResponseCurve.CURVE_LOGIT, "expected": [0.0, 0.5, 1.0, 0.39014]},
		{"type": NNResponseCurve.CURVE_NORMAL, "expected": [0.00674, 1.0, 0.00674, 0.28650]},
		{"type": NNResponseCurve.CURVE_SINE, "expected": [0.0, 1.0, 0.0, 0.5]},
		{"type": NNResponseCurve.CURVE_STEP, "expected": [0.0, 1.0, 1.0, 0.0]},
	]
	var inputs := [0.0, 0.5, 1.0, 0.25]

	for test_case in cases:
		var curve := _curve(test_case["type"])
		for i in inputs.size():
			assert_almost_eq(curve.sample(inputs[i]), test_case["expected"][i], 0.0001,
					"type %d at x %s" % [test_case["type"], inputs[i]])


func test_input_and_result_are_clamped() -> void:
	var linear := _curve(NNResponseCurve.CURVE_LINEAR)
	assert_almost_eq(linear.sample(-1.0), 0.0, 0.0001)
	assert_almost_eq(linear.sample(2.0), 1.0, 0.0001)

	var raised := _curve(NNResponseCurve.CURVE_LINEAR, {"y_shift": 0.5})
	assert_almost_eq(raised.sample(0.25), 0.75, 0.0001)
	assert_almost_eq(raised.sample(1.0), 1.0, 0.0001)

	var lowered := _curve(NNResponseCurve.CURVE_LINEAR, {"y_shift": -0.5})
	assert_almost_eq(lowered.sample(0.25), 0.0, 0.0001)
	assert_almost_eq(lowered.sample(1.0), 0.5, 0.0001)


func test_x_shift_moves_the_curve_right() -> void:
	var linear := _curve(NNResponseCurve.CURVE_LINEAR, {"x_shift": 0.25})
	assert_almost_eq(linear.sample(0.25), 0.0, 0.0001)
	assert_almost_eq(linear.sample(0.75), 0.5, 0.0001)

	var logistic := _curve(NNResponseCurve.CURVE_LOGISTIC, {"x_shift": 0.25})
	assert_almost_eq(logistic.sample(0.75), 0.5, 0.0001)


func test_invert_flips_the_clamped_result() -> void:
	var inverted := _curve(NNResponseCurve.CURVE_LINEAR, {"invert": true})
	assert_almost_eq(inverted.sample(0.0), 1.0, 0.0001)
	assert_almost_eq(inverted.sample(0.25), 0.75, 0.0001)
	assert_almost_eq(inverted.sample(1.0), 0.0, 0.0001)


func test_consideration_scores_through_a_response_curve() -> void:
	var behaviour: NNBehaviour = NNBehaviour.new()
	var consideration := Fixtures.consideration(0.5)
	consideration.activation_curve = _curve(NNResponseCurve.CURVE_POLYNOMIAL)
	behaviour.add_child(consideration)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.25, 0.0001)


func test_consideration_still_accepts_a_hand_drawn_curve() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var behaviour: NNBehaviour = NNBehaviour.new()
	var consideration := Fixtures.consideration(0.5)
	consideration.activation_curve = curve
	behaviour.add_child(consideration)
	var agent := Fixtures.add_manual_agent(self, [behaviour])

	agent.evaluate_options(1.0)
	assert_almost_eq(consideration.score, 0.5, 0.0001)


func test_search_criterion_scores_through_a_response_curve() -> void:
	var container: Node2D = add_child_autofree(Node2D.new())
	var candidate: Node2D = Node2D.new()
	candidate.position = Vector2(10.0, 0.0)
	container.add_child(candidate)

	var criterion: NNDistanceToVector2SearchCriterion = NNDistanceToVector2SearchCriterion.new()
	criterion.distance_to_vector = Vector2.ZERO
	criterion.max_distance = 20.0
	criterion.use_for_filtering = false
	criterion.use_for_scoring = true
	criterion.activation_curve = _curve(NNResponseCurve.CURVE_POLYNOMIAL)

	var query := NqsHelpers.make_query(self, container, criterion)
	NqsHelpers.run_to_completion(self, NqsHelpers.make_nqs(self), query)

	assert_almost_eq(query.get_query_result_scores()[0], 0.0625, 0.0001, "the raw 0.25 distance score is squared")


func test_assigning_a_non_curve_resource_is_rejected() -> void:
	var consideration: NNConsideration = Fixtures.consideration(0.5)
	add_child_autofree(consideration)
	var response_curve := _curve(NNResponseCurve.CURVE_LINEAR)
	consideration.activation_curve = response_curve

	consideration.activation_curve = Resource.new()

	assert_engine_error(NON_CURVE_ERROR)
	assert_same(consideration.activation_curve, response_curve)


func test_preview_reflects_the_parameters() -> void:
	var curve := _curve(NNResponseCurve.CURVE_POLYNOMIAL)
	assert_almost_eq(curve.get_preview().sample(0.25), curve.sample(0.25), 0.001)

	curve.exponent = 3.0
	assert_almost_eq(curve.get_preview().sample(0.5), 0.125, 0.001)


func test_exponent_is_hidden_for_types_that_ignore_it() -> void:
	var curve := NNResponseCurve.new()
	var exponent_visible := func() -> bool:
		for property in curve.get_property_list():
			if property.name == "exponent":
				return property.usage & PROPERTY_USAGE_EDITOR != 0
		return false

	assert_false(exponent_visible.call())
	curve.curve_type = NNResponseCurve.CURVE_POLYNOMIAL
	assert_true(exponent_visible.call())
	curve.curve_type = NNResponseCurve.CURVE_STEP
	assert_false(exponent_visible.call())
	assert_eq(curve.exponent, 2.0, "the hidden value is kept")

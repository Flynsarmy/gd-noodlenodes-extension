extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# Regression tests for point grid base spacing validation.
#
# The base spacing drives the generation loop increments.  If a zero, negative
# or non-finite spacing were stored, generation would never make progress and
# later valid assignments would be rejected because the stored value was
# already corrupted.  Only finite, strictly positive spacing must be accepted.

const PROBE_SCRIPT := "res://test/support/point_grid_spacing_probe.gd"
const PROBE_TIMEOUT_MSEC := 10000

# A unique marker per test process avoids collisions when GUT runs concurrently
# on this shared machine, since user:// is shared by every copy of the project.
var _probe_marker: String = ""

const VALID_2D_A := Vector2(4.0, 3.0)
const VALID_2D_C := Vector2(0.5, 0.25)
const VALID_3D_A := Vector3(4.0, 3.0, 2.0)
const VALID_3D_C := Vector3(0.5, 0.25, 0.125)


func _make_space_2d() -> NNPointGrid2DSearchSpace:
	return add_child_autofree(NNPointGrid2DSearchSpace.new())


func _make_space_3d() -> NNPointGrid3DSearchSpace:
	return add_child_autofree(NNPointGrid3DSearchSpace.new())


func _assert_2d_spacing(space: NNPointGrid2DSearchSpace, expected: Vector2, reason: String) -> void:
	assert_eq(space.point_grid_base_spacing_vector, expected, reason)


func _assert_3d_spacing(space: NNPointGrid3DSearchSpace, expected: Vector3, reason: String) -> void:
	assert_eq(space.point_grid_base_spacing_vector, expected, reason)


# 2D rejection tests.


func test_2d_zero_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()
	space.point_grid_base_spacing_vector = VALID_2D_A

	space.point_grid_base_spacing_vector = Vector2(0.0, VALID_2D_A.y)
	_assert_2d_spacing(space, VALID_2D_A, "Zero x spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector2(VALID_2D_A.x, 0.0)
	_assert_2d_spacing(space, VALID_2D_A, "Zero y spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector2.ZERO
	_assert_2d_spacing(space, VALID_2D_A, "All-zero spacing must be rejected.")


func test_2d_negative_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()
	space.point_grid_base_spacing_vector = VALID_2D_A

	space.point_grid_base_spacing_vector = Vector2(-1.0, VALID_2D_A.y)
	_assert_2d_spacing(space, VALID_2D_A, "Negative x spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector2(VALID_2D_A.x, -1.0)
	_assert_2d_spacing(space, VALID_2D_A, "Negative y spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector2(-1.0, -1.0)
	_assert_2d_spacing(space, VALID_2D_A, "All-negative spacing must be rejected.")


func test_2d_non_finite_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()
	space.point_grid_base_spacing_vector = VALID_2D_A

	var invalid_values: Array[float] = [NAN, INF, -INF]
	for invalid: float in invalid_values:
		space.point_grid_base_spacing_vector = Vector2(invalid, VALID_2D_A.y)
		_assert_2d_spacing(space, VALID_2D_A, "Non-finite x spacing (%s) must be rejected." % str(invalid))
		space.point_grid_base_spacing_vector = Vector2(VALID_2D_A.x, invalid)
		_assert_2d_spacing(space, VALID_2D_A, "Non-finite y spacing (%s) must be rejected." % str(invalid))


func test_2d_recovery_after_rejection() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()

	space.point_grid_base_spacing_vector = VALID_2D_A
	_assert_2d_spacing(space, VALID_2D_A, "Valid spacing A must be stored.")

	space.point_grid_base_spacing_vector = Vector2.ZERO
	_assert_2d_spacing(space, VALID_2D_A, "Invalid spacing B must keep the previous value.")

	space.point_grid_base_spacing_vector = VALID_2D_C
	_assert_2d_spacing(space, VALID_2D_C, "Valid spacing C must be accepted after a rejection.")


func test_2d_audit_sequence_zero_then_one_retains_one() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()

	space.point_grid_base_spacing_vector = Vector2.ZERO
	space.point_grid_base_spacing_vector = Vector2.ONE

	_assert_2d_spacing(space, Vector2.ONE, "The corrective spacing must be retained after an invalid zero spacing.")


# 3D rejection tests.


func test_3d_zero_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()
	space.point_grid_base_spacing_vector = VALID_3D_A

	space.point_grid_base_spacing_vector = Vector3(0.0, VALID_3D_A.y, VALID_3D_A.z)
	_assert_3d_spacing(space, VALID_3D_A, "Zero x spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, 0.0, VALID_3D_A.z)
	_assert_3d_spacing(space, VALID_3D_A, "Zero y spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, VALID_3D_A.y, 0.0)
	_assert_3d_spacing(space, VALID_3D_A, "Zero z spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3.ZERO
	_assert_3d_spacing(space, VALID_3D_A, "All-zero spacing must be rejected.")


func test_3d_negative_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()
	space.point_grid_base_spacing_vector = VALID_3D_A

	space.point_grid_base_spacing_vector = Vector3(-1.0, VALID_3D_A.y, VALID_3D_A.z)
	_assert_3d_spacing(space, VALID_3D_A, "Negative x spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, -1.0, VALID_3D_A.z)
	_assert_3d_spacing(space, VALID_3D_A, "Negative y spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, VALID_3D_A.y, -1.0)
	_assert_3d_spacing(space, VALID_3D_A, "Negative z spacing must be rejected.")
	space.point_grid_base_spacing_vector = Vector3(-1.0, -1.0, -1.0)
	_assert_3d_spacing(space, VALID_3D_A, "All-negative spacing must be rejected.")


func test_3d_non_finite_component_on_each_axis_is_rejected() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()
	space.point_grid_base_spacing_vector = VALID_3D_A

	var invalid_values: Array[float] = [NAN, INF, -INF]
	for invalid: float in invalid_values:
		space.point_grid_base_spacing_vector = Vector3(invalid, VALID_3D_A.y, VALID_3D_A.z)
		_assert_3d_spacing(space, VALID_3D_A, "Non-finite x spacing (%s) must be rejected." % str(invalid))
		space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, invalid, VALID_3D_A.z)
		_assert_3d_spacing(space, VALID_3D_A, "Non-finite y spacing (%s) must be rejected." % str(invalid))
		space.point_grid_base_spacing_vector = Vector3(VALID_3D_A.x, VALID_3D_A.y, invalid)
		_assert_3d_spacing(space, VALID_3D_A, "Non-finite z spacing (%s) must be rejected." % str(invalid))


func test_3d_recovery_after_rejection() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()

	space.point_grid_base_spacing_vector = VALID_3D_A
	_assert_3d_spacing(space, VALID_3D_A, "Valid spacing A must be stored.")

	space.point_grid_base_spacing_vector = Vector3.ZERO
	_assert_3d_spacing(space, VALID_3D_A, "Invalid spacing B must keep the previous value.")

	space.point_grid_base_spacing_vector = VALID_3D_C
	_assert_3d_spacing(space, VALID_3D_C, "Valid spacing C must be accepted after a rejection.")


func test_3d_audit_sequence_zero_then_one_retains_one() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()

	space.point_grid_base_spacing_vector = Vector3.ZERO
	space.point_grid_base_spacing_vector = Vector3.ONE

	_assert_3d_spacing(space, Vector3.ONE, "The corrective spacing must be retained after an invalid zero spacing.")


# Generation tests.


func _make_generated_space_2d(grid_size: Vector2, spacing: Vector2) -> NNPointGrid2DSearchSpace:
	var parent: Node2D = add_child_autofree(Node2D.new())
	var space: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space.grid_size = grid_size
	space.point_grid_base_spacing_vector = spacing
	space.point_grid_lattice_vector = Vector2.ZERO
	space.use_navigation_mesh_positions = false
	space.point_grid_parent_node = parent
	parent.add_child(space)
	return space


func _make_generated_space_3d(grid_size: Vector3, spacing: Vector3) -> NNPointGrid3DSearchSpace:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var space: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space.grid_size = grid_size
	space.point_grid_base_spacing_vector = spacing
	space.point_grid_lattice_vector = Vector3.ZERO
	space.use_navigation_mesh_positions = false
	space.point_grid_parent_node = parent
	parent.add_child(space)
	return space


func test_2d_generation_uses_fractional_spacing() -> void:
	var space: NNPointGrid2DSearchSpace = _make_generated_space_2d(Vector2(2.0, 2.0), VALID_2D_C)

	assert_eq(space.point_grid_base_spacing_vector, VALID_2D_C, "Fractional spacing must be accepted.")
	# 5 x values (-1 ... 1 step 0.5) and 9 y values (-1 ... 1 step 0.25).  Each
	# point also emits its lattice point (zero lattice vector), so 2 * 5 * 9.
	assert_eq(space.point_grid.size(), 90, "Generation must use the fractional spacing increments.")

	var positions: Dictionary = {}
	for node: Node2D in space.point_grid:
		positions[node.position] = true
	assert_true(positions.has(Vector2(0.5, 0.25)), "Fractional positions must be generated.")

	# The destructor bug is fixed separately; clear the managed array first so
	# it cannot obscure these spacing assertions.
	space.point_grid = []


func test_3d_generation_uses_fractional_spacing() -> void:
	var space: NNPointGrid3DSearchSpace = _make_generated_space_3d(Vector3(0.5, 0.5, 0.5), VALID_3D_C)

	assert_eq(space.point_grid_base_spacing_vector, VALID_3D_C, "Fractional spacing must be accepted.")
	# 2 x values (-0.25 ... 0.25 step 0.5), 3 y values (step 0.25) and 5 z
	# values (step 0.125).  Each point also emits its lattice point.
	assert_eq(space.point_grid.size(), 60, "Generation must use the fractional spacing increments.")

	var positions: Dictionary = {}
	for node: Node3D in space.point_grid:
		positions[node.position] = true
	assert_true(positions.has(Vector3(0.25, 0.0, 0.125)), "Fractional positions must be generated.")

	space.point_grid = []


func test_2d_generation_with_integer_spacing_is_unchanged() -> void:
	var space: NNPointGrid2DSearchSpace = _make_generated_space_2d(Vector2(2.0, 2.0), Vector2.ONE)

	# 3 x values and 3 y values (-1 ... 1 step 1), doubled by the lattice point.
	assert_eq(space.point_grid.size(), 18)
	assert_eq(space.point_grid_base_spacing_vector, Vector2.ONE)

	space.point_grid = []


# Bounded hang regression.


func _remove_probe_marker() -> void:
	if _probe_marker != "" and FileAccess.file_exists(_probe_marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_probe_marker))


func test_probe_zero_spacing_sequence_terminates_within_deadline() -> void:
	_probe_marker = "user://point_grid_spacing_probe_%d_%d_ok.txt" % [OS.get_process_id(), Time.get_ticks_usec()]
	_remove_probe_marker()

	var pid: int = OS.create_process(
			OS.get_executable_path(),
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"-s",
				PROBE_SCRIPT,
				"--",
				_probe_marker,
			])
	assert_gt(pid, 0, "The bounded probe process must start.")
	if pid <= 0:
		return

	var deadline_msec: int = Time.get_ticks_msec() + PROBE_TIMEOUT_MSEC
	var terminated_in_time: bool = false
	while Time.get_ticks_msec() < deadline_msec:
		if not OS.is_process_running(pid):
			terminated_in_time = true
			break
		OS.delay_msec(50)

	if not terminated_in_time and OS.is_process_running(pid):
		OS.kill(pid)

	assert_true(
			terminated_in_time,
			"The zero spacing recovery probe must terminate before the %d ms deadline." % PROBE_TIMEOUT_MSEC)
	assert_true(
			FileAccess.file_exists(_probe_marker),
			"The probe must write its completion marker after generating both grids.")

	_remove_probe_marker()

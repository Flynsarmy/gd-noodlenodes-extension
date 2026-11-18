extends GutTest
@warning_ignore('unused_parameter')
@warning_ignore('return_value_discarded')

# The base spacing drives the generation loop increments, so a zero, negative or
# non-finite spacing would make generation loop forever.

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


func test_2d_invalid_spacing_is_rejected_and_keeps_the_last_valid_value() -> void:
	var space: NNPointGrid2DSearchSpace = _make_space_2d()
	space.point_grid_base_spacing_vector = VALID_2D_A

	for invalid: float in [0.0, -1.0, NAN, INF, -INF]:
		for spacing in [Vector2(invalid, VALID_2D_A.y), Vector2(VALID_2D_A.x, invalid)]:
			space.point_grid_base_spacing_vector = spacing
			_assert_2d_spacing(space, VALID_2D_A, "%s must be rejected" % spacing)

	space.point_grid_base_spacing_vector = VALID_2D_C
	_assert_2d_spacing(space, VALID_2D_C, "a valid spacing is accepted after a rejection")


func test_3d_invalid_spacing_is_rejected_and_keeps_the_last_valid_value() -> void:
	var space: NNPointGrid3DSearchSpace = _make_space_3d()
	space.point_grid_base_spacing_vector = VALID_3D_A

	for invalid: float in [0.0, -1.0, NAN, INF, -INF]:
		for spacing in [
			Vector3(invalid, VALID_3D_A.y, VALID_3D_A.z),
			Vector3(VALID_3D_A.x, invalid, VALID_3D_A.z),
			Vector3(VALID_3D_A.x, VALID_3D_A.y, invalid),
		]:
			space.point_grid_base_spacing_vector = spacing
			_assert_3d_spacing(space, VALID_3D_A, "%s must be rejected" % spacing)

	space.point_grid_base_spacing_vector = VALID_3D_C
	_assert_3d_spacing(space, VALID_3D_C, "a valid spacing is accepted after a rejection")


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


func test_2d_generation_with_integer_spacing() -> void:
	var space: NNPointGrid2DSearchSpace = _make_generated_space_2d(Vector2(2.0, 2.0), Vector2.ONE)

	# 3 x values and 3 y values (-1 ... 1 step 1), doubled by the lattice point.
	assert_eq(space.point_grid.size(), 18)
	assert_eq(space.point_grid_base_spacing_vector, Vector2.ONE)


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

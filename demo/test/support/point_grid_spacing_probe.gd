extends SceneTree

# Runs in a subprocess so a generation hang can be detected: assigns zero then ONE
# spacing, generates a grid and only then writes the marker. No test_ prefix, so
# GUT does not collect it.

const DEFAULT_MARKER_PATH := "user://point_grid_spacing_probe_ok.txt"

var _marker_path: String = DEFAULT_MARKER_PATH


func _initialize() -> void:
	# The GUT test passes a unique marker path so concurrent runs on the shared
	# machine cannot delete or observe each other's completion marker.
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not user_args.is_empty():
		_marker_path = user_args[0]
	call_deferred("_run")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _run() -> void:
	var probe_root: Node = Node.new()
	root.add_child(probe_root)

	var parent_2d: Node2D = Node2D.new()
	probe_root.add_child(parent_2d)

	var space_2d: NNPointGrid2DSearchSpace = NNPointGrid2DSearchSpace.new()
	space_2d.point_grid_base_spacing_vector = Vector2.ZERO
	space_2d.point_grid_base_spacing_vector = Vector2.ONE
	if space_2d.point_grid_base_spacing_vector != Vector2.ONE:
		_fail("2D corrective spacing was not retained: %s" % str(space_2d.point_grid_base_spacing_vector))
		return

	space_2d.grid_size = Vector2(2.0, 2.0)
	space_2d.point_grid_lattice_vector = Vector2.ZERO
	space_2d.use_navigation_mesh_positions = false
	space_2d.point_grid_parent_node = parent_2d
	parent_2d.add_child(space_2d)
	if space_2d.point_grid.is_empty():
		_fail("2D generation produced an empty point grid.")
		return
	space_2d.point_grid = []

	var parent_3d: Node3D = Node3D.new()
	probe_root.add_child(parent_3d)

	var space_3d: NNPointGrid3DSearchSpace = NNPointGrid3DSearchSpace.new()
	space_3d.point_grid_base_spacing_vector = Vector3.ZERO
	space_3d.point_grid_base_spacing_vector = Vector3.ONE
	if space_3d.point_grid_base_spacing_vector != Vector3.ONE:
		_fail("3D corrective spacing was not retained: %s" % str(space_3d.point_grid_base_spacing_vector))
		return

	space_3d.grid_size = Vector3(1.0, 1.0, 1.0)
	space_3d.point_grid_lattice_vector = Vector3.ZERO
	space_3d.use_navigation_mesh_positions = false
	space_3d.point_grid_parent_node = parent_3d
	parent_3d.add_child(space_3d)
	if space_3d.point_grid.is_empty():
		_fail("3D generation produced an empty point grid.")
		return
	space_3d.point_grid = []

	var marker: FileAccess = FileAccess.open(_marker_path, FileAccess.WRITE)
	if marker == null:
		_fail("Could not open the probe marker file at %s." % _marker_path)
		return
	marker.store_string("ok")
	marker.close()

	quit(0)

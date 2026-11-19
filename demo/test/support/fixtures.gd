## Fixture builders shared across subsystems. Preload with
## `const Fixtures = preload("res://test/support/fixtures.gd")`.


static func add_manual_st_root(test: GutTest, root: NNSTRoot = null) -> NNSTRoot:
	if root == null:
		root = NNSTRoot.new()
	root.process_thread = NNSTRoot.MANUAL
	return test.add_child_autofree(root)


static func consideration(value: float, enabled := true) -> NNConsideration:
	var result := NNConsideration.new()
	result.activation_input_value = value
	result.is_enabled = enabled
	return result


static func behaviour(value: float, node_name := "") -> NNBehaviour:
	var result := NNBehaviour.new()
	if node_name != "":
		result.name = node_name
	result.add_child(consideration(value))
	return result


static func add_manual_agent(test: GutTest, children: Array = []) -> NNAgent:
	var agent := NNAgent.new()
	agent.process_thread = NNAgent.MANUAL
	for child in children:
		agent.add_child(child)
	return test.add_child_autofree(agent)


static func save_serialised_scene(test: GutTest, scene_root: Node, path: String) -> String:
	var packed := PackedScene.new()
	test.assert_eq(packed.pack(scene_root), OK, "packing the scene succeeds")
	test.assert_eq(ResourceSaver.save(packed, path), OK, "saving the scene succeeds")
	var file := FileAccess.open(path, FileAccess.READ)
	test.assert_not_null(file, "the saved scene is readable")
	var text := file.get_as_text()
	file.close()
	return text


static func delete_serialised_scene(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

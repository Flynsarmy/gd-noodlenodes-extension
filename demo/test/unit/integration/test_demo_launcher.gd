extends GutTest

const LAUNCHER_PATH := "res://main.tscn"


func _demo_folders() -> PackedStringArray:
	var folders := PackedStringArray()
	for folder in DirAccess.get_directories_at("res://"):
		if folder.begins_with("demo_"):
			folders.append(folder)
	return folders


func _button_scenes(launcher: Node) -> PackedStringArray:
	var scenes := PackedStringArray()
	for button in launcher.find_children("*", "Button", true, false):
		scenes.append(button.get_meta(&"scene", ""))
	return scenes


func test_every_demo_folder_has_a_button_that_opens_an_existing_scene() -> void:
	var launcher: Node = add_child_autofree(load(LAUNCHER_PATH).instantiate())
	var scenes := _button_scenes(launcher)
	var folders := _demo_folders()
	assert_gt(folders.size(), 0, "No demo_* folders found")

	for folder in folders:
		var prefix := "res://%s/" % folder
		var matching := Array(scenes).filter(func(scene: String) -> bool: return scene.begins_with(prefix))
		assert_eq(matching.size(), 1, "Expected one launcher button for %s" % folder)
	for scene in scenes:
		assert_true(ResourceLoader.exists(scene, "PackedScene"), "Launcher scene missing: %s" % scene)

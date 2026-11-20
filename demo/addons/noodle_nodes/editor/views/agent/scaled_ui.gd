@tool
## Applies the editor display scale to the 1x pixel sizes authored in the agent
## view's scenes. Instanced sub-scenes scale themselves.

const EditorScale := preload("res://addons/noodle_nodes/editor/editor_scale.gd")


static func apply(root: Control) -> void:
	var scale := EditorScale.get_scale()
	if is_equal_approx(scale, 1.0):
		return
	var scene_path := root.scene_file_path
	_apply_to(root, scale)
	for node in root.find_children("*", "Control", true, false):
		if node.scene_file_path == "" or node.scene_file_path == scene_path:
			_apply_to(node, scale)


static func _apply_to(control: Control, scale: float) -> void:
	control.custom_minimum_size *= scale
	if control is BoxContainer:
		control.add_theme_constant_override("separation", roundi(control.get_theme_constant("separation") * scale))
	elif control is MarginContainer:
		for side in ["left", "top", "right", "bottom"]:
			var key: String = "margin_" + side
			control.add_theme_constant_override(key, roundi(control.get_theme_constant(key) * scale))
	elif control is SplitContainer:
		control.split_offset = roundi(control.split_offset * scale)
	if control is PanelContainer:
		var panel := control.get_theme_stylebox("panel")
		if panel != null:
			control.add_theme_stylebox_override("panel", _scale_style(panel, scale))
	elif control is ProgressBar:
		for style_name in ["background", "fill"]:
			var style := control.get_theme_stylebox(style_name)
			if style != null:
				control.add_theme_stylebox_override(style_name, _scale_style(style, scale))


static func _scale_style(style: StyleBox, scale: float) -> StyleBox:
	var copy := style.duplicate()
	copy.content_margin_left = _scaled(copy.content_margin_left, scale)
	copy.content_margin_top = _scaled(copy.content_margin_top, scale)
	copy.content_margin_right = _scaled(copy.content_margin_right, scale)
	copy.content_margin_bottom = _scaled(copy.content_margin_bottom, scale)
	if copy is StyleBoxFlat:
		copy.corner_radius_top_left = roundi(copy.corner_radius_top_left * scale)
		copy.corner_radius_top_right = roundi(copy.corner_radius_top_right * scale)
		copy.corner_radius_bottom_right = roundi(copy.corner_radius_bottom_right * scale)
		copy.corner_radius_bottom_left = roundi(copy.corner_radius_bottom_left * scale)
		copy.border_width_left = roundi(copy.border_width_left * scale)
		copy.border_width_top = roundi(copy.border_width_top * scale)
		copy.border_width_right = roundi(copy.border_width_right * scale)
		copy.border_width_bottom = roundi(copy.border_width_bottom * scale)
	return copy


static func _scaled(value: float, scale: float) -> float:
	return roundf(value * scale) if value >= 0.0 else value

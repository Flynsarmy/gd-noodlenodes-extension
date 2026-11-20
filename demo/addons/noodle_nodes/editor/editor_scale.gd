@tool
## Pixel sizes in the editor UI must follow the editor's display scale, or they
## render tiny on HiDPI screens. Headless tests and games get 1.0.


static func get_scale() -> float:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return 1.0
	return Engine.get_singleton("EditorInterface").get_editor_scale()


static func px(value: float) -> float:
	return value * get_scale()

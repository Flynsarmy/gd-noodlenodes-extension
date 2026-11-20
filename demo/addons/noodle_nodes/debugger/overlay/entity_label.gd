extends RichTextLabel
## One entity's active path, anchored above the entity in the overlay.

signal pressed(entity_id: int)

var entity_id := 0


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	pressed.emit(entity_id)
	accept_event()

extends RichTextLabel
## One entity's active path, anchored above the entity in the overlay.

signal pressed(owner_id: int)

var owner_id := 0


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	pressed.emit(owner_id)
	accept_event()

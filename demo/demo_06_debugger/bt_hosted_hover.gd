extends NNBTLeaf

# Always running so the hosted tree keeps an active path to show in the overlay.
func on_tick(_delta: float) -> Status:
	return RUNNING

extends NNBTLeaf

func on_tick(_delta: float) -> Status:
	var actor := get_actor()
	# Check if the distance is less than expected.
	if actor.sensor_distance.distance < 90:
		return SUCCESS # Success = Too close
	return FAILURE # Failure = Not too close

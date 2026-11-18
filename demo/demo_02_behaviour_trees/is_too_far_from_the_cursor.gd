extends NNBTLeaf

func on_tick(_delta: float) -> Status:
	var actor := get_actor()
	if actor.sensor_distance.distance > 150.0:
		return SUCCESS # Success = Far
	return FAILURE # Failure = Not far

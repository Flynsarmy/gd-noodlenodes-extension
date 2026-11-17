extends NNBTPassThrough

# NNBTTaskNodes declares on_tick as a Status-returning virtual method, so
# GDScript refuses to override it with a void signature. Awaiting makes the
# call return a non-int value at runtime, which is the non-int case this
# fixture covers: the tick result must be left untouched.
signal _never_emitted

func on_tick(_blackboard: Variant, _delta: float) -> Status:
	await _never_emitted
	return Status.SUCCESS

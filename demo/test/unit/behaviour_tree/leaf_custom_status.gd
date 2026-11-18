extends Node


# Untyped so on_tick can return non-int Variants; a "-> Status" override can only return ints.
var payload: Variant


func on_tick(_delta: float) -> Variant:
	return payload

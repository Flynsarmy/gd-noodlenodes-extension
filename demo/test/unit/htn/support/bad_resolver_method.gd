extends Node


# Untyped so it can return a non-Array; a typed NNHTNMethod override must return Array[Dictionary].
func on_resolve_arguments(_state: Dictionary, args: Dictionary) -> Variant:
	return args

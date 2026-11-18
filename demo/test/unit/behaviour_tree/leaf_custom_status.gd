extends Node


# Test fixture: an NNBTLeaf script whose on_tick returns an arbitrary Variant.
# A typed "-> Status" override can only ever return ints, so this fixture is
# needed to feed null/float/bool/string on_tick results into NNBTLeaf.tick().
var payload: Variant


func on_tick(_delta: float) -> Variant:
	return payload

extends "res://test/unit/htn/support/scripted_task.gd"

## Predicts which target was chosen, so a later sibling can depend on the argument.
func on_get_effects(_state: Dictionary, args: Dictionary) -> Dictionary:
	return {"chosen": args.get("target")}

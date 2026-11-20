@tool
## Display formatting for debugger values, shared by the editor shell and the
## in-game overlay so both render the same value the same way.


## A short, readable rendering of value.
static func format(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return "%.2f" % value
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return "(%.2f, %.2f)" % [vector2.x, vector2.y]
		TYPE_VECTOR3:
			var vector3: Vector3 = value
			return "(%.2f, %.2f, %.2f)" % [vector3.x, vector3.y, vector3.z]
		TYPE_NODE_PATH:
			var path: NodePath = value
			if path.is_empty():
				return "(none)"
			return str(path.get_name(path.get_name_count() - 1)) if path.get_name_count() > 0 else str(path)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value)
	return var_to_str(value)


## The full rendering of value, for tooltips. Empty when format() already shows everything.
static func full(value: Variant) -> String:
	var text := var_to_str(value)
	var shown := format(value)
	return "" if shown == text or shown == str(value) else text

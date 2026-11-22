@tool
## Display formatting for debugger values, shared by the editor shell and the
## in-game overlay so both render the same value the same way.

## Wire keys for Object values that survive the debugger as a reference rather
## than a class name string.
const RESOURCE_PATH_KEY := "__resource"
const RESOURCE_CLASS_KEY := "__resource_class"


## A short, readable rendering of value.
static func format(value: Variant) -> String:
	if is_resource_ref(value):
		var res_class := str(value.get(RESOURCE_CLASS_KEY, "Resource"))
		var path := resource_path(value)
		return res_class if path.is_empty() else "%s (%s)" % [path.get_file(), res_class]
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
	if is_resource_ref(value):
		return _stored_path(value)
	var text := var_to_str(value)
	var shown := format(value)
	return "" if shown == text or shown == str(value) else text


## True for the envelope the debugger writes for an Object reference.
static func is_resource_ref(value: Variant) -> bool:
	return value is Dictionary and (value.has(RESOURCE_PATH_KEY) or value.has(RESOURCE_CLASS_KEY))


## The path to open a resource from, or "" when it is not a loadable file.
static func resource_path(value: Variant) -> String:
	var path := _stored_path(value)
	if path.is_empty() or path.contains("::") or not ResourceLoader.exists(path):
		return ""
	return path


static func _stored_path(value: Variant) -> String:
	var path: Variant = value.get(RESOURCE_PATH_KEY) if value is Dictionary else null
	return path if path is String else ""

## NNBlackboardSchema builders shared by the blackboard and behaviour tree tests.


# Each declaration is name -> [type] or [type, default].
static func make_schema(declarations: Dictionary, allow_unknown_keys := true) -> NNBlackboardSchema:
	var schema := NNBlackboardSchema.new()
	schema.allow_unknown_keys = allow_unknown_keys
	for key_name in declarations:
		var declaration: Array = declarations[key_name]
		var entry := NNBlackboardKey.new()
		entry.key = key_name
		entry.value_type = declaration[0]
		if declaration.size() > 1:
			entry.has_default = true
			entry.default_value = declaration[1]
		schema.keys.append(entry)
	return schema


static func consume_errors(test: GutTest, expected: int, msg: String) -> void:
	var errors: Array = test.get_errors().filter(func(error) -> bool: return not error.handled)
	test.assert_eq(errors.size(), expected, msg)
	for error in errors:
		error.handled = true

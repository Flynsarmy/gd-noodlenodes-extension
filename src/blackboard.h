#pragma once

#include "blackboard_schema.h"

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class NNBlackboard : public Resource {
	GDCLASS(NNBlackboard, Resource)

private:
	// Typed as Dictionary<String, Variant>. A NIL value type accepts any value.
	Dictionary _values;
	Ref<NNBlackboardSchema> _schema;

	bool _check_write(const String &p_key, const Variant &p_value) const;
	void _install_defaults();

protected:
	static void _bind_methods();

public:
	NNBlackboard();
	~NNBlackboard();

	// Getters and setters for attributes.

	void set_values(const Dictionary &values);
	Dictionary get_values() const;
	void set_schema(const Ref<NNBlackboardSchema> &schema);
	Ref<NNBlackboardSchema> get_schema() const;

	// Handling functions.

	bool has_value(const String &key) const;
	Variant get_value(const String &key, const Variant &default_value = Variant()) const;
	bool set_value(const String &key, const Variant &value);
	bool apply_values(const Dictionary &values);
	bool erase_value(const String &key);
	void clear();

	Array keys() const;
	Dictionary get_debug_data() const;
	// The per-value sanitisation get_debug_data() applies, for other debug views of board values.
	static Variant sanitize_debug_value(const Variant &p_value);
};

} //namespace godot

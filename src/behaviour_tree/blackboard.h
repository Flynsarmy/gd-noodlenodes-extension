#pragma once

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

protected:
	static void _bind_methods();

public:
	NNBlackboard();
	~NNBlackboard();

	// Getters and setters for attributes.

	void set_values(const Dictionary &values);
	Dictionary get_values() const;

	// Handling functions.

	bool has_value(const String &key) const;
	Variant get_value(const String &key, const Variant &default_value = Variant()) const;
	bool set_value(const String &key, const Variant &value);
	bool erase_value(const String &key);
	void clear();

	Array keys() const;
	Dictionary get_debug_data() const;
};

} //namespace godot

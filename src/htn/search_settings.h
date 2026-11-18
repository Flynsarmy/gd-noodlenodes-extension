#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class NNHTNSearchSettings : public Resource {
	GDCLASS(NNHTNSearchSettings, Resource)

public:
	enum Policy {
		ORDERED,
		RANKED,
		LOWEST_COST,
	};

private:
	Policy _policy = ORDERED;
	int _max_expansions = 10000;
	int _max_time_ms = 0;
	int _max_binding_candidates = 256;
	int _max_history_attempts = 100;
	int _max_history_bytes = 2097152;
	int _max_trace_events = 5000;

protected:
	static void _bind_methods();

public:
	void set_policy(Policy p_policy);
	Policy get_policy() const;
	void set_max_expansions(int p_max_expansions);
	int get_max_expansions() const;
	void set_max_time_ms(int p_max_time_ms);
	int get_max_time_ms() const;
	void set_max_binding_candidates(int p_max_binding_candidates);
	int get_max_binding_candidates() const;
	void set_max_history_attempts(int p_max_history_attempts);
	int get_max_history_attempts() const;
	void set_max_history_bytes(int p_max_history_bytes);
	int get_max_history_bytes() const;
	void set_max_trace_events(int p_max_trace_events);
	int get_max_trace_events() const;

	PackedStringArray get_validation_errors() const;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNSearchSettings::Policy)

#pragma once

#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

class NNHTNExecutionSettings : public Resource {
	GDCLASS(NNHTNExecutionSettings, Resource)

public:
	enum InterruptionPolicy {
		IMMEDIATE,
		FINISH_CURRENT_STEP,
	};

private:
	InterruptionPolicy _interruption_policy = IMMEDIATE;
	bool _local_repair = false;
	double _switch_hysteresis = 0.0;

protected:
	static void _bind_methods();

public:
	void set_interruption_policy(InterruptionPolicy p_interruption_policy);
	InterruptionPolicy get_interruption_policy() const;
	void set_local_repair(bool p_local_repair);
	bool get_local_repair() const;
	void set_switch_hysteresis(double p_switch_hysteresis);
	double get_switch_hysteresis() const;

	PackedStringArray get_validation_errors() const;
};

} //namespace godot

VARIANT_ENUM_CAST(NNHTNExecutionSettings::InterruptionPolicy)

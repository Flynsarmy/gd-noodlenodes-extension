#include "task_nodes.h"

#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

NNBTTaskNodes::NNBTTaskNodes() {
}

NNBTTaskNodes::~NNBTTaskNodes() {
}

void NNBTTaskNodes::_bind_methods() {
	GDVIRTUAL_BIND(on_tick, "blackboard", "delta");
}

bool NNBTTaskNodes::_call_on_tick(Variant blackboard, float delta, Variant &r_result) const {
	if (!gdextension_interface::object_has_script_method(_owner, &_gdvirtual_on_tick_sn)) {
		return false;
	}

	GDExtensionCallError call_error;
	Variant args[2] = { blackboard, Variant(delta) };
	const Variant *arg_ptrs[2] = { &args[0], &args[1] };
	gdextension_interface::object_call_script_method(_owner, &_gdvirtual_on_tick_sn, (const GDExtensionConstVariantPtr *)arg_ptrs, 2, &r_result, &call_error);
	return call_error.error == GDEXTENSION_CALL_OK;
}

NNBTNodes::Status NNBTTaskNodes::_validate_on_tick_result(const Variant &p_result) const {
	const String accepted_values = "SKIP (-2), FAILURE (-1), RUNNING (0) or SUCCESS (1)";

	if (p_result.get_type() != Variant::INT) {
		ERR_PRINT(vformat("NNBTTaskNodes::on_tick(): Node '%s' (%s) returned a value of type '%s' ('%s'); on_tick must return one of %s. Treating the result as FAILURE.",
				get_name(), get_class(), Variant::get_type_name(p_result.get_type()).to_lower(), p_result.stringify(), accepted_values));
		return Status::FAILURE;
	}

	const int64_t value = p_result;
	if (value < static_cast<int64_t>(Status::SKIP) || value > static_cast<int64_t>(Status::SUCCESS)) {
		ERR_PRINT(vformat("NNBTTaskNodes::on_tick(): Node '%s' (%s) returned '%d'; on_tick must return one of %s. Treating the result as FAILURE.",
				get_name(), get_class(), value, accepted_values));
		return Status::FAILURE;
	}

	return static_cast<Status>(value);
}

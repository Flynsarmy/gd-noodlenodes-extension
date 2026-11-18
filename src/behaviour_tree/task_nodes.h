#pragma once

#include "nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/core/binder_common.hpp>
#include <godot_cpp/core/gdvirtual.gen.inc>

namespace godot {

class NNBTTaskNodes : public NNBTNodes {
	GDCLASS(NNBTTaskNodes, NNBTNodes)

private:
protected:
	static void _bind_methods();

	virtual Status on_tick(double delta) { return Status::FAILURE; };

	GDVIRTUAL1R(Status, on_tick, double);

	// Lifecycle script hooks. A script may implement any subset of them; the
	// calls are silent when a hook is not defined.
	virtual void _on_before_run(float delta) override;
	virtual void _on_after_run(float delta) override;
	virtual void _on_interrupt(float delta) override;

	GDVIRTUAL1(on_before_run, double);
	GDVIRTUAL1(on_after_run, double);
	GDVIRTUAL1(on_interrupt, double);

	// Rejects on_tick return values outside the documented Status enum.
	// On rejection it reports a single engine error and returns FAILURE.
	Status _validate_on_tick_result(const Variant &p_result) const;

	// Calls the script's on_tick override and preserves its raw Variant result
	// so the type can be validated before any Status coercion. Returns false
	// when the script does not implement on_tick or the call fails.
	bool _call_on_tick(float delta, Variant &r_result) const;

public:
	NNBTTaskNodes();
	~NNBTTaskNodes();
};

} //namespace godot

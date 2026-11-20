#pragma once

#include "guard.h"

namespace godot {

class NNSTNotGuard : public NNSTGuard {
	GDCLASS(NNSTNotGuard, NNSTGuard)

protected:
	static void _bind_methods();
	Ref<NNSTGuard> _guard;

public:
	void set_guard(const Ref<NNSTGuard> &p_guard); // Setter
	Ref<NNSTGuard> get_guard() const { return _guard; } // Getter
	virtual bool is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) override;
	virtual int get_supported_trigger_types() const override;
#ifdef DEBUG_ENABLED
	virtual String get_debug_description() const override;
#endif
};

} //namespace godot

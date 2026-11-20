#pragma once

#include "guard.h"

namespace godot {

class NNSTAllOfGuard : public NNSTGuard {
	GDCLASS(NNSTAllOfGuard, NNSTGuard)

protected:
	static void _bind_methods();
	TypedArray<NNSTGuard> guards;

public:
	virtual bool is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) override;
	virtual int get_supported_trigger_types() const override;
	TypedArray<NNSTGuard> get_guards() const;
	void set_guards(const TypedArray<NNSTGuard> &p_guards);
#ifdef DEBUG_ENABLED
	virtual String get_debug_description() const override;
#endif
};

} //namespace godot

#pragma once

#include "../expression_util.h"
#include "guard.h"

namespace godot {

class NNSTExpressionGuard : public NNSTGuard {
	GDCLASS(NNSTExpressionGuard, NNSTGuard)

protected:
	static void _bind_methods();
	String expression;

public:
	virtual bool is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state) override;
	virtual int get_supported_trigger_types() const override;
	String get_expression() const;
	void set_expression(const String &p_expression);
#ifdef DEBUG_ENABLED
	virtual String get_debug_description() const override;
#endif

private:
	PackedStringArray _read_keys;
	mutable NNCachedExpression _cache;
};

} //namespace godot

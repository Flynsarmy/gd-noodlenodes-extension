#pragma once

#include "root.h"
#include "transition.h"

#include <godot_cpp/core/gdvirtual.gen.inc>

namespace godot {

class NNSTGuard : public Resource {
	GDCLASS(NNSTGuard, Resource)

protected:
	static void _bind_methods();

	GDVIRTUAL2R(bool, on_is_satisfied, NNSTTransition *, NNSTTickedNodes *);
	GDVIRTUAL0RC(int, on_get_supported_trigger_types);

public:
	virtual bool is_satisfied(NNSTTransition *p_transition, NNSTTickedNodes *p_state);

	// Returns a bit mask of NNSTRoot::TriggerType values that describe which
	// changes can affect this guard's result. Automatic transitions use this to
	// decide when they need to be re-evaluated. The base implementation reports
	// NONE, so custom guards that do not implement on_get_supported_trigger_types()
	// are only checked on STATE_ENTER (which every automatic transition supports).
	virtual int get_supported_trigger_types() const;

#ifdef DEBUG_ENABLED
	// Display-ready description of the guard's configuration, used by the
	// debugger's st_guard events and the state-tree snapshot.
	virtual String get_debug_description() const;
	// Display-ready summary of the latest evaluation, including sub-guard
	// results for composite guards. Empty when it was not built.
	String get_debug_detail() const;
	void set_debug_detail(const String &p_detail);

private:
	String _debug_last_detail;
#endif
};

#ifdef DEBUG_ENABLED
// True while the root p_state belongs to is watched, i.e. while guard
// evaluation detail is worth building.
bool nn_guard_debug_active(const NNSTTickedNodes *p_state);
#endif

} //namespace godot

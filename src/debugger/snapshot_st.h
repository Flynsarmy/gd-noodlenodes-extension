#pragma once

#ifdef DEBUG_ENABLED

#include <godot_cpp/classes/ref.hpp>

namespace godot {

class NNDebugRoot;
class NNSTGuard;

// "event" | "state_enter" | "property_change" | "state_change", or "".
const char *nn_debug_trigger_name(int p_trigger_type);

// Records st_guard for the evaluation p_transition just ran. The id and guard
// are captured before the guard runs, because user code may free the
// transition. p_debug_root may be null, in which case nothing is built.
void nn_debug_record_guard(NNDebugRoot *p_debug_root, int64_t p_transition_id, const Ref<NNSTGuard> &p_guard, const char *p_trigger, bool p_result);

} //namespace godot

#endif

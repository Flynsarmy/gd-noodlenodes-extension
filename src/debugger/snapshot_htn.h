#pragma once

#ifdef DEBUG_ENABLED

#include <godot_cpp/classes/ref.hpp>

namespace godot {

class NNHTNPlanStep;
class NNHTNRoot;

// "pending" | "running" | "verifying" | "staged" | "succeeded" | "failed" |
// "cancelled". p_state is an NNHTNPlanStep::State.
const char *nn_debug_step_state_name(int p_state);
// "found" | "no_plan" | "budget_exhausted" | "invalid_domain".
const char *nn_debug_search_status_name(int p_status);

// Records htn_step for p_step's current state on p_root's event log.
void nn_debug_record_htn_step(NNHTNRoot *p_root, const Ref<NNHTNPlanStep> &p_step);

} //namespace godot

#endif

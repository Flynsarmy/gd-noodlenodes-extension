#pragma once

#include "plan_step.h"

#include <godot_cpp/classes/ref.hpp>
#include <vector>

namespace godot {

namespace NNHTNPlanUtils {

// Sets every frame's span to the inclusive indices, within r_plan, of the steps sharing its frame_id.
void annotate_spans(std::vector<Ref<NNHTNPlanStep>> &r_plan);

// Whether p_candidate is the same occurrence as p_current: the same template, call path, arguments,
// captured effects and committed keys, produced by the same decompositions. Frame ids and spans are ignored.
// A concurrent group branch never matches.
bool occurrence_matches(const Ref<NNHTNPlanStep> &p_current, const Ref<NNHTNPlanStep> &p_candidate);

} //namespace NNHTNPlanUtils

} //namespace godot

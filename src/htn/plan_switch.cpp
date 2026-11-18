#include "plan_switch.h"

#include "plan_utils.h"
#include "task.h"

using namespace godot;

NNHTNPlanSwitch::Decision NNHTNPlanSwitch::decide(NNHTNSearch::Result &r_result, NNHTNRunner &r_runner, const NNHTNExecutionSettings &p_execution, NNHTNSearchSettings::Policy p_policy, bool p_urgent) {
	if (r_result.plan.empty()) {
		// A cutoff without a plan proves nothing about the running plan.
		if (r_result.status == NNHTNSearch::BUDGET_EXHAUSTED && r_runner.has_plan()) {
			return KEEP;
		}
		clear(r_runner);
		return ABANDON;
	}

	const Ref<NNHTNPlanStep> current = r_runner.get_current_step();
	const bool current_available = current.is_valid() && r_runner.is_current_available();
	// An active parallel group is committed as a whole, so it counts as started.
	const bool started = current_available && r_runner.is_running(current);
	const bool matches = started && NNHTNPlanUtils::occurrence_matches(current, r_result.plan.front());

	if (!p_urgent && current_available) {
		const double hysteresis = p_execution.get_switch_hysteresis();
		if (hysteresis > 0.0 && p_policy == NNHTNSearchSettings::RANKED && r_result.utility - _installed_utility <= hysteresis) {
			return KEEP;
		}
		if (started && p_execution.get_interruption_policy() == NNHTNExecutionSettings::FINISH_CURRENT_STEP) {
			_waiting = true;
			_committed = current;
			_candidate.clear();
			if (matches) {
				_candidate = r_result.plan;
			}
			_candidate_utility = r_result.utility;
			_candidate_keys = r_result.dependency_keys;
			_candidate_wildcard = r_result.dependencies_wildcard;
			r_runner.set_holding(true);
			return DEFER;
		}
	}

	if (matches && current->get_task()->get_resumable()) {
		// The retained occurrence joins the new plan, so it takes the new plan's frames for later repairs.
		current->provenance() = r_result.plan.front()->provenance();
		r_result.plan.front() = current;
	}
	clear(r_runner);
	return INSTALL;
}

void NNHTNPlanSwitch::note_installed(double p_utility) {
	_installed_utility = p_utility;
}

bool NNHTNPlanSwitch::is_waiting() const {
	return _waiting;
}

bool NNHTNPlanSwitch::take_ready(NNHTNRunner &r_runner, Ready &r_ready) {
	if (!_waiting || r_runner.is_running(_committed)) {
		return false;
	}
	r_ready = Ready();
	if (_committed->get_state() == NNHTNPlanStep::SUCCEEDED && _candidate.size() > 1) {
		_committed->provenance() = _candidate.front()->provenance();
		r_ready.install = true;
		r_ready.completed.push_back(_committed);
		r_ready.steps.assign(_candidate.begin() + 1, _candidate.end());
		r_ready.utility = _candidate_utility;
		r_ready.dependency_keys = _candidate_keys;
		r_ready.dependencies_wildcard = _candidate_wildcard;
	}
	clear(r_runner);
	return true;
}

void NNHTNPlanSwitch::clear(NNHTNRunner &r_runner) {
	_waiting = false;
	_committed.unref();
	_candidate.clear();
	_candidate_keys.clear();
	r_runner.set_holding(false);
}

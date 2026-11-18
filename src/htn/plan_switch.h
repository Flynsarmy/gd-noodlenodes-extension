#pragma once

#include "execution_settings.h"
#include "runner.h"
#include "search.h"

namespace godot {

// Decides what a search result does to the running plan, and holds a candidate that
// waits for the started step to finish under FINISH_CURRENT_STEP.
class NNHTNPlanSwitch {
public:
	enum Decision {
		// Install the result's plan. Its first step may be the retained started occurrence.
		INSTALL,
		// The result proves there is no plan; drop the running one.
		ABANDON,
		// Keep the running plan and ignore the result.
		KEEP,
		// Keep the running plan until its started step finishes.
		DEFER,
	};

	// A deferred candidate that is ready, because its committed step or group is no longer running.
	struct Ready {
		// False when the candidate cannot follow the committed step, so a new search must run.
		bool install = false;
		std::vector<Ref<NNHTNPlanStep>> steps;
		std::vector<Ref<NNHTNPlanStep>> completed;
		double utility = 0.0;
		HashSet<String> dependency_keys;
		bool dependencies_wildcard = false;
	};

	Decision decide(NNHTNSearch::Result &r_result, NNHTNRunner &r_runner, const NNHTNExecutionSettings &p_execution, NNHTNSearchSettings::Policy p_policy, bool p_urgent);
	void note_installed(double p_utility);

	bool is_waiting() const;
	// Returns true, releasing the runner, once the committed step or group is no longer running.
	bool take_ready(NNHTNRunner &r_runner, Ready &r_ready);
	// Drops any waiting candidate and releases the runner.
	void clear(NNHTNRunner &r_runner);

private:
	bool _waiting = false;
	Ref<NNHTNPlanStep> _committed;
	// The whole candidate, starting with the step matching _committed, or empty when none matched.
	std::vector<Ref<NNHTNPlanStep>> _candidate;
	double _candidate_utility = 0.0;
	HashSet<String> _candidate_keys;
	bool _candidate_wildcard = false;
	double _installed_utility = 0.0;
};

} //namespace godot

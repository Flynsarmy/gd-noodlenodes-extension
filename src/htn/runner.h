#pragma once

#include "plan_step.h"

#include <godot_cpp/classes/ref.hpp>
#include <vector>

namespace godot {

class NNHTNRoot;

// Executes an installed plan against the live board, one occurrence at a time
// except for the branches of a parallel group, which advance together.
class NNHTNRunner {
public:
	enum Outcome {
		NONE,
		COMPLETED,
		FAILED,
	};

	// The plan as it stood when a step failed, for local repair.
	struct Failure {
		Ref<NNHTNPlanStep> step;
		std::vector<Ref<NNHTNPlanStep>> completed;
		// Starts with the failed step.
		std::vector<Ref<NNHTNPlanStep>> remaining;
	};

	// The owner must outlive the runner.
	void configure(NNHTNRoot *p_owner);

	// Installs p_steps after p_completed, which already ran. The started occurrence, or every
	// started branch of the active group, is cancelled unless it is p_steps' first step, which
	// then keeps running.
	void set_plan(std::vector<Ref<NNHTNPlanStep>> &&p_steps, std::vector<Ref<NNHTNPlanStep>> &&p_completed = {});
	// Cancels the started occurrence and drops the plan. From inside a hook the
	// drop is deferred until the hook returns, so the hook never sees itself cancelled.
	void abandon();
	// While held, the runner finishes the started occurrence or active group but starts no other.
	void set_holding(bool p_holding);

	// Runs occurrences until one is still running or the plan ends. COMPLETED and
	// FAILED report that the plan ended during this call.
	Outcome advance(double p_delta);

	bool has_plan() const;
	Ref<NNHTNPlanStep> get_current_step() const;
	const std::vector<Ref<NNHTNPlanStep>> &get_steps() const;
	const std::vector<Ref<NNHTNPlanStep>> &get_completed_steps() const;
	// Whether the current step, or every unfinished branch of the current group and the group
	// itself, passes the checks made before it is ticked.
	bool is_current_available() const;
	// Started and not finished, or a branch of the group that is under way.
	bool is_running(const Ref<NNHTNPlanStep> &p_step) const;
	// The failure that ended the last plan, cleared by taking it or by the next plan.
	Failure take_failure();

private:
	enum class Progress {
		// Still running, or a hook requested an abandon.
		WAITING,
		FINISHED,
		FAILED,
	};

	NNHTNRoot *_owner = nullptr;
	std::vector<Ref<NNHTNPlanStep>> _steps;
	std::vector<Ref<NNHTNPlanStep>> _completed;
	Failure _failure;
	bool _executing = false;
	bool _abandon_requested = false;
	bool _holding = false;
	// The parallel_group_id of the group under way at the front of the plan, or 0.
	int64_t _active_group_id = 0;

	// The checks made before p_step is ticked. Returns the failure reason, or nullptr. A verifying
	// step is not held to its start preconditions, which its own action may have consumed.
	const char *_check(const Ref<NNHTNPlanStep> &p_step) const;
	// Starts, executes and verifies p_step for one tick. A failure sets r_reason.
	Progress _progress(const Ref<NNHTNPlanStep> &p_step, double p_delta, const char *&r_reason);
	Progress _verify(const Ref<NNHTNPlanStep> &p_step, double p_delta, const char *&r_reason);
	Progress _advance_step(double p_delta);
	void _succeed_front();
	void _cancel_current();
	// Cancels every started step of p_steps other than p_except.
	static void _cancel_started(const std::vector<Ref<NNHTNPlanStep>> &p_steps, const Ref<NNHTNPlanStep> &p_except);
	void _fail(const Ref<NNHTNPlanStep> &p_step, const String &p_reason);
	void _clear();

	// The branches of the group at the front of the plan.
	std::vector<Ref<NNHTNPlanStep>> _front_group() const;
	const char *_check_group(const Ref<NNHTNPlanStep> &p_branch) const;
	Progress _advance_group(double p_delta);
	void _fail_group(const std::vector<Ref<NNHTNPlanStep>> &p_branches, const Ref<NNHTNPlanStep> &p_step, const char *p_reason);
};

} //namespace godot

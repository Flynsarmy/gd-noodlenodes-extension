#include "runner.h"

#include "../blackboard.h"
#include "parallel_task.h"
#include "root.h"
#include "task.h"

#include <godot_cpp/core/error_macros.hpp>

#ifdef DEBUG_ENABLED
#include "../debugger/debug_root.h"
#include "../debugger/snapshot_common.h"
#include "../debugger/snapshot_htn.h"
#endif

using namespace godot;

static const char *const INVALIDATED = "invalidated";
static const char *const EXECUTION_FAILED = "execution_failed";
static const char *const VERIFICATION_FAILED = "verification_failed";
static const char *const VERIFICATION_TIMEOUT = "verification_timeout";
static const char *const VERIFICATION_UNSAFE = "verification_unsafe";
static const char *const EFFECT_COMMIT_FAILED = "effect_commit_failed";

void NNHTNRunner::configure(NNHTNRoot *p_owner) {
	_owner = p_owner;
}

void NNHTNRunner::set_plan(std::vector<Ref<NNHTNPlanStep>> &&p_steps, std::vector<Ref<NNHTNPlanStep>> &&p_completed) {
	ERR_FAIL_COND_MSG(_executing, "NNHTNRunner: a plan cannot be installed while an occurrence is executing.");
	if (p_steps.empty() || get_current_step() != p_steps.front()) {
		_cancel_current();
		// on_cancel may have disabled the root, which has already dropped its plan.
		if (!_owner->get_is_enabled()) {
			return;
		}
	}
	_steps = std::move(p_steps);
	_completed = std::move(p_completed);
	_failure = Failure();
	_holding = false;

	Array steps;
	for (const Ref<NNHTNPlanStep> &step : _steps) {
		steps.push_back(step);
	}
#ifdef DEBUG_ENABLED
	if (NNDebugRoot *debug_root = nn_debug_watched_root(_owner)) {
		Array occurrences;
		for (const Ref<NNHTNPlanStep> &step : _steps) {
			occurrences.push_back(step->get_occurrence_id());
		}
		Dictionary fields;
		fields["occurrences"] = occurrences;
		debug_root->record("htn_plan_set", fields);
	}
#endif
	_owner->emit_signal("plan_set", steps);
}

void NNHTNRunner::abandon() {
	if (_executing) {
		_abandon_requested = true;
		return;
	}
	_cancel_current();
	_clear();
	_failure = Failure();
}

void NNHTNRunner::set_holding(bool p_holding) {
	_holding = p_holding;
}

NNHTNRunner::Outcome NNHTNRunner::advance(double p_delta) {
	Outcome outcome = NONE;
	_executing = true;
	while (!_steps.empty() && !_abandon_requested) {
		if (_holding && !is_running(_steps.front())) {
			break;
		}
		const Progress progress = _steps.front()->get_parallel_group_id() != 0 ? _advance_group(p_delta) : _advance_step(p_delta);
		if (progress == Progress::FAILED) {
			outcome = FAILED;
			break;
		}
		if (progress == Progress::WAITING) {
			break;
		}
		if (_steps.empty()) {
			_clear();
			outcome = COMPLETED;
		}
	}
	_executing = false;

	if (_abandon_requested) {
		_abandon_requested = false;
		abandon();
		return NONE;
	}
	return outcome;
}

NNHTNRunner::Progress NNHTNRunner::_advance_step(double p_delta) {
	const Ref<NNHTNPlanStep> step = _steps.front();
	const char *reason = _check(step);
	Progress progress = reason != nullptr ? Progress::FAILED : _progress(step, p_delta, reason);
	if (progress == Progress::FINISHED && !_owner->_commit_effects(step->get_committed_effects())) {
		reason = EFFECT_COMMIT_FAILED;
		progress = Progress::FAILED;
	}
	if (progress == Progress::FAILED) {
		_fail(step, reason);
	} else if (progress == Progress::FINISHED) {
		_succeed_front();
	}
	return progress;
}

const char *NNHTNRunner::_check(const Ref<NNHTNPlanStep> &p_step) const {
	if (!p_step->has_valid_references()) {
		return INVALIDATED;
	}
	NNHTNTask *task = p_step->get_task();
	if (p_step->get_state() == NNHTNPlanStep::VERIFYING) {
		return task->can_continue_verification(p_step) ? nullptr : VERIFICATION_UNSAFE;
	}
	const NNHTNStateView live(_owner->get_blackboard_resource()->get_values());
	return task->check_preconditions(live, p_step->get_args()) ? nullptr : INVALIDATED;
}

NNHTNRunner::Progress NNHTNRunner::_progress(const Ref<NNHTNPlanStep> &p_step, double p_delta, const char *&r_reason) {
	NNHTNTask *task = p_step->get_task();
	if (p_step->get_state() == NNHTNPlanStep::PENDING) {
		p_step->set_state(NNHTNPlanStep::RUNNING);
#ifdef DEBUG_ENABLED
		nn_debug_record_htn_step(_owner, p_step);
#endif
		task->emit_signal("started");
		_owner->emit_signal("step_state_changed", p_step, NNHTNTask::RUNNING);
		if (_abandon_requested) {
			return Progress::WAITING;
		}
	}

	// on_execute is never called again once it returned SUCCESS, however long verification waits.
	if (p_step->get_state() == NNHTNPlanStep::RUNNING) {
		const NNHTNTask::Status result = task->execute(p_delta, p_step);
		if (_abandon_requested || result == NNHTNTask::RUNNING) {
			return Progress::WAITING;
		}
		if (result == NNHTNTask::FAILURE) {
			r_reason = EXECUTION_FAILED;
			return Progress::FAILED;
		}
		if (task->get_verification_mode() == NNHTNTask::VERIFY) {
			p_step->set_state(NNHTNPlanStep::VERIFYING);
#ifdef DEBUG_ENABLED
			nn_debug_record_htn_step(_owner, p_step);
#endif
			_owner->emit_signal("verification_started", p_step);
			if (_abandon_requested) {
				return Progress::WAITING;
			}
		}
	}

	if (p_step->get_state() == NNHTNPlanStep::VERIFYING) {
		const Progress verification = _verify(p_step, p_delta, r_reason);
		if (verification != Progress::FINISHED) {
			return verification;
		}
		if (_abandon_requested) {
			return Progress::WAITING;
		}
	}
	return Progress::FINISHED;
}

NNHTNRunner::Progress NNHTNRunner::_verify(const Ref<NNHTNPlanStep> &p_step, double p_delta, const char *&r_reason) {
	NNHTNTask *task = p_step->get_task();
	p_step->add_verification_elapsed(p_delta);
	const NNHTNTask::Status result = task->verify(_owner->get_blackboard_resource()->get_values(), p_step);
	if (result == NNHTNTask::SUCCESS) {
		return Progress::FINISHED;
	}
	// The runner enforces the timeout, so a hook that keeps returning RUNNING cannot wait forever.
	if (result == NNHTNTask::RUNNING && p_step->get_verification_elapsed() < task->get_verification_timeout()) {
		return Progress::WAITING;
	}
	r_reason = result == NNHTNTask::RUNNING ? VERIFICATION_TIMEOUT : VERIFICATION_FAILED;
	return Progress::FAILED;
}

void NNHTNRunner::_succeed_front() {
	const Ref<NNHTNPlanStep> step = _steps.front();
	step->set_state(NNHTNPlanStep::SUCCEEDED);
	_steps.erase(_steps.begin());
	_completed.push_back(step);
	if (NNHTNTask *task = step->get_task()) {
		task->emit_signal("succeeded");
	}
#ifdef DEBUG_ENABLED
	nn_debug_record_htn_step(_owner, step);
#endif
	_owner->emit_signal("step_state_changed", step, NNHTNTask::SUCCESS);
}

bool NNHTNRunner::has_plan() const {
	return !_steps.empty();
}

Ref<NNHTNPlanStep> NNHTNRunner::get_current_step() const {
	return _steps.empty() ? Ref<NNHTNPlanStep>() : _steps.front();
}

const std::vector<Ref<NNHTNPlanStep>> &NNHTNRunner::get_steps() const {
	return _steps;
}

const std::vector<Ref<NNHTNPlanStep>> &NNHTNRunner::get_completed_steps() const {
	return _completed;
}

bool NNHTNRunner::is_current_available() const {
	if (_steps.empty()) {
		return false;
	}
	if (_steps.front()->get_parallel_group_id() == 0) {
		return _check(_steps.front()) == nullptr;
	}
	if (_check_group(_steps.front()) != nullptr) {
		return false;
	}
	for (const Ref<NNHTNPlanStep> &branch : _front_group()) {
		if (branch->get_state() != NNHTNPlanStep::STAGED && _check(branch) != nullptr) {
			return false;
		}
	}
	return true;
}

bool NNHTNRunner::is_running(const Ref<NNHTNPlanStep> &p_step) const {
	return p_step->is_started() || (p_step->get_parallel_group_id() != 0 && p_step->get_parallel_group_id() == _active_group_id);
}

NNHTNRunner::Failure NNHTNRunner::take_failure() {
	Failure failure = std::move(_failure);
	_failure = Failure();
	return failure;
}

void NNHTNRunner::_cancel_current() {
	if (_steps.empty()) {
		return;
	}
	const Ref<NNHTNPlanStep> front = _steps.front();
	if (front->get_parallel_group_id() == 0) {
		_cancel_started({ front }, Ref<NNHTNPlanStep>());
		return;
	}
	_cancel_started(_front_group(), Ref<NNHTNPlanStep>());
	if (front->get_parallel_group_id() == _active_group_id) {
		_active_group_id = 0;
		_owner->emit_signal("parallel_group_finished", front->get_parallel_group(), false);
	}
}

void NNHTNRunner::_cancel_started(const std::vector<Ref<NNHTNPlanStep>> &p_steps, const Ref<NNHTNPlanStep> &p_except) {
	std::vector<Ref<NNHTNPlanStep>> started;
	for (const Ref<NNHTNPlanStep> &step : p_steps) {
		if (step != p_except && step->is_started()) {
			started.push_back(step);
		}
	}
	// States change first so a hook that re-enters the runner cannot cancel twice.
	for (const Ref<NNHTNPlanStep> &step : started) {
		step->set_state(NNHTNPlanStep::CANCELLED);
	}
	for (const Ref<NNHTNPlanStep> &step : started) {
		if (NNHTNTask *task = step->get_task()) {
			task->cancel(step);
		}
	}
}

void NNHTNRunner::_fail(const Ref<NNHTNPlanStep> &p_step, const String &p_reason) {
	const bool was_started = p_step->is_started();
	const bool invalidated = p_reason == INVALIDATED;
	p_step->set_state(NNHTNPlanStep::FAILED);
	p_step->set_failure_reason(p_reason);
	_failure.step = p_step;
	_failure.completed = std::move(_completed);
	_failure.remaining = std::move(_steps);
	_clear();

	NNHTNTask *task = p_step->get_task();
	// An occurrence abandoned while running is cancelled; one that returned its own result is finished.
	if (invalidated && was_started && task != nullptr) {
		task->cancel(p_step);
	}
	if (invalidated) {
		_owner->emit_signal("plan_invalidated", p_step);
	} else if (p_reason == VERIFICATION_FAILED || p_reason == VERIFICATION_TIMEOUT) {
#ifdef DEBUG_ENABLED
		if (NNDebugRoot *debug_root = nn_debug_watched_root(_owner)) {
			Dictionary fields;
			fields["occurrence_id"] = p_step->get_occurrence_id();
			fields["reason"] = p_reason;
			debug_root->record("htn_verification_failed", fields);
		}
#endif
		_owner->emit_signal("verification_failed", p_step, p_reason);
	} else if (p_reason == EFFECT_COMMIT_FAILED) {
		_owner->emit_signal("effect_commit_failed", p_step);
	}
	if (was_started && task != nullptr) {
		task->emit_signal("failed");
	}
#ifdef DEBUG_ENABLED
	nn_debug_record_htn_step(_owner, p_step);
#endif
	_owner->emit_signal("step_state_changed", p_step, NNHTNTask::FAILURE);
}

void NNHTNRunner::_clear() {
	_steps.clear();
	_completed.clear();
	_holding = false;
	_active_group_id = 0;
}

// Parallel groups.

std::vector<Ref<NNHTNPlanStep>> NNHTNRunner::_front_group() const {
	std::vector<Ref<NNHTNPlanStep>> branches;
	const int64_t group_id = _steps.front()->get_parallel_group_id();
	for (const Ref<NNHTNPlanStep> &step : _steps) {
		if (step->get_parallel_group_id() != group_id) {
			break;
		}
		branches.push_back(step);
	}
	return branches;
}

const char *NNHTNRunner::_check_group(const Ref<NNHTNPlanStep> &p_branch) const {
	NNHTNParallelTask *group = p_branch->get_parallel_group();
	if (group == nullptr || !group->get_is_enabled() || group->is_queued_for_deletion()) {
		return INVALIDATED;
	}
	const NNHTNStateView live(_owner->get_blackboard_resource()->get_values());
	return group->check_preconditions(live, p_branch->get_parallel_group_args()) ? nullptr : INVALIDATED;
}

NNHTNRunner::Progress NNHTNRunner::_advance_group(double p_delta) {
	const std::vector<Ref<NNHTNPlanStep>> branches = _front_group();
	const Ref<NNHTNPlanStep> front = branches.front();
	if (_active_group_id != front->get_parallel_group_id()) {
		_active_group_id = front->get_parallel_group_id();
		Array steps;
		for (const Ref<NNHTNPlanStep> &branch : branches) {
			steps.push_back(branch);
		}
		_owner->emit_signal("parallel_group_started", front->get_parallel_group(), steps);
		if (_abandon_requested) {
			return Progress::WAITING;
		}
	}

	// Every check runs before any branch does, so all of them see the same live state.
	if (const char *reason = _check_group(front)) {
		_fail_group(branches, front, reason);
		return Progress::FAILED;
	}
	for (const Ref<NNHTNPlanStep> &branch : branches) {
		if (branch->get_state() == NNHTNPlanStep::STAGED) {
			continue;
		}
		if (const char *reason = _check(branch)) {
			_fail_group(branches, branch, reason);
			return Progress::FAILED;
		}
	}

	bool all_staged = true;
	for (const Ref<NNHTNPlanStep> &branch : branches) {
		if (branch->get_state() == NNHTNPlanStep::STAGED) {
			continue;
		}
		const char *reason = nullptr;
		const Progress progress = _progress(branch, p_delta, reason);
		if (progress == Progress::FAILED) {
			_fail_group(branches, branch, reason);
			return Progress::FAILED;
		}
		if (_abandon_requested) {
			return Progress::WAITING;
		}
		if (progress == Progress::WAITING) {
			all_staged = false;
			continue;
		}
		// Staged effects stay off the board until the whole group commits, so siblings never see them.
		branch->set_state(NNHTNPlanStep::STAGED);
		_owner->emit_signal("parallel_branch_staged", front->get_parallel_group(), branch);
		if (_abandon_requested) {
			return Progress::WAITING;
		}
	}
	if (!all_staged) {
		return Progress::WAITING;
	}

	Dictionary effects;
	for (const Ref<NNHTNPlanStep> &branch : branches) {
		effects.merge(branch->get_committed_effects());
	}
	effects.merge(front->get_parallel_group_effects());
	if (!_owner->_commit_effects(effects)) {
		_fail_group(branches, front, EFFECT_COMMIT_FAILED);
		return Progress::FAILED;
	}
	_active_group_id = 0;
	for (size_t i = 0; i < branches.size(); i++) {
		_succeed_front();
	}
	_owner->emit_signal("parallel_group_finished", front->get_parallel_group(), true);
	return Progress::FINISHED;
}

void NNHTNRunner::_fail_group(const std::vector<Ref<NNHTNPlanStep>> &p_branches, const Ref<NNHTNPlanStep> &p_step, const char *p_reason) {
	_cancel_started(p_branches, p_step);
	_active_group_id = 0;
	_fail(p_step, p_reason);
	_owner->emit_signal("parallel_group_finished", p_step->get_parallel_group(), false);
}

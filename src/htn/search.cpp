#include "search.h"

#include "binding.h"
#include "compound_task.h"
#include "method.h"
#include "parallel_task.h"
#include "plan_utils.h"
#include "subtask_call.h"
#include "task.h"

#include <algorithm>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

static const char *const KIND_COMPOUND = "compound";
static const char *const KIND_METHOD = "method";
static const char *const KIND_TASK = "task";
static const char *const KIND_CALL = "call";
static const char *const KIND_BINDING = "binding";
static const char *const KIND_ORDER = "order";
static const char *const KIND_GROUP = "parallel";
static const char *const KIND_PLAN = "plan";
static const char *const KIND_SEARCH = "search";

static const char *const CONSIDERED = "considered";
static const char *const ACCEPTED = "accepted";
static const char *const REJECTED = "rejected";
static const char *const PRUNED = "pruned";
static const char *const TRUNCATED = "truncated";
static const char *const CUTOFF = "cutoff";
static const char *const SERIALIZED = "serialized";

NNHTNSearch::Result NNHTNSearch::plan(NNHTNCompoundTask *p_domain, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace) {
	_begin(p_state, p_settings, p_schema, p_trace);

	Dictionary root_args;
	root_args.make_read_only();
	WorkItem root;
	root.node = p_domain;
	root.args = root_args;
	root.path = p_domain->get_name();
	root.append_name = false;

	std::vector<WorkItem> pending;
	pending.push_back(root);
	Terminal terminal = []() { return TerminalDecision::ACCEPT; };
	if (_policy == NNHTNSearchSettings::LOWEST_COST) {
		terminal = [this]() { return _keep_cheapest(); };
	}
	return _finish(_run(std::move(pending), terminal));
}

NNHTNSearch::Result NNHTNSearch::repair(const Boundary &p_boundary, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace) {
	_begin(p_state, p_settings, p_schema, p_trace);
	_frames = p_boundary.frames;
	_active = p_boundary.active;

	WorkItem item;
	item.node = p_boundary.node;
	item.args = p_boundary.args;
	item.path = p_boundary.path;
	item.append_name = p_boundary.append_name;
	item.child_index = p_boundary.child_index;

	std::vector<WorkItem> pending;
	pending.push_back(item);
	const bool lowest_cost = _policy == NNHTNSearchSettings::LOWEST_COST;
	const std::vector<Ref<NNHTNPlanStep>> &suffix = p_boundary.suffix;
	Terminal terminal = [this, lowest_cost, &suffix]() {
		if (!_append_suffix(suffix)) {
			return TerminalDecision::CONTINUE;
		}
		return lowest_cost ? _keep_cheapest() : TerminalDecision::ACCEPT;
	};
	return _finish(_run(std::move(pending), terminal));
}

NNHTNSearch::Result NNHTNSearch::_finish(bool p_found) {
	const bool lowest_cost = _policy == NNHTNSearchSettings::LOWEST_COST;
	Result result;
	result.expansions = _expansions;
	result.cutoff_reason = _cutoff_reason;
	if (lowest_cost && _has_best) {
		result.plan = std::move(_best_plan);
		result.cost = _best_cost;
	} else if (p_found) {
		result.plan = std::move(_plan);
	}

	// Omitted candidates might have produced a plan or a cheaper one, so the search is incomplete.
	const bool incomplete = _cutoff || (_candidates_truncated && (lowest_cost || result.plan.empty()));
	if (incomplete) {
		result.status = BUDGET_EXHAUSTED;
	} else {
		result.status = result.plan.empty() ? NO_PLAN : FOUND;
	}
	result.cost_optimal = lowest_cost && result.status == FOUND;
	if (_candidates_truncated && result.cutoff_reason.is_empty()) {
		result.cutoff_reason = vformat("binding candidate cap of %d reached", _settings->get_max_binding_candidates());
	}
	result.utility = _utility_of(result.plan);
	NNHTNPlanUtils::annotate_spans(result.plan);
	result.dependency_keys = std::move(_dependency_keys);
	result.dependencies_wildcard = _dependencies_wildcard;
	result.suffix_rejection = _suffix_rejection;

	_end();
	return result;
}

void NNHTNSearch::_begin(const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace) {
	_settings = &p_settings;
	_policy = p_settings.get_policy();
	_schema = p_schema;
	_trace = p_trace;
	_state.reset(p_state.duplicate(true));
	_plan.clear();
	_plan_cost = 0.0;
	_frames.clear();
	_active.clear();
	_pending_undo.clear();
	_frame_undo.clear();
	_active_undo.clear();
	_pending_low = 0;
	_frames_low = 0;
	_active_low = 0;
	_frame_child_epochs.clear();
	_suffix_rejection = String();
	_has_best = false;
	_best_plan.clear();
	_best_cost = 0.0;
	_expansions = 0;
	_cutoff = false;
	_cutoff_reason = String();
	_candidates_truncated = false;
	_dependency_keys.clear();
	_dependencies_wildcard = false;
	_recorded_nodes.clear();
	const int time_ms = p_settings.get_max_time_ms();
	_deadline_usec = time_ms > 0 ? Time::get_singleton()->get_ticks_usec() + (uint64_t)time_ms * 1000 : 0;
}

void NNHTNSearch::_end() {
	_settings = nullptr;
	_schema.unref();
	_trace = nullptr;
	_state.reset(Dictionary());
	_plan.clear();
	_best_plan.clear();
	_pending.clear();
	_choice_points.clear();
	_frames.clear();
	_active.clear();
	_pending_undo.clear();
	_frame_undo.clear();
	_active_undo.clear();
	_pending_low = 0;
	_frames_low = 0;
	_active_low = 0;
	_frame_child_epochs.clear();
	_recorded_nodes.clear();
}

bool NNHTNSearch::_run(std::vector<WorkItem> &&p_pending, const Terminal &p_terminal) {
	_pending = std::move(p_pending);
	_choice_points.clear();

	while (true) {
		if (!_check_deadline()) {
			return false;
		}
		if (_pending.empty()) {
			if (_trace != nullptr) {
				_trace_event(NNHTNSearchTrace::NO_EVENT, KIND_PLAN, String(), ACCEPTED, "PLAN_FOUND", vformat("%d steps, cost %s", (int64_t)_plan.size(), _plan_cost));
			}
			if (p_terminal() == TerminalDecision::ACCEPT) {
				return true;
			}
			if (!_backtrack()) {
				return false;
			}
			continue;
		}

		const size_t depth = _pending.size() - 1;
		WorkItem popped = std::move(_pending.back());
		_pending.pop_back();
		const WorkItem *item = &popped;
		// A position that existed at the newest mark must be put back on backtracking.
		if (depth < _pending_low) {
			_pending_low = depth;
			_pending_undo.push_back(PendingUndo{ depth, std::move(popped) });
			// Only this loop appends to the undo log, so the pointer stays valid while the item runs.
			item = &_pending_undo.back().item;
		}
		bool ok = true;
		switch (item->kind) {
			case WorkItem::NODE:
				ok = _process_node(*item);
				break;
			case WorkItem::END_METHOD:
				_finish_method(*item);
				break;
			case WorkItem::ORDER:
				ok = _process_order(*item);
				break;
			case WorkItem::END_SERIALIZED_GROUP:
				_finish_serialized_group(*item);
				break;
		}
		if (!ok && !_backtrack()) {
			return false;
		}
	}
}

bool NNHTNSearch::_backtrack() {
	while (!_cutoff && !_choice_points.empty()) {
		ChoicePoint &choice_point = _choice_points.back();
		_restore(choice_point.mark);
		if (_resume(choice_point)) {
			return true;
		}
		_choice_points.pop_back();
	}
	return false;
}

bool NNHTNSearch::_resume(ChoicePoint &r_choice_point) {
	if (MethodChoice *choice = std::get_if<MethodChoice>(&r_choice_point.choice)) {
		Alternative alternative;
		// A rejected alternative changes nothing, so the next one starts from the same restored state.
		while (_next_alternative(*choice, alternative)) {
			if (_start_alternative(*choice, alternative)) {
				return true;
			}
		}
		return false;
	}

	OrderChoice &choice = std::get<OrderChoice>(r_choice_point.choice);
	if (choice.ready_index >= choice.ready.size()) {
		return false;
	}
	const int index = choice.ready[choice.ready_index++];
	int parent = choice.item.trace_parent;
	if (_trace != nullptr) {
		const NNHTNNodes *child = choice.item.schedule->children[index];
		const int event = _trace_event(parent, KIND_ORDER, choice.item.path + String("/") + String(child->get_name()), CONSIDERED, "ORDER_CHOICE", vformat("Scheduled next of %d ready children.", (int64_t)choice.ready.size()), choice.item.args);
		parent = event != NNHTNSearchTrace::NO_EVENT ? event : parent;
	}
	_schedule_ready_child(choice.item, index, parent);
	return true;
}

NNHTNSearch::Mark NNHTNSearch::_mark() {
	Mark mark;
	mark.state_trail = _state.get_trail_mark();
	mark.pending_size = _pending.size();
	mark.pending_trail = _pending_undo.size();
	mark.frame_size = _frames.size();
	mark.frame_trail = _frame_undo.size();
	mark.active_size = _active.size();
	mark.active_trail = _active_undo.size();
	mark.plan_size = _plan.size();
	mark.plan_cost = _plan_cost;
	_begin_epoch();
	return mark;
}

void NNHTNSearch::_begin_epoch() {
	_pending_low = _pending.size();
	_frames_low = _frames.size();
	_active_low = _active.size();
	_state.set_trail_floor(_state.get_trail_mark());
	_epoch++;
}

void NNHTNSearch::_restore(const Mark &p_mark) {
	_state.restore_trail(p_mark.state_trail);
	_plan.resize(p_mark.plan_size);
	_plan_cost = p_mark.plan_cost;

	// Pushes are not logged, so the stack is truncated and only logged pops are re-seated.
	// Replaying newest first leaves the oldest entry in each position, which is the one the mark saw.
	_pending.resize(p_mark.pending_size);
	while (_pending_undo.size() > p_mark.pending_trail) {
		const PendingUndo &undo = _pending_undo.back();
		if (undo.depth < p_mark.pending_size) {
			_pending[undo.depth] = undo.item;
		}
		_pending_undo.pop_back();
	}

	_frames.resize(p_mark.frame_size);
	while (_frame_undo.size() > p_mark.frame_trail) {
		const FrameUndo &undo = _frame_undo.back();
		if (undo.depth < p_mark.frame_size) {
			if (undo.kind == FrameUndo::POPPED) {
				_frames[undo.depth] = undo.frame;
			} else {
				_frames[undo.depth].child_index = undo.child_index;
			}
		}
		_frame_undo.pop_back();
	}

	_active.resize(p_mark.active_size);
	while (_active_undo.size() > p_mark.active_trail) {
		const ActiveUndo &undo = _active_undo.back();
		if (undo.depth < p_mark.active_size) {
			_active[undo.depth] = undo.compound;
		}
		_active_undo.pop_back();
	}
	_begin_epoch();
}

void NNHTNSearch::_pop_active() {
	const size_t depth = _active.size() - 1;
	NNHTNCompoundTask *compound = _active.back();
	_active.pop_back();
	if (depth < _active_low) {
		_active_low = depth;
		_active_undo.push_back(ActiveUndo{ depth, compound });
	}
}

void NNHTNSearch::_pop_frames(size_t p_depth) {
	while (_frames.size() > p_depth) {
		const size_t depth = _frames.size() - 1;
		if (depth < _frames_low) {
			_frames_low = depth;
			_frame_undo.push_back(FrameUndo{ FrameUndo::POPPED, depth, -1, _frames.back() });
		}
		_frames.pop_back();
	}
}

bool NNHTNSearch::_process_node(const WorkItem &p_item) {
	NNHTNNodes *node = p_item.node;
	String path = p_item.append_name ? p_item.path + String("/") + String(node->get_name()) : p_item.path;
	Dictionary args = p_item.args;
	if (!_frames.empty()) {
		const size_t depth = _frames.size() - 1;
		// A frame popped since the mark is re-seated with its own child index, so only the
		// still-in-place frames need their index restored, and only once per mark.
		if (depth < _frames_low && (depth >= _frame_child_epochs.size() || _frame_child_epochs[depth] != _epoch)) {
			if (depth >= _frame_child_epochs.size()) {
				_frame_child_epochs.resize(depth + 1, 0);
			}
			_frame_child_epochs[depth] = _epoch;
			_frame_undo.push_back(FrameUndo{ FrameUndo::CHILD_INDEX, depth, _frames.back().child_index });
		}
		_frames.back().child_index = p_item.child_index;
	}
	_record_dependencies(node);

	if (NNHTNSubtaskCall *call = Object::cast_to<NNHTNSubtaskCall>(node)) {
		if (!_resolve_call(call, p_item.args, p_item.trace_parent, node, args, path)) {
			return false;
		}
	}

	NNHTNCompoundTask *compound = Object::cast_to<NNHTNCompoundTask>(node);
	NNHTNParallelTask *group = Object::cast_to<NNHTNParallelTask>(node);
	if (!node->get_is_enabled()) {
		_trace_event(p_item.trace_parent, compound != nullptr ? KIND_COMPOUND : (group != nullptr ? KIND_GROUP : KIND_TASK), path, REJECTED, "DISABLED", String(), args);
		return false;
	}
	if (compound != nullptr) {
		return _process_compound(compound, args, path, p_item.trace_parent);
	}
	if (group != nullptr) {
		return _process_group(group, p_item, args, path);
	}
	if (NNHTNTask *task = Object::cast_to<NNHTNTask>(node)) {
		return _process_task(task, args, path, p_item.trace_parent);
	}
	return false;
}

bool NNHTNSearch::_resolve_call(NNHTNSubtaskCall *p_call, const Dictionary &p_args, int p_trace_parent, NNHTNNodes *&r_node, Dictionary &r_args, String &r_path) {
	Dictionary failure;
	const uint64_t hook_reads = _state.get_hook_state_reads();
	const bool available = p_call->check_preconditions(_state, p_args, _trace != nullptr ? &failure : nullptr);
	_note_hooks_called(p_call, hook_reads);
	if (!available) {
		_trace_event(p_trace_parent, KIND_CALL, r_path, REJECTED, "PRECONDITION_FALSE", String(), p_args, failure);
		return false;
	}
	r_node = p_call->get_template();
	if (r_node == nullptr) {
		_trace_event(p_trace_parent, KIND_CALL, r_path, REJECTED, "MISSING_TEMPLATE", String(), p_args);
		return false;
	}
	if (!p_call->resolve_args(_state, p_args, r_args)) {
		_trace_event(p_trace_parent, KIND_CALL, r_path, REJECTED, "INVALID_ARGUMENT_REFERENCE", String(), p_args);
		return false;
	}
	r_path += String("/") + String(r_node->get_name());
	_record_dependencies(r_node);
	return true;
}

bool NNHTNSearch::_process_compound(NNHTNCompoundTask *p_compound, const Dictionary &p_args, const String &p_path, int p_trace_parent) {
	if (_active.size() >= MAX_ACTIVE_COMPOUNDS || std::find(_active.begin(), _active.end(), p_compound) != _active.end()) {
		_trace_event(p_trace_parent, KIND_COMPOUND, p_path, REJECTED, "RECURSION_LIMIT", String(), p_args);
		return false;
	}
	Dictionary failure;
	const uint64_t hook_reads = _state.get_hook_state_reads();
	const bool available = p_compound->check_preconditions(_state, p_args, _trace != nullptr ? &failure : nullptr);
	_note_hooks_called(p_compound, hook_reads);
	if (!available) {
		_trace_event(p_trace_parent, KIND_COMPOUND, p_path, REJECTED, "PRECONDITION_FALSE", String(), p_args, failure);
		return false;
	}
	const int trace_id = _trace_event(p_trace_parent, KIND_COMPOUND, p_path, CONSIDERED, "CONSIDERED", String(), p_args);
	std::vector<RankedMethod> methods = _rank_methods(p_compound, p_args, p_path, trace_id);
	if (methods.empty()) {
		_trace_event(trace_id, KIND_COMPOUND, p_path, REJECTED, "NO_METHODS", String(), p_args);
		return false;
	}

	_active.push_back(p_compound);
	MethodChoice choice;
	choice.compound = p_compound;
	choice.args = p_args;
	choice.path = p_path;
	choice.trace_id = trace_id;
	choice.methods = std::move(methods);
	_choice_points.push_back(ChoicePoint{ _mark(), std::move(choice) });
	if (!_resume(_choice_points.back())) {
		_choice_points.pop_back();
		_pop_active();
		return false;
	}
	return true;
}

std::vector<NNHTNSearch::RankedMethod> NNHTNSearch::_rank_methods(NNHTNCompoundTask *p_compound, const Dictionary &p_args, const String &p_path, int p_trace_parent) {
	std::vector<RankedMethod> ranked;
	for (NNHTNMethod *method : p_compound->get_enabled_methods()) {
		if (_policy == NNHTNSearchSettings::ORDERED) {
			ranked.push_back(RankedMethod{ method, 0.0 });
			continue;
		}
		_record_dependencies(method);
		double priority = 0.0;
		const uint64_t hook_reads = _state.get_hook_state_reads();
		const bool valid = method->compute_priority(_state, p_args, priority);
		_note_hooks_called(method, hook_reads);
		if (!valid) {
			_trace_event(p_trace_parent, KIND_METHOD, p_path + String("/") + String(method->get_name()), REJECTED, "INVALID_PRIORITY", String(), p_args);
			continue;
		}
		ranked.push_back(RankedMethod{ method, priority });
	}
	std::stable_sort(ranked.begin(), ranked.end(), [](const RankedMethod &a, const RankedMethod &b) {
		return a.priority > b.priority;
	});
	return ranked;
}

bool NNHTNSearch::_next_alternative(MethodChoice &r_choice, Alternative &r_alternative) {
	while (r_choice.method_index < r_choice.methods.size()) {
		if (!_check_deadline()) {
			return false;
		}
		const RankedMethod &ranked = r_choice.methods[r_choice.method_index];
		const String method_path = r_choice.path + String("/") + String(ranked.method->get_name());
		const bool usable = r_choice.method_entered || _enter_method(r_choice, ranked.method, method_path);
		r_choice.method_entered = true;
		if (usable && _next_candidate_args(r_choice, ranked.method, method_path, r_alternative.args)) {
			r_alternative.method = ranked.method;
			r_alternative.priority = ranked.priority;
			r_alternative.schedule = r_choice.schedule;
			return true;
		}
		if (_cutoff) {
			return false;
		}
		r_choice.method_index++;
		r_choice.method_entered = false;
	}
	return false;
}

bool NNHTNSearch::_enter_method(MethodChoice &r_choice, NNHTNMethod *p_method, const String &p_method_path) {
	_record_dependencies(p_method);
	r_choice.schedule.reset();
	r_choice.candidates.clear();
	r_choice.candidate_index = 0;
	r_choice.binding_levels.clear();

	std::shared_ptr<Schedule> schedule = std::make_shared<Schedule>();
	if (!p_method->get_schedulable_children(schedule->children)) {
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, REJECTED, "INVALID_CHILDREN", String(), r_choice.args);
		return false;
	}
	// An empty method is a failed decomposition, not a successful empty plan.
	if (schedule->children.empty()) {
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, REJECTED, "EMPTY_METHOD", String(), r_choice.args);
		return false;
	}
	const NNHTNMethod::OrderingMode mode = p_method->get_ordering_mode();
	PackedStringArray ordering_errors;
	if (mode == NNHTNMethod::PARTIAL_ORDER) {
		schedule->partial_order = p_method->build_predecessor_graph(schedule->children, schedule->predecessors, ordering_errors);
	} else if (mode != NNHTNMethod::SEQUENTIAL) {
		ordering_errors.push_back(vformat("ordering_mode %d is invalid.", (int)mode));
	}
	const PackedStringArray binding_errors = p_method->get_binding_errors();
	PackedStringArray errors = ordering_errors;
	errors.append_array(binding_errors);
	p_method->report_configuration_error(errors.is_empty() ? String() : String(" ").join(errors) + " The method is skipped.");
	if (!ordering_errors.is_empty()) {
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, REJECTED, "INVALID_ORDERING", String(" ").join(ordering_errors), r_choice.args);
		return false;
	}
	if (!binding_errors.is_empty()) {
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, REJECTED, "INVALID_BINDING", String(" ").join(binding_errors), r_choice.args);
		return false;
	}

	bool truncated = false;
	const uint64_t hook_reads = _state.get_hook_state_reads();
	const bool resolved = p_method->resolve_argument_candidates(_state, r_choice.args, _settings->get_max_binding_candidates(), r_choice.candidates, truncated);
	_note_hooks_called(p_method, hook_reads);
	if (resolved && truncated) {
		_candidates_truncated = true;
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, TRUNCATED, "CANDIDATE_CAP", "on_resolve_arguments() offered more candidates than max_binding_candidates.", r_choice.args);
	}
	if (r_choice.candidates.empty()) {
		_trace_event(r_choice.trace_id, KIND_METHOD, p_method_path, REJECTED, "NO_ARGUMENT_CANDIDATES", String(), r_choice.args);
		return false;
	}
	r_choice.schedule = std::move(schedule);
	return true;
}

bool NNHTNSearch::_next_candidate_args(MethodChoice &r_choice, NNHTNMethod *p_method, const String &p_method_path, Dictionary &r_args) {
	const TypedArray<NNHTNBinding> bindings = p_method->get_bindings();
	if (bindings.is_empty()) {
		if (r_choice.candidate_index >= r_choice.candidates.size()) {
			return false;
		}
		r_args = r_choice.candidates[r_choice.candidate_index++];
		return true;
	}
	while (true) {
		if (_next_binding_args(r_choice, bindings, p_method_path, r_args)) {
			return true;
		}
		if (_cutoff || r_choice.candidate_index >= r_choice.candidates.size()) {
			return false;
		}
		if (!_push_binding_level(r_choice, bindings, 0, r_choice.candidates[r_choice.candidate_index++], p_method_path)) {
			return false;
		}
	}
}

bool NNHTNSearch::_next_binding_args(MethodChoice &r_choice, const TypedArray<NNHTNBinding> &p_bindings, const String &p_method_path, Dictionary &r_args) {
	while (!r_choice.binding_levels.empty()) {
		if (!_check_deadline()) {
			return false;
		}
		BindingLevel &level = r_choice.binding_levels.back();
		if (level.value_index >= level.values.size()) {
			r_choice.binding_levels.pop_back();
			continue;
		}
		const Ref<NNHTNBinding> binding = p_bindings[(int)r_choice.binding_levels.size() - 1];
		Dictionary args = level.parent_args.duplicate(true);
		args[binding->get_variable()] = level.values[level.value_index++];
		args.make_read_only();
		const int next_index = (int)r_choice.binding_levels.size();
		if (next_index == p_bindings.size()) {
			r_args = args;
			return true;
		}
		if (!_push_binding_level(r_choice, p_bindings, next_index, args, p_method_path)) {
			return false;
		}
	}
	return false;
}

bool NNHTNSearch::_push_binding_level(MethodChoice &r_choice, const TypedArray<NNHTNBinding> &p_bindings, int p_index, const Dictionary &p_parent_args, const String &p_method_path) {
	// Every collection counts, so a deeper binding with no values cannot make a large join free.
	if (!_try_expand()) {
		return false;
	}
	const Ref<NNHTNBinding> binding = p_bindings[p_index];
	BindingLevel level;
	level.parent_args = p_parent_args;
	bool truncated = false;
	binding->collect_values(_state, p_parent_args, _settings->get_max_binding_candidates(), level.values, truncated);
	if (truncated) {
		_candidates_truncated = true;
		_trace_event(r_choice.trace_id, KIND_BINDING, p_method_path, TRUNCATED, "CANDIDATE_CAP", vformat("Binding '%s' has more values than max_binding_candidates.", binding->get_variable()), p_parent_args);
	}
	if (level.values.empty()) {
		_trace_event(r_choice.trace_id, KIND_BINDING, p_method_path, REJECTED, "BINDING_NO_VALUES", vformat("Binding '%s' has no values from '%s'.", binding->get_variable(), binding->get_state_key()), p_parent_args);
	}
	r_choice.binding_levels.push_back(std::move(level));
	return true;
}

bool NNHTNSearch::_start_alternative(const MethodChoice &p_choice, const Alternative &p_alternative) {
	NNHTNMethod *method = p_alternative.method;
	const String method_path = p_choice.path + String("/") + String(method->get_name());
	if (_cost_pruned(_plan_cost)) {
		if (_trace != nullptr) {
			_trace_event(p_choice.trace_id, KIND_METHOD, method_path, PRUNED, "COST_PRUNE", vformat("Partial cost %s is not below the best plan's %s.", _plan_cost, _best_cost), p_alternative.args);
		}
		return false;
	}
	if (!_try_expand()) {
		return false;
	}
	Dictionary failure;
	const uint64_t hook_reads = _state.get_hook_state_reads();
	const bool available = method->check_preconditions(_state, p_alternative.args, _trace != nullptr ? &failure : nullptr);
	_note_hooks_called(method, hook_reads);
	if (!available) {
		_trace_event(p_choice.trace_id, KIND_METHOD, method_path, REJECTED, "PRECONDITION_FALSE", String(), p_alternative.args, failure);
		return false;
	}
	const int trace_id = _trace_event(p_choice.trace_id, KIND_METHOD, method_path, ACCEPTED, "ACCEPTED", String(), p_alternative.args);

	NNHTNProvenanceFrame frame;
	frame.frame_id = _next_frame_id++;
	frame.compound_id = p_choice.compound->get_instance_id();
	frame.method_id = method->get_instance_id();
	frame.compound_args = p_choice.args;
	frame.args = p_alternative.args;
	frame.method_path = method_path;
	frame.priority = p_alternative.priority;
	_frames.push_back(frame);

	// The method's scope ends after its children, so a later sibling may reuse the compound without counting as recursion.
	WorkItem end;
	end.kind = WorkItem::END_METHOD;
	end.frame_depth = _frames.size() - 1;
	_pending.push_back(end);
	_schedule_children(p_alternative.schedule, p_alternative.args, method_path, trace_id);
	return true;
}

void NNHTNSearch::_schedule_children(const std::shared_ptr<const Schedule> &p_schedule, const Dictionary &p_args, const String &p_path, int p_trace_parent) {
	if (p_schedule->partial_order) {
		WorkItem order;
		order.kind = WorkItem::ORDER;
		order.args = p_args;
		order.path = p_path;
		order.trace_parent = p_trace_parent;
		order.schedule = p_schedule;
		order.scheduled.assign(p_schedule->children.size(), false);
		_pending.push_back(std::move(order));
		return;
	}
	for (size_t i = p_schedule->children.size(); i-- > 0;) {
		WorkItem item;
		item.node = p_schedule->children[i];
		item.args = p_args;
		item.path = p_path;
		item.child_index = (int)i;
		item.trace_parent = p_trace_parent;
		_pending.push_back(item);
	}
}

bool NNHTNSearch::_process_order(const WorkItem &p_item) {
	const Schedule &schedule = *p_item.schedule;
	std::vector<int> ready;
	bool remaining = false;
	for (size_t i = 0; i < schedule.children.size(); i++) {
		if (p_item.scheduled[i]) {
			continue;
		}
		remaining = true;
		const std::vector<int> &predecessors = schedule.predecessors[i];
		if (std::all_of(predecessors.begin(), predecessors.end(), [&p_item](int p_predecessor) { return p_item.scheduled[p_predecessor]; })) {
			ready.push_back((int)i);
		}
	}
	if (!remaining) {
		return true;
	}
	// Unreachable for a validated acyclic graph, which always has a ready child.
	ERR_FAIL_COND_V(ready.empty(), false);
	if (ready.size() == 1) {
		_schedule_ready_child(p_item, ready[0], p_item.trace_parent);
		return true;
	}

	OrderChoice choice;
	choice.item = p_item;
	choice.ready = std::move(ready);
	_choice_points.push_back(ChoicePoint{ _mark(), std::move(choice) });
	return _resume(_choice_points.back());
}

void NNHTNSearch::_schedule_ready_child(const WorkItem &p_item, int p_index, int p_trace_parent) {
	WorkItem rest = p_item;
	rest.scheduled[p_index] = true;
	_pending.push_back(std::move(rest));

	WorkItem child;
	child.node = p_item.schedule->children[p_index];
	child.args = p_item.args;
	child.path = p_item.path;
	child.child_index = p_index;
	child.trace_parent = p_trace_parent;
	_pending.push_back(std::move(child));
}

void NNHTNSearch::_finish_method(const WorkItem &p_item) {
	_pop_active();
	_pop_frames(p_item.frame_depth);
}

NNHTNSearch::TerminalDecision NNHTNSearch::_keep_cheapest() {
	// Pruning already rejected every plan at least as expensive, so this one is the new best.
	_has_best = true;
	_best_plan = _plan;
	_best_cost = _plan_cost;
	return TerminalDecision::CONTINUE;
}

bool NNHTNSearch::_append_suffix(const std::vector<Ref<NNHTNPlanStep>> &p_suffix) {
	// A rejection backtracks, and backtracking restores the predicted state this writes to.
	const char *rejection = nullptr;
	for (const Ref<NNHTNPlanStep> &step : p_suffix) {
		NNHTNTask *task = step->get_task();
		if (!step->has_valid_references()) {
			rejection = "a retained step's task or arguments are no longer valid";
			break;
		}
		_record_dependencies(task);
		const uint64_t hook_reads = _state.get_hook_state_reads();
		const bool available = task->check_preconditions(_state, step->get_args());
		_note_hooks_called(task, hook_reads);
		if (!available) {
			rejection = "a retained step's preconditions no longer hold";
			break;
		}
		const Dictionary effects = step->get_effects();
		if (!_accepts_effects(task, effects)) {
			rejection = "a retained step's effects violate the blackboard schema";
			break;
		}
		_apply_effects(effects);
	}
	if (rejection != nullptr) {
		_suffix_rejection = vformat("outer suffix rejected: %s", rejection);
		_trace_event(NNHTNSearchTrace::NO_EVENT, KIND_PLAN, String(), REJECTED, "SUFFIX_REJECTED", _suffix_rejection);
		return false;
	}
	_suffix_rejection = String();
	for (const Ref<NNHTNPlanStep> &step : p_suffix) {
		_plan.push_back(step);
		_plan_cost += step->get_cost();
	}
	return true;
}

bool NNHTNSearch::_process_task(NNHTNTask *p_task, const Dictionary &p_args, const String &p_path, int p_trace_parent) {
	Ref<NNHTNPlanStep> step;
	if (!_ground_task(p_task, p_args, p_path, p_trace_parent, step)) {
		return false;
	}
	const double cost = step->get_cost();
	if (_cost_pruned(_plan_cost + cost)) {
		if (_trace != nullptr) {
			_trace_event(p_trace_parent, KIND_TASK, p_path, PRUNED, "COST_PRUNE", vformat("Partial cost %s is not below the best plan's %s.", _plan_cost + cost, _best_cost), p_args);
		}
		return false;
	}

	_apply_effects(step->get_effects());
	_plan.push_back(step);
	_plan_cost += cost;
	_trace_event(p_trace_parent, KIND_TASK, p_path, ACCEPTED, "ACCEPTED", String(), p_args, Dictionary(), step->get_occurrence_id());
	return true;
}

bool NNHTNSearch::_ground_task(NNHTNTask *p_task, const Dictionary &p_args, const String &p_path, int p_trace_parent, Ref<NNHTNPlanStep> &r_step) {
	if (!_try_expand()) {
		return false;
	}
	// Precondition, effect and cost hooks all count, so a rejection by any of them still records the wildcard.
	const uint64_t hook_reads = _state.get_hook_state_reads();
	Dictionary failure;
	Dictionary effects;
	double cost = 0.0;
	const bool available = p_task->check_preconditions(_state, p_args, _trace != nullptr ? &failure : nullptr);
	const PackedStringArray execution_errors = p_task->get_execution_errors();
	p_task->report_configuration_error(execution_errors.is_empty() ? String() : String(" ").join(execution_errors) + " Its occurrences are rejected.");
	const bool effects_valid = available && p_task->compute_effects(_state, p_args, effects) && _accepts_effects(p_task, effects);
	const bool cost_valid = effects_valid && (_policy != NNHTNSearchSettings::LOWEST_COST || p_task->compute_estimated_cost(_state, p_args, cost));
	_note_hooks_called(p_task, hook_reads);
	if (!available) {
		_trace_event(p_trace_parent, KIND_TASK, p_path, REJECTED, "PRECONDITION_FALSE", String(), p_args, failure);
		return false;
	}
	if (!effects_valid) {
		_trace_event(p_trace_parent, KIND_TASK, p_path, REJECTED, "INVALID_EFFECTS", String(), p_args);
		return false;
	}
	if (!cost_valid) {
		_trace_event(p_trace_parent, KIND_TASK, p_path, REJECTED, "INVALID_COST", String(), p_args);
		return false;
	}
	if (!execution_errors.is_empty()) {
		_trace_event(p_trace_parent, KIND_TASK, p_path, REJECTED, "INVALID_EXECUTION_SETTINGS", String(" ").join(execution_errors), p_args);
		return false;
	}

	Ref<NNHTNPlanStep> step;
	step.instantiate();
	std::vector<NNHTNProvenanceFrame> provenance = _frames;
	step->setup(p_task, p_args, effects, p_task->get_committed_effect_keys(effects), cost, p_path, std::move(provenance));
	// An occurrence bound to a freed object would only be invalidated before it starts.
	if (!step->has_valid_references()) {
		_trace_event(p_trace_parent, KIND_TASK, p_path, REJECTED, "INVALID_REFERENCE", String(), p_args);
		return false;
	}
	r_step = step;
	return true;
}

bool NNHTNSearch::_process_group(NNHTNParallelTask *p_group, const WorkItem &p_item, const Dictionary &p_args, const String &p_path) {
	const int parent = p_item.trace_parent;
	std::vector<NNHTNNodes *> branches;
	const String structure_error = p_group->resolve_branches(branches);
	if (!structure_error.is_empty()) {
		p_group->report_configuration_error(structure_error + String(" The group is rejected."));
		_trace_event(parent, KIND_GROUP, p_path, REJECTED, "INVALID_GROUP", structure_error, p_args);
		return false;
	}
	Dictionary failure;
	const uint64_t hook_reads = _state.get_hook_state_reads();
	const bool available = p_group->check_preconditions(_state, p_args, _trace != nullptr ? &failure : nullptr);
	_note_hooks_called(p_group, hook_reads);
	if (!available) {
		_trace_event(parent, KIND_GROUP, p_path, REJECTED, "PRECONDITION_FALSE", String(), p_args, failure);
		return false;
	}
	const Dictionary group_effects = p_group->get_effects().duplicate(true);
	if (!_accepts_effects(p_group, group_effects)) {
		_trace_event(parent, KIND_GROUP, p_path, REJECTED, "INVALID_EFFECTS", String(), p_args);
		return false;
	}
	const int trace_id = _trace_event(parent, KIND_GROUP, p_path, CONSIDERED, "CONSIDERED", String(), p_args);

	// Every branch sees the same predicted state, so no sibling's effects can enable another branch.
	std::vector<Ref<NNHTNPlanStep>> steps;
	for (NNHTNNodes *branch : branches) {
		Ref<NNHTNPlanStep> step;
		if (!_ground_branch(branch, p_args, p_path, trace_id, step)) {
			if (_cutoff) {
				return false;
			}
			return _serialize_or_reject(p_group, branches, p_item, p_args, p_path, trace_id, "BRANCH_UNAVAILABLE", vformat("branch '%s' is unavailable in the concurrent snapshot", branch->get_name()), false);
		}
		steps.push_back(step);
	}
	const PackedStringArray conflicts = _group_conflicts(p_group, branches, steps, p_path, trace_id);
	if (!conflicts.is_empty()) {
		return _serialize_or_reject(p_group, branches, p_item, p_args, p_path, trace_id, "PARALLEL_CONFLICT", "its branches may not run concurrently: " + String("; ").join(conflicts), true);
	}

	double cost = 0.0;
	for (const Ref<NNHTNPlanStep> &step : steps) {
		cost += step->get_cost();
	}
	if (_cost_pruned(_plan_cost + cost)) {
		if (_trace != nullptr) {
			_trace_event(trace_id, KIND_GROUP, p_path, PRUNED, "COST_PRUNE", vformat("Partial cost %s is not below the best plan's %s.", _plan_cost + cost, _best_cost), p_args);
		}
		return false;
	}

	const uint64_t group_id = _next_group_id++;
	for (size_t i = 0; i < steps.size(); i++) {
		const Ref<NNHTNPlanStep> &step = steps[i];
		step->set_parallel_group(p_group, group_id, (int)i, (int)steps.size(), p_args, group_effects);
		_apply_effects(step->get_effects());
		_plan.push_back(step);
		_trace_event(trace_id, KIND_TASK, step->get_call_path(), ACCEPTED, "ACCEPTED", String(), step->get_args(), Dictionary(), step->get_occurrence_id());
	}
	_apply_effects(group_effects);
	_plan_cost += cost;
	p_group->report_configuration_error(String());
	p_group->report_serialization(String());
	_trace_event(trace_id, KIND_GROUP, p_path, ACCEPTED, "ACCEPTED", vformat("%d concurrent branches.", (int64_t)steps.size()), p_args);
	return true;
}

bool NNHTNSearch::_ground_branch(NNHTNNodes *p_branch, const Dictionary &p_args, const String &p_group_path, int p_trace_parent, Ref<NNHTNPlanStep> &r_step) {
	NNHTNNodes *node = p_branch;
	Dictionary args = p_args;
	String path = p_group_path + String("/") + String(p_branch->get_name());
	_record_dependencies(p_branch);
	if (NNHTNSubtaskCall *call = Object::cast_to<NNHTNSubtaskCall>(p_branch)) {
		if (!_resolve_call(call, p_args, p_trace_parent, node, args, path)) {
			return false;
		}
	}
	if (!node->get_is_enabled()) {
		_trace_event(p_trace_parent, KIND_TASK, path, REJECTED, "DISABLED", String(), args);
		return false;
	}
	NNHTNTask *task = Object::cast_to<NNHTNTask>(node);
	return task != nullptr && _ground_task(task, args, path, p_trace_parent, r_step);
}

bool NNHTNSearch::_serialize_or_reject(NNHTNParallelTask *p_group, const std::vector<NNHTNNodes *> &p_branches, const WorkItem &p_item, const Dictionary &p_args, const String &p_path, int p_trace_id, const char *p_reason, const String &p_detail, bool p_conflict) {
	if (p_group->get_unsafe_policy() != NNHTNParallelTask::SERIALIZE) {
		if (p_conflict) {
			p_group->report_configuration_error(vformat("The group is rejected because %s.", p_detail));
		}
		_trace_event(p_trace_id, KIND_GROUP, p_path, REJECTED, p_reason, p_detail, p_args);
		return false;
	}
	p_group->report_configuration_error(String());
	p_group->report_serialization(vformat("The group runs its branches in scene order because %s.", p_detail));
	_trace_event(p_trace_id, KIND_GROUP, p_path, SERIALIZED, p_reason, p_detail, p_args);

	WorkItem end;
	end.kind = WorkItem::END_SERIALIZED_GROUP;
	end.node = p_group;
	end.args = p_args;
	end.plan_base = _plan.size();
	_pending.push_back(end);
	// Branches keep the group's child index, so the method frame still names the group.
	for (size_t i = p_branches.size(); i-- > 0;) {
		WorkItem item;
		item.node = p_branches[i];
		item.args = p_args;
		item.path = p_path;
		item.child_index = p_item.child_index;
		item.trace_parent = p_trace_id;
		_pending.push_back(item);
	}
	return true;
}

void NNHTNSearch::_finish_serialized_group(const WorkItem &p_item) {
	NNHTNParallelTask *group = Object::cast_to<NNHTNParallelTask>(p_item.node);
	const Dictionary effects = group->get_effects().duplicate(true);
	const int count = (int)(_plan.size() - p_item.plan_base);
	for (int i = 0; i < count; i++) {
		_plan[p_item.plan_base + i]->set_parallel_group(group, 0, i, count, p_item.args, Dictionary());
	}
	if (!effects.is_empty()) {
		_plan.back()->set_deferred_group_effects(effects);
	}
	_apply_effects(effects);
}

static String _shared_keys(const HashSet<String> &p_left, const HashSet<String> &p_right) {
	PackedStringArray shared;
	for (const String &key : p_left) {
		if (p_right.has(key)) {
			shared.push_back(key);
		}
	}
	shared.sort();
	return shared.is_empty() ? String() : "'" + String("', '").join(shared) + "'";
}

PackedStringArray NNHTNSearch::_group_conflicts(const NNHTNParallelTask *p_group, const std::vector<NNHTNNodes *> &p_branches, const std::vector<Ref<NNHTNPlanStep>> &p_steps, const String &p_path, int p_trace_id) {
	struct Contract {
		String name;
		bool complete = false;
		HashSet<String> reads;
		HashSet<String> writes;
		HashSet<String> resources;
	};
	PackedStringArray conflicts;
	const auto conflict = [this, &conflicts, &p_path, p_trace_id](const char *p_reason, const String &p_message) {
		conflicts.push_back(p_message);
		_trace_event(p_trace_id, KIND_GROUP, p_path, REJECTED, p_reason, p_message);
	};

	std::vector<Contract> contracts(p_steps.size());
	for (size_t i = 0; i < p_steps.size(); i++) {
		const NNHTNTask *task = p_steps[i]->get_task();
		Contract &contract = contracts[i];
		contract.name = p_branches[i]->get_name();
		const PackedStringArray resources = task->get_actor_resources();
		const PackedStringArray reads = task->get_concurrency_read_keys();
		const PackedStringArray writes = task->get_concurrency_write_keys();
		if (!task->get_concurrency_contract_complete()) {
			conflict("CONTRACT_INCOMPLETE", vformat("'%s' does not set concurrency_contract_complete", contract.name));
			continue;
		}
		if (resources.has(String()) || reads.has(String()) || writes.has(String())) {
			conflict("CONTRACT_INCOMPLETE", vformat("'%s' has an empty concurrency contract entry", contract.name));
			continue;
		}
		contract.complete = true;
		for (const String &resource : resources) {
			contract.resources.insert(resource);
		}
		task->collect_concurrency_reads(contract.reads);
		p_branches[i]->collect_dependency_keys(contract.reads);
		for (const String &key : writes) {
			contract.writes.insert(key);
		}
		const Array effect_keys = p_steps[i]->get_effects().keys();
		for (int j = 0; j < effect_keys.size(); j++) {
			contract.writes.insert(effect_keys[j]);
		}
	}

	for (size_t i = 0; i < contracts.size(); i++) {
		for (size_t j = i + 1; j < contracts.size(); j++) {
			const Contract &left = contracts[i];
			const Contract &right = contracts[j];
			if (!left.complete || !right.complete) {
				continue;
			}
			const String resources = _shared_keys(left.resources, right.resources);
			if (!resources.is_empty()) {
				conflict("RESOURCE_CONFLICT", vformat("'%s' and '%s' both use actor resource %s", left.name, right.name, resources));
			}
			const String writes = _shared_keys(left.writes, right.writes);
			if (!writes.is_empty()) {
				conflict("WRITE_CONFLICT", vformat("'%s' and '%s' both write %s", left.name, right.name, writes));
			}
			const String left_reads = _shared_keys(left.reads, right.writes);
			if (!left_reads.is_empty()) {
				conflict("READ_WRITE_CONFLICT", vformat("'%s' reads %s, which '%s' writes", left.name, left_reads, right.name));
			}
			const String right_reads = _shared_keys(right.reads, left.writes);
			if (!right_reads.is_empty()) {
				conflict("READ_WRITE_CONFLICT", vformat("'%s' reads %s, which '%s' writes", right.name, right_reads, left.name));
			}
		}
	}

	HashSet<String> group_writes;
	const Array group_keys = p_group->get_effects().keys();
	for (int i = 0; i < group_keys.size(); i++) {
		group_writes.insert(group_keys[i]);
	}
	for (const Contract &contract : contracts) {
		const String shared = _shared_keys(group_writes, contract.writes);
		if (contract.complete && !shared.is_empty()) {
			conflict("GROUP_EFFECT_CONFLICT", vformat("the group's effects and '%s' both write %s", contract.name, shared));
		}
	}
	return conflicts;
}

void NNHTNSearch::_apply_effects(const Dictionary &p_effects) {
	const Array keys = p_effects.keys();
	for (int i = 0; i < keys.size(); i++) {
		_state.set_value(keys[i], p_effects[keys[i]]);
	}
}

bool NNHTNSearch::_accepts_effects(const NNHTNNodes *p_node, const Dictionary &p_effects) const {
	const Array keys = p_effects.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant &key = keys[i];
		if (key.get_type() != Variant::STRING || String(key).is_empty()) {
			ERR_PRINT(vformat("%s '%s': effect key %s is not a non-empty String; the occurrence is rejected.", p_node->get_class(), p_node->get_name(), key));
			return false;
		}
		if (_schema.is_valid() && !_schema->accepts(key, p_effects[key])) {
			ERR_PRINT(vformat("%s '%s': predicted effect rejected by the blackboard schema: %s. The occurrence is rejected.", p_node->get_class(), p_node->get_name(), _schema->describe_rejection(key, p_effects[key])));
			return false;
		}
	}
	return true;
}

bool NNHTNSearch::_cost_pruned(double p_cost) const {
	// Costs are non-negative, so a partial plan already this expensive cannot become cheaper.
	return _policy == NNHTNSearchSettings::LOWEST_COST && _has_best && p_cost >= _best_cost;
}

bool NNHTNSearch::_try_expand() {
	if (!_check_deadline()) {
		return false;
	}
	if (_expansions >= _settings->get_max_expansions()) {
		_mark_cutoff(vformat("expansion budget of %d reached", _settings->get_max_expansions()));
		return false;
	}
	_expansions++;
	return true;
}

bool NNHTNSearch::_check_deadline() {
	if (_cutoff) {
		return false;
	}
	if (_deadline_usec > 0 && Time::get_singleton()->get_ticks_usec() >= _deadline_usec) {
		_mark_cutoff(vformat("time budget of %d ms reached", _settings->get_max_time_ms()));
		return false;
	}
	return true;
}

void NNHTNSearch::_mark_cutoff(const String &p_reason) {
	_cutoff = true;
	_cutoff_reason = p_reason;
	_trace_event(NNHTNSearchTrace::NO_EVENT, KIND_SEARCH, String(), CUTOFF, "BUDGET_EXHAUSTED", p_reason);
}

void NNHTNSearch::_record_dependencies(const NNHTNNodes *p_node) {
	const uint64_t id = p_node->get_instance_id();
	if (_recorded_nodes.has(id)) {
		return;
	}
	_recorded_nodes.insert(id);
	p_node->collect_dependency_keys(_dependency_keys);
}

void NNHTNSearch::_note_hooks_called(const NNHTNNodes *p_node, uint64_t p_hook_reads_before) {
	// A hook that ran may have read any key, unless its node declares its reads complete.
	if (_state.get_hook_state_reads() != p_hook_reads_before && !p_node->get_dependencies_complete()) {
		_dependencies_wildcard = true;
	}
}

int NNHTNSearch::_trace_event(int p_parent_id, const char *p_kind, const String &p_path, const char *p_outcome, const char *p_reason, const String &p_detail, const Dictionary &p_args, const Dictionary &p_failure, int64_t p_occurrence_id) {
	if (_trace == nullptr) {
		return NNHTNSearchTrace::NO_EVENT;
	}
	return _trace->record(p_parent_id, p_kind, p_path, p_outcome, p_reason, p_detail, p_args, _state.get_values(), p_failure, p_occurrence_id);
}

double NNHTNSearch::_utility_of(const std::vector<Ref<NNHTNPlanStep>> &p_plan) {
	// Every selected method produced at least one step, so the steps' provenance names them all.
	HashSet<uint64_t> counted;
	double utility = 0.0;
	for (const Ref<NNHTNPlanStep> &step : p_plan) {
		for (const NNHTNProvenanceFrame &frame : step->provenance()) {
			if (!counted.has(frame.frame_id)) {
				counted.insert(frame.frame_id);
				utility += frame.priority;
			}
		}
	}
	return utility;
}

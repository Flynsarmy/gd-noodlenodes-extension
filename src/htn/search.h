#pragma once

#include "../blackboard_schema.h"
#include "nodes.h"
#include "plan_step.h"
#include "search_settings.h"
#include "search_trace.h"

#include <functional>
#include <godot_cpp/templates/hash_set.hpp>
#include <memory>
#include <variant>
#include <vector>

namespace godot {

class NNHTNBinding;
class NNHTNCompoundTask;
class NNHTNMethod;
class NNHTNParallelTask;
class NNHTNSubtaskCall;
class NNHTNTask;

// Depth-first HTN decomposition with backtracking, driven by explicit heap
// stacks so deep domains never grow the native call stack. Each search works
// on a private predicted copy of the world state and never touches the board.
class NNHTNSearch {
public:
	enum Status {
		FOUND,
		NO_PLAN,
		BUDGET_EXHAUSTED,
		INVALID_DOMAIN,
	};

	static constexpr size_t MAX_ACTIVE_COMPOUNDS = 64;

	struct Result {
		Status status = NO_PLAN;
		// Under LOWEST_COST a BUDGET_EXHAUSTED search may still return its best plan so far.
		std::vector<Ref<NNHTNPlanStep>> plan;
		int expansions = 0;
		double cost = 0.0;
		bool cost_optimal = false;
		// Sum of the priorities of the methods that produced the plan.
		double utility = 0.0;
		String cutoff_reason;
		// Keys read anywhere in the search, including rejected alternatives.
		HashSet<String> dependency_keys;
		bool dependencies_wildcard = false;
		// Why the last local solution's retained suffix was rejected, for a repair.
		String suffix_rejection;
	};

	// A local re-decomposition of p_node inside enclosing decompositions that stay in place.
	struct Boundary {
		NNHTNNodes *node = nullptr;
		Dictionary args;
		// The path p_node is reached from, with its name appended unless append_name is false.
		String path;
		bool append_name = true;
		int child_index = -1;
		// The enclosing method decompositions, outermost first, kept with their frame ids.
		std::vector<NNHTNProvenanceFrame> frames;
		std::vector<NNHTNCompoundTask *> active;
		// Planned occurrences that follow the boundary. Each local solution keeps them only if
		// they are still available and their effects still fit, in order, on its prediction.
		std::vector<Ref<NNHTNPlanStep>> suffix;
	};

	// p_trace, when given, receives the decision events of an attempt the caller has begun.
	Result plan(NNHTNCompoundTask *p_domain, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace);
	// Plans p_boundary from p_state. A found plan is the local solution followed by the suffix.
	Result repair(const Boundary &p_boundary, const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace);

private:
	// Judges each complete prediction: ACCEPT ends the search, CONTINUE backtracks
	// for another so an exhaustive policy can compare plans.
	enum class TerminalDecision {
		ACCEPT,
		CONTINUE,
	};
	using Terminal = std::function<TerminalDecision()>;

	// A method's enabled children and, for PARTIAL_ORDER, each child's predecessor indices.
	struct Schedule {
		std::vector<NNHTNNodes *> children;
		bool partial_order = false;
		std::vector<std::vector<int>> predecessors;
	};

	// Raw node pointers live only for one synchronous search; planning hooks must not mutate the scene.
	struct WorkItem {
		enum Kind {
			NODE,
			END_METHOD,
			// Schedules the next ready child of a PARTIAL_ORDER method.
			ORDER,
			// Ends a serialized parallel group whose branches were planned from plan_base on.
			END_SERIALIZED_GROUP,
		};
		Kind kind = NODE;
		NNHTNNodes *node = nullptr;
		Dictionary args;
		String path;
		int child_index = -1;
		bool append_name = true;
		size_t frame_depth = 0;
		int trace_parent = NNHTNSearchTrace::NO_EVENT;
		std::shared_ptr<const Schedule> schedule;
		std::vector<bool> scheduled;
		size_t plan_base = 0;
	};

	// Stack sizes, log lengths and trail length a choice point rewinds to before each alternative.
	struct Mark {
		size_t state_trail = 0;
		size_t pending_size = 0;
		size_t pending_trail = 0;
		size_t frame_size = 0;
		size_t frame_trail = 0;
		size_t active_size = 0;
		size_t active_trail = 0;
		size_t plan_size = 0;
		double plan_cost = 0.0;
	};

	// Undo records for the pops that a live mark can still need, replayed newest first.
	struct PendingUndo {
		size_t depth = 0;
		WorkItem item;
	};

	struct FrameUndo {
		enum Kind {
			POPPED,
			CHILD_INDEX,
		};
		Kind kind = POPPED;
		size_t depth = 0;
		int child_index = -1;
		NNHTNProvenanceFrame frame;
	};

	struct ActiveUndo {
		size_t depth = 0;
		NNHTNCompoundTask *compound = nullptr;
	};

	struct RankedMethod {
		NNHTNMethod *method = nullptr;
		double priority = 0.0;
	};

	// One binding's values for one partial assignment of the bindings before it.
	struct BindingLevel {
		std::vector<Variant> values;
		size_t value_index = 0;
		Dictionary parent_args;
	};

	// A compound's untried methods, each method's argument candidates, and each
	// candidate's binding combinations, all enumerated lazily.
	struct MethodChoice {
		NNHTNCompoundTask *compound = nullptr;
		Dictionary args;
		String path;
		int trace_id = NNHTNSearchTrace::NO_EVENT;
		std::vector<RankedMethod> methods;
		size_t method_index = 0;
		bool method_entered = false;
		std::shared_ptr<const Schedule> schedule;
		std::vector<Dictionary> candidates;
		size_t candidate_index = 0;
		std::vector<BindingLevel> binding_levels;
	};

	// The ready children of a PARTIAL_ORDER method that may be scheduled next.
	struct OrderChoice {
		WorkItem item;
		std::vector<int> ready;
		size_t ready_index = 0;
	};

	struct ChoicePoint {
		Mark mark;
		std::variant<MethodChoice, OrderChoice> choice;
	};

	struct Alternative {
		NNHTNMethod *method = nullptr;
		Dictionary args;
		double priority = 0.0;
		std::shared_ptr<const Schedule> schedule;
	};

	const NNHTNSearchSettings *_settings = nullptr;
	NNHTNSearchSettings::Policy _policy = NNHTNSearchSettings::ORDERED;
	Ref<NNBlackboardSchema> _schema;
	NNHTNSearchTrace *_trace = nullptr;

	NNHTNStateView _state;
	std::vector<Ref<NNHTNPlanStep>> _plan;
	double _plan_cost = 0.0;
	std::vector<WorkItem> _pending;
	std::vector<ChoicePoint> _choice_points;
	std::vector<NNHTNProvenanceFrame> _frames;
	std::vector<NNHTNCompoundTask *> _active;
	std::vector<PendingUndo> _pending_undo;
	std::vector<FrameUndo> _frame_undo;
	std::vector<ActiveUndo> _active_undo;
	// Lowest stack size since the newest mark: pops at or above it are still in place at the mark.
	size_t _pending_low = 0;
	size_t _frames_low = 0;
	size_t _active_low = 0;
	// Identifies the newest mark, so a frame logs its child index once per mark.
	uint64_t _epoch = 0;
	std::vector<uint64_t> _frame_child_epochs;
	// Never reset, so a repair's new frames cannot collide with those of the steps it keeps.
	uint64_t _next_frame_id = 1;
	uint64_t _next_group_id = 1;
	String _suffix_rejection;

	bool _has_best = false;
	std::vector<Ref<NNHTNPlanStep>> _best_plan;
	double _best_cost = 0.0;

	int _expansions = 0;
	uint64_t _deadline_usec = 0;
	bool _cutoff = false;
	String _cutoff_reason;
	bool _candidates_truncated = false;

	HashSet<String> _dependency_keys;
	bool _dependencies_wildcard = false;
	HashSet<uint64_t> _recorded_nodes;

	void _begin(const Dictionary &p_state, const NNHTNSearchSettings &p_settings, const Ref<NNBlackboardSchema> &p_schema, NNHTNSearchTrace *p_trace);
	Result _finish(bool p_found);
	void _end();
	bool _run(std::vector<WorkItem> &&p_pending, const Terminal &p_terminal);
	bool _backtrack();
	// Starts the choice point's next alternative. Returns false once none is left.
	bool _resume(ChoicePoint &r_choice_point);
	// Records the mark and makes it the one whose alternatives decide what is logged.
	Mark _mark();
	void _restore(const Mark &p_mark);
	void _begin_epoch();
	// Popped entries are kept in the undo logs so a choice point can put them back.
	void _pop_active();
	void _pop_frames(size_t p_depth);

	bool _process_node(const WorkItem &p_item);
	bool _process_compound(NNHTNCompoundTask *p_compound, const Dictionary &p_args, const String &p_path, int p_trace_parent);
	bool _process_task(NNHTNTask *p_task, const Dictionary &p_args, const String &p_path, int p_trace_parent);
	bool _process_order(const WorkItem &p_item);
	bool _process_group(NNHTNParallelTask *p_group, const WorkItem &p_item, const Dictionary &p_args, const String &p_path);
	// Plans p_group's branches in scene order under SERIALIZE, else rejects it.
	bool _serialize_or_reject(NNHTNParallelTask *p_group, const std::vector<NNHTNNodes *> &p_branches, const WorkItem &p_item, const Dictionary &p_args, const String &p_path, int p_trace_id, const char *p_reason, const String &p_detail, bool p_conflict);
	void _finish_serialized_group(const WorkItem &p_item);
	// Why the grounded branches may not run together, one entry per conflict, each traced with its reason.
	PackedStringArray _group_conflicts(const NNHTNParallelTask *p_group, const std::vector<NNHTNNodes *> &p_branches, const std::vector<Ref<NNHTNPlanStep>> &p_steps, const String &p_path, int p_trace_id);

	// Resolves p_call's template and arguments and appends the template's name to r_path. Rejections are traced.
	bool _resolve_call(NNHTNSubtaskCall *p_call, const Dictionary &p_args, int p_trace_parent, NNHTNNodes *&r_node, Dictionary &r_args, String &r_path);
	bool _ground_branch(NNHTNNodes *p_branch, const Dictionary &p_args, const String &p_group_path, int p_trace_parent, Ref<NNHTNPlanStep> &r_step);
	// Builds p_task's occurrence against the predicted state without applying it. Rejections are traced.
	bool _ground_task(NNHTNTask *p_task, const Dictionary &p_args, const String &p_path, int p_trace_parent, Ref<NNHTNPlanStep> &r_step);

	std::vector<RankedMethod> _rank_methods(NNHTNCompoundTask *p_compound, const Dictionary &p_args, const String &p_path, int p_trace_parent);
	bool _next_alternative(MethodChoice &r_choice, Alternative &r_alternative);
	// Resolves the current method's schedule and argument candidates. Returns false when it is unusable.
	bool _enter_method(MethodChoice &r_choice, NNHTNMethod *p_method, const String &p_method_path);
	bool _next_candidate_args(MethodChoice &r_choice, NNHTNMethod *p_method, const String &p_method_path, Dictionary &r_args);
	bool _next_binding_args(MethodChoice &r_choice, const TypedArray<NNHTNBinding> &p_bindings, const String &p_method_path, Dictionary &r_args);
	// Collects the values of binding p_index for p_parent_args. Returns false at a cutoff.
	bool _push_binding_level(MethodChoice &r_choice, const TypedArray<NNHTNBinding> &p_bindings, int p_index, const Dictionary &p_parent_args, const String &p_method_path);
	bool _start_alternative(const MethodChoice &p_choice, const Alternative &p_alternative);
	// Pushes a method's children so the first one to plan is processed next.
	void _schedule_children(const std::shared_ptr<const Schedule> &p_schedule, const Dictionary &p_args, const String &p_path, int p_trace_parent);
	void _schedule_ready_child(const WorkItem &p_item, int p_index, int p_trace_parent);
	void _finish_method(const WorkItem &p_item);
	TerminalDecision _keep_cheapest();
	// Appends p_suffix to the plan when it still fits the prediction. Returns false with the reason otherwise.
	bool _append_suffix(const std::vector<Ref<NNHTNPlanStep>> &p_suffix);

	bool _accepts_effects(const NNHTNNodes *p_node, const Dictionary &p_effects) const;
	void _apply_effects(const Dictionary &p_effects);
	bool _cost_pruned(double p_cost) const;
	bool _try_expand();
	bool _check_deadline();
	void _mark_cutoff(const String &p_reason);
	void _record_dependencies(const NNHTNNodes *p_node);
	void _note_hooks_called(const NNHTNNodes *p_node, uint64_t p_hook_reads_before);
	int _trace_event(int p_parent_id, const char *p_kind, const String &p_path, const char *p_outcome, const char *p_reason, const String &p_detail = String(), const Dictionary &p_args = Dictionary(), const Dictionary &p_failure = Dictionary(), int64_t p_occurrence_id = 0);
	static double _utility_of(const std::vector<Ref<NNHTNPlanStep>> &p_plan);
};

} //namespace godot

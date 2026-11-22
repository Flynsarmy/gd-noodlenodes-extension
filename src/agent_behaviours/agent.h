#pragma once

#include "../debugger/blackboard_watch.h"
#include "../debugger/debug_root.h"
#include "../host.h"
#include "../root_context.h"
#include "../tick_scheduler.h"
#include "noodle_nodes.h"

#include "performance_monitor_singleton.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>

#include "action.h"
#include "behaviour.h"
#include "behaviour_group.h"
#include "sensors.h"
#include <godot_cpp/core/object_id.hpp>
#include <memory>
#include <vector>

namespace godot {

class NNAgent : public NoodleNodes {
	GDCLASS(NNAgent, NoodleNodes)

private:
	NNRootContext _root_context;

	Ref<RandomNumberGenerator> _rng;
	// Scene nodes are tracked by instance ID. They can be freed, removed or
	// reparented from arbitrary engine/user callbacks between uses, so a raw
	// pointer must never be kept as durable state.
	ObjectID _current_behaviour_group_id;
	ObjectID _current_behaviour_id;
	ObjectID _current_action_id;
	// An action started during behaviour selection is reported through
	// action_changed on the next update_current_behaviour(), where the signal
	// is documented to fire.
	bool _current_action_change_pending;

	float _current_behaviour_bias;

	struct TopScoringBehaviour {
		ObjectID group_id;
		ObjectID behaviour_id;
		float score;
	};

	int _num_behaviours_to_select;
	std::vector<TopScoringBehaviour> _top_scoring_behaviours;
	godot::String _top_scoring_behaviour_name;
	godot::String _current_behaviour_name;

	NNTickScheduler _tick_scheduler;
	NNHostedRoot _hosted_root;
#ifdef DEBUG_ENABLED
	NNDebugRoot _debug_root;
	NNBlackboardDebugWatch _debug_blackboard_watch;
	// The most recent non-zero behaviour chosen, kept after it completes.
	ObjectID _debug_last_behaviour_id;
#endif

#ifdef DEBUG_ENABLED
	// Records the elapsed usec on scope exit, so every early return reports once.
	class NNTimingScope {
	public:
		NNTimingScope(uint64_t &total_usec, void (NNPerformanceMonitorSingleton::*increment)(uint64_t)) :
				_start_usec(godot::Time::get_singleton()->get_ticks_usec()), _total_usec(total_usec), _increment(increment) {}
		~NNTimingScope() {
			_total_usec = godot::Time::get_singleton()->get_ticks_usec() - _start_usec;
			(NNPerformanceMonitorSingleton::get_singleton()->*_increment)(_total_usec);
		}

		inline uint64_t get_start_usec() const { return _start_usec; }

	private:
		uint64_t _start_usec;
		uint64_t &_total_usec;
		void (NNPerformanceMonitorSingleton::*_increment)(uint64_t);
	};

	uint64_t _total_evaluate_options_usec;
	uint64_t _total_update_behaviour_usec;
#endif

	// Immutable snapshots: a refresh rebinds the pointer and leaves any list
	// still being iterated alive.
	std::shared_ptr<const std::vector<ObjectID>> _child_sensor_ids;
	std::shared_ptr<const std::vector<ObjectID>> _child_behaviour_ids;
	void _refresh_child_caches();
	void _reconcile_selected_nodes();
	void _end_current_action(bool emit_action_changed);
	enum class BehaviourExit {
		DESELECTED,
		ABORTED,
		COMPLETED,
	};
	void _exit_current_behaviour(BehaviourExit exit);
	void _exit_behaviour_group(ObjectID behaviour_group_id, bool require_direct_child = false);
	void _tick_selected_nodes(const char *signal_name, double delta);
	void _advance_behaviour_cooldowns(double delta);

	void _on_scene_tree_process_frame();
	void _on_scene_tree_physics_frame();
	bool _auto_tick_step_callback(double p_delta, double p_tick_delta, bool p_due);

	NNBehaviourGroup *_resolve_behaviour_group(const ObjectID &behaviour_group_id) const;
	NNBehaviour *_resolve_behaviour(const ObjectID &behaviour_id) const;
	NNAction *_resolve_action(const ObjectID &action_id) const;

	bool _is_behaviour_available(NNBehaviour *behaviour) const;
	bool _is_action_available(NNAction *action, NNBehaviour *behaviour) const;

	NNSensors *_get_child_sensor(const ObjectID &sensor_id) const;
	NNBehaviours *_get_child_behaviour(const ObjectID &behaviour_id) const;
	NNBehaviours *_get_group_child_behaviour(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id) const;
	NNBehaviour *_get_candidate(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id) const;
	void _emit_node_signal(const char *signal_name, const ObjectID &node_id);

#ifdef DEBUG_ENABLED
	void _debug_record_action_changed(const ObjectID &p_action_id);
	void _debug_record_behaviour_changed(const ObjectID &p_behaviour_id, const ObjectID &p_group_id, const ObjectID &p_action_id);
#endif

protected:
	static void _bind_methods();
	void place_into_top_n_behaviour_list(const ObjectID &behaviour_group_id, const ObjectID &behaviour_id, float score);

	virtual void _on_is_enabled_changed(bool p_is_enabled) override;

#ifdef DEBUG_ENABLED
	uint64_t _last_evaluated_timestamp;
	uint64_t _last_visited_timestamp;
#endif
public:
	enum ProcessThread {
		IDLE = NNTickScheduler::IDLE,
		PHYSICS = NNTickScheduler::PHYSICS,
		MANUAL = NNTickScheduler::MANUAL,
	};

	NNAgent();
	~NNAgent();

	// Getters and setters for attributes.

	bool is_root() const override { return true; }

	NNHostedRoot *get_hosted_root() override { return &_hosted_root; }
#ifdef DEBUG_ENABLED
	NNDebugRoot *get_debug_root() override { return &_debug_root; }
	NNBlackboardDebugWatch *get_debug_blackboard_watch() override { return &_debug_blackboard_watch; }
	Dictionary get_debug_snapshot() const override;
#endif

	void set_assigned_blackboard(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_assigned_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
	// The debug overlay peeks these so a refresh never reconciles the agent.
	NNBehaviour *peek_current_behaviour() const;
	NNAction *peek_current_action() const;
	NNBehaviourGroup *peek_current_behaviour_group() const;
	// The most recently chosen behaviour, resolved through ObjectDB so a freed
	// one reads as null. Kept after the behaviour completes or is deselected.
	NNBehaviour *peek_last_behaviour() const;
	// [{ "behaviour": id, "group": id, "score": float }] best first.
	Array get_debug_top_scoring() const;
#endif

	void set_process_thread(int p_process_thread);
	int get_process_thread() const;
	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;

	NNBehaviourGroup *get_current_behaviour_group_node() const;

	NNBehaviour *get_current_behaviour_node() const;

	godot::String get_current_behaviour_name() const;

	void set_num_behaviours_to_select(int num_behaviours_to_select);
	int get_num_behaviours_to_select() const;

	void set_current_behaviour_bias(float current_behaviour_bias);
	float get_current_behaviour_bias() const;

	void set_random_seed(uint64_t random_seed);
	uint64_t get_random_seed() const;

	godot::String get_top_scoring_behaviour_name() const;

	NNAction *get_current_action_node() const;

#ifdef DEBUG_ENABLED
	uint64_t get_total_evaluate_options_usec() const;

	uint64_t get_total_update_behaviour_usec() const;
#endif
	// Handling functions.

	void evaluate_options(float delta);

	void update_current_behaviour();

	void tick(double delta);

	bool auto_tick_step(int p_process_thread, double p_delta);

	void set_current_action_is_finished(bool is_finished);
	void abort_current_behaviour();

	// Godot virtuals
	void _notification(int p_what);
	virtual PackedStringArray _get_configuration_warnings() const override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNAgent::ProcessThread)

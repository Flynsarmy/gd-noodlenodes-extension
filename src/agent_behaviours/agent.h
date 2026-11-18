#pragma once

#include "../host.h"
#include "../root_context.h"
#include "../tick_scheduler.h"
#include "noodle_nodes.h"

#include "performance_monitor_singleton.h"
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>

#include "action.h"
#include "behaviour.h"
#include "behaviour_group.h"
#include "sensors.h"
#include <godot_cpp/core/object_id.hpp>
#include <vector>

#define UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS 16

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

	int _num_behaviours_to_select;
	int _num_possible_behaviours;
	ObjectID _top_scoring_behaviour_group_ids[UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS];
	ObjectID _top_scoring_behaviour_ids[UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS];
	float _top_scoring_behaviours_score[UTILITYAIAGENT_MAX_TOP_SCORING_BEHAVIOURS];
	godot::String _top_scoring_behaviour_name;
	godot::String _current_behaviour_name;

	NNTickScheduler _tick_scheduler;
	NNHostedRoot _hosted_root;

#ifdef DEBUG_ENABLED
	uint64_t _total_evaluate_options_usec;
	uint64_t _total_update_behaviour_usec;
#endif

	std::vector<ObjectID> _child_sensor_ids;
	std::vector<ObjectID> _child_behaviour_ids;
	void _refresh_child_caches();
	void _reconcile_selected_nodes();
	void _end_current_action(bool emit_action_changed);
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

	void set_blackboard_resource(const Ref<NNBlackboard> &p_blackboard);
	Ref<NNBlackboard> get_assigned_blackboard() const;
	NNBlackboard *get_blackboard_resource() const override;

	void set_actor(Node *p_actor);
	Node *get_assigned_actor() const;
	Node *get_actor() const override;
	void set_actor_node_path(const NodePath &p_actor_node_path);
	NodePath get_actor_node_path() const;

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
#endif

	void set_process_thread(int p_process_thread);
	int get_process_thread() const;
	void set_tick_rate(int p_tick_rate);
	int get_tick_rate() const;

	void set_current_behaviour_group_node(NNBehaviourGroup *new_behaviour_group_node);
	NNBehaviourGroup *get_current_behaviour_group_node() const;

	void set_current_behaviour_node(NNBehaviour *new_behaviour_node);
	NNBehaviour *get_current_behaviour_node() const;

	void set_current_behaviour_name(godot::String current_behaviour_name);
	godot::String get_current_behaviour_name() const;

	void set_num_behaviours_to_select(int num_behaviours_to_select);
	int get_num_behaviours_to_select() const;

	void set_current_behaviour_bias(float current_behaviour_bias);
	float get_current_behaviour_bias() const;

	void set_random_seed(uint64_t random_seed);
	uint64_t get_random_seed() const;

	void set_top_scoring_behaviour_name(godot::String top_scoring_behaviour_name);
	godot::String get_top_scoring_behaviour_name() const;

	void set_current_action_node(NNAction *new_action_node);
	NNAction *get_current_action_node() const;

#ifdef DEBUG_ENABLED
	void set_total_evaluate_options_usec(uint64_t total_evaluate_options_usec);
	uint64_t get_total_evaluate_options_usec() const;

	void set_total_update_behaviour_usec(uint64_t total_update_behaviour_usec);
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

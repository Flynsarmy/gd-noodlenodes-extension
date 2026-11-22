#pragma once

#include "noodle_nodes.h"
#include <godot_cpp/classes/node.hpp>

#include "action.h"
#include "action_group.h"
#include "behaviours.h"
#include "considerations.h"
#include <vector>

namespace godot {

class NNBehaviour : public NNBehaviours {
	GDCLASS(NNBehaviour, NNBehaviours)

private:
	float _cooldown_seconds;
	float _current_cooldown_seconds;
	float _seconds_since_active;
	bool _is_active;
	int _cooldown_turns;
	int _current_cooldown_turns;
	int _behaviour_id;
	int _current_action_index;

	bool _can_be_interrupted;

	String _on_selected_event;
	NodePath _on_selected_event_path;

protected:
	static void _bind_methods();
#ifdef DEBUG_ENABLED
	uint64_t _last_evaluated_timestamp;
	uint64_t _last_visited_timestamp;
#endif
public:
	NNBehaviour();
	~NNBehaviour();

	// Getters and setters for attributes.

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
	inline float get_debug_cooldown_remaining() const { return _current_cooldown_seconds; }
	inline int get_debug_cooldown_turns_remaining() const { return _current_cooldown_turns; }
#endif

	void set_behaviour_id(int behaviour_id);
	int get_behaviour_id() const;

	void set_can_be_interrupted(bool can_be_interrupted);
	bool get_can_be_interrupted() const;

	void set_cooldown_seconds(float cooldown_seconds);
	float get_cooldown_seconds() const;

	void set_cooldown_turns(int cooldown_turns);
	int get_cooldown_turns() const;

	float get_seconds_since_active() const;

	void set_on_selected_event(const String &on_selected_event);
	String get_on_selected_event() const;

	void set_on_selected_event_path(const NodePath &on_selected_event_path);
	NodePath get_on_selected_event_path() const;

	void set_current_action_index(int current_action_index);
	int get_current_action_index() const;

	// Godot virtuals.
	void _ready() override;

	// Handling functions.

	void advance_cooldown(double delta);
	float evaluate() override;
	NNAction *start_behaviour();
	void end_behaviour();
	NNAction *update_behaviour();

	Node *step_actions();
};

} //namespace godot

#pragma once

#include "noodle_nodes.h"
#include <godot_cpp/classes/node.hpp>

#include "considerations.h"
#include <godot_cpp/core/object_id.hpp>
#include <vector>

namespace godot {

class NNBehaviours : public NoodleNodes {
	GDCLASS(NNBehaviours, NoodleNodes)

private:
protected:
	static void _bind_methods();
#ifdef DEBUG_ENABLED
	uint64_t _last_evaluated_timestamp;
	uint64_t _last_visited_timestamp;
#endif

	EvaluationMethod _evaluation_method;

	float _score;

	std::vector<NNConsiderations *> _child_considerations;
	unsigned int _num_child_considerations;

	// Child behaviours are stored by instance ID. A child can be freed by user
	// code while its parent still holds cached state, so the pointers must be
	// resolved through ObjectDB before every use.
	std::vector<ObjectID> _child_behaviour_ids;
	unsigned int _num_child_behaviours;

public:
	NNBehaviours() {
		_score = 0.0f;
		_evaluation_method = EVALUATION_MULTIPLY;
#ifdef DEBUG_ENABLED
		_last_evaluated_timestamp = 0;
		_last_visited_timestamp = 0;
#endif
	};

	// Getters and setters for attributes.

	void set_evaluation_method(EvaluationMethod evaluation_method);
	EvaluationMethod get_evaluation_method() const;

#ifdef DEBUG_ENABLED
	inline uint64_t get_last_visited_timestamp() const { return _last_visited_timestamp; };
	inline uint64_t get_last_evaluated_timestamp() const { return _last_evaluated_timestamp; };
	inline void set_last_visited_timestamp(uint64_t new_timestamp) { _last_visited_timestamp = new_timestamp; };
	inline void set_last_evaluated_timestamp(uint64_t new_timestamp) { _last_evaluated_timestamp = new_timestamp; };
#endif

	void set_score(float score) { _score = score; };
	float get_score() const { return _score; };

	std::vector<ObjectID> get_child_behaviour_ids() const { return _child_behaviour_ids; };
	ObjectID get_child_behaviour_id(unsigned int index) const;
	NNBehaviours *get_child_behaviour(unsigned int index) const;
	unsigned int get_num_child_behaviours() const { return _num_child_behaviours; };

	void _notification(int p_what);

	// Handling functions.

	virtual float evaluate() {
		_score = 0.0f;
		return _score;
	};
	virtual bool is_behaviour_group() const { return false; };
	virtual float get_activation_score() const { return 0.0f; };
};

} //namespace godot

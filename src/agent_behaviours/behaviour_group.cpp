#include "behaviour_group.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../score_aggregation.h"
#include "consideration.h"

using namespace godot;

// Method binds.

void NNBehaviourGroup::_bind_methods() {
	ADD_SUBGROUP("Configuration", "");
	ClassDB::bind_method(D_METHOD("set_activation_score", "activation_score"), &NNBehaviourGroup::set_activation_score);
	ClassDB::bind_method(D_METHOD("get_activation_score"), &NNBehaviourGroup::get_activation_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "activation_score", PROPERTY_HINT_RANGE, "0.0,1.0"), "set_activation_score", "get_activation_score");

	ADD_SUBGROUP("Debugging", "");

	// Signals.
	ADD_SIGNAL(MethodInfo("behaviour_group_entered"));
	ADD_SIGNAL(MethodInfo("frame_tick", PropertyInfo(Variant::FLOAT, "delta")));
	ADD_SIGNAL(MethodInfo("behaviour_group_exited"));
}

// Constructor and destructor.

NNBehaviourGroup::NNBehaviourGroup() {
	_score = 0.0;
	_activation_score = 0.0;
}

NNBehaviourGroup::~NNBehaviourGroup() {
}

// Getters and Setters.

void NNBehaviourGroup::set_activation_score(float activation_score) {
	_activation_score = activation_score;
}

float NNBehaviourGroup::get_activation_score() const {
	return _activation_score;
}

// Handling functions.

float NNBehaviourGroup::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	int num_children = get_child_count();
	_score = 0.0f;
	if (num_children < 1)
		return _score;

	// For the behaviour groups the considerations are evaluated and
	// compared to the set value to determine if the behaviours
	// within the group should be evaluated.
	ScoreAggregation aggregation(_evaluation_method);

	// Evaluate the children.
	for (unsigned int i = 0; i < _num_child_considerations; i++) {
		NNConsiderations *considerationsNode = _child_considerations[i];
		if (!considerationsNode->get_is_enabled())
			continue;
		float child_score = considerationsNode->evaluate();
		if (considerationsNode->get_has_vetoed()) {
			_score = 0.0f;
			return _score;
		}
		if (aggregation.add(child_score)) {
			break;
		}
	} //endfor children

	_score = aggregation.result();
	return _score;
}

#include "score_based_picker.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

// Method binds.

void NNBTScoreBasedPicker::_bind_methods() {
}

// Constructor and destructor.

NNBTScoreBasedPicker::NNBTScoreBasedPicker() {
	_current_child_index = -1;
}

NNBTScoreBasedPicker::~NNBTScoreBasedPicker() {
}

// Handling functions.

// Getters and Setters.

void NNBTScoreBasedPicker::_on_before_run(float delta) {
	// Evaluate the scores and pick the child with the highest
	// score to run.
	_current_child_index = -1;
	float current_highest_score = -99999999.9999;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}
		// Evaluate the node to get its score.
		float score = btnode->evaluate();
		if (score > current_highest_score) {
			_current_child_index = i;
			current_highest_score = score;
		}
	} //endfor children
}

NNBTNodes::Status NNBTScoreBasedPicker::_tick(float delta) {
	if (_current_child_index < 0) {
		return Status::FAILURE; // No valid child found.
	}

	NNBTNodes *btnode = _child_btnodes[_current_child_index];
	if (btnode != nullptr) {
		Status return_value = btnode->tick(delta);
		if (return_value == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
		}
		return return_value;
	} //endif node was of correct type
	return Status::FAILURE;
}

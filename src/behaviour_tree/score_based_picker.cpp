#include "score_based_picker.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

using namespace godot;

// Method binds.

void NNBTScoreBasedPicker::_bind_methods() {
}

// Constructor and destructor.

NNBTScoreBasedPicker::NNBTScoreBasedPicker() {
	_selected_child = nullptr;
}

NNBTScoreBasedPicker::~NNBTScoreBasedPicker() {
}

// Handling functions.

void NNBTScoreBasedPicker::update_child_vectors() {
	NNBTNodes::update_child_vectors();

	if (_selected_child != nullptr && std::find(_child_btnodes.begin(), _child_btnodes.end(), _selected_child) == _child_btnodes.end()) {
		// The selected child left mid-run, so the next tick fails the run and
		// the run after that picks a new child from the survivors.
		_selected_child = nullptr;
	}
}

// Getters and Setters.

void NNBTScoreBasedPicker::_on_before_run(float delta) {
	// Evaluate the scores and pick the child with the highest
	// score to run.
	_selected_child = nullptr;
	float current_highest_score = -99999999.9999;
	for (NNBTNodes *btnode : _child_btnodes) {
		if (!btnode->get_is_enabled()) {
			continue;
		}
		// Evaluate the node to get its score.
		float score = btnode->evaluate();
		if (score > current_highest_score) {
			_selected_child = btnode;
			current_highest_score = score;
		}
	} //endfor children
}

NNBTNodes::Status NNBTScoreBasedPicker::_tick(float delta) {
	if (_selected_child == nullptr) {
		return Status::FAILURE; // No valid child found.
	}

	Status return_value = _selected_child->tick(delta);
	if (return_value == Status::RUNNING) {
		_interrupt_other_active_children(_selected_child);
	}
	return return_value;
}

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

void NNBTScoreBasedPicker::reset_bt_node() {
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

NNBTNodes::Status NNBTScoreBasedPicker::_tick(Variant blackboard, float delta) {
	if (get_internal_status() == BT_INTERNAL_STATUS_UNTICKED) {
		reset_bt_node();
	}

	set_internal_status(BT_INTERNAL_STATUS_TICKED);

	if (_current_child_index < 0) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE; // No valid child found.
	}

	NNBTNodes *btnode = _child_btnodes[_current_child_index];
	if (btnode != nullptr) {
		Status return_value = btnode->tick(blackboard, delta);
		set_tick_result(return_value);
		if (return_value == Status::FAILURE || return_value == Status::SUCCESS) {
			_current_child_index = -1;
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		} else if (return_value == Status::RUNNING) {
			_interrupt_other_active_children(btnode);
		}
		return return_value;
	} //endif node was of correct type
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	return Status::FAILURE;
}

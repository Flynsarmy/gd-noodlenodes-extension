#include "consideration_group.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include "../score_aggregation.h"

using namespace godot;

// Method binds.

void NNConsiderationGroup::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_evaluation_method", "evaluation_method"), &NNConsiderationGroup::set_evaluation_method);
	ClassDB::bind_method(D_METHOD("get_evaluation_method"), &NNConsiderationGroup::get_evaluation_method);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "evaluation_method", PROPERTY_HINT_ENUM, "Sum,Min,Max,Mean,Multiply,First Non Zero", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_CLASS_IS_ENUM, "NoodleNodes.EvaluationMethod"), "set_evaluation_method", "get_evaluation_method");

	ClassDB::bind_method(D_METHOD("set_invert_score", "invert_score"), &NNConsiderationGroup::set_invert_score);
	ClassDB::bind_method(D_METHOD("get_invert_score"), &NNConsiderationGroup::get_invert_score);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "invert_score", PROPERTY_HINT_NONE), "set_invert_score", "get_invert_score");
}

// Constructor and destructor.

NNConsiderationGroup::NNConsiderationGroup() {
	_evaluation_method = EVALUATION_MULTIPLY;
	_invert_score = false;
}

NNConsiderationGroup::~NNConsiderationGroup() {
}

// Getters and Setters.

void NNConsiderationGroup::set_evaluation_method(EvaluationMethod evaluation_method) {
	_evaluation_method = evaluation_method;
}

NoodleNodes::EvaluationMethod NNConsiderationGroup::get_evaluation_method() const {
	return _evaluation_method;
}

void NNConsiderationGroup::set_invert_score(bool invert_score) {
	_invert_score = invert_score;
}

bool NNConsiderationGroup::get_invert_score() const {
	return _invert_score;
}

// Handling functions.

float NNConsiderationGroup::evaluate() {
#ifdef DEBUG_ENABLED
	_last_evaluated_timestamp = godot::Time::get_singleton()->get_ticks_usec();
#endif

	_score = 0.0f;
	_has_vetoed = false;

	if (_child_considerations.empty()) {
		return _score;
	}

	ScoreAggregation aggregation(_evaluation_method);
	for (unsigned int i = 0; i < _child_considerations.size(); i++) {
		NNConsiderations *consideration = _child_considerations[i];
		if (!consideration->get_is_enabled()) {
			continue;
		}
		float child_score = consideration->evaluate();
		if (consideration->get_has_vetoed()) {
			_has_vetoed = true;
			return _score;
		}
		if (aggregation.add(child_score)) {
			break;
		}
	}

	_score = aggregation.result();
	if (_invert_score) {
		_score = 1.0f - _score;
	}

	return _score;
}

// Godot virtuals.

void NNConsiderationGroup::_notification(int p_what) {
	if (p_what != NOTIFICATION_CHILD_ORDER_CHANGED) {
		return;
	}

	_child_considerations.clear();
	for (int i = 0; i < get_child_count(); i++) {
		if (NNConsiderations *consideration = godot::Object::cast_to<NNConsiderations>(get_child(i))) {
			_child_considerations.push_back(consideration);
		}
	}
}

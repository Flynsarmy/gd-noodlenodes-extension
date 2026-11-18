#include "nqs_query.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

// Method binds.

void NNNQSQuerySensor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_nqs_search_space", "nqs_search_space"), &NNNQSQuerySensor::set_nqs_search_space);
	ClassDB::bind_method(D_METHOD("get_nqs_search_space"), &NNNQSQuerySensor::get_nqs_search_space);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "nqs_search_space", PROPERTY_HINT_NODE_TYPE, "NNNQSSearchSpaces"), "set_nqs_search_space", "get_nqs_search_space");

	ClassDB::bind_method(D_METHOD("set_is_high_priority", "is_high_priority"), &NNNQSQuerySensor::set_is_high_priority);
	ClassDB::bind_method(D_METHOD("get_is_high_priority"), &NNNQSQuerySensor::get_is_high_priority);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_high_priority", PROPERTY_HINT_NONE), "set_is_high_priority", "get_is_high_priority");

	ClassDB::bind_method(D_METHOD("set_best_result_key", "best_result_key"), &NNNQSQuerySensor::set_best_result_key);
	ClassDB::bind_method(D_METHOD("get_best_result_key"), &NNNQSQuerySensor::get_best_result_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "best_result_key", PROPERTY_HINT_NONE), "set_best_result_key", "get_best_result_key");
}

// Constructor and destructor.

NNNQSQuerySensor::NNNQSQuerySensor() {
	set_sensor_value(0.0f);
	_is_high_priority = true;
	_best_result_key = "nqs_result";
	_query_state = QueryState::IDLE;
	_posted_query_registration = 0;
}

NNNQSQuerySensor::~NNNQSQuerySensor() {
	_cancel_posted_query();
}

// Getters and Setters.

void NNNQSQuerySensor::set_nqs_search_space(NNNQSSearchSpaces *nqs_search_space) {
	ObjectID search_space_id = nqs_search_space != nullptr ? ObjectID(nqs_search_space->get_instance_id()) : ObjectID();
	if (_nqs_search_space_cache == search_space_id) {
		return;
	}
	_cancel_posted_query();
	_nqs_search_space_cache = search_space_id;
}

NNNQSSearchSpaces *NNNQSQuerySensor::get_nqs_search_space() const {
	return _resolve_nqs_search_space();
}

NNNQSSearchSpaces *NNNQSQuerySensor::_resolve_nqs_search_space() const {
	return godot::Object::cast_to<NNNQSSearchSpaces>(ObjectDB::get_instance(_nqs_search_space_cache));
}

void NNNQSQuerySensor::set_is_high_priority(bool is_high_priority) {
	_is_high_priority = is_high_priority;
}

bool NNNQSQuerySensor::get_is_high_priority() const {
	return _is_high_priority;
}

void NNNQSQuerySensor::set_best_result_key(const String &best_result_key) {
	_best_result_key = best_result_key;
}

String NNNQSQuerySensor::get_best_result_key() const {
	return _best_result_key;
}

// Handling functions.

void NNNQSQuerySensor::_cancel_posted_query() {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space != nullptr) {
		if (_query_completed_callable.is_valid() && search_space->is_connected("query_completed", _query_completed_callable)) {
			search_space->disconnect("query_completed", _query_completed_callable);
		}
		// Stop only our live registration, never an externally replaced query.
		if (_posted_query_registration != 0 && search_space->get_nqs_query_registration() == _posted_query_registration) {
			NNNodeQuerySystem *nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
			if (nqs != nullptr) {
				nqs->stop_query(search_space);
			}
		}
	}
	_query_completed_callable = Callable();
	_posted_query_registration = 0;
	_query_state = QueryState::IDLE;
}

bool NNNQSQuerySensor::_connect_query_completed(NNNQSSearchSpaces *p_search_space) {
	_query_completed_callable = callable_mp(this, &NNNQSQuerySensor::_on_query_completed)
										.bind(static_cast<int64_t>(_posted_query_registration));
	return p_search_space->connect("query_completed", _query_completed_callable, Object::CONNECT_ONE_SHOT) == OK;
}

void NNNQSQuerySensor::_on_query_completed(Object *p_search_space, int64_t p_query_registration) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr || search_space != p_search_space || _query_state != QueryState::RUNNING) {
		return;
	}
	if (static_cast<uint64_t>(p_query_registration) != _posted_query_registration ||
			search_space->get_nqs_query_registration() != _posted_query_registration) {
		return;
	}

	// Copy before the board write: a value_changed listener may free this sensor.
	TypedArray<Node> results = search_space->get_query_results();
	PackedFloat64Array scores = search_space->get_query_result_scores();
	const String best_result_key = _best_result_key;
	Ref<NNBlackboard> board = get_blackboard_resource_ref();

	_query_state = QueryState::IDLE;
	_posted_query_registration = 0;

	if (results.is_empty() || scores.is_empty()) {
		set_sensor_value(0.0f);
		if (board.is_valid() && !best_result_key.is_empty()) {
			board->erase_value(best_result_key);
		}
		return;
	}

	set_sensor_value((float)scores[0]);
	if (board.is_valid() && !best_result_key.is_empty()) {
		board->set_value(best_result_key, results[0]);
	}
}

float NNNQSQuerySensor::evaluate_sensor_value() {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	NNNodeQuerySystem *nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
	if (!is_node_ready() || Engine::get_singleton()->is_editor_hint() || search_space == nullptr || nqs == nullptr) {
		_cancel_posted_query();
		return get_sensor_value();
	}

	if (_query_state == QueryState::RUNNING &&
			(search_space->get_nqs_query_registration() != _posted_query_registration || !search_space->get_is_query_still_running())) {
		_cancel_posted_query();
		return get_sensor_value();
	}

	if (_query_state == QueryState::IDLE) {
		if (nqs->post_query(search_space, _is_high_priority) == 1) {
			search_space->set_top_n_to_find(1);
			_posted_query_registration = search_space->get_nqs_query_registration();
			_query_state = QueryState::RUNNING;
			if (!_connect_query_completed(search_space)) {
				_cancel_posted_query();
			}
		}
	}

	return get_sensor_value();
}

void NNNQSQuerySensor::uninitialize_sensor() {
	_cancel_posted_query();
}

// Godot virtuals.

void NNNQSQuerySensor::_on_is_enabled_changed(bool p_is_enabled) {
	NoodleNodes::_on_is_enabled_changed(p_is_enabled);
	if (!p_is_enabled) {
		_cancel_posted_query();
	}
}

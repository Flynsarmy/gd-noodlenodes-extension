#include "run_nqs_query.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>

using namespace godot;

void NNBTRunNQSQuery::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_nqs_search_space", "nqs_search_space"), &NNBTRunNQSQuery::set_nqs_search_space);
	ClassDB::bind_method(D_METHOD("get_nqs_search_space"), &NNBTRunNQSQuery::get_nqs_search_space);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "nqs_search_space", PROPERTY_HINT_NODE_TYPE, "NNNQSSearchSpaces"), "set_nqs_search_space", "get_nqs_search_space");

	ClassDB::bind_method(D_METHOD("set_top_n_to_find", "top_n_to_find"), &NNBTRunNQSQuery::set_top_n_to_find);
	ClassDB::bind_method(D_METHOD("get_top_n_to_find"), &NNBTRunNQSQuery::get_top_n_to_find);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "top_n_to_find", PROPERTY_HINT_RANGE, "1,32,or_greater"), "set_top_n_to_find", "get_top_n_to_find");

	ClassDB::bind_method(D_METHOD("set_is_high_priority", "is_high_priority"), &NNBTRunNQSQuery::set_is_high_priority);
	ClassDB::bind_method(D_METHOD("get_is_high_priority"), &NNBTRunNQSQuery::get_is_high_priority);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_high_priority", PROPERTY_HINT_NONE), "set_is_high_priority", "get_is_high_priority");
}

NNBTRunNQSQuery::NNBTRunNQSQuery() {
	_time_budget_usec = 200;
	_top_n_to_find = 1;
	_query_state = QueryState::IDLE;
	_posted_query_registration = 0;
	_is_high_priority = true;
}

NNBTRunNQSQuery::~NNBTRunNQSQuery() {
	_cancel_posted_query();
}

void NNBTRunNQSQuery::set_nqs_search_space(NNNQSSearchSpaces *nqs_search_space) {
	ObjectID search_space_id = nqs_search_space != nullptr ? ObjectID(nqs_search_space->get_instance_id()) : ObjectID();
	if (_nqs_search_space_cache == search_space_id) {
		return;
	}
	_cancel_posted_query();
	_nqs_search_space_cache = search_space_id;
}

NNNQSSearchSpaces *NNBTRunNQSQuery::get_nqs_search_space() const {
	return _resolve_nqs_search_space();
}

NNNQSSearchSpaces *NNBTRunNQSQuery::_resolve_nqs_search_space() const {
	return godot::Object::cast_to<NNNQSSearchSpaces>(ObjectDB::get_instance(_nqs_search_space_cache));
}

void NNBTRunNQSQuery::set_time_budget_usec(int time_budget_usec) {
	_time_budget_usec = time_budget_usec;
}

int NNBTRunNQSQuery::get_time_budget_usec() const {
	return _time_budget_usec;
}

void NNBTRunNQSQuery::set_top_n_to_find(int top_n_to_find) {
	_top_n_to_find = top_n_to_find;
}

int NNBTRunNQSQuery::get_top_n_to_find() const {
	return _top_n_to_find;
}

void NNBTRunNQSQuery::set_is_high_priority(bool is_high_priority) {
	_is_high_priority = is_high_priority;
}

bool NNBTRunNQSQuery::get_is_high_priority() const {
	return _is_high_priority;
}

void NNBTRunNQSQuery::_cancel_posted_query() {
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
	// post_query() initializes query variables when the next run actually starts.
}

bool NNBTRunNQSQuery::_connect_query_completed(NNNQSSearchSpaces *p_search_space) {
	_query_completed_callable = callable_mp(this, &NNBTRunNQSQuery::_on_query_completed)
										.bind(static_cast<int64_t>(_posted_query_registration));
	return p_search_space->connect("query_completed", _query_completed_callable, Object::CONNECT_ONE_SHOT) == OK;
}

void NNBTRunNQSQuery::_on_query_completed(Object *p_search_space, int64_t p_query_registration) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr || search_space != p_search_space || _query_state != QueryState::RUNNING) {
		return;
	}
	if (static_cast<uint64_t>(p_query_registration) == _posted_query_registration &&
			search_space->get_nqs_query_registration() == _posted_query_registration) {
		_query_state = QueryState::COMPLETED;
	}
}

NNBTNodes::Status NNBTRunNQSQuery::_tick(float delta) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	NNNodeQuerySystem *nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
	Status result = Status::FAILURE;
	if (!is_node_ready() || Engine::get_singleton()->is_editor_hint() || search_space == nullptr || nqs == nullptr) {
		_cancel_posted_query();
	} else {
		if (_query_state == QueryState::RUNNING &&
				(search_space->get_nqs_query_registration() != _posted_query_registration || !search_space->get_is_query_still_running())) {
			_query_state = QueryState::CANCELLED;
		}

		if (_query_state == QueryState::CANCELLED) {
			_cancel_posted_query();
		} else {
			switch (_query_state) {
				case QueryState::IDLE: {
					if (nqs->post_query(search_space, _is_high_priority) == 1) {
						search_space->set_top_n_to_find(_top_n_to_find);
						_posted_query_registration = search_space->get_nqs_query_registration();
						_query_state = QueryState::RUNNING;
						if (_connect_query_completed(search_space)) {
							result = Status::RUNNING;
						} else {
							_cancel_posted_query();
						}
					}
				} break;
				case QueryState::RUNNING:
					result = Status::RUNNING;
					break;
				case QueryState::COMPLETED:
					result = Status::SUCCESS;
					break;
				case QueryState::CANCELLED:
					break;
			}
		}
	}

	return result;
}

void NNBTRunNQSQuery::_on_after_run(float delta) {
	// The run is over, so drop the posted query and its completion connection.
	_cancel_posted_query();
	NNBTTaskNodes::_on_after_run(delta);
}

void NNBTRunNQSQuery::_on_interrupt(float delta) {
	// Stop only this leaf's own posted query before running the script hook.
	_cancel_posted_query();
	NNBTTaskNodes::_on_interrupt(delta);
}

void NNBTRunNQSQuery::_exit_tree() {
	_cancel_posted_query();
}

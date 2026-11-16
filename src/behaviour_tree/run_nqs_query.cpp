#include "run_nqs_query.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

// Method binds.

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

// Constructor and destructor.

NNBTRunNQSQuery::NNBTRunNQSQuery() {
	_nqs_search_space_cache = ObjectID();
	_nqs = nullptr;
	_time_budget_usec = 200;
	_top_n_to_find = 1;
	_query_state = QS_IDLE;
	_is_high_priority = true;
}

NNBTRunNQSQuery::~NNBTRunNQSQuery() {
	_nqs_search_space_cache = ObjectID();
	_nqs = nullptr;
}

// Getters and Setters.

void NNBTRunNQSQuery::set_nqs_search_space(NNNQSSearchSpaces *nqs_search_space) {
	ObjectID search_space_id;
	if (nqs_search_space != nullptr) {
		search_space_id = ObjectID(nqs_search_space->get_instance_id());
	}
	// Compare instance IDs rather than raw pointers: a freed node's address can
	// be reused by a new node, and that must count as a reassignment.
	if (_nqs_search_space_cache == search_space_id) {
		return;
	}
	_nqs_search_space_cache = search_space_id;
	// A different search space owns any new query. Do not inherit the previous
	// space's in-flight state, which would otherwise mask the new query.
	_query_state = QS_IDLE;
}

NNNQSSearchSpaces *NNBTRunNQSQuery::get_nqs_search_space() const {
	// Only the cache is authoritative. A raw pointer to a freed node must never
	// be handed back to GDScript, so resolve the instance ID every time.
	return _resolve_nqs_search_space();
}

NNNQSSearchSpaces *NNBTRunNQSQuery::_resolve_nqs_search_space() const {
	if (_nqs_search_space_cache.is_null()) {
		return nullptr;
	}
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

// Handling methods.

void NNBTRunNQSQuery::reset_bt_node() {
	_query_state = QS_IDLE;
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr) {
		// The space may have been freed while the leaf still referenced it.
		// Drop the stale reference instead of dereferencing it.
		_nqs_search_space_cache = ObjectID();
		return;
	}
	search_space->reset_query_variables();
}

NNBTNodes::Status NNBTRunNQSQuery::tick(Variant blackboard, float delta) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr) {
		// The cached search space is unset or has been freed. Reset the query
		// state so a later reassignment can post a fresh query.
		_nqs_search_space_cache = ObjectID();
		_query_state = QS_IDLE;
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	//if( _is_first_tick ) {
	//    _is_first_tick = false;
	//    emit_signal("btnode_entered", blackboard, delta);
	//}

	switch (_query_state) {
		case QS_IDLE: {
			search_space->set_top_n_to_find(_top_n_to_find);
			//_nqs_search_space_node->start_query(_time_budget_usec);
			_nqs->post_query(search_space, _is_high_priority);
			_query_state = QS_RUNNING;
			set_tick_result(Status::RUNNING);
			//emit_signal("btnode_ticked", blackboard, delta);
			return Status::RUNNING;
		} break;
		case QS_COMPLETED: {
			set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
			set_tick_result(Status::SUCCESS);
			//emit_signal("btnode_exited", blackboard, delta);
			return Status::SUCCESS;
		} break;
		default: {
			set_tick_result(Status::RUNNING);
			//emit_signal("btnode_ticked", blackboard, delta);
			return Status::RUNNING;
		} break;
	}
	// We shouldn't get here.
	set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
	set_tick_result(Status::FAILURE);
	//emit_signal("btnode_exited", blackboard, delta);
	return Status::FAILURE;
}

void NNBTRunNQSQuery::_ready() {
	if (Engine::get_singleton()->is_editor_hint())
		return;
	_nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
	// godot::Object::cast_to<NNNodeQuerySystem>(godot::Engine::get_singleton("NodeQuerySystem"));
}

void NNBTRunNQSQuery::_physics_process(double delta) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr) {
		// The search space died while a query was in flight. Forget the query
		// state so a later reassignment posts a fresh query.
		_nqs_search_space_cache = ObjectID();
		_query_state = QS_IDLE;
		return;
	}
	if (_nqs == nullptr)
		return;
	if (_query_state == QS_RUNNING) {
		bool is_still_running = search_space->get_is_query_still_running(); //->execute_query(_time_budget_usec);
		if (!is_still_running) {
			_query_state = QS_COMPLETED;
		}
	}
}

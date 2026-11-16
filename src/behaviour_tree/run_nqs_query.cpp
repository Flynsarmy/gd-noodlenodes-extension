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
	_has_query_completed = false;
	_owns_query = false;
	_posted_query_registration = 0;
	_is_high_priority = true;
}

NNBTRunNQSQuery::~NNBTRunNQSQuery() {
	// Do not touch the search space here: it may already be freed. Godot drops
	// connections whose target object is destroyed.
	_query_completed_callable = Callable();
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
	// The old space keeps its scheduled query if we simply forget it. Release a
	// query we posted, but never one owned by another poster, and drop the old
	// completion connection so it cannot complete the new space's run.
	NNNQSSearchSpaces *previous_search_space = _resolve_nqs_search_space();
	_release_in_flight_query(previous_search_space);
	_disconnect_query_completed(previous_search_space);

	_nqs_search_space_cache = search_space_id;
	// A different search space owns any new query. Do not inherit the previous
	// space's in-flight state, which would otherwise mask the new query.
	_query_state = QS_IDLE;
	_has_query_completed = false;
	_owns_query = false;
	_posted_query_registration = 0;
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
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	// A run is starting over: a completion from the previous run must not be
	// able to finish the next one.
	_release_in_flight_query(search_space);
	_disconnect_query_completed(search_space);
	// Only a query this leaf posted may have its variables reset. A rejected
	// post belongs to another poster, and clearing its progress would corrupt it.
	const bool had_own_query = _owns_query;
	_has_query_completed = false;
	_owns_query = false;
	_posted_query_registration = 0;
	_query_state = QS_IDLE;
	if (search_space == nullptr) {
		// The space may have been freed while the leaf still referenced it.
		// Drop the stale reference instead of dereferencing it.
		_nqs_search_space_cache = ObjectID();
		return;
	}
	if (had_own_query) {
		search_space->reset_query_variables();
	}
}

bool NNBTRunNQSQuery::_connect_query_completed(NNNQSSearchSpaces *p_search_space) {
	if (p_search_space == nullptr) {
		return false;
	}
	// Bind the instance ID and registration rather than relying on the signal's
	// search-space argument: a callback must not touch a stale pointer, and only
	// the registration this leaf posted may complete the current run.
	_query_completed_callable = callable_mp(this, &NNBTRunNQSQuery::_on_query_completed)
										.bind(static_cast<int64_t>(_nqs_search_space_cache),
												static_cast<int64_t>(_posted_query_registration));
	Error error = p_search_space->connect("query_completed", _query_completed_callable, Object::CONNECT_ONE_SHOT);
	if (error != OK) {
		_query_completed_callable = Callable();
		return false;
	}
	return true;
}

void NNBTRunNQSQuery::_disconnect_query_completed(NNNQSSearchSpaces *p_search_space) {
	if (p_search_space == nullptr || !_query_completed_callable.is_valid()) {
		_query_completed_callable = Callable();
		return;
	}
	if (p_search_space->is_connected("query_completed", _query_completed_callable)) {
		p_search_space->disconnect("query_completed", _query_completed_callable);
	}
	_query_completed_callable = Callable();
}

void NNBTRunNQSQuery::_release_in_flight_query(NNNQSSearchSpaces *p_search_space) {
	if (p_search_space == nullptr || _nqs == nullptr || !_owns_query) {
		return;
	}
	// The registration proves the scheduled query is the one this leaf posted.
	// If an external stop/re-post changed it, the query is not ours to stop.
	if (p_search_space->get_nqs_query_index() < 0 ||
			p_search_space->get_nqs_query_registration() != _posted_query_registration) {
		return;
	}
	_nqs->stop_query(p_search_space);
}

void NNBTRunNQSQuery::_on_query_completed(Object *p_search_space, int64_t p_search_space_instance_id, int64_t p_query_registration) {
	(void)p_search_space; // Unused: the bound IDs are authoritative.
	if (ObjectID(static_cast<uint64_t>(p_search_space_instance_id)) != _nqs_search_space_cache) {
		return; // Completion from a space this leaf no longer references.
	}
	if (static_cast<uint64_t>(p_query_registration) != _posted_query_registration) {
		return; // Completion from a previous registration of the same space.
	}
	if (_query_state != QS_RUNNING) {
		return; // Only an in-flight query can be promoted to completed.
	}
	_has_query_completed = true;
}

NNBTNodes::Status NNBTRunNQSQuery::tick(Variant blackboard, float delta) {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space == nullptr) {
		// The cached search space is unset or has been freed. Reset the query
		// state so a later reassignment can post a fresh query.
		_nqs_search_space_cache = ObjectID();
		_query_state = QS_IDLE;
		_has_query_completed = false;
		_owns_query = false;
		_posted_query_registration = 0;
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}
	if (_nqs == nullptr) {
		// Ticked before the singleton was resolved (for example before _ready).
		_query_state = QS_IDLE;
		_has_query_completed = false;
		_owns_query = false;
		_posted_query_registration = 0;
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		return Status::FAILURE;
	}

	// Resolve the in-flight query before the reset rules run. Otherwise a reset
	// rule could clear the state and turn a cancelled query into a fresh post,
	// hiding the cancellation from this tick.
	if (_query_state == QS_RUNNING) {
		if (_has_query_completed) {
			_query_state = QS_COMPLETED;
		} else if (!search_space->get_is_query_still_running()) {
			// The space stopped without the completion signal: cancelled through
			// stop_query()/clear_queries(), or the query never really started.
			_query_state = QS_CANCELLED;
		}
	}

	if (_query_state == QS_CANCELLED) {
		// Drop anything still scheduled for this run (for example a space that
		// never actually started because it was disabled) and detach the
		// completion listener before reporting the failure.
		_release_in_flight_query(search_space);
		_disconnect_query_completed(search_space);
		_has_query_completed = false;
		// Distinct from completion: report failure so callers cannot mistake a
		// cancelled query for a successful one.
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		set_tick_result(Status::FAILURE);
		_owns_query = false;
		_posted_query_registration = 0;
		// Arm the next tick to post a fresh query. The reset rules decide when
		// that tick happens; NEVER leaves the failure latched. Without this the
		// cancelled state would be returned forever and the leaf could never run
		// again after a cancellation.
		if (get_reset_rule() != NNBTNodesResetRule::NEVER) {
			_query_state = QS_IDLE;
		}
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
			// A leftover one-shot connection from an abandoned run must not fire
			// for the query posted below.
			_disconnect_query_completed(search_space);
			_has_query_completed = false;
			int post_result = _nqs->post_query(search_space, _is_high_priority);
			if (post_result != 1) {
				// The singleton rejected the post (for example because another
				// poster already scheduled this space). That is a failure, not a
				// running query.
				_owns_query = false;
				_posted_query_registration = 0;
				_query_state = QS_IDLE;
				set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
				set_tick_result(Status::FAILURE);
				return Status::FAILURE;
			}
			_owns_query = true;
			_posted_query_registration = search_space->get_nqs_query_registration();
			_query_state = QS_RUNNING;
			if (!_connect_query_completed(search_space)) {
				// Without the completion signal a genuine completion is
				// indistinguishable from a cancellation. Do not leave an
				// unobservable query scheduled.
				_release_in_flight_query(search_space);
				_owns_query = false;
				_posted_query_registration = 0;
				_query_state = QS_IDLE;
				set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
				set_tick_result(Status::FAILURE);
				return Status::FAILURE;
			}
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
		_has_query_completed = false;
		_owns_query = false;
		_posted_query_registration = 0;
		return;
	}
	if (_nqs == nullptr)
		return;
	if (_query_state == QS_RUNNING) {
		if (_has_query_completed) {
			// Genuine completion is signalled explicitly; an empty result set is
			// still a successful completion.
			_query_state = QS_COMPLETED;
		} else if (!search_space->get_is_query_still_running()) {
			// Stopped without a completion signal (stop_query/clear_queries).
			_query_state = QS_CANCELLED;
		}
	}
}

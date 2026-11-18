#include "run_nqs_query.h"

#include "../blackboard.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

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

	ClassDB::bind_method(D_METHOD("set_best_result_key", "best_result_key"), &NNBTRunNQSQuery::set_best_result_key);
	ClassDB::bind_method(D_METHOD("get_best_result_key"), &NNBTRunNQSQuery::get_best_result_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "best_result_key"), "set_best_result_key", "get_best_result_key");

	ClassDB::bind_method(D_METHOD("set_results_key", "results_key"), &NNBTRunNQSQuery::set_results_key);
	ClassDB::bind_method(D_METHOD("get_results_key"), &NNBTRunNQSQuery::get_results_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "results_key"), "set_results_key", "get_results_key");

	ClassDB::bind_method(D_METHOD("set_result_scores_key", "result_scores_key"), &NNBTRunNQSQuery::set_result_scores_key);
	ClassDB::bind_method(D_METHOD("get_result_scores_key"), &NNBTRunNQSQuery::get_result_scores_key);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "result_scores_key"), "set_result_scores_key", "get_result_scores_key");
}

NNBTRunNQSQuery::NNBTRunNQSQuery() {
	_time_budget_usec = 200;
	_top_n_to_find = 1;
	_query_state = QueryState::IDLE;
	_posted_query_registration = 0;
	_owns_posted_query = false;
	_is_high_priority = true;
	_best_result_key = "nqs_result";
	_results_key = "";
	_result_scores_key = "";
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

void NNBTRunNQSQuery::set_best_result_key(const String &best_result_key) {
	_best_result_key = best_result_key;
}

String NNBTRunNQSQuery::get_best_result_key() const {
	return _best_result_key;
}

void NNBTRunNQSQuery::set_results_key(const String &results_key) {
	_results_key = results_key;
}

String NNBTRunNQSQuery::get_results_key() const {
	return _results_key;
}

void NNBTRunNQSQuery::set_result_scores_key(const String &result_scores_key) {
	_result_scores_key = result_scores_key;
}

String NNBTRunNQSQuery::get_result_scores_key() const {
	return _result_scores_key;
}

void NNBTRunNQSQuery::_cancel_posted_query() {
	NNNQSSearchSpaces *search_space = _resolve_nqs_search_space();
	if (search_space != nullptr) {
		if (_query_completed_callable.is_valid() && search_space->is_connected("query_completed", _query_completed_callable)) {
			search_space->disconnect("query_completed", _query_completed_callable);
		}
		// Stop only our live registration, never a joined or externally replaced query.
		if (_owns_posted_query && _posted_query_registration != 0 && search_space->get_nqs_query_registration() == _posted_query_registration) {
			NNNodeQuerySystem *nqs = godot::Object::cast_to<NNNodeQuerySystem>(Engine::get_singleton()->get_singleton("NodeQuerySystem"));
			if (nqs != nullptr) {
				nqs->stop_query(search_space);
			}
		}
	}
	_query_completed_callable = Callable();
	_posted_query_registration = 0;
	_owns_posted_query = false;
	_query_state = QueryState::IDLE;
	// post_query() initializes query variables when the next run actually starts.
}

// Joining another poster's query avoids starving behind a sensor that re-posts the space before this leaf ticks.
bool NNBTRunNQSQuery::_post_or_join_query(NNNQSSearchSpaces *p_search_space, NNNodeQuerySystem *p_nqs) {
	if (p_nqs->post_query(p_search_space, _is_high_priority) == 1) {
		p_search_space->set_top_n_to_find(_top_n_to_find);
		_owns_posted_query = true;
	} else if (p_search_space->get_nqs_query_index() > -1 && p_search_space->get_is_query_still_running() &&
			p_search_space->get_top_n_to_find() >= _top_n_to_find) {
		_owns_posted_query = false;
	} else {
		return false;
	}
	_posted_query_registration = p_search_space->get_nqs_query_registration();
	_query_state = QueryState::RUNNING;
	if (!_connect_query_completed(p_search_space)) {
		_cancel_posted_query();
		return false;
	}
	return true;
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
	if (static_cast<uint64_t>(p_query_registration) != _posted_query_registration ||
			search_space->get_nqs_query_registration() != _posted_query_registration) {
		return;
	}

	// Copied before any board write: a value_changed listener may free this
	// leaf, its root or the search space, so nothing is read from those after
	// the first write.
	TypedArray<Node> results = search_space->get_query_results();
	PackedFloat64Array scores = search_space->get_query_result_scores();
	if (results.size() > _top_n_to_find) {
		// slice() copies: the space's own array is shared with the query's other listeners.
		results = results.slice(0, _top_n_to_find);
		scores.resize(_top_n_to_find);
	}
	String best_result_key = _best_result_key;
	String results_key = _results_key;
	String result_scores_key = _result_scores_key;
	Ref<NNBlackboard> board = get_blackboard_resource_ref();

	_query_state = QueryState::COMPLETED;

	if (board.is_null()) {
		return;
	}

	if (results.is_empty()) {
		// A completed query with no results is still a success, so stale keys
		// from an earlier run are erased instead of left behind.
		if (!best_result_key.is_empty()) {
			board->erase_value(best_result_key);
		}
		if (!results_key.is_empty()) {
			board->erase_value(results_key);
		}
		if (!result_scores_key.is_empty()) {
			board->erase_value(result_scores_key);
		}
		return;
	}

	if (!results_key.is_empty()) {
		board->set_value(results_key, results);
	}
	if (!result_scores_key.is_empty()) {
		board->set_value(result_scores_key, scores);
	}
	// The best result goes last so a value_changed listener always sees the
	// arrays it came from.
	if (!best_result_key.is_empty()) {
		board->set_value(best_result_key, results[0]);
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
			if (_owns_posted_query) {
				_query_state = QueryState::CANCELLED;
			} else {
				// The joined query's owner stopped it, which is no failure of this leaf's.
				_cancel_posted_query();
			}
		}

		if (_query_state == QueryState::CANCELLED) {
			_cancel_posted_query();
		} else {
			switch (_query_state) {
				case QueryState::IDLE: {
					if (_post_or_join_query(search_space, nqs)) {
						result = Status::RUNNING;
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

#include "parallel.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

// Method binds.

void NNBTParallel::_bind_methods() {
	BIND_ENUM_CONSTANT(SUCCESS_REQUIRE_ALL);
	BIND_ENUM_CONSTANT(SUCCESS_REQUIRE_ONE);
	BIND_ENUM_CONSTANT(FAILURE_REQUIRE_ONE);
	BIND_ENUM_CONSTANT(FAILURE_REQUIRE_ALL);

	ClassDB::bind_method(D_METHOD("set_success_policy", "success_policy"), &NNBTParallel::set_success_policy);
	ClassDB::bind_method(D_METHOD("get_success_policy"), &NNBTParallel::get_success_policy);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "success_policy", PROPERTY_HINT_ENUM, "RequireAll:0,RequireOne:1"), "set_success_policy", "get_success_policy");

	ClassDB::bind_method(D_METHOD("set_failure_policy", "failure_policy"), &NNBTParallel::set_failure_policy);
	ClassDB::bind_method(D_METHOD("get_failure_policy"), &NNBTParallel::get_failure_policy);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "failure_policy", PROPERTY_HINT_ENUM, "RequireOne:0,RequireAll:1"), "set_failure_policy", "get_failure_policy");

	//ClassDB::bind_method(D_METHOD("set_is_reactive", "is_reactive"), &NNBTParallel::set_is_reactive);
	//ClassDB::bind_method(D_METHOD("get_is_reactive"), &NNBTParallel::get_is_reactive);
	//ADD_PROPERTY(PropertyInfo(Variant::BOOL, "is_reactive", PROPERTY_HINT_NONE), "set_is_reactive","get_is_reactive");

	/*
	ClassDB::bind_method(D_METHOD("set_score", "score"), &NNBTParallel::set_score);
	ClassDB::bind_method(D_METHOD("get_score"), &NNBTParallel::get_score);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "score", PROPERTY_HINT_NONE ), "set_score","get_score");
	/**/
	//ClassDB::bind_method(D_METHOD("_tick", "blackboard", "delta"), &NNBTParallel::tick);
}

// Constructor and destructor.

NNBTParallel::NNBTParallel() {
	_current_child_index = 0;
	_success_policy = SuccessPolicy::SUCCESS_REQUIRE_ALL;
	_failure_policy = FailurePolicy::FAILURE_REQUIRE_ONE;
	//_is_reactive = true;
}

NNBTParallel::~NNBTParallel() {
}

// Handling functions.

// Getters and Setters.

void NNBTParallel::set_success_policy(int p_success_policy) {
	if (p_success_policy < SuccessPolicy::SUCCESS_REQUIRE_ALL || p_success_policy > SuccessPolicy::SUCCESS_REQUIRE_ONE) {
		ERR_PRINT(vformat("NNBTParallel::set_success_policy(): received %d; the valid range is %d to %d. Keeping the previous success policy.", p_success_policy, (int)SuccessPolicy::SUCCESS_REQUIRE_ALL, (int)SuccessPolicy::SUCCESS_REQUIRE_ONE));
		return;
	}
	_success_policy = p_success_policy;
}

int NNBTParallel::get_success_policy() const {
	return _success_policy;
}

void NNBTParallel::set_failure_policy(int p_failure_policy) {
	if (p_failure_policy < FailurePolicy::FAILURE_REQUIRE_ONE || p_failure_policy > FailurePolicy::FAILURE_REQUIRE_ALL) {
		ERR_PRINT(vformat("NNBTParallel::set_failure_policy(): received %d; the valid range is %d to %d. Keeping the previous failure policy.", p_failure_policy, (int)FailurePolicy::FAILURE_REQUIRE_ONE, (int)FailurePolicy::FAILURE_REQUIRE_ALL));
		return;
	}
	_failure_policy = p_failure_policy;
}

int NNBTParallel::get_failure_policy() const {
	return _failure_policy;
}

/**
void NNBTParallel::set_is_reactive( bool is_reactive ) {
	_is_reactive = is_reactive;
}

bool NNBTParallel::get_is_reactive() const {
	return _is_reactive;
}
/**/

NNBTNodes::Status NNBTParallel::_tick(Variant blackboard, float delta) {
	set_internal_status(BT_INTERNAL_STATUS_TICKED);
	//if( _is_first_tick ) {
	//    _is_first_tick = false;
	//    emit_signal("btnode_entered", blackboard, delta);
	//}
	// Every enabled child is ticked; this node never early-exits.
	int num_enabled = 0;
	int num_success = 0;
	int num_failure = 0;
	bool has_running = false;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		//if( btnode != nullptr ) {
		if (!btnode->get_is_enabled()) {
			continue;
		}
		++num_enabled;
		Status result = btnode->tick(blackboard, delta);
		if (result == Status::FAILURE) {
			++num_failure;
		} else if (result == Status::RUNNING) {
			has_running = true;
		} else {
			// SUCCESS and SKIP both count as a success so that the defaults
			// below reproduce the historical behaviour exactly: SKIP never
			// caused a failure, and a lone SKIP child returned SUCCESS.
			++num_success;
		}
		//}//endif node was of correct type
	} //endfor btnodes
	//emit_signal("btnode_ticked", blackboard, delta);
	// RUNNING takes precedence over everything else, regardless of child order.
	Status parallelresult;
	if (has_running) {
		parallelresult = Status::RUNNING;
	} else {
		// An empty parallel has num_enabled == 0, so "require all" is trivially
		// true and "require one" is false.
		bool success_met = (_success_policy == SuccessPolicy::SUCCESS_REQUIRE_ALL) ? (num_success == num_enabled) : (num_success > 0);
		bool failure_met = (_failure_policy == FailurePolicy::FAILURE_REQUIRE_ALL) ? (num_failure == num_enabled) : (num_failure > 0);
		if (success_met && failure_met) {
			// Both-met tie goes to FAILURE, matching the historical matrix.
			parallelresult = Status::FAILURE;
		} else if (success_met) {
			parallelresult = Status::SUCCESS;
		} else {
			// FAILURE is the documented fallback for mixed outcomes under
			// SUCCESS_REQUIRE_ALL and FAILURE_REQUIRE_ALL.
			parallelresult = Status::FAILURE;
		}
	}
	if (parallelresult != Status::RUNNING) {
		set_internal_status(BT_INTERNAL_STATUS_COMPLETED);
		//emit_signal("btnode_exited", blackboard, delta);
	}
	set_tick_result(parallelresult);
	return parallelresult;
}

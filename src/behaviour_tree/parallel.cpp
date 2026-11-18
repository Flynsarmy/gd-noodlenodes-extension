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
	_success_policy = SuccessPolicy::SUCCESS_REQUIRE_ALL;
	_failure_policy = FailurePolicy::FAILURE_REQUIRE_ONE;
	//_is_reactive = true;
}

NNBTParallel::~NNBTParallel() {
}

// Handling functions.

void NNBTParallel::update_child_vectors() {
	NNBTNodes::update_child_vectors();

	// Drop the results of children that are no longer part of this node so a
	// removed child is never looked up again.
	for (std::map<NNBTNodes *, Status>::iterator it = _child_results.begin(); it != _child_results.end();) {
		bool is_child = false;
		for (unsigned int i = 0; i < _num_child_btnodes; i++) {
			if (_child_btnodes[i] == it->first) {
				is_child = true;
				break;
			}
		}
		if (is_child) {
			++it;
		} else {
			it = _child_results.erase(it);
		}
	}
}

void NNBTParallel::_on_before_run(Variant blackboard, float delta) {
	// Every run starts with fresh per-child memory.
	_child_results.clear();
}

void NNBTParallel::_on_after_run(Variant blackboard, float delta) {
	_child_results.clear();
}

void NNBTParallel::_on_interrupt(Variant blackboard, float delta) {
	_child_results.clear();
}

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

NNBTNodes::Status NNBTParallel::_evaluate_policies(int p_num_enabled, int p_num_success, int p_num_failure) const {
	// An empty parallel has p_num_enabled == 0, so "require all" is trivially
	// true and "require one" is false.
	bool success_met = (_success_policy == SuccessPolicy::SUCCESS_REQUIRE_ALL) ? (p_num_success == p_num_enabled) : (p_num_success > 0);
	bool failure_met = (_failure_policy == FailurePolicy::FAILURE_REQUIRE_ALL) ? (p_num_failure == p_num_enabled) : (p_num_failure > 0);

	if (success_met && failure_met) {
		// Both-met tie goes to FAILURE, matching the historical matrix.
		return Status::FAILURE;
	}
	if (success_met) {
		return Status::SUCCESS;
	}
	if (failure_met) {
		return Status::FAILURE;
	}
	if (p_num_success + p_num_failure == p_num_enabled) {
		// Every enabled child is terminal but neither policy is met. This is
		// the documented fallback for mixed outcomes under REQUIRE_ALL.
		return Status::FAILURE;
	}
	// Some enabled children have no terminal result yet.
	return Status::RUNNING;
}

NNBTNodes::Status NNBTParallel::_tick(Variant blackboard, float delta) {
	// The enabled count is fixed for this tick so a "require all" policy only
	// becomes true once every enabled child has a terminal result.
	int num_enabled = 0;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		if (_child_btnodes[i]->get_is_enabled()) {
			++num_enabled;
		}
	}

	int num_success = 0;
	int num_failure = 0;
	for (unsigned int i = 0; i < _num_child_btnodes; i++) {
		NNBTNodes *btnode = _child_btnodes[i];
		if (!btnode->get_is_enabled()) {
			continue;
		}

		std::map<NNBTNodes *, Status>::iterator recorded = _child_results.find(btnode);
		if (recorded == _child_results.end()) {
			Status result = btnode->tick(blackboard, delta);
			if (result != Status::RUNNING) {
				// SKIP and SUCCESS both count as a success. Only terminal
				// results are remembered; a RUNNING child is ticked again on
				// the next tick.
				_child_results[btnode] = (result == Status::FAILURE) ? Status::FAILURE : Status::SUCCESS;
				recorded = _child_results.find(btnode);
			}
		}

		if (recorded != _child_results.end()) {
			if (recorded->second == Status::FAILURE) {
				++num_failure;
			} else {
				++num_success;
			}
		}

		// Evaluate after every child so a decided outcome returns immediately.
		// The base tick() then interrupts any still-running children.
		Status outcome = _evaluate_policies(num_enabled, num_success, num_failure);
		if (outcome != Status::RUNNING) {
			return outcome;
		}
	}

	Status outcome = _evaluate_policies(num_enabled, num_success, num_failure);
	return outcome;
}

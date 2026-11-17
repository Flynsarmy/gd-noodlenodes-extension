#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>
#include <map>

namespace godot {

class NNBTParallel : public NNBTCompositeNodes {
	GDCLASS(NNBTParallel, NNBTCompositeNodes)

public:
	enum SuccessPolicy {
		SUCCESS_REQUIRE_ALL = 0,
		SUCCESS_REQUIRE_ONE = 1,
	};

	enum FailurePolicy {
		FAILURE_REQUIRE_ONE = 0,
		FAILURE_REQUIRE_ALL = 1,
	};

private:
	//bool _is_reactive;
	int _success_policy;
	int _failure_policy;
	// Terminal result of every child that has finished in the current run. A
	// child present here is not ticked again until the parallel starts a new
	// run.
	std::map<NNBTNodes *, Status> _child_results;

	Status _evaluate_policies(int p_num_enabled, int p_num_success, int p_num_failure) const;

protected:
	static void _bind_methods();

	virtual void _on_before_run(Variant blackboard, float delta) override;
	virtual void _on_after_run(Variant blackboard, float delta) override;
	virtual void _on_interrupt(Variant blackboard, float delta) override;

public:
	NNBTParallel();
	~NNBTParallel();

	// Getters and setters for attributes.
	//void set_is_reactive( bool is_reactive );
	//bool get_is_reactive() const;

	void set_success_policy(int p_success_policy);
	int get_success_policy() const;

	void set_failure_policy(int p_failure_policy);
	int get_failure_policy() const;

	// Handling functions.

	virtual void reset_bt_node() override;
	virtual void update_child_vectors() override;

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot

VARIANT_ENUM_CAST(NNBTParallel::SuccessPolicy)
VARIANT_ENUM_CAST(NNBTParallel::FailurePolicy)

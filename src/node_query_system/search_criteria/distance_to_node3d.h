#pragma once

#include "distance_range.h"
#include "nqs.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/object_id.hpp>

namespace godot {

class NNDistanceToNode3DSearchCriterion : public NNNQSSearchCriteria {
	GDCLASS(NNDistanceToNode3DSearchCriterion, NNNQSSearchCriteria)

private:
	NNDistanceRange _distance_range;

	ObjectID _distance_to_id;

protected:
	static void _bind_methods();
	virtual void _initialize_criterion() override;

public:
	// Getters and setters for attributes.

	void set_distance_to(Node3D *distance_to);
	Node3D *get_distance_to() const;

	void set_min_distance(float min_distance);
	float get_min_distance() const;

	void set_max_distance(float max_distance);
	float get_max_distance() const;

	// Handling methods.

	virtual void apply_criterion(Node *node, bool &filter_out, float &score) override;
	virtual std::unique_ptr<NNNQSThreadedCriterion> create_threaded_criterion() const override;
};

} //namespace godot

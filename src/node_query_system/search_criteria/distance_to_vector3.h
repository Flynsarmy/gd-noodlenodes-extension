#pragma once

#include "distance_range.h"
#include "nqs.h"

namespace godot {

class NNDistanceToVector3SearchCriterion : public NNNQSSearchCriteria {
	GDCLASS(NNDistanceToVector3SearchCriterion, NNNQSSearchCriteria)

private:
	NNDistanceRange _distance_range;

	Vector3 _distance_to_vector;

protected:
	static void _bind_methods();
	virtual void _initialize_criterion() override;

public:
	NNDistanceToVector3SearchCriterion();
	~NNDistanceToVector3SearchCriterion();

	// Getters and setters for attributes.

	void set_distance_to_vector(Vector3 distance_to_vector);
	Vector3 get_distance_to_vector() const;

	void set_min_distance(float min_distance);
	float get_min_distance() const;

	void set_max_distance(float max_distance);
	float get_max_distance() const;

	// Handling methods.

	virtual void apply_criterion(Node *node, bool &filter_out, float &score) override;
};

} //namespace godot

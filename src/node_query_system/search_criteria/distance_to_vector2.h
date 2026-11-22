#pragma once

#include "distance_range.h"
#include "nqs.h"

namespace godot {

class NNDistanceToVector2SearchCriterion : public NNNQSSearchCriteria {
	GDCLASS(NNDistanceToVector2SearchCriterion, NNNQSSearchCriteria)

private:
	NNDistanceRange _distance_range;

	Vector2 _distance_to_vector;

protected:
	static void _bind_methods();
	virtual void _initialize_criterion() override;

public:
	NNDistanceToVector2SearchCriterion();
	~NNDistanceToVector2SearchCriterion();

	// Getters and setters for attributes.

	void set_distance_to_vector(Vector2 distance_to_vector);
	Vector2 get_distance_to_vector() const;

	void set_min_distance(float min_distance);
	float get_min_distance() const;

	void set_max_distance(float max_distance);
	float get_max_distance() const;

	// Handling methods.

	virtual void apply_criterion(Node *node, bool &filter_out, float &score) override;
	virtual std::unique_ptr<NNNQSThreadedCriterion> create_threaded_criterion() const override;
};

} //namespace godot

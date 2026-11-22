#pragma once

#include "angle_range.h"
#include "nqs.h"

namespace godot {

class NNAngleToVector2SearchCriterion : public NNNQSSearchCriteria {
	GDCLASS(NNAngleToVector2SearchCriterion, NNNQSSearchCriteria)

private:
	NNAngleRange _angle_range;

	Vector2 _angle_to_direction_vector;

protected:
	static void _bind_methods();
	virtual void _initialize_criterion() override;

public:
	NNAngleToVector2SearchCriterion();
	~NNAngleToVector2SearchCriterion();

	// Getters and setters for attributes.

	void set_angle_to_direction_vector(Vector2 angle_to_direction_vector);
	Vector2 get_angle_to_direction_vector() const;

	void set_min_angle_degrees(float min_angle_degrees);
	float get_min_angle_degrees() const;

	void set_max_angle_degrees(float max_angle_degrees);
	float get_max_angle_degrees() const;

	// Handling methods.

	virtual void apply_criterion(Node *node, bool &filter_out, float &score) override;
	virtual std::unique_ptr<NNNQSThreadedCriterion> create_threaded_criterion() const override;
};

} //namespace godot

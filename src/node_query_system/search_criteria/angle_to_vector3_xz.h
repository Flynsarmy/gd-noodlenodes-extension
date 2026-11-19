#pragma once

#include "angle_range.h"
#include "nqs.h"

namespace godot {

class NNAngleToVector3XZSearchCriterion : public NNNQSSearchCriteria {
	GDCLASS(NNAngleToVector3XZSearchCriterion, NNNQSSearchCriteria)

private:
	NNAngleRange _angle_range;

	Vector3 _angle_to_direction_vector;
	Vector2 _xz_angle_vector;

	Vector2 _project_direction_to_xz(Vector3 direction) const;

protected:
	static void _bind_methods();
	virtual void _initialize_criterion() override;

public:
	NNAngleToVector3XZSearchCriterion();
	~NNAngleToVector3XZSearchCriterion();

	// Getters and setters for attributes.

	void set_angle_to_direction_vector(Vector3 angle_to_direction_vector);
	Vector3 get_angle_to_direction_vector() const;

	void set_min_angle_degrees(float min_angle_degrees);
	float get_min_angle_degrees() const;

	void set_max_angle_degrees(float max_angle_degrees);
	float get_max_angle_degrees() const;

	// Handling methods.

	virtual void apply_criterion(Node *node, bool &filter_out, float &score) override;
};

} //namespace godot

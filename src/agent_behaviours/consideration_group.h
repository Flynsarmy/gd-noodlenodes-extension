#pragma once

#include "considerations.h"

#include <godot_cpp/classes/node.hpp>
#include <vector>

namespace godot {

class NNConsiderationGroup : public NNConsiderations {
	GDCLASS(NNConsiderationGroup, NNConsiderations)

private:
	EvaluationMethod _evaluation_method;
	bool _invert_score;

	std::vector<NNConsiderations *> _child_considerations;

protected:
	static void _bind_methods();

public:
	NNConsiderationGroup();
	~NNConsiderationGroup();

	// Getters and setters for attributes.

	void set_evaluation_method(EvaluationMethod evaluation_method);
	EvaluationMethod get_evaluation_method() const;

	void set_invert_score(bool invert_score);
	bool get_invert_score() const;

	// Handling functions.

	virtual float evaluate() override;

	// Godot virtuals.
	void _notification(int p_what);
};

} //namespace godot

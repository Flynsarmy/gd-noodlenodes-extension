#pragma once

#include "sequence.h"

namespace godot {

// Memory sequence. Unlike NNBTSequence, a failure does not erase the current
// child index, so the next run resumes at the child that failed instead of
// re-ticking the children that already succeeded.
class NNBTSequenceStar : public NNBTSequence {
	GDCLASS(NNBTSequenceStar, NNBTSequence)

protected:
	static void _bind_methods();

	virtual void _on_before_run(Variant blackboard, float delta) override;

public:
	NNBTSequenceStar();
	~NNBTSequenceStar();

	// Handling functions.

	virtual void reset() override;

	virtual Status _tick(Variant blackboard, float delta) override;
};

} //namespace godot

#pragma once

#include "composite_nodes.h"
#include <godot_cpp/classes/node.hpp>

namespace godot {

// Shared child-cursor loop for NNBTSequence and NNBTSelector. Not registered
// with ClassDB, so subclasses name their nearest registered ancestor.
class NNBTOrderedComposite : public NNBTCompositeNodes {
protected:
	NNBTOrderedComposite(Status p_short_circuit_status, Status p_fall_through_status);
	~NNBTOrderedComposite();

	virtual void _on_before_run(float delta) override;
	virtual Status _tick(float delta) override;

	int _current_child_index;

public:
	void set_reactive(bool p_reactive);
	bool get_reactive() const;

private:
	bool _is_reactive;
	// Compared, never dereferenced.
	NNBTNodes *_running_child;
	Status _short_circuit_status;
	Status _fall_through_status;
};

} //namespace godot

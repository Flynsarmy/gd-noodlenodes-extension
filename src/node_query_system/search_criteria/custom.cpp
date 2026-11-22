#include "custom.h"

using namespace godot;

void NNCustomSearchCriterion::_bind_methods() {
	GDVIRTUAL_BIND(on_apply_criterion, "node");
}

NNCustomSearchCriterion::NNCustomSearchCriterion() {
}

NNCustomSearchCriterion::~NNCustomSearchCriterion() {
}

void NNCustomSearchCriterion::apply_criterion(Node *node, bool &filter_out, float &score) {
	_score = 1.0f;
	_is_filtered = false;
	GDVIRTUAL_CALL(on_apply_criterion, node);
	filter_out = _is_filtered;
	score = _score;
}

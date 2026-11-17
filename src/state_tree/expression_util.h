#pragma once

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace godot {

class NNSTRoot; // Forward declaration
class Node; // Forward declaration

/**
 * Shared helpers for evaluating Godot [Expression]s against a state tree's
 * blackboard. Used by both the expression guard and transition delays so the
 * parsing/execution logic only exists in one place.
 */
namespace NNSTExpressionUtil {

/**
 * Evaluates `expression` using the blackboard keys of `state_chart` as input
 * names. Returns `default_value` (and prints an error) when the expression
 * cannot be parsed or executed.
 */
Variant evaluate_expression(const String &context, NNSTRoot *state_chart, const String &expression, const Variant &default_value);

/**
 * Returns a human readable path for `node` that is also safe to build when the
 * node is not inside the tree yet.
 */
String path_of(const Node *node);

} //namespace NNSTExpressionUtil
} //namespace godot

extends RefCounted
## Builders for HTN test domains. Roots are created in MANUAL mode so tests drive them with tick().

const ScriptedTask = preload("res://test/unit/htn/support/scripted_task.gd")

const RUNNING_FOR_A_WHILE := [NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING, NNHTNTask.RUNNING]


## Counts the searches a root runs, so tests can assert that one did or did not happen.
class SearchCounter:
	var count := 0

	func _init(root: NNHTNRoot) -> void:
		root.search_finished.connect(func(_status: int, _expansions: int, _cost: float, _optimal: bool) -> void:
			count += 1)

	func reset() -> void:
		count = 0


static func make_root(script: Script = null) -> NNHTNRoot:
	var root := NNHTNRoot.new()
	if script != null:
		root.set_script(script)
	root.name = "HTN"
	root.process_thread = NNHTNRoot.MANUAL
	return root


static func condition(expression: String) -> NNHTNCondition:
	var node := NNHTNCondition.new()
	node.expression = expression
	return node


static func conditions(expressions: Array) -> Array[NNHTNCondition]:
	var result: Array[NNHTNCondition] = []
	for expression in expressions:
		result.append(condition(expression))
	return result


## A plain child holding task templates, so the root's only direct compound stays the domain.
static func templates(root: Node) -> Node:
	var node := Node.new()
	node.name = "Templates"
	root.add_child(node)
	return node


static func typed_schema(key: String, value_type: int) -> NNBlackboardSchema:
	var entry := NNBlackboardKey.new()
	entry.key = key
	entry.value_type = value_type
	var schema := NNBlackboardSchema.new()
	schema.keys.append(entry)
	return schema


static func compound(parent: Node, node_name: String, expressions: Array = []) -> NNHTNCompoundTask:
	var node := NNHTNCompoundTask.new()
	node.conditions = conditions(expressions)
	return _attach(parent, node, node_name)


static func method(parent: Node, node_name: String, expressions: Array = [], node: NNHTNMethod = null) -> NNHTNMethod:
	if node == null:
		node = NNHTNMethod.new()
	node.conditions = conditions(expressions)
	return _attach(parent, node, node_name)


## A ScriptedTask, or an instance of task_script when given.
static func task(parent: Node, node_name: String, effects: Dictionary = {}, expressions: Array = [], task_script: Script = ScriptedTask) -> NNHTNTask:
	var node: NNHTNTask = task_script.new()
	node.effects = effects
	node.conditions = conditions(expressions)
	return _attach(parent, node, node_name)


static func parallel(parent: Node, node_name: String, effects: Dictionary = {}, policy := NNHTNParallelTask.REJECT) -> NNHTNParallelTask:
	var node := NNHTNParallelTask.new()
	node.effects = effects
	node.unsafe_policy = policy
	return _attach(parent, node, node_name)


## A ScriptedTask branch whose concurrency contract is complete, declaring read_keys as its reads.
static func branch(group: NNHTNParallelTask, node_name: String, effects: Dictionary = {}, read_keys: Array = []) -> NNHTNTask:
	var node := task(group, node_name, effects)
	node.concurrency_contract_complete = true
	node.concurrency_read_keys = PackedStringArray(read_keys)
	return node


static func subtask_call(parent: Node, node_name: String, template: NNHTNNodes, args: Dictionary = {}) -> NNHTNSubtaskCall:
	var node := NNHTNSubtaskCall.new()
	node.task = template
	node.args = args
	return _attach(parent, node, node_name)


static func settings(policy := NNHTNSearchSettings.ORDERED, max_expansions := 10000) -> NNHTNSearchSettings:
	var result := NNHTNSearchSettings.new()
	result.policy = policy
	result.max_expansions = max_expansions
	return result


static func execution(policy := NNHTNExecutionSettings.IMMEDIATE, local_repair := false, switch_hysteresis := 0.0) -> NNHTNExecutionSettings:
	var result := NNHTNExecutionSettings.new()
	result.interruption_policy = policy
	result.local_repair = local_repair
	result.switch_hysteresis = switch_hysteresis
	return result


static func binding(state_key: String, variable: String, order := NNHTNBinding.SOURCE) -> NNHTNBinding:
	var result := NNHTNBinding.new()
	result.state_key = state_key
	result.variable = variable
	result.order = order
	return result


static func set_predecessors(node: NNHTNNodes, predecessors: Array) -> void:
	var typed: Array[NNHTNNodes] = []
	typed.assign(predecessors)
	node.predecessors = typed


static func _attach(parent: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	return node


## Ticks once and returns the steps of the plan installed during that tick.
static func tick_and_capture_plan(root: NNHTNRoot, delta := 0.1) -> Array:
	var captured := []
	var capture := func(steps: Array) -> void: captured.assign(steps)
	root.plan_set.connect(capture)
	root.tick(delta)
	root.plan_set.disconnect(capture)
	return captured


static func step_names(steps: Array) -> Array:
	return steps.map(func(step: NNHTNPlanStep) -> String: return String(step.task.name))

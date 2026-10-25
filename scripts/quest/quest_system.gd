@tool
class_name QuestManager
extends Node

signal quests_changed
signal quest_accepted(quest_id: StringName)
signal quest_completed(quest_id: StringName)
signal actions_changed

const SCHEMA_VERSION := 2
const STATE_KINDS := [&"have_item", &"recipe_known", &"recipe_materials", &"fact"]
const EVENT_KINDS := [&"craft_confirmed", &"talk", &"delivery", &"story_completed"]
const ACTION_KINDS := [&"request_story", &"accept_quest", &"grant_item"]

@export var catalog: QuestCatalog = preload("res://data/quests/catalog.tres")
var quests: Array[QuestData]:
	get:
		return _quest_override if _has_override else (catalog.quests if catalog != null else [])
	set(value):
		_has_override = true
		_quest_override = value

var is_restoring := false
var _inventory: InventorySystem
var _progress: Node
var _flow: Node
var _accepted: Dictionary = {}
var _tracked: StringName = &""
var _tracker_collapsed := true
var _actions: Dictionary = {}
var _facts: Dictionary = {}
var _history: Dictionary = {}
var _receipts: Dictionary = {}
var _next_event := 1
var _scene_path := ""
var _transaction_depth := 0
var _refreshing := false
var _has_override := false
var _quest_override: Array[QuestData] = []
var _evaluators: Dictionary = {}
var _event_matchers: Dictionary = {}

func set_dependencies(inventory: InventorySystem, progress: Node) -> void:
	_inventory = inventory
	_progress = progress

func set_flow(flow: Node) -> void:
	_flow = flow

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _inventory == null:
		_inventory = get_node("/root/PlayerInventory")
	if _progress == null:
		_progress = get_node("/root/GameProgress")
	if not _inventory.inventory_changed.is_connected(refresh):
		_inventory.inventory_changed.connect(refresh)
	if not _progress.recipes_changed.is_connected(refresh):
		_progress.recipes_changed.connect(refresh)
	get_tree().scene_changed.connect(_on_scene_changed)
	if get_node_or_null("/root/QuestSystem") == self:
		_connect_save.call_deferred()

func _connect_save() -> void:
	var save := get_node_or_null("/root/SaveSystem")
	if save != null:
		save.restore_started.connect(begin_restore)
		save.restore_finished.connect(end_restore)

func _on_scene_changed() -> void:
	if not is_inside_tree() or not can_process_events():
		return
	var scene := get_tree().current_scene
	_scene_path = scene.scene_file_path if scene != null else ""
	refresh()

func can_process_events() -> bool:
	if is_restoring or _inventory == null or _progress == null:
		return false
	if is_inside_tree():
		var save := get_node_or_null("/root/SaveSystem")
		if save != null and save.is_restoring:
			return false
	return true

func begin_restore() -> void:
	is_restoring = true

func end_restore() -> void:
	is_restoring = false
	if is_inside_tree():
		var scene := get_tree().current_scene
		_scene_path = scene.scene_file_path if scene != null else ""
	refresh()

func begin_transaction() -> void:
	_transaction_depth += 1

func end_transaction() -> void:
	_transaction_depth = maxi(0, _transaction_depth - 1)

func is_transaction_active() -> bool:
	return _transaction_depth > 0

## Registered evaluators return a public view dictionary. Matchers return event credit.
func register_objective_handler(kind: StringName, evaluator: Callable, matcher: Callable = Callable()) -> void:
	_evaluators[kind] = evaluator
	if matcher.is_valid():
		_event_matchers[kind] = matcher

func get_quest(id: StringName) -> QuestData:
	for quest in quests:
		if quest != null and quest.quest_id == id:
			return quest
	return null

func get_accepted_quests() -> Array[StringName]:
	var result: Array[StringName] = []
	for quest in quests:
		if quest != null and _accepted.has(quest.quest_id):
			result.append(quest.quest_id)
	return result

func get_quest_state(id: StringName) -> Dictionary:
	return _accepted.get(id, {}).duplicate(true)

func is_completed(id: StringName) -> bool:
	return _accepted.has(id) and _accepted[id].status == "completed"

func can_accept_quest(id: StringName) -> bool:
	var quest := get_quest(id)
	if quest == null or _accepted.has(id):
		return false
	for condition in quest.accept_conditions:
		if not _condition_met(condition):
			return false
	return not quest.get_stages().is_empty()

func accept_quest(id: StringName) -> bool:
	if not can_process_events() or not can_accept_quest(id):
		return false
	_accept(id)
	refresh()
	return true

func _accept(id: StringName) -> void:
	var quest := get_quest(id)
	_accepted[id] = _initial_state(quest)
	if _tracked == &"" or is_completed(_tracked):
		_tracked = id
		_tracker_collapsed = true
	quest_accepted.emit(id)
	quests_changed.emit()

func _initial_state(quest: QuestData) -> Dictionary:
	return {"status": "active", "stage_id": quest.stage_ids[0], "completed_stages": [], "completed_objectives": {}, "objective_counts": {}}

func get_tracked_quest_id() -> StringName:
	return _tracked

func track_quest(id: StringName) -> bool:
	if id != &"" and not _accepted.has(id):
		return false
	if _tracked != id:
		_tracked = id
		_tracker_collapsed = true
		quests_changed.emit()
	return true

func is_tracker_collapsed() -> bool:
	return _tracker_collapsed

func set_tracker_collapsed(value: bool) -> void:
	if _tracker_collapsed != value:
		_tracker_collapsed = value
		quests_changed.emit()

func get_active_stage(id: StringName) -> QuestStageData:
	var quest := get_quest(id)
	if quest == null or not _accepted.has(id) or is_completed(id):
		return null
	return quest.get_stage(StringName(_accepted[id].stage_id))

func get_active_objective(id: StringName, objective_id: StringName) -> QuestObjectiveData:
	var stage := get_active_stage(id)
	if stage != null:
		for goal in stage.objectives:
			if goal != null and goal.objective_id == objective_id and not _evaluate(id, stage.stage_id, goal).completed:
				return goal
	return null

func refresh() -> void:
	if not can_process_events() or _refreshing:
		return
	_refreshing = true
	# At most one acceptance per definition and one completion per stage.
	for pass_index in quests.size() + 2:
		var changed := false
		for quest in quests:
			if quest != null and quest.auto_accept and can_accept_quest(quest.quest_id):
				_accept(quest.quest_id)
				changed = true
		for id in _accepted.keys():
			changed = _advance(id) or changed
		if not changed:
			break
	_refreshing = false
	quests_changed.emit()

func _advance(id: StringName) -> bool:
	if is_completed(id):
		return false
	var quest := get_quest(id)
	if quest == null:
		return false
	var changed := false
	for step in quest.get_stages().size():
		var stage := get_active_stage(id)
		if stage == null or stage.objectives.is_empty():
			break
		var all_done := true
		var any_done := false
		var completed_goals: Array[StringName] = []
		for goal in stage.objectives:
			var done: bool = goal != null and _evaluate(id, stage.stage_id, goal).completed
			all_done = all_done and done
			any_done = any_done or done
			if done:
				completed_goals.append(goal.objective_id)
		if not (any_done if stage.match_mode == &"any" else all_done):
			break
		var state: Dictionary = _accepted[id]
		state.completed_stages.append(stage.stage_id)
		if not state.has("completed_objectives"):
			state.completed_objectives = {}
		state.completed_objectives[stage.stage_id] = completed_goals
		changed = true
		var index := quest.stage_ids.find(stage.stage_id)
		if index + 1 < quest.stage_ids.size():
			state.stage_id = quest.stage_ids[index + 1]
		else:
			state.status = "completed"
			_enqueue_actions(quest)
			quest_completed.emit(id)
			break
	return changed

func _condition_met(condition: QuestConditionData) -> bool:
	if condition == null:
		return false
	match condition.kind:
		&"quest_completed": return is_completed(condition.target_id)
		&"story_completed": return _flow != null and _flow.is_story_completed(condition.target_id)
		&"have_item": return _inventory != null and _inventory.get_amount(condition.target_id) >= condition.amount
		&"recipe_known": return _recipe_known(condition.target_id)
		&"fact": return int(_facts.get(condition.target_id, 0)) >= condition.amount
		&"scene": return _scene_path == str(condition.target_id)
	return false

func set_fact(id: StringName, value: int = 1) -> void:
	_facts[id] = maxi(0, value)
	refresh()

func get_fact(id: StringName) -> int:
	return int(_facts.get(id, 0))

func _recipe_known(id: StringName, quest: QuestData = null, recipe: AlchemyRecipe = null) -> bool:
	if id == &"" and recipe != null:
		id = recipe.recipe_id
	if _progress != null and _progress.is_recipe_unlocked(id):
		return true
	if _inventory == null:
		return false
	if quest != null and quest.recipe_item_id != &"" and _inventory.get_amount(quest.recipe_item_id) > 0:
		if quest.recipe == null or quest.recipe.recipe_id == id:
			return true
	for item_id in _inventory.get_items():
		var item := _inventory.get_item(StringName(item_id))
		if item != null and item.alchemy_recipe != null and item.alchemy_recipe.recipe_id == id:
			return true
	return false

func _goal_count(id: StringName, stage_id: StringName, goal: QuestObjectiveData) -> int:
	var counts: Dictionary = _accepted.get(id, {}).get("objective_counts", {})
	var current := int(counts.get(stage_id, {}).get(goal.objective_id, 0))
	if goal.include_history:
		current = maxi(current, int(_history.get(_history_key(goal, id, stage_id), 0)))
		if goal.kind == &"story_completed" and _flow != null and _flow.is_story_completed(goal.target_id):
			current = maxi(current, 1)
	return current

func _evaluate(id: StringName, stage_id: StringName, goal: QuestObjectiveData) -> Dictionary:
	if _evaluators.has(goal.kind):
		return _evaluators[goal.kind].call(self, get_quest(id), goal, _goal_count(id, stage_id, goal))
	var current := 0
	var required := goal.amount
	var counted := false
	match goal.kind:
		&"have_item":
			current = _inventory.get_amount(goal.target_id) if _inventory != null else 0
			counted = true
		&"recipe_known":
			current = 1 if _recipe_known(goal.target_id, get_quest(id), goal.recipe) else 0
			required = 1
		&"recipe_materials":
			current = 1 if goal.recipe != null and _inventory != null and AlchemySystem.new(_inventory).check_material_availability(goal.recipe).ok else 0
			required = 1
		&"fact":
			current = int(_facts.get(goal.target_id, 0))
			counted = goal.amount > 1
		_:
			current = _goal_count(id, stage_id, goal)
			counted = goal.amount > 1
	return {"current": current, "required": required, "completed": current >= required, "has_count": counted}

func _material_requirements(recipe: AlchemyRecipe) -> Dictionary:
	var result := {}
	if recipe == null:
		return result
	for index in recipe.ingredients.size():
		if recipe.is_hidden_slot(index):
			continue
		var requirement := recipe.ingredients[index]
		if requirement != null and requirement.item_id != &"":
			result[requirement.item_id] = int(result.get(requirement.item_id, 0)) + requirement.amount
	return result

func get_public_material_requirements(id: StringName) -> Dictionary:
	var quest := get_quest(id)
	if quest != null:
		for stage in quest.get_stages():
			for goal in stage.objectives:
				if goal != null and goal.kind == &"recipe_materials":
					return _material_requirements(goal.recipe)
	return {}

func build_objective_view(id: StringName, stage_id: StringName, objective_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest := get_quest(id)
	var stage := quest.get_stage(stage_id) if quest != null else null
	if stage == null:
		return result
	for goal in stage.objectives:
		if goal == null or goal.objective_id != objective_id or not goal.visible:
			continue
		var state: Dictionary = _accepted.get(id, {})
		var stage_done: bool = state.get("completed_stages", []).has(stage_id)
		# ALL stages and legacy saves retain their original latch semantics. An
		# ANY stage remembers which alternatives actually met its completion rule.
		var achieved: Dictionary = state.get("completed_objectives", {})
		var done: bool = stage_done and (stage.match_mode != &"any" or not achieved.has(stage_id) or achieved[stage_id].has(goal.objective_id))
		var skipped: bool = stage_done and not done
		if goal.kind == &"recipe_materials":
			var exact := _material_requirements(goal.recipe)
			var categories := {}
			if goal.recipe != null:
				for index in goal.recipe.ingredients.size():
					if goal.recipe.is_hidden_slot(index):
						continue
					var requirement := goal.recipe.ingredients[index]
					if requirement != null and requirement.item_id == &"" and requirement.category != &"":
						categories[requirement.category] = int(categories.get(requirement.category, 0)) + requirement.amount
			for item_id in exact:
				var item := _inventory.get_item(item_id) if _inventory != null else null
				var amount := _inventory.get_amount(item_id) if _inventory != null else 0
				result.append({"stage_id": stage_id, "objective_id": objective_id, "item_id": item_id,
					"text": item.display_name if item != null else str(item_id), "current": amount,
					"required": exact[item_id], "completed": done or (amount >= int(exact[item_id]) and not skipped), "has_count": true, "skipped": skipped})
			for category in categories:
				var amount := 0
				if _inventory != null:
					for item_id in _inventory.get_items():
						var item := _inventory.get_item(StringName(item_id))
						if item != null and item.category == category:
							amount += maxi(0, _inventory.get_amount(StringName(item_id)) - int(exact.get(item_id, 0)))
				result.append({"stage_id": stage_id, "objective_id": objective_id, "text": "%s 类素材" % category,
					"current": amount, "required": categories[category], "completed": done or (amount >= int(categories[category]) and not skipped), "has_count": true, "skipped": skipped})
		else:
			var view := _evaluate(id, stage_id, goal).duplicate()
			view["stage_id"] = stage_id
			view["objective_id"] = objective_id
			view["text"] = goal.text if not goal.text.is_empty() else stage.title
			view["completed"] = done or (view.completed and not skipped)
			view["skipped"] = skipped
			if done and not STATE_KINDS.has(goal.kind):
				view.current = goal.amount
			result.append(view)
	return result

func get_objectives(id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var quest := get_quest(id)
	if quest == null or not _accepted.has(id):
		return result
	for stage in quest.get_stages():
		for goal in stage.objectives:
			if goal != null:
				result.append_array(build_objective_view(id, stage.stage_id, goal.objective_id))
	return result

func _history_key(goal: QuestObjectiveData, quest_id: StringName = &"", stage_id: StringName = &"") -> String:
	var identity := [str(goal.kind), str(goal.target_id), str(goal.actor_id), str(goal.topic_id), str(goal.recipe.recipe_id) if goal.recipe != null else ""]
	# A hand-in belongs to its selected quest, stage and objective even when
	# another objective asks for the same items from the same recipient.
	if goal.kind == &"delivery":
		identity.append_array([str(quest_id), str(stage_id), str(goal.objective_id)])
	return JSON.stringify(identity)

func _event_credit(kind: StringName, payload: Dictionary, goal: QuestObjectiveData, quest_id: StringName, stage_id: StringName) -> int:
	if _event_matchers.has(goal.kind):
		return maxi(0, int(_event_matchers[goal.kind].call(kind, payload, goal)))
	if kind != goal.kind:
		return 0
	match kind:
		&"craft_confirmed":
			if payload.get("ok", false) != true or StringName(payload.get("source", "")) != &"alchemy" or StringName(payload.get("outcome", "")) == &"waste":
				return 0
			if goal.recipe != null and StringName(payload.get("recipe_id", "")) != goal.recipe.recipe_id:
				return 0
			if StringName(payload.get("item_id", "")) != goal.target_id:
				return 0
			return maxi(0, int(payload.get("amount", 0)))
		&"talk":
			if goal.actor_id != &"" and StringName(payload.get("actor_id", "")) != goal.actor_id: return 0
			if goal.topic_id != &"" and StringName(payload.get("topic_id", "")) != goal.topic_id: return 0
			if goal.target_id != &"" and StringName(payload.get("story_id", "")) != goal.target_id: return 0
			return 1
		&"delivery":
			if StringName(payload.get("quest_id", "")) != quest_id or StringName(payload.get("objective_id", "")) != goal.objective_id or StringName(payload.get("actor_id", "")) != goal.actor_id:
				return 0
			if StringName(payload.get("stage_id", "")) != stage_id:
				return 0
			var delivered: Dictionary = payload.get("items", {})
			for item_id in goal.items:
				if int(delivered.get(item_id, 0)) < int(goal.items[item_id]): return 0
			return 1
		&"story_completed":
			return 1 if StringName(payload.get("story_id", "")) == goal.target_id else 0
	return 0

func report_event(kind: StringName, payload: Dictionary, event_id: String = "") -> bool:
	if not can_process_events():
		return false
	if event_id.is_empty():
		event_id = "event:%d" % _next_event
		_next_event += 1
	if _receipts.has(event_id):
		return false
	if kind == &"scene_entered":
		_scene_path = str(payload.get("scene_path", ""))
		refresh()
		return true
	if kind == &"fact":
		var fact_id := StringName(payload.get("fact_id", payload.get("target_id", "")))
		if fact_id != &"":
			_facts[fact_id] = int(_facts.get(fact_id, 0)) + maxi(0, int(payload.get("amount", 1)))
			_receipts[event_id] = true
			refresh()
			return true
	# Snapshot active goals before processing. A following stage cannot reuse this event.
	var targets: Array[Dictionary] = []
	for id in get_accepted_quests():
		var stage := get_active_stage(id)
		if stage != null:
			for goal in stage.objectives:
				if goal != null:
					targets.append({"quest_id": id, "stage_id": stage.stage_id, "goal": goal})
	var credited := false
	for target in targets:
		var goal: QuestObjectiveData = target.goal
		var value := _event_credit(kind, payload, goal, target.quest_id, target.stage_id)
		if value <= 0:
			continue
		var state: Dictionary = _accepted[target.quest_id]
		var counts: Dictionary = state.objective_counts
		if not counts.has(target.stage_id): counts[target.stage_id] = {}
		var stage_counts: Dictionary = counts[target.stage_id]
		stage_counts[goal.objective_id] = mini(goal.amount, int(stage_counts.get(goal.objective_id, 0)) + value)
		credited = true
	var historic: Dictionary = {}
	for quest in quests:
		if quest == null: continue
		for stage in quest.get_stages():
			for goal in stage.objectives:
				if goal != null and goal.include_history:
					var key := _history_key(goal, quest.quest_id, stage.stage_id)
					if not historic.has(key):
						var value := _event_credit(kind, payload, goal, quest.quest_id, stage.stage_id)
						if value > 0:
							_history[key] = int(_history.get(key, 0)) + value
							historic[key] = true
							credited = true
	# Even an event with no active recipient has already happened. A duplicate
	# must not become a new action after another goal is activated or accepted.
	_receipts[event_id] = true
	refresh()
	return credited

func on_result_confirmed(result: Dictionary) -> void:
	var event_id := str(result.get("event_id", result.get("transaction_id", result.get("craft_id", ""))))
	report_event(&"craft_confirmed", result, event_id)

func _enqueue_actions(quest: QuestData) -> void:
	for action in quest.completion_actions:
		var key := "%s::%s" % [quest.quest_id, action.action_id]
		if not _actions.has(key):
			_actions[key] = {"quest_id": quest.quest_id, "action_id": action.action_id, "status": "pending"}
	actions_changed.emit()

func _action_for(record: Dictionary) -> QuestActionData:
	var quest := get_quest(StringName(record.get("quest_id", "")))
	if quest != null:
		for action in quest.completion_actions:
			if action != null and action.action_id == StringName(record.get("action_id", "")):
				return action
	return null

func get_pending_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in _actions:
		var record: Dictionary = _actions[key]
		if record.status == "pending":
			result.append({"key": key, "action": _action_for(record), "status": record.status})
	return result

func mark_action_started(key: String) -> void:
	if _actions.has(key):
		_actions[key].status = "running"

func complete_action(key: String) -> void:
	if _actions.has(key) and _actions[key].status != "done":
		_actions[key].status = "done"
		actions_changed.emit()

func reset_action(key: String) -> void:
	if _actions.has(key) and _actions[key].status != "done":
		_actions[key].status = "pending"
		actions_changed.emit()

func get_save_state() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "accepted": _accepted.duplicate(true), "tracked": _tracked,
		"tracker_collapsed": _tracker_collapsed, "actions": _actions.duplicate(true), "facts": _facts.duplicate(),
		"history": _history.duplicate(), "receipts": _receipts.duplicate(), "next_event": _next_event}

func validate_save_state(state: Dictionary) -> Dictionary:
	if state.is_empty(): return _success()
	if not state.get("accepted") is Dictionary or not _is_id(state.get("tracked")) or not state.get("tracker_collapsed", true) is bool:
		return _error("存档中的任务结构无效。")
	var version: Variant = state.get("schema_version", 1)
	if not version is int or version < 1 or version > SCHEMA_VERSION: return _error("任务存档版本不兼容。")
	for id in state.accepted:
		if not _is_id(id) or get_quest(StringName(id)) == null or not state.accepted[id] is Dictionary:
			return _error("存档包含未知任务。")
		var quest := get_quest(StringName(id))
		var record: Dictionary = state.accepted[id]
		if record.get("status") not in ["active", "completed"] or not _is_id(record.get("stage_id")) or not record.get("completed_stages") is Array:
			return _error("存档中的任务阶段无效。")
		var ids := quest.stage_ids
		var stage_index := ids.find(StringName(record.stage_id))
		var expected := ids.size() if record.status == "completed" else stage_index
		if stage_index < 0 or record.completed_stages.size() != expected or (record.status == "completed" and stage_index != ids.size() - 1):
			return _error("存档中的任务阶段与完成记录不一致。")
		for index in expected:
			if not _is_id(record.completed_stages[index]) or StringName(record.completed_stages[index]) != ids[index]:
				return _error("存档中的任务阶段顺序无效。")
		var counts: Variant = record.get("objective_counts", {})
		if not counts is Dictionary: return _error("存档中的目标计数无效。")
		for stage_id in counts:
			if not _is_id(stage_id): return _error("存档中的阶段计数 ID 无效。")
			var stage := quest.get_stage(StringName(stage_id))
			if stage == null or not counts[stage_id] is Dictionary: return _error("存档包含未知阶段计数。")
			for goal_id in counts[stage_id]:
				if not _is_id(goal_id): return _error("存档中的目标计数 ID 无效。")
				var found: QuestObjectiveData
				for goal in stage.objectives:
					if goal.objective_id == StringName(goal_id): found = goal
				var amount: Variant = counts[stage_id][goal_id]
				if found == null or not amount is int or amount < 0 or amount > found.amount:
					return _error("存档中的目标计数无效。")
		var achieved: Variant = record.get("completed_objectives", {})
		if not achieved is Dictionary: return _error("存档中的目标完成记录无效。")
		for stage_id in achieved:
			if not _is_id(stage_id) or not record.completed_stages.has(stage_id) or not achieved[stage_id] is Array:
				return _error("存档中的目标完成阶段无效。")
			var stage := quest.get_stage(StringName(stage_id))
			var seen := {}
			for goal_id in achieved[stage_id]:
				if not _is_id(goal_id) or seen.has(goal_id): return _error("存档中的目标完成 ID 无效。")
				var found := false
				for goal in stage.objectives:
					found = found or goal.objective_id == StringName(goal_id)
				if not found: return _error("存档包含未知的已完成目标。")
				seen[goal_id] = true
			if seen.is_empty() or (stage.match_mode == &"all" and seen.size() != stage.objectives.size()):
				return _error("存档中的目标完成记录与阶段规则不一致。")
	if not str(state.tracked).is_empty() and not state.accepted.has(StringName(state.tracked)):
		return _error("存档中追踪了未接取的任务。")
	if version >= 2:
		for field in ["actions", "facts", "history", "receipts"]:
			if not state.get(field) is Dictionary: return _error("存档中的任务记录缺失。")
		if not state.get("next_event") is int or state.next_event < 1: return _error("任务事件序号无效。")
		for key in state.actions:
			var record: Variant = state.actions[key]
			if not key is String or not record is Dictionary or not _is_id(record.get("quest_id")) or not _is_id(record.get("action_id")) or _action_for(record) == null or record.get("status") not in ["pending", "running", "done"]:
				return _error("存档中的任务动作无效。")
			var expected_key := "%s::%s" % [record.get("quest_id", ""), record.get("action_id", "")]
			if key != expected_key or not state.accepted.has(StringName(record.quest_id)) or state.accepted[StringName(record.quest_id)].status != "completed":
				return _error("存档中的动作与任务不一致。")
		for field in ["facts", "history"]:
			for key in state[field]:
				if not _is_id(key) or not state[field][key] is int or state[field][key] < 0: return _error("任务事实记录无效。")
		for key in state.receipts:
			if not key is String or state.receipts[key] != true: return _error("任务事件收据无效。")
	return _success()

func restore_save_state(state: Dictionary, notify: bool = true) -> void:
	_accepted.clear()
	for id in state.get("accepted", {}):
		var record: Dictionary = state.accepted[id].duplicate(true)
		record.stage_id = StringName(record.stage_id)
		var done: Array[StringName] = []
		for stage in record.completed_stages: done.append(StringName(stage))
		record.completed_stages = done
		record.objective_counts = record.get("objective_counts", {})
		_accepted[StringName(id)] = record
	_tracked = StringName(state.get("tracked", ""))
	_tracker_collapsed = state.get("tracker_collapsed", true)
	_actions = state.get("actions", {}).duplicate(true)
	_facts = state.get("facts", {}).duplicate()
	_history = state.get("history", {}).duplicate()
	_receipts = state.get("receipts", {}).duplicate()
	_next_event = state.get("next_event", 1)
	if int(state.get("schema_version", 1)) < 2:
		for id in _accepted:
			if is_completed(id): _enqueue_actions(get_quest(id))
	if notify: notify_save_state_restored()

func notify_save_state_restored() -> void:
	refresh()
	quests_changed.emit()

func reset_for_new_game() -> void:
	_accepted.clear()
	_tracked = &""
	_tracker_collapsed = true
	_actions.clear()
	_facts.clear()
	_history.clear()
	_receipts.clear()
	_scene_path = ""
	_next_event = 1
	quests_changed.emit()
	actions_changed.emit()

func migrate_legacy_state(progress: Dictionary, scene_path: String) -> Dictionary:
	# This is the only task-specific migration; normal progression reads definitions.
	var result := {"schema_version": 2, "accepted": {}, "tracked": &"", "tracker_collapsed": true,
		"actions": {}, "facts": {}, "history": {}, "receipts": {}, "next_event": 1}
	var quest := get_quest(&"make_cleanser")
	if quest == null: return result
	var confirmed: bool = progress.get("cleanser_timeline_started", false) or progress.get("cleanser_timeline_completed", false)
	var relevant := scene_path in ["res://scenes/RovinRoom.tscn", "res://scenes/AlchemyRoom.tscn"] or confirmed
	relevant = relevant or progress.get("unlocked_recipes", {}).has(quest.recipe.recipe_id)
	for id in progress.get("claimed_interactions", {}):
		relevant = relevant or str(id).begins_with("RovinRoom/")
	if relevant:
		var record := _initial_state(quest)
		if confirmed:
			record.status = "completed"
			record.stage_id = quest.stage_ids[-1]
			record.completed_stages = quest.stage_ids.duplicate()
			for action in quest.completion_actions:
				result.actions["%s::%s" % [quest.quest_id, action.action_id]] = {"quest_id": quest.quest_id, "action_id": action.action_id,
					"status": "done" if progress.get("cleanser_timeline_completed", false) else "pending"}
		result.accepted[quest.quest_id] = record
		result.tracked = quest.quest_id
	return result

func validate_catalog(candidate: QuestCatalog = null) -> Dictionary:
	if candidate == null: candidate = catalog
	if candidate == null: return _error("任务目录为空。")
	var quest_ids := {}
	var story_ids := {}
	for story in candidate.stories:
		if story == null or story.story_id == &"" or story_ids.has(story.story_id): return _error("剧情 ID 为空或重复。")
		if story.timeline_path.is_empty() or not ResourceLoader.exists(story.timeline_path) or not load(story.timeline_path) is DialogicTimeline or story.completion_signal == &"": return _error("剧情引用或完成信号无效。")
		for path in [story.return_scene_path, story.allowed_scene_path]:
			if not path.is_empty() and (not ResourceLoader.exists(path) or not load(path) is PackedScene): return _error("剧情场景引用无效。")
		story_ids[story.story_id] = true
	for quest in candidate.quests:
		if quest == null or quest.quest_id == &"" or quest_ids.has(quest.quest_id): return _error("任务 ID 为空或重复。")
		quest_ids[quest.quest_id] = true
	for quest in candidate.quests:
		var stage_ids := {}
		var stages := quest.get_stages()
		if stages.is_empty(): return _error("任务至少需要一个阶段。")
		for stage in stages:
			if stage == null or stage.stage_id == &"" or stage_ids.has(stage.stage_id) or stage.match_mode not in [&"all", &"any"] or stage.objectives.is_empty():
				return _error("阶段 ID、规则或目标无效。")
			stage_ids[stage.stage_id] = true
			var goal_ids := {}
			for goal in stage.objectives:
				if goal == null or goal.objective_id == &"" or goal_ids.has(goal.objective_id) or goal.amount < 1:
					return _error("目标 ID 或数量无效。")
				goal_ids[goal.objective_id] = true
				if not STATE_KINDS.has(goal.kind) and not EVENT_KINDS.has(goal.kind) and not _evaluators.has(goal.kind): return _error("未知目标类型。")
				match goal.kind:
					&"have_item", &"craft_confirmed":
						if _inventory != null and _inventory.get_item(goal.target_id) == null: return _error("目标物品引用无效。")
					&"recipe_known", &"recipe_materials":
						if goal.kind == &"recipe_materials" and goal.recipe == null: return _error("素材目标缺少配方。")
						if goal.kind == &"recipe_known" and goal.target_id == &"" and goal.recipe == null: return _error("配方目标缺少配方 ID。")
						if goal.recipe != null and _inventory != null and not AlchemySystem.new(_inventory).check_recipe(goal.recipe).ok: return _error("目标配方无效。")
					&"fact":
						if goal.target_id == &"": return _error("事实目标缺少记录 ID。")
					&"talk":
						if goal.actor_id == &"" or goal.topic_id == &"": return _error("交谈目标缺少对象或话题。")
						if goal.target_id != &"" and not story_ids.has(goal.target_id): return _error("交谈剧情引用无效。")
					&"story_completed":
						if not story_ids.has(goal.target_id): return _error("剧情目标引用无效。")
					&"delivery":
						if goal.actor_id == &"" or goal.items.is_empty(): return _error("交付目标缺少接收人或物品。")
						for item_id in goal.items:
							if not _is_id(item_id) or not goal.items[item_id] is int or goal.items[item_id] < 1 or (_inventory != null and _inventory.get_item(StringName(item_id)) == null):
								return _error("交付物品无效。")
		for condition in quest.accept_conditions:
			if condition == null or condition.amount < 1: return _error("接取条件无效。")
			match condition.kind:
				&"quest_completed":
					if not quest_ids.has(condition.target_id) or condition.target_id == quest.quest_id: return _error("前置任务引用无效。")
				&"story_completed":
					if not story_ids.has(condition.target_id): return _error("前置剧情引用无效。")
				&"have_item":
					if _inventory != null and _inventory.get_item(condition.target_id) == null: return _error("前置物品引用无效。")
				&"recipe_known", &"scene", &"fact":
					if condition.target_id == &"": return _error("接取条件缺少目标。")
				_: return _error("未知接取条件。")
		var action_ids := {}
		for action in quest.completion_actions:
			if action == null or action.action_id == &"" or action_ids.has(action.action_id) or not ACTION_KINDS.has(action.kind) or action.amount < 1:
				return _error("完成动作 ID、类型或数量无效。")
			action_ids[action.action_id] = true
			if action.kind == &"request_story" and not story_ids.has(action.target_id): return _error("完成动作的剧情不存在。")
			if action.kind == &"accept_quest" and (not quest_ids.has(action.target_id) or action.target_id == quest.quest_id): return _error("后续任务引用无效。")
			if action.kind == &"grant_item" and _inventory != null and _inventory.get_item(action.target_id) == null: return _error("奖励物品引用无效。")
	return _success()

func _is_id(value: Variant) -> bool:
	return value is String or value is StringName

func _success() -> Dictionary:
	return {"ok": true, "error": ""}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

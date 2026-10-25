class_name RovinTutorialController
extends Node

## Only maps quest objectives to room hotspots; QuestSystem owns progression.
enum Stage { GET_RECIPE, COLLECT_MATERIALS, ENTER_ALCHEMY }

@export_node_path("CanvasLayer") var tutorial_ui_path: NodePath = ^"../TutorialUI"

var stage: Stage = Stage.GET_RECIPE
var _inventory: InventorySystem
var _progress: GameProgressState
var _quests: Node
var _rewards: Dictionary
var _hotspots: Dictionary
var _view: RovinTutorialUI
var _configured := false
var _quest_id: StringName = &"make_cleanser"
var _guidance_id: StringName = &""

func setup(inventory: InventorySystem, progress: GameProgressState, _recipe: AlchemyRecipe, _recipe_item_id: StringName, rewards: Dictionary, hotspots: Dictionary, quest_id: StringName = &"make_cleanser") -> void:
	_inventory = inventory
	_progress = progress
	_quests = get_node("/root/QuestSystem")
	_rewards = rewards
	_hotspots = hotspots
	_quest_id = quest_id
	var quest: QuestData = _quests.get_quest(_quest_id)
	_guidance_id = quest.guidance_id if quest != null else &""
	_view = get_node(tutorial_ui_path) as RovinTutorialUI
	_quests.quests_changed.connect(refresh)
	_inventory.inventory_changed.connect(refresh)
	_progress.guidance_changed.connect(_on_guidance_changed)
	_configured = true
	refresh()

func refresh() -> void:
	if not _configured:
		return
	var state: Dictionary = _quests.get_quest_state(_quest_id)
	if state.is_empty() or not _progress.should_show_guidance(_guidance_id):
		_view.hide_tutorial()
		return
	if state.status == &"completed":
		_progress.complete_guidance(_guidance_id)
		_view.hide_tutorial()
		return
	var targets: Array[Dictionary] = []
	var active_stage: QuestStageData = _quests.get_active_stage(_quest_id)
	var objective: QuestObjectiveData
	if active_stage != null:
		for candidate: QuestObjectiveData in active_stage.objectives:
			if candidate == null:
				continue
			objective = _quests.get_active_objective(_quest_id, candidate.objective_id)
			if objective != null:
				break
	if objective == null:
		_view.hide_tutorial()
		return
	match objective.kind:
		&"recipe_known":
			stage = Stage.GET_RECIPE
			_add_target(targets, "recipe", "获取配方")
		&"recipe_materials":
			stage = Stage.COLLECT_MATERIALS
			# Only public mandatory ItemIDs may determine a highlighted location.
			var required: Dictionary = _quests.get_public_material_requirements(_quest_id)
			for id in _rewards:
				var item_id := StringName((_rewards[id] as Dictionary).get("item_id", ""))
				if required.has(item_id) and _inventory.get_amount(item_id) < int(required[item_id]):
					_add_target(targets, str(id), "搜集素材")
		&"craft_confirmed":
			stage = Stage.ENTER_ALCHEMY
			_add_target(targets, "alchemy", "制作并确认清洗剂")
	_view.show_targets(targets)

func _on_guidance_changed(id: StringName) -> void:
	if id == &"" or id == _guidance_id:
		refresh()

func on_alchemy_entered() -> void:
	# Entering the room is not a completed craft or the end of the quest.
	pass

func update_highlight_positions() -> void:
	if _configured:
		_view.update_highlight_positions()

func _add_target(targets: Array[Dictionary], id: String, label: String) -> void:
	if _hotspots.has(id) and not (_hotspots[id] as Button).disabled:
		var button: Button = _hotspots[id]
		targets.append({"control": button, "label": "%s · %s" % [button.tooltip_text, label]})

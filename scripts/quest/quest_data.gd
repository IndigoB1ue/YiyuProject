@tool
class_name QuestData
extends Resource

@export var quest_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var category: String = "主线"
@export var student_id: StringName
@export var guidance_id: StringName
@export var auto_accept: bool = false
@export var accept_conditions: Array[QuestConditionData] = []
@export var stages: Array[QuestStageData] = []
@export var completion_actions: Array[QuestActionData] = []
# Compatibility metadata for existing resource references and old saves.
@export var recipe: AlchemyRecipe
@export var recipe_item_id: StringName
@export_file("*.dtl") var completion_timeline: String

var stage_ids: Array[StringName]:
	get:
		var result: Array[StringName] = []
		for stage in get_stages():
			result.append(stage.stage_id)
		return result
var stage_titles: Array[String]:
	get:
		var result: Array[String] = []
		for stage in get_stages(): result.append(stage.title)
		return result
var stage_descriptions: Array[String]:
	get:
		var result: Array[String] = []
		for stage in get_stages(): result.append(stage.description)
		return result

func get_stages() -> Array[QuestStageData]:
	if not stages.is_empty() or recipe == null:
		return stages
	# Read legacy recipe-only definitions without mutating their shared Resource.
	var result: Array[QuestStageData] = []
	var ids: Array[StringName] = [&"get_recipe", &"collect_materials", &"craft"]
	var kinds: Array[StringName] = [&"recipe_known", &"recipe_materials", &"craft_confirmed"]
	var titles := ["寻找清洗剂配方", "收集炼金素材", "制作并确认获得清洗剂"]
	for index in 3:
		var stage := QuestStageData.new()
		stage.stage_id = ids[index]
		stage.title = titles[index]
		var goal := QuestObjectiveData.new()
		goal.objective_id = ids[index]
		goal.kind = kinds[index]
		goal.recipe = recipe
		goal.target_id = recipe.result_item_id if index == 2 else recipe.recipe_id
		goal.text = titles[index]
		stage.objectives.append(goal)
		result.append(stage)
	return result

func get_stage(id: StringName) -> QuestStageData:
	for stage in get_stages():
		if stage != null and stage.stage_id == id: return stage
	return null

func get_stage_title(id: StringName) -> String:
	var stage := get_stage(id)
	return stage.title if stage != null else ""

func get_stage_description(id: StringName) -> String:
	var stage := get_stage(id)
	return stage.description if stage != null else ""

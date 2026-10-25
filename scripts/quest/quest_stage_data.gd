@tool
class_name QuestStageData
extends Resource

@export var stage_id: StringName
@export var title: String
@export_multiline var description: String
## all checks live conditions together; any completes after one goal succeeds.
@export var match_mode: StringName = &"all"
@export var objectives: Array[QuestObjectiveData] = []

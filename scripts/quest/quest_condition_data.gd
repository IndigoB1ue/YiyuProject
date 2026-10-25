@tool
class_name QuestConditionData
extends Resource

## Read-only acceptance conditions. Side effects belong to actions and services.
@export var kind: StringName = &"quest_completed"
@export var target_id: StringName
@export_range(1, 999999) var amount: int = 1

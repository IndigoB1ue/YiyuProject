@tool
class_name QuestActionData
extends Resource

## Stable action_id is persisted with its receipt so a load cannot repeat it.
@export var action_id: StringName
@export var kind: StringName = &"request_story"
@export var target_id: StringName
@export_range(1, 999999) var amount: int = 1

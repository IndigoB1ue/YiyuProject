@tool
class_name QuestObjectiveData
extends Resource

## A definition shared by all saves. Counters and receipts belong to QuestManager.
@export var objective_id: StringName
@export var kind: StringName = &"have_item"
@export_multiline var text: String
@export var target_id: StringName
@export var actor_id: StringName
@export var topic_id: StringName
@export_range(1, 999999) var amount: int = 1
@export var items: Dictionary = {}
@export var recipe: AlchemyRecipe
@export var include_history: bool = false
@export var visible: bool = true

class_name QuestSandboxSave
extends Resource

## F6 sandbox snapshots never use or overwrite SaveSystem's game slots.
@export var inventory: Dictionary = {}
@export var progress: Dictionary = {}
@export var quests: Dictionary = {}
@export var flow: Dictionary = {}
@export var dialogue: DialogicSaveState

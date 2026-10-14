class_name GameSaveData
extends Resource

@export var format_version: int = 1
@export var scene_path: String = ""
@export var chapter: int = 1
@export var saved_at: String = ""
@export var play_seconds: float = 0.0
@export var thumbnail_png: PackedByteArray
@export var inventory: Dictionary = {}
@export var progress: Dictionary = {}
@export var scene_state: Dictionary = {}
@export var dialogic_state: DialogicSaveState

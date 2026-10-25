@tool
class_name QuestStoryData
extends Resource

## A named content sequence. The flow runner owns playback; quests only request it.
@export var story_id: StringName
@export_file("*.dtl") var timeline_path: String
@export var completion_signal: StringName
@export_file("*.tscn") var return_scene_path: String
@export_file("*.tscn") var allowed_scene_path: String
## Optional identity for a conversation objective, never inferred from a portrait.
@export var actor_id: StringName
@export var topic_id: StringName
## Compatibility bridges for existing demo saves. New content leaves these empty.
@export var legacy_started_flag: StringName
@export var legacy_completed_flag: StringName

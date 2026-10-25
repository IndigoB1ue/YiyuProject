class_name AlchemyStoryTrigger
extends Node

## Scene adapter: business confirmation goes to quests; QuestFlow owns content.
signal playback_failed(message: String)

@export var quest_id: StringName = &"make_cleanser"
@export var story_id: StringName = &"after_cleanser"
@export var target_item_id: StringName = &"clear_potion"
@export var completes_guidance_on_confirmation: bool = true
@export_file("*.dtl") var timeline_path: String = ""
@export_file("*.tscn") var return_scene_path: String = "res://scenes/RovinRoom.tscn"
@export_node_path("Control") var interface_path: NodePath = ^"../Margin"

var is_playing: bool:
	get:
		return is_instance_valid(_flow) and _flow.is_story_playing(story_id)
var _interface_was_visible := true
var _interface_hidden_for_story := false

@onready var _progress: GameProgressState = get_node("/root/GameProgress")
@onready var _quests: Node = get_node("/root/QuestSystem")
@onready var _flow: QuestFlowRunner = get_node("/root/QuestFlow")
@onready var _interface: Control = get_node(interface_path)
@onready var _save_system: Node = get_node("/root/SaveSystem")

func _ready() -> void:
	var story := _flow.get_story(story_id)
	if story != null and timeline_path.is_empty():
		timeline_path = story.timeline_path
	_flow.story_started.connect(_on_story_started)
	_flow.story_finished.connect(_on_story_finished)
	_flow.playback_failed.connect(_on_playback_failed)
	_apply_options()
	resume_pending_story.call_deferred()

func _exit_tree() -> void:
	if not is_instance_valid(_flow):
		return
	if _flow.story_started.is_connected(_on_story_started):
		_flow.story_started.disconnect(_on_story_started)
	if _flow.story_finished.is_connected(_on_story_finished):
		_flow.story_finished.disconnect(_on_story_finished)
	if _flow.playback_failed.is_connected(_on_playback_failed):
		_flow.playback_failed.disconnect(_on_playback_failed)

func on_result_confirmed(result: Dictionary) -> void:
	if not _can_handle() or not result.get("ok", false) or StringName(result.get("source", "")) != &"alchemy":
		return
	_apply_options()
	_quests.on_result_confirmed(result)
	var quest: QuestData = _quests.get_quest(quest_id)
	if completes_guidance_on_confirmation and quest != null and _quests.is_completed(quest_id):
		_progress.complete_guidance(quest.guidance_id)
	resume_pending_story()

func resume_pending_story() -> void:
	if not _can_handle() or not _quests.is_completed(quest_id):
		return
	_apply_options()
	# Content actions execute after the confirmation click has been consumed.
	_try_pending.call_deferred()

func _try_pending() -> void:
	if not _can_handle():
		return
	_flow.execute_pending_actions()

func _start_timeline() -> void:
	if not _can_handle():
		return
	_apply_options()
	var result := _flow.start_story(story_id)
	if not result.ok:
		playback_failed.emit(result.error)

func _apply_options() -> void:
	_flow.set_story_override(story_id, {"timeline_path": timeline_path, "return_scene_path": return_scene_path})

func _on_story_started(id: StringName) -> void:
	if id != story_id or not is_inside_tree():
		return
	if not _interface_hidden_for_story:
		_interface_was_visible = _interface.visible
	_interface_hidden_for_story = true
	_interface.hide()

func _on_story_finished(id: StringName, _completed: bool) -> void:
	if id == story_id and is_inside_tree():
		_interface.visible = _interface_was_visible
		_interface_hidden_for_story = false

func _on_playback_failed(message: String) -> void:
	if _can_handle():
		playback_failed.emit(message)

func _on_timeline_ended() -> void:
	# Compatibility for already-queued calls from an older scene controller.
	pass

func restore_playback(playing: bool) -> void:
	_apply_options()
	_flow.restore_playback(story_id, playing)
	_interface_was_visible = true
	_interface_hidden_for_story = playing
	_interface.visible = not playing

func _can_handle() -> bool:
	return is_inside_tree() and is_instance_valid(_save_system) and not _save_system.is_restoring and not _flow.is_restoring

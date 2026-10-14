class_name AlchemyStoryTrigger
extends Node

signal playback_failed(message: String)

@export var target_item_id: StringName = &"clear_potion"
@export_file("*.dtl") var timeline_path: String = ""
@export_file("*.tscn") var return_scene_path: String = "res://scenes/RovinRoom.tscn"
@export_node_path("Control") var interface_path: NodePath = ^"../Margin"

var is_playing := false
var _starting := false
var _requested := false
var _interface_was_visible := true
var _playing_timeline: DialogicTimeline

const ROVINROOMSCENE = "res://scenes/RovinRoom.tscn"

@onready var _progress: GameProgressState = get_node("/root/GameProgress")
@onready var _interface: Control = get_node(interface_path)
@onready var _dialogic = get_node("/root/Dialogic")
@onready var _save_system: Node = get_node("/root/SaveSystem")

func _ready() -> void:
	_dialogic.timeline_started.connect(_on_timeline_started)
	_dialogic.timeline_ended.connect(_on_timeline_ended)
	_dialogic.signal_event.connect(_on_dialogic_signal)

func _exit_tree() -> void:
	if not is_instance_valid(_dialogic):
		return
	if _dialogic.timeline_started.is_connected(_on_timeline_started):
		_dialogic.timeline_started.disconnect(_on_timeline_started)
	if _dialogic.timeline_ended.is_connected(_on_timeline_ended):
		_dialogic.timeline_ended.disconnect(_on_timeline_ended)
	if _dialogic.signal_event.is_connected(_on_dialogic_signal):
		_dialogic.signal_event.disconnect(_on_dialogic_signal)

func on_result_confirmed(result: Dictionary) -> void:
	if not result.get("ok", false) or result.get("item_id", &"") != target_item_id:
		return
	if timeline_path.is_empty() or _progress.cleanser_timeline_started or _requested or is_playing:
		return
	_requested = true
	# Start after the confirmation input and popup hide have finished processing.
	_start_timeline.call_deferred()  ## 在帧的末尾调用，确保时序

func _start_timeline() -> void:
	if not is_inside_tree() or not is_instance_valid(_save_system) or _save_system.is_restoring:
		_requested = false
		return
	if _progress.cleanser_timeline_started:
		_requested = false
		return
	if not ResourceLoader.exists(timeline_path):
		_fail("无法播放清洗剂后续剧情：timeline 不存在。\n%s" % timeline_path)
		return
	var timeline := load(timeline_path) as DialogicTimeline
	if timeline == null:
		_fail("无法播放清洗剂后续剧情：所选文件不是有效的 Dialogic timeline。")
		return
	_interface_was_visible = _interface.visible
	_playing_timeline = timeline
	_interface.hide()
	is_playing = true
	_starting = true
	_dialogic.start(timeline)

func _on_timeline_started() -> void:
	if not is_inside_tree():
		return
	# Resource identity supports both res:// paths and editor-saved uid:// paths.
	if _starting and _dialogic.current_timeline == _playing_timeline:
		_progress.cleanser_timeline_started = true
		_starting = false
		_requested = false

func _on_timeline_ended() -> void:
	if not is_inside_tree() or not is_playing or _starting:
		return
	if not is_instance_valid(_save_system) or _save_system.is_restoring:
		return
	is_playing = false
	_progress.complete_cleanser_timeline()
	_return_to_room.call_deferred()

func restore_playback(playing: bool) -> void:
	is_playing = playing
	_starting = false
	_requested = false
	_interface_was_visible = true
	_interface.visible = not playing

func _on_dialogic_signal(argument:String) -> void:
	if not is_inside_tree() or not is_instance_valid(_save_system) or _save_system.is_restoring:
		return
	if argument == "CheckAndActiveStairs":
		is_playing = false
		_starting = false
		_requested = false
		_progress.complete_cleanser_timeline()
		await _dialogic.end_timeline(true)
		# Other scene changes may have detached this controller during cleanup.
		if not is_inside_tree() or not is_instance_valid(_save_system) or _save_system.is_restoring:
			return
		get_tree().change_scene_to_file(ROVINROOMSCENE)

func _return_to_room() -> void:
	if not is_inside_tree() or not is_instance_valid(_save_system) or _save_system.is_restoring:
		return
	if return_scene_path.is_empty():
		_interface.visible = _interface_was_visible
		return
	var scene_error := get_tree().change_scene_to_file(return_scene_path)
	if scene_error != OK:
		_interface.visible = _interface_was_visible
		_fail("剧情已结束，但无法返回房间，请检查场景路径。\n%s" % return_scene_path)

func _fail(message: String) -> void:
	_requested = false
	playback_failed.emit(message)

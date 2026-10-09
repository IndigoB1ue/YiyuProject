class_name RovinStairsTrigger
extends Node

signal playback_failed(message: String)

@export_file("*.dtl") var timeline_path: String = "res://dialogic/timeline/CP01_EP02_SI03.dtl"

var is_playing := false
var _starting := false
var _configured := false
var _timeline: DialogicTimeline
var _progress: GameProgressState
var _button: Button
var _room_was_visible := true

@onready var _room: Control = get_parent() as Control
@onready var _dialogic = get_node("/root/Dialogic")

func _ready() -> void:
	_dialogic.timeline_started.connect(_on_timeline_started)
	_dialogic.timeline_ended.connect(_on_timeline_ended)

func setup(progress: GameProgressState, button: Button) -> void:
	_progress = progress
	_button = button
	_progress.room_story_changed.connect(refresh)
	_configured = true
	refresh()

func refresh() -> void:
	if not _configured:
		return
	var available := _progress.cleanser_timeline_completed and not _progress.stairs_timeline_started
	_button.visible = available
	_button.disabled = not available or is_playing
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _button.disabled else Control.CURSOR_ARROW

func activate() -> void:
	if not _configured or is_playing or _progress.stairs_timeline_started:
		return
	if not _progress.cleanser_timeline_completed:
		playback_failed.emit("请先完成清洗剂制作后的剧情，再前往楼梯。")
		return
	if timeline_path.is_empty() or not ResourceLoader.exists(timeline_path):
		playback_failed.emit("无法播放楼梯剧情，timeline 未配置或不存在。\n%s" % timeline_path)
		return
	_timeline = load(timeline_path) as DialogicTimeline
	if _timeline == null:
		playback_failed.emit("楼梯配置的文件不是有效的 Dialogic timeline。")
		return
	is_playing = true
	_starting = true
	_room_was_visible = _room.visible
	_room.hide()
	refresh()
	# Prevent the click that opens the story from advancing its first line.
	_start_timeline.call_deferred()

func _start_timeline() -> void:
	_dialogic.start(_timeline)

func _on_timeline_started() -> void:
	if _starting and _dialogic.current_timeline == _timeline:
		_starting = false
		_progress.mark_stairs_timeline_started()

func _on_timeline_ended() -> void:
	if not is_playing or _starting:
		return
	is_playing = false
	_room.visible = _room_was_visible
	refresh()

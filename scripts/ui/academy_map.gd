extends Control

@export_file("*.dtl") var hall_timeline_path := "res://dialogic/timeline/CP01_EP02_SI03.dtl"
@export_file("*.tscn") var room_scene_path := "res://scenes/RovinRoom.tscn"

var _starting := false
var _playing := false
var _timeline: DialogicTimeline
@onready var _progress: GameProgressState = get_node("/root/GameProgress")
@onready var _dialogic = get_node("/root/Dialogic")
@onready var _save_system: Node = get_node("/root/SaveSystem")
@onready var _hall: Button = %Hall
@onready var _hint: Label = %Hint

func _ready() -> void:
	_dialogic.timeline_started.connect(_on_timeline_started)
	_dialogic.timeline_ended.connect(_on_timeline_ended)
	_progress.room_story_changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if is_instance_valid(_dialogic):
		if _dialogic.timeline_started.is_connected(_on_timeline_started):
			_dialogic.timeline_started.disconnect(_on_timeline_started)
		if _dialogic.timeline_ended.is_connected(_on_timeline_ended):
			_dialogic.timeline_ended.disconnect(_on_timeline_ended)
	if is_instance_valid(_progress) and _progress.room_story_changed.is_connected(_refresh):
		_progress.room_story_changed.disconnect(_refresh)

func _refresh() -> void:
	_hall.disabled = not _progress.cleanser_timeline_completed or _progress.stairs_timeline_started
	if _progress.stairs_timeline_started:
		_hall.text = "学生礼堂 · 剧情已观看"
		_hint.text = "礼堂剧情已观看，可返回罗维宿舍。"
	elif not _progress.cleanser_timeline_completed:
		_hall.text = "学生礼堂 · 尚未开放"
		_hint.text = "先在罗维宿舍制作清洗剂并完成剧情，再前往学生礼堂。"
	else:
		_hall.text = "学生礼堂 · 前往典礼"
		_hint.text = "洗漱完毕，点击学生礼堂参加开学典礼。"

func _on_rovin_pressed() -> void:
	if _starting or _playing or _dialogic.current_timeline != null or get_tree().paused:
		return
	if get_tree().change_scene_to_file(room_scene_path) != OK:
		_hint.text = "无法进入罗维宿舍，请检查房间场景配置。"

func _on_hall_pressed() -> void:
	if _starting or _playing or _dialogic.current_timeline != null or get_tree().paused:
		return
	if not _progress.cleanser_timeline_completed or _progress.stairs_timeline_started:
		return
	if not ResourceLoader.exists(hall_timeline_path):
		_hint.text = "礼堂剧情不存在，请检查 timeline 配置。"
		return
	_timeline = load(hall_timeline_path) as DialogicTimeline
	if _timeline == null:
		_hint.text = "礼堂配置不是有效的 Dialogic timeline。"
		return
	_starting = true
	_start_hall.call_deferred()

func _start_hall() -> void:
	if not is_inside_tree():
		return
	hide()
	_playing = true
	_dialogic.start(_timeline)

func _on_timeline_started() -> void:
	if not is_inside_tree():
		return
	if _starting and _dialogic.current_timeline == _timeline:
		_starting = false
		# Legacy flag now records entering the hall, rather than clicking stairs.
		_progress.mark_stairs_timeline_started()

func _on_timeline_ended() -> void:
	if not is_inside_tree() or not _playing or _starting:
		return
	if not is_instance_valid(_save_system) or _save_system.is_restoring:
		return
	_playing = false
	show()
	_refresh()

func get_save_state() -> Dictionary:
	return {"playing": _playing}

func validate_save_state(state: Dictionary, _inventory: InventorySystem, _progress_state: Dictionary) -> Dictionary:
	return {"ok": state.get("playing") is bool, "error": "存档中的地图剧情状态无效。"}

func restore_save_state(state: Dictionary) -> void:
	_playing = state.get("playing", false)
	_starting = false
	visible = not _playing
	_refresh()

class_name RovinStairsTrigger
extends Node

signal playback_failed(message: String)

var is_playing := false
var _progress: GameProgressState
var _button: Button

func setup(progress: GameProgressState, button: Button) -> void:
	_progress = progress
	_button = button
	_progress.room_story_changed.connect(refresh)
	refresh()

func refresh() -> void:
	if _button == null:
		return
	var available := _progress.cleanser_timeline_completed
	_button.visible = available
	_button.disabled = not available
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
	_button.tooltip_text = "离开罗维宿舍，前往学院地图"

func activate() -> void:
	if _progress == null or not _progress.cleanser_timeline_completed:
		playback_failed.emit("请先完成清洗剂制作后的剧情，再前往楼梯。")
		return
	if not SceneManager.open_map():
		playback_failed.emit("当前无法打开学院地图。")

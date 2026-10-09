class_name GameProgressState
extends Control

var message_dialog: AcceptDialog

signal recipes_changed
signal rovin_tutorial_changed
signal room_story_changed

var rovin_tutorial_completed: bool = false
var rovin_tutorial_skipped: bool = false
var cleanser_timeline_started: bool = false
var cleanser_timeline_completed: bool = false
var stairs_timeline_started: bool = false

var _unlocked_recipes: Dictionary = {}
var _claimed_interactions: Dictionary = {}

func _ready() -> void:
	## 绘制确认框
	message_dialog = AcceptDialog.new()
	message_dialog.ok_button_text = "确认"
	message_dialog.dialog_autowrap = true
	# 不允许 Esc 关闭。
	message_dialog.dialog_close_on_escape = false
	# 隐藏标题栏和右上角关闭按钮。
	message_dialog.borderless = true
	message_dialog.unresizable = true
	# 弹窗显示时阻止点击后面的界面。
	message_dialog.exclusive = true
	message_dialog.popup_window = false
	
	add_child(message_dialog)
	message_dialog.confirmed.connect(_on_confirmed)
	
func show_message(text: String) -> void:
	var skip = Dialogic.Inputs.auto_skip
	skip.enabled = false
	message_dialog.dialog_text = text
	message_dialog.popup_centered(Vector2i(420, 180))

func _on_confirmed() -> void:
	print("玩家确认了信息")
	# 在这里执行确认后的逻辑。
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	Dialogic.end_timeline(true)
	
func is_recipe_unlocked(recipe_id: StringName) -> bool:
	return _unlocked_recipes.has(recipe_id)

func unlock_recipe(recipe_id: StringName) -> bool:
	if recipe_id == &"" or is_recipe_unlocked(recipe_id):
		return false
	_unlocked_recipes[recipe_id] = true
	recipes_changed.emit()
	return true

func is_interaction_claimed(interaction_id: StringName) -> bool:
	return _claimed_interactions.has(interaction_id)

func claim_interaction(interaction_id: StringName) -> bool:
	if is_interaction_claimed(interaction_id):
		return false
	_claimed_interactions[interaction_id] = true
	return true

## Failed rewards must remain available for another attempt.
func release_interaction(interaction_id: StringName) -> void:
	_claimed_interactions.erase(interaction_id)

func should_show_rovin_tutorial() -> bool:
	return not rovin_tutorial_completed and not rovin_tutorial_skipped

func complete_rovin_tutorial() -> void:
	if not should_show_rovin_tutorial():
		return
	rovin_tutorial_completed = true
	rovin_tutorial_changed.emit()

func skip_rovin_tutorial() -> void:
	if not should_show_rovin_tutorial():
		return
	rovin_tutorial_skipped = true
	rovin_tutorial_changed.emit()

func complete_cleanser_timeline() -> void:
	if cleanser_timeline_completed:
		return
	cleanser_timeline_completed = true
	room_story_changed.emit()

func mark_stairs_timeline_started() -> void:
	if stairs_timeline_started:
		return
	stairs_timeline_started = true
	room_story_changed.emit()

func exit_game() -> void:
	get_tree().quit();

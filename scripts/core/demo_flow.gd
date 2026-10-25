extends CanvasLayer

## The existing demo ending belongs to content flow, rather than saved progress.
@export_file("*.tscn") var menu_scene_path := "res://scenes/main_menu.tscn"
@onready var _message: AcceptDialog = $Message
@onready var _dialogic: Node = get_node("/root/Dialogic")

func show_message(text: String) -> void:
	_dialogic.Inputs.auto_skip.enabled = false
	_message.dialog_text = text
	_message.popup_centered(Vector2i(420, 180))

func close_message() -> void:
	_message.hide()

func _on_confirmed() -> void:
	var scene := get_tree().current_scene
	await _dialogic.end_timeline(true)
	if not get_node("/root/SaveSystem").is_restoring and get_tree().current_scene == scene:
		get_tree().change_scene_to_file(menu_scene_path)

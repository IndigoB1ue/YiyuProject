extends Control

const WORLD_SCENE := "res://scenes/world.tscn"

@onready var menu_buttons: Array[TextureButton] = [
	$MenuBar/LoadGame,
	$MenuBar/NewGame,
	$MenuBar/Gallery,
	$MenuBar/Options,
	$MenuBar/Exit,
]
@onready var notice_layer: Control = $NoticeLayer
@onready var notice_title: Label = $NoticeLayer/NoticePanel/Margin/Content/NoticeTitle
@onready var notice_text: Label = $NoticeLayer/NoticePanel/Margin/Content/NoticeText
@onready var notice_close: Button = $NoticeLayer/NoticePanel/Margin/Content/Close


func _ready() -> void:
	for button in menu_buttons:
		button.mouse_entered.connect(_animate_button.bind(button, true))
		button.mouse_exited.connect(_animate_button.bind(button, false))
		button.focus_entered.connect(_animate_button.bind(button, true))
		button.focus_exited.connect(_animate_button.bind(button, false))

	call_deferred("_finish_layout")
	_play_intro()


func _unhandled_input(event: InputEvent) -> void:
	if notice_layer.visible and event.is_action_pressed("ui_cancel"):
		_on_notice_close_pressed()
		get_viewport().set_input_as_handled()


func _finish_layout() -> void:
	for button in menu_buttons:
		button.pivot_offset = button.size * 0.5
	menu_buttons[1].grab_focus()


func _play_intro() -> void:
	$TitleBlock.modulate.a = 0.0
	var title_tween := create_tween()
	title_tween.tween_property($TitleBlock, "modulate:a", 1.0, 0.8).set_delay(0.15)

	for index in menu_buttons.size():
		var button := menu_buttons[index]
		button.modulate.a = 0.0
		button.position.y += 20.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(button, "modulate:a", 1.0, 0.35).set_delay(0.25 + index * 0.07)
		tween.tween_property(button, "position:y", button.position.y - 20.0, 0.42).set_delay(0.25 + index * 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _animate_button(button: TextureButton, highlighted: bool) -> void:
	if not is_instance_valid(button):
		return
	var tween := create_tween().set_parallel(true)
	var target_scale := Vector2(1.08, 1.08) if highlighted else Vector2.ONE
	var target_color := Color(1.0, 0.78, 0.82, 1.0) if highlighted else Color.WHITE
	tween.tween_property(button, "scale", target_scale, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "modulate", target_color, 0.14)


func _show_notice(title: String, message: String) -> void:
	notice_title.text = title
	notice_text.text = message
	notice_layer.visible = true
	notice_layer.modulate.a = 0.0
	notice_close.grab_focus()
	create_tween().tween_property(notice_layer, "modulate:a", 1.0, 0.18)


func _on_load_game_pressed() -> void:
	_show_notice("读取存档", "存档列表将在接入游戏存档数据后显示。")


func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_gallery_pressed() -> void:
	_show_notice("画廊", "CG 鉴赏与额外故事入口已经预留。")


func _on_options_pressed() -> void:
	_show_notice("设置", "文字、画面与声音设置界面将在这里打开。")


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_notice_close_pressed() -> void:
	notice_layer.visible = false
	menu_buttons[1].grab_focus()

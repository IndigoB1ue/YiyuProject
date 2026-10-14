extends CanvasLayer

var _important := false
@onready var _panel: PanelContainer = $Panel
@onready var _settings: Node = get_node("/root/GameSettings")


func _ready() -> void:
	_panel.hide()
	var dialogic := get_node("/root/Dialogic")
	dialogic.Choices.question_shown.connect(_on_question_shown)
	dialogic.Choices.choice_selected.connect(_hide_hint)
	dialogic.timeline_started.connect(_reset_hint)
	dialogic.timeline_ended.connect(_reset_hint)
	_settings.settings_changed.connect(_on_settings_changed)


func _on_question_shown(info: Dictionary) -> void:
	_important = false
	for choice: Dictionary in info.get("choices", []):
		if choice.get("visible", true) and not choice.get("disabled", false) and choice.get("important", false) in [true, "true", "1"]:
			_important = true
	_refresh()


func _on_settings_changed(section: String) -> void:
	if section == "text":
		_refresh()


func _refresh() -> void:
	_panel.visible = _important and _settings.get_value("text", "important_hints")


func _hide_hint(_info: Dictionary) -> void:
	_reset_hint()


func _reset_hint() -> void:
	_important = false
	_panel.hide()

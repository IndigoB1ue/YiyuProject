class_name RovinTutorialUI
extends CanvasLayer

signal skip_requested

@export var target_highlight_scene: PackedScene

@onready var _overlay: Control = $Overlay
@onready var _highlight_container: Control = $Overlay/Highlights
@onready var _title: Label = $Overlay/Card/Margin/Content/Title
@onready var _message: Label = $Overlay/Card/Margin/Content/Message
@onready var _progress_text: Label = $Overlay/Card/Margin/Content/Progress

var _targets: Array[Dictionary] = []
var _indicators: Array[Control] = []

func show_step(title: String, message: String, progress_text: String, targets: Array[Dictionary]) -> void:
	_title.text = title
	_message.text = message
	_progress_text.text = progress_text
	_clear_highlights()
	_targets = targets
	for target in _targets:
		var indicator := target_highlight_scene.instantiate() as Control
		_highlight_container.add_child(indicator)
		(indicator.get_node("TargetName") as Label).text = target.label
		_indicators.append(indicator)
	update_highlight_positions()
	show()

func hide_tutorial() -> void:
	hide()
	_clear_highlights()

func update_highlight_positions() -> void:
	if not is_node_ready():
		return
	for index in _indicators.size():
		var target: Control = _targets[index].control
		if is_instance_valid(target):
			var bounds := target.get_global_rect()
			_indicators[index].position = bounds.position - _highlight_container.global_position
			_indicators[index].size = bounds.size

func _clear_highlights() -> void:
	for indicator in _indicators:
		_highlight_container.remove_child(indicator)
		indicator.queue_free()
	_indicators.clear()
	_targets.clear()

func _on_skip_pressed() -> void:
	skip_requested.emit()

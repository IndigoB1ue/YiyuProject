@tool
extends HBoxContainer

signal value_changed(value: float)

@export var label_text := "选项":
	set(value):
		label_text = value
		if is_node_ready():
			$Title.text = value
@export var minimum: float = 0.0
@export var maximum: float = 10.0
@export var suffix := ""


func _ready() -> void:
	$Title.text = label_text
	$Slider.min_value = minimum
	$Slider.max_value = maximum
	_update_number($Slider.value)


func set_value(value: float) -> void:
	$Slider.set_value_no_signal(value)
	_update_number(value)


func _on_slider_changed(value: float) -> void:
	_update_number(value)
	value_changed.emit(value)


func _update_number(value: float) -> void:
	$Value.text = "%d%s" % [roundi(value), suffix]

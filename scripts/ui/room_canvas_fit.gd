@tool
extends Control

signal layout_updated

## Children retain their editor-authored coordinates within this reference canvas.
@export var reference_size: Vector2 = Vector2(1070, 787):
	set(value):
		reference_size = Vector2(maxf(1.0, value.x), maxf(1.0, value.y))
		if is_node_ready():
			_fit_to_parent()

func _ready() -> void:
	var parent := get_parent() as Control
	if parent != null:
		parent.resized.connect(_fit_to_parent)
	_fit_to_parent()
	_fit_to_parent.call_deferred()

func _fit_to_parent() -> void:
	var parent := get_parent() as Control
	if parent == null or parent.size.x <= 0 or parent.size.y <= 0:
		return
	var ratio := minf(parent.size.x / reference_size.x, parent.size.y / reference_size.y)
	size = reference_size
	scale = Vector2.ONE * ratio
	position = (parent.size - reference_size * ratio) / 2.0
	if not Engine.is_editor_hint():
		layout_updated.emit()

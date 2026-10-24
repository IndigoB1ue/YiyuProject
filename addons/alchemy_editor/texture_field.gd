@tool
extends HBoxContainer

signal changed

var texture: Texture2D:
	set(value):
		texture = value
		if is_node_ready():
			_refresh()


func _ready() -> void:
	%Choose.pressed.connect(func(): %FileDialog.popup_centered_ratio(0.7))
	%Clear.pressed.connect(func(): texture = null; changed.emit())
	%FileDialog.file_selected.connect(_set_path)
	_refresh()


func _refresh() -> void:
	%Preview.texture = texture
	%Path.text = texture.resource_path if texture != null else "未选择图片（可拖入项目图片）"
	%Path.tooltip_text = %Path.text


func _set_path(path: String) -> void:
	var value := load(path) as Texture2D
	if value != null:
		texture = value
		changed.emit()


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	if data.get("type") == "resource":
		return data.get("resource") is Texture2D
	if data.get("type") == "files" and data.get("files", []).size() == 1:
		return ResourceLoader.load(data.files[0], "Texture2D") is Texture2D
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data.get("type") == "resource":
		texture = data.resource
		changed.emit()
	else:
		_set_path(data.files[0])

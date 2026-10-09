@tool
extends DialogicPortrait

## Shared image portrait: only the current speaker is bright and in front.
@export_group("Main")
@export_file var image: String = ""
@export var inactive_color := Color(0.35, 0.35, 0.35, 1.0)
@export var speaking_z_order: int = 100

var _dialogic: Node
var _is_speaking := false
var _normal_z_order := 0
var _raised := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_dialogic = get_node("/root/Dialogic")
	_dialogic.Portraits.character_joined.connect(_on_character_joined)
	_is_speaking = character != null and _dialogic.Text.get_current_speaker() == character
	_refresh_color()
	# Join events apply their configured order after instancing the portrait.
	_refresh_order.call_deferred()


func _should_do_portrait_update(_character: DialogicCharacter, _portrait: String) -> bool:
	# Keep speaking state when the same character changes expression.
	return true


func _update_portrait(passed_character: DialogicCharacter, passed_portrait: String) -> void:
	apply_character_and_portrait(passed_character, passed_portrait)
	apply_texture($Portrait, image)
	_refresh_color()


func _highlight() -> void:
	_is_speaking = true
	_refresh_color()
	_refresh_order()


func _unhighlight() -> void:
	_is_speaking = false
	_refresh_color()
	_refresh_order()


func _refresh_color() -> void:
	$Portrait.self_modulate = Color.WHITE if Engine.is_editor_hint() or _is_speaking else inactive_color


func _refresh_order() -> void:
	if Engine.is_editor_hint() or not is_instance_valid(_dialogic):
		return
	if not _dialogic.Portraits.is_character_joined(character):
		return
	if _dialogic.Portraits.get_character_portrait(character) != self:
		return

	var character_node: Node = _dialogic.Portraits.get_character_node(character)
	var container: Node = character_node.get_parent()
	if _is_speaking:
		if not _raised:
			_normal_z_order = int(container.get_meta("z_index", 0))
			_raised = true
		var front_order := speaking_z_order
		for other in container.get_parent().get_children():
			if other != container:
				front_order = maxi(front_order, int(other.get_meta("z_index", 0)) + 1)
		_dialogic.Portraits.change_character_z_index(character, front_order)
	elif _raised:
		_dialogic.Portraits.change_character_z_index(character, _normal_z_order)
		_raised = false


func _on_character_joined(_info: Dictionary) -> void:
	# A new character may enter with a larger authored order during this line.
	if _is_speaking:
		_refresh_order()

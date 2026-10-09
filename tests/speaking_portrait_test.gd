extends SceneTree

var _failures := 0
var _dialogic: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	# Allow the textbox visibility animation and input debounce to finish.
	await create_timer(0.25).timeout
	for frame in 8:
		await process_frame


func _advance() -> void:
	var previous_index: int = _dialogic.current_event_idx
	for attempt in 30:
		_dialogic.Text.skip_text_reveal()
		await create_timer(0.1).timeout
		if _dialogic.current_event_idx != previous_index:
			break
		_dialogic.Inputs.dialogic_action.emit()
		await create_timer(0.1).timeout
		if _dialogic.current_event_idx != previous_index:
			break
	_expect(_dialogic.current_event_idx != previous_index, "Manual advance reaches the next text event")
	await _settle()


func _end() -> void:
	_dialogic.end_timeline()
	if _dialogic.current_timeline != null:
		await _dialogic.timeline_ended
	await _settle()


func _color(character: DialogicCharacter) -> Color:
	return _dialogic.Portraits.get_character_portrait(character).get_node("Portrait").self_modulate


func _container(character: DialogicCharacter) -> Node:
	return _dialogic.Portraits.get_character_node(character).get_parent()


func _expect_front(character: DialogicCharacter) -> void:
	var container := _container(character)
	_expect(container.get_index() == container.get_parent().get_child_count() - 1,
		"Speaker is the last drawn portrait container")
	for other in container.get_parent().get_children():
		if other != container:
			_expect(int(container.get_meta("z_index", 0)) > int(other.get_meta("z_index", 0)),
				"Speaker order exceeds every other joined character")


func _run() -> void:
	_dialogic = root.get_node("Dialogic")
	var rovin := load("res://dialogic/character/Rovin.dch") as DialogicCharacter
	var ammy := load("res://dialogic/character/Ammy.dch") as DialogicCharacter
	var elder := load("res://dialogic/character/Elder.dch") as DialogicCharacter
	var timeline := DialogicTimeline.new()
	timeline.from_text("\n".join([
		'join Rovin left [animation="Instant In" length="0.0" z_index="7"]',
		'join Ammy right [animation="Instant In" length="0.0" z_index="250"]',
		'入场检查。',
		'Rovin: 轮到我说话。',
		'Rovin (WaveHand): 更换表情后继续说话。',
		'Ammy: 现在轮到我。',
		'旁白检查。',
		'Rovin: 新角色将要入场。',
		'结束检查。',
	]))
	_dialogic.start(timeline)
	await _settle()
	var dark := Color(0.35, 0.35, 0.35, 1.0)
	var ammy_dark: Color = str_to_var(ammy.portraits["Idle"]["export_overrides"].get(
		"inactive_color", "Color(0.35, 0.35, 0.35, 1.0)"))
	_expect(_dialogic.Portraits.default_portrait_scene.resource_path == "res://scenes/dialogue/speaking_portrait.tscn",
		"All default image portraits use the project's shared scene")
	_expect(_color(rovin) == dark and _color(ammy) == ammy_dark, "Every joined portrait starts dark before dialogue")
	_expect(_container(rovin).get_meta("z_index") == 7 and _container(ammy).get_meta("z_index") == 250,
		"Authored layer orders remain intact before speaking")
	var original: DialogicPortrait = _dialogic.Portraits.get_character_portrait(rovin)
	_expect(original.is_visible_in_tree(), "Shared portrait scene is visible after joining")
	_expect(_dialogic.Portraits.get_character_portrait(ammy).is_visible_in_tree(), "Other joined portraits are visible too")
	var original_texture: Texture2D = original.get_node("Portrait").texture
	_expect(original_texture != null and original._get_covered_rect().has_area(), "Existing image and bounds are loaded")
	await _advance()
	_expect(_color(rovin) == Color.WHITE and _color(ammy) == ammy_dark, "First speaker is bright and all others stay dark")
	_expect_front(rovin)
	await _advance()
	_expect(_dialogic.Portraits.get_character_portrait(rovin) == original, "Expression update reuses the portrait and its speaking state")
	_expect(original.get_node("Portrait").texture != original_texture, "Expression update loads the correct new image")
	_expect(_color(rovin) == Color.WHITE, "Changing expression during consecutive lines keeps the speaker bright")
	_expect_front(rovin)
	await _advance()
	_expect(_color(rovin) == dark and _color(ammy) == Color.WHITE, "Speaker switch dims the old speaker and brightens the new speaker")
	_expect(_container(rovin).get_meta("z_index") == 7, "Old speaker restores its authored layer order")
	_expect_front(ammy)
	await _advance()
	_expect(_color(rovin) == dark and _color(ammy) == ammy_dark, "Narration dims every character")
	_expect(_container(ammy).get_meta("z_index") == 250, "Narration restores even a high authored layer order")
	await _advance()
	await _dialogic.Portraits.join_character(elder, "", "center", false, 900, "", "Instant In", 0.0, false)
	await _settle()
	_expect(_color(elder) == dark, "Characters joining during dialogue start dark")
	_expect(_color(rovin) == Color.WHITE, "An entrant does not dim the current speaker")
	_expect_front(rovin)
	await _advance()
	_expect(_container(rovin).get_meta("z_index") == 7, "Repeated promotion still restores the original order")
	await _end()
	_expect(_dialogic.current_timeline == null, "The timeline ends normally")
	_dialogic.start(timeline)
	await _settle()
	_expect(_color(rovin) == dark and _color(ammy) == ammy_dark, "Next timeline begins with fresh dark portraits")
	await _end()
	print("Speaking portrait integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

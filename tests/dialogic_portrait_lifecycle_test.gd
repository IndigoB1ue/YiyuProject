extends SceneTree

const TIMELINE := "res://tests/fixtures/CP03_save_test.dtl"
const CHARACTER := "res://dialogic/character/Rovin.dch"

var _failures := 0
var _dialogic: Node
var _save: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 12:
		await process_frame


func _start() -> void:
	_dialogic.start(TIMELINE)
	await _dialogic.Text.text_started
	await _settle()


func _run() -> void:
	_dialogic = root.get_node("Dialogic")
	_save = root.get_node("SaveSystem")
	_save.storage_directory = "user://portrait_lifecycle_test"
	root.get_node("GameProgress").skip_rovin_tutorial()
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_expect(_save.save_slot(1).ok, "The room can be saved before dialogue")
	await _start()
	var portraits: Node = _dialogic.Portraits
	var character := load(CHARACTER) as DialogicCharacter
	var character_node: Node = portraits.get_character_node(character)
	_expect(is_instance_valid(character_node), "The fixture creates a live character portrait")
	var animation: DialogicAnimation = portraits.animate_character(character, "Fade In", 5.0)
	_dialogic.paused = true
	_expect(character_node.process_mode == Node.PROCESS_MODE_DISABLED, "A live portrait animation still pauses")
	_dialogic.paused = false
	_expect(character_node.process_mode == Node.PROCESS_MODE_INHERIT, "A live portrait animation still resumes")
	animation.queue_free()
	await _settle()
	# Metadata can outlive its animation even while the character remains alive.
	_dialogic.paused = true
	_dialogic.paused = false
	character_node.remove_meta("animation_node")
	_dialogic.paused = true
	_dialogic.paused = false

	# Different layouts recreate portraits from serialized info after the old nodes exit.
	var alternate := (load("res://dialogic/style/MyStyle.tres") as DialogicStyle).duplicate() as DialogicStyle
	alternate.name = "PortraitLifecycleTest"
	_expect(ResourceSaver.save(alternate, "user://portrait_lifecycle_style.tres") == OK, "A temporary alternate layout is available")
	_dialogic.Styles.change_style("user://portrait_lifecycle_style.tres")
	await _settle()
	_expect(not is_instance_valid(character_node) and is_instance_valid(portraits.get_character_node(character)),
		"A style change removes old references and recreates the character")
	_dialogic.Styles.change_style("MyStyle")
	await _settle()
	character_node = portraits.get_character_node(character)
	_expect(is_instance_valid(character_node), "Returning to the original style preserves its joined character")
	_expect(_save.save_slot(2).ok, "An active dialogue saves its portrait")
	var event_index: int = _dialogic.current_event_idx
	for entry in [["SettingsUI", "open_settings", "close_settings"],
		["InventoryUI", "open_inventory", "close_inventory"], ["SaveUI", "open_load", "close_window"]]:
		var overlay: Node = root.get_node(entry[0])
		overlay.call(entry[1])
		_expect(overlay.is_open() and _dialogic.paused, "%s pauses the portrait timeline" % entry[0])
		overlay.call(entry[2])
		_expect(not paused and not _dialogic.paused and _dialogic.current_event_idx == event_index,
			"%s resumes the same dialogue event" % entry[0])

	await _dialogic.end_timeline(true)
	await _settle()
	_expect(not is_instance_valid(character_node), "Ending the timeline frees its character node")
	_expect(portraits.character_nodes.is_empty(), "Freed character nodes are removed from the live registry")
	_expect(not portraits.is_character_joined(character), "Serialized portrait info does not count as a live joined character")
	_dialogic.paused = true
	_dialogic.paused = false
	_expect(_save.save_slot(3).ok, "Saving after a portrait timeline ends does not inspect freed nodes")
	var result: Dictionary = await _save.load_slot(2)
	await _settle()
	_expect(result.ok and is_instance_valid(portraits.get_character_node(character)),
		"Loading after timeline teardown restores a live portrait")
	await _dialogic.end_timeline(true)
	await _settle()
	result = await _save.load_slot(1)
	await _settle()
	_expect(result.ok and _dialogic.current_timeline == null and not _dialogic.paused,
		"A room save also loads after the previous portraits were freed")

	await _start()
	await _dialogic.end_timeline(true)
	await _settle()
	result = await _save.start_new_game()
	await _dialogic.Text.text_started
	await _settle()
	_expect(result.ok and not _save.is_restoring and not _dialogic.paused,
		"Starting a new game after portrait teardown does not retain an invalid pause")
	await _dialogic.end_timeline(true)
	await _settle()
	print("Dialogic portrait lifecycle: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

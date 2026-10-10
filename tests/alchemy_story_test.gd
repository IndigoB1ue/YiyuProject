extends SceneTree

var _failures = 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame

func _confirm(ui: Control) -> void:
	ui._result.get_ok_button().pressed.emit()
	await _settle()

func _run() -> void:
	# Keep the test timeline outside the game's authored dialogue library.
	var fixture_path = "res://.godot/alchemy_story_test.dtl"
	var fixture = FileAccess.open(fixture_path, FileAccess.WRITE)
	fixture.store_string("[wait time=\"60.0\" hide_text=\"true\"]\n[end_timeline]\n")
	fixture.close()
	var fixture_uid = ResourceUID.create_id()
	ResourceUID.add_id(fixture_uid, fixture_path)
	var fixture_reference = ResourceUID.id_to_text(fixture_uid)
	var inventory = root.get_node("PlayerInventory") as InventorySystem
	var progress = root.get_node("GameProgress")
	var dialogic = root.get_node("Dialogic")
	progress.unlock_recipe(&"ClearPotion")
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	var ui: Control = current_scene
	var trigger = ui.get_node("StoryTrigger")
	_expect(trigger.return_scene_path == "res://scenes/RovinRoom.tscn", "Story completion is configured to return to the room")
	trigger.timeline_path = fixture_reference
	ui._synthesize()
	await _confirm(ui)
	_expect(not progress.cleanser_timeline_started and not trigger.is_playing, "Failed synthesis cannot start the storyline")
	ui._result.show_result({"ok": true, "item_id": &"Potion", "amount": 1}, inventory)
	await _confirm(ui)
	_expect(not progress.cleanser_timeline_started, "Other item results cannot start the cleanser storyline")
	inventory.add_item(&"cleaning_powder", 1)
	inventory.add_item(&"Water", 3)
	for index in ui._slots.size():
		ui._activate_slot(index)
		for cell in ui._picker._grid.get_children():
			if cell is Button and not cell.disabled:
				cell.pressed.emit()
				break
	ui._synthesize()
	_expect(ui._result.visible and inventory.get_amount(&"clear_potion") == 1 and not trigger.is_playing, "The result is shown and committed before playing the timeline")
	trigger.timeline_path = ""
	await _confirm(ui)
	_expect(not progress.cleanser_timeline_started and dialogic.current_timeline == null, "Empty timeline path safely skips playback")
	_expect(inventory.get_amount(&"clear_potion") == 1 and (ui.get_node("Margin") as Control).visible, "Empty configuration preserves the successful reward and interface")
	ui._result.show_result({"ok": true, "item_id": &"clear_potion", "amount": 1}, inventory)
	trigger.timeline_path = "res://tests/fixtures/missing_story.dtl"
	await _confirm(ui)
	_expect(not progress.cleanser_timeline_started and ui._result.dialog_text.contains("timeline 不存在"), "Invalid timeline gives a clear error without claiming playback")
	_expect(inventory.get_amount(&"clear_potion") == 1, "Playback failure cannot roll back or consume the awarded cleanser")
	await _confirm(ui)
	trigger.timeline_path = fixture_reference
	ui._result.show_result({"ok": true, "item_id": &"clear_potion", "amount": 1}, inventory)
	var before = inventory.get_items()
	await _confirm(ui)
	_expect(progress.cleanser_timeline_started and trigger.is_playing, "Confirmed cleanser starts Dialogic once")
	_expect(dialogic.current_timeline != null and dialogic.current_timeline.resource_path == fixture_path, "The configured UID resolves to the actual timeline resource")
	_expect(not (ui.get_node("Margin") as Control).visible, "Alchemy controls are hidden during dialogue")
	_expect(inventory.get_items() == before, "Starting dialogue does not change inventory")
	await dialogic.end_timeline(true)
	await _settle()
	_expect(current_scene.name == "RovinRoom" and progress.cleanser_timeline_completed, "Ending dialogue returns to the room and records completion")
	var room: Control = current_scene
	_expect(room._hotspots.stairs.visible and not room._hotspots.stairs.disabled, "Story completion enables the stairs")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	ui = current_scene
	trigger = ui.get_node("StoryTrigger")
	trigger.timeline_path = fixture_reference
	ui._result.show_result({"ok": true, "item_id": &"clear_potion", "amount": 1}, inventory)
	await _confirm(ui)
	_expect(dialogic.current_timeline == null and not trigger.is_playing, "Repeated rewards do not replay the story")
	ui._on_back_pressed()
	await _settle()
	(current_scene as Control)._hotspots.alchemy.pressed.emit()
	await _settle()
	ui = current_scene
	trigger = ui.get_node("StoryTrigger")
	trigger.timeline_path = fixture_reference
	ui._result.show_result({"ok": true, "item_id": &"clear_potion", "amount": 1}, inventory)
	await _confirm(ui)
	_expect(not trigger.is_playing and progress.cleanser_timeline_started, "Playback flag persists across scenes")
	print("Alchemy storyline tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

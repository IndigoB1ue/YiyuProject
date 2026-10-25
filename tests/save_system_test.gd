extends SceneTree

var _failures := 0
var _save: Node
var _inventory: InventorySystem
var _progress: Node
var _dialogic: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 12:
		await process_frame


func _run() -> void:
	_save = root.get_node("SaveSystem")
	_inventory = root.get_node("PlayerInventory")
	_progress = root.get_node("GameProgress")
	_dialogic = root.get_node("Dialogic")
	if OS.get_cmdline_user_args().has("--verify-persisted"):
		_expect(_save.get_slot_record(1).state == "saved", "Save records persist in a separate process")
		var loaded: Dictionary = await _save.load_slot(1)
		await _settle()
		_expect(loaded.ok and current_scene.scene_file_path == "res://scenes/RovinRoom.tscn", "A new process restores the saved room")
		_expect(_inventory.get_amount(&"Water") == 3 and _progress.is_interaction_claimed(&"RovinRoom/shoe"), "Backpack and collection persist across launches")
		_finish()
		return
	_expect(_save.SLOT_COUNT == 120 and _save.PAGE_SIZE == 12, "120 save slots use ten 12-record pages")
	_expect(_save.format_play_time(3661.9) == "01:01:01", "Play time uses hours, minutes and seconds")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_progress.reset_for_new_game()
	_progress.skip_rovin_tutorial()
	_progress.unlock_recipe(&"ClearPotion")
	_progress.claim_interaction(&"RovinRoom/shoe")
	for id in _inventory.get_items():
		_inventory.remove_item(id, _inventory.get_amount(id))
	_inventory.add_item(&"Water", 3)
	_inventory.add_item(&"cleaning_powder", 1)
	_inventory.add_item(&"Herb", 1)
	_inventory.add_item(&"clear_potion_recipe", 1)
	_save.set_chapter(2)
	_save.play_seconds = 3661.0
	var thumbnail := Image.create(480, 270, false, Image.FORMAT_RGB8)
	thumbnail.fill(Color(0.15, 0.3, 0.4))
	_expect(_save.save_slot(1, thumbnail).ok, "Room progress saves successfully")
	var record: Dictionary = _save.get_slot_record(1)
	_expect(record.state == "saved" and record.chapter == "第2章" and record.play_time == "01:01:01", "A record reports the saved chapter and play time")
	_expect(record.texture != null and record.texture.get_size() == Vector2(480, 270) and record.saved_at.contains("/"), "Record stores a screenshot and calendar timestamp")
	_inventory.remove_item(&"Water", 3)
	_progress.reset_for_new_game()
	_save.play_seconds = 2.0
	var result: Dictionary = await _save.load_slot(1)
	await _settle()
	_expect(result.ok and _inventory.get_amount(&"Water") == 3, "Loading restores inventory instead of merging or duplicating it")
	_expect(_progress.rovin_tutorial_skipped and _progress.is_recipe_unlocked(&"ClearPotion") and _progress.is_interaction_claimed(&"RovinRoom/shoe"), "Loading restores tutorial, unlocked recipes and claimed interactions")
	_expect(current_scene._hotspots.shoe.disabled and _save.chapter == 2 and _save.play_seconds >= 3661, "The rebuilt room reflects its collection and session state")
	var before: float = _save.play_seconds
	root.get_node("SaveUI").open_save()
	await create_timer(0.3).timeout
	_expect(is_equal_approx(before, _save.play_seconds), "Play time stops while the save window is open")
	root.get_node("SaveUI").close_window()
	await create_timer(0.2).timeout
	_expect(_save.play_seconds > before, "Play time resumes during active gameplay")
	_expect(_save.save_slot(120, thumbnail).ok and _save.get_slot_record(120).state == "saved", "The last of the 120 slots is writable")
	_expect(not _save.save_slot(121).ok and not (await _save.load_slot(0)).ok, "Invalid slot numbers are rejected")
	var inventory_before := _inventory.get_items()
	var scene_before: Node = current_scene
	var damaged := GameSaveData.new()
	damaged.scene_path = "res://scenes/RovinRoom.tscn"
	damaged.saved_at = "2026/10/13 12:00:00"
	damaged.inventory = {"capacity": 200, "items": {&"InvalidID": 5}}
	damaged.progress = _progress.get_save_state()
	damaged.dialogic_state = _dialogic.get_full_state()
	ResourceSaver.save(damaged, _save._slot_path(119))
	result = await _save.load_slot(119)
	_expect(not result.ok and result.error.contains("ItemID") and current_scene == scene_before and _inventory.get_items() == inventory_before,
		"Invalid save contents never alter the live scene or inventory")
	var versioned := GameSaveData.new()
	versioned.format_version = 99
	ResourceSaver.save(versioned, _save._slot_path(118))
	_expect(_save.get_slot_record(118).state == "corrupt" and not (await _save.load_slot(118)).ok, "Incompatible save versions are clearly rejected")
	var denied_path: String = _save.storage_directory
	_save.storage_directory = "res://project.godot/cannot_write"
	_expect(not _save.save_slot(1).ok, "Filesystem failure is reported without damaging the existing record")
	_save.storage_directory = denied_path
	_expect(_save.get_slot_record(1).state == "saved", "Failed saving preserves the existing slot")

	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	var alchemy: Control = current_scene
	alchemy._select_recipe(load("res://data/recipes/clear_potion.tres"))
	alchemy._select_material(&"cleaning_powder", 1)
	alchemy._activate_slot(1)
	alchemy._select_material(&"Herb", 1)
	var selected: Array = alchemy._selection.duplicate(true)
	_expect(_save.save_slot(13, thumbnail).ok, "Partial alchemy selection can be saved")
	alchemy._clear_slot(1)
	result = await _save.load_slot(13)
	await _settle()
	_expect(result.ok and current_scene._selection == selected and current_scene._active_slot == 1, "Alchemy restores the selected recipe, reserved materials and active slot")
	_dialogic.start("res://tests/fixtures/CP03_save_test.dtl")
	for frame in 4:
		await process_frame
	result = await _save.load_slot(13)
	await _settle()
	_expect(result.ok and _dialogic.current_timeline == null, "Reading during a pending dialogue entrance cancels it safely")

	_dialogic.VAR.set_variable("player.name_1", "保存的名字")
	_dialogic.start("res://tests/fixtures/CP03_save_test.dtl")
	await _dialogic.Text.text_started
	await _settle()
	var event_index: int = _dialogic.current_event_idx
	_expect(_dialogic.current_state == DialogicGameHandler.States.REVEALING_TEXT, "Timeline fixture saves during active text reveal")
	_expect(_save.chapter == 3 and _save.can_save().ok, "Timeline names determine the chapter and allow saving at a text node")
	_expect(_save.save_slot(2, thumbnail).ok, "Dialogic text and portraits save alongside game state")
	_dialogic.VAR.set_variable("player.name_1", "变更的名字")
	result = await _save.load_slot(2)
	await _settle()
	_expect(result.ok and _dialogic.current_timeline.resource_path == "res://tests/fixtures/CP03_save_test.dtl" and _dialogic.current_event_idx == event_index,
		"Loading resumes the saved timeline node without restarting the introduction")
	_expect(_dialogic.VAR.get_variable("player.name_1") == "保存的名字" and _dialogic.Portraits.is_character_joined(load("res://dialogic/character/Rovin.dch")),
		"Dialogic variables and joined character portraits are restored")
	_expect(not paused and not _dialogic.paused and not _save.is_restoring, "Loading does not leave a stuck modal or pause")
	await _dialogic.end_timeline(true)
	await _settle()
	# Restored scene controllers must continue their original end-of-timeline routes.
	current_scene._story.restore_playback(true)
	_progress.cleanser_timeline_started = true
	_dialogic.start(current_scene._story.timeline_path)
	await _dialogic.Text.text_started
	await _settle()
	_expect(_save.save_slot(14, thumbnail).ok, "Alchemy follow-up playback state saves")
	result = await _save.load_slot(14)
	await _settle()
	_expect(result.ok and current_scene._story.is_playing and not current_scene.get_node("Margin").visible,
		"Loading alchemy follow-up restores its hidden interface and active story controller")
	_dialogic.signal_event.emit("CheckAndActiveStairs")
	await _settle()
	_expect(current_scene.scene_file_path == "res://scenes/RovinRoom.tscn" and _progress.cleanser_timeline_completed,
		"A restored alchemy follow-up still returns to the room and completes progression")
	change_scene_to_file("res://scenes/AcademyMap.tscn")
	await _settle()
	var academy: Control = current_scene
	_progress.stairs_timeline_started = false
	academy.hall_timeline_path = "res://tests/fixtures/CP03_save_test.dtl"
	academy._on_hall_pressed()
	await _dialogic.Text.text_started
	await _settle()
	_expect(_save.save_slot(15, thumbnail).ok, "Hall dialogue saves on the first-level map")
	result = await _save.load_slot(15)
	await _settle()
	_expect(result.ok and current_scene._playing and not current_scene.visible, "Hall dialogue loading restores the hidden map")
	_dialogic.paused = true
	await _dialogic.end_timeline(true)
	_dialogic.paused = false
	await _settle()
	_expect(current_scene.visible and current_scene.get_node("%Hall").disabled, "Restored hall dialogue ends on the map and preserves its watched state")
	_progress.cleanser_timeline_started = true
	_progress.cleanser_timeline_completed = true
	var music: Variant = root.get_node("GameSettings").get_value("audio", "music")
	result = await _save.start_new_game()
	await _dialogic.Text.text_started
	await _settle()
	_expect(result.ok and _inventory.get_items() == _inventory.catalog.initial_inventory and not _progress.cleanser_timeline_started and not _progress.is_interaction_claimed(&"RovinRoom/shoe"),
		"New game clears old inventory, recipes, claims and story flags")
	_expect(_save.chapter == 1 and _save.play_seconds < 5 and root.get_node("GameSettings").get_value("audio", "music") == music,
		"New game resets chapter and time while preserving options")
	await _dialogic.end_timeline(true)
	_finish()


func _finish() -> void:
	print("Game save behavior: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

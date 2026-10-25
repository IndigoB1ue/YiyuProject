extends SceneTree

var _failures := 0
var _completions := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 4:
		await process_frame


func _run() -> void:
	var manager := root.get_node("QuestSystem") as QuestManager
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	var progress := root.get_node("GameProgress") as GameProgressState
	var save := root.get_node("SaveSystem")
	progress.reset_for_new_game()
	inventory.reset_for_new_game()
	manager.reset_for_new_game()
	manager.quest_completed.connect(func(_id: StringName) -> void: _completions += 1)
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_expect(manager.get_accepted_quests() == [&"make_cleanser"] and manager.get_tracked_quest_id() == &"make_cleanser" and manager.is_tracker_collapsed(), "First room visit accepts and tracks the quest with the tracker collapsed")
	_expect(not manager.accept_quest(&"make_cleanser"), "A repeated acceptance is ignored")
	manager.track_quest(&"")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_expect(manager.get_tracked_quest_id() == &"", "Room reentry does not override the tracking choice")
	manager.set_tracker_collapsed(false)
	manager.track_quest(&"make_cleanser")
	_expect(manager.is_tracker_collapsed(), "Selecting a task starts with its floating tracker collapsed")
	manager.track_quest(&"")
	var requirements := manager.get_public_material_requirements(&"make_cleanser")
	_expect(requirements.get(&"Water") == 2 and requirements.get(&"Herb") == 1 and requirements.get(&"cleaning_powder") == 1, "Requirements combine repeated public slots from the actual recipe")
	inventory.add_item(&"Water", requirements[&"Water"])
	inventory.add_item(&"cleaning_powder", requirements[&"cleaning_powder"])
	_expect(manager.get_quest_state(&"make_cleanser").stage_id == &"get_recipe", "Collecting materials first does not bypass the recipe objective")
	progress.unlock_recipe(&"ClearPotion")
	_expect(manager.get_quest_state(&"make_cleanser").stage_id == &"craft", "Existing materials and recipe unlock immediately satisfy their stages")
	progress.skip_rovin_tutorial()
	manager.set_tracker_collapsed(true)
	_expect(not manager.is_completed(&"make_cleanser") and manager.get_accepted_quests().size() == 1, "Skipping hints, collapsing and untracking leave the quest active")
	inventory.remove_item(&"Water", requirements[&"Water"])
	_expect(manager.get_quest_state(&"make_cleanser").stage_id == &"craft", "Recorded stages do not regress after materials are consumed")
	_expect(not AlchemySystem.new(inventory).check_material_availability(manager.get_quest(&"make_cleanser").recipe).ok, "Recorded material progress never bypasses actual alchemy validation")
	inventory.add_item(&"clear_potion", 1)
	_expect(not manager.is_completed(&"make_cleanser"), "Owning the target output does not count as confirming synthesis")
	var confirmation := {"source": &"alchemy", "recipe_id": &"ClearPotion", "ok": true, "item_id": &"clear_potion", "amount": 1, "outcome": &"base"}
	for changes: Dictionary in [{"ok": false}, {"item_id": &"Potion"}, {"source": &"reward"}, {"recipe_id": &"OtherRecipe"}, {"outcome": &"waste"}, {"amount": 0}]:
		var invalid := confirmation.duplicate()
		invalid.merge(changes, true)
		manager.on_result_confirmed(invalid)
	_expect(not manager.is_completed(&"make_cleanser"), "Failed, unrelated and non-synthesis confirmations cannot complete the quest")
	manager.on_result_confirmed(confirmation)
	manager.on_result_confirmed(confirmation)
	_expect(manager.is_completed(&"make_cleanser") and _completions == 1, "Valid confirmation completes exactly once")
	manager.set_tracker_collapsed(false)
	var state := manager.get_save_state()
	_expect(manager.validate_save_state(state).ok, "Current quest state is valid for saving")
	manager.reset_for_new_game()
	manager.restore_save_state(state)
	_expect(manager.is_completed(&"make_cleanser") and not manager.is_tracker_collapsed() and manager.get_tracked_quest_id() == &"" and _completions == 1, "Restore preserves an explicitly expanded tracker without replaying completion")
	var legacy_display := state.duplicate(true)
	legacy_display.erase("tracker_collapsed")
	_expect(manager.validate_save_state(legacy_display).ok, "Old task saves without a display flag remain valid")
	manager.restore_save_state(legacy_display)
	_expect(manager.is_tracker_collapsed(), "Missing display state defaults to a collapsed tracker")
	var invalid := state.duplicate(true)
	invalid.accepted[&"make_cleanser"].completed_stages = [&"craft"]
	_expect(not manager.validate_save_state(invalid).ok, "Invalid stage records are rejected")
	invalid = state.duplicate(true)
	invalid.tracked = &"unknown"
	_expect(not manager.validate_save_state(invalid).ok, "Tracking an unaccepted quest is rejected")
	var legacy := progress.get_save_state()
	legacy.cleanser_timeline_started = false
	legacy.cleanser_timeline_completed = false
	legacy.rovin_tutorial_completed = true
	legacy.rovin_tutorial_skipped = true
	var migrated := manager.migrate_legacy_state(legacy, "res://scenes/RovinRoom.tscn")
	_expect(manager.validate_save_state(migrated).ok and migrated.accepted[&"make_cleanser"].status == "active" and migrated.tracker_collapsed, "Legacy tutorial flags do not imply crafting and initialize a collapsed tracker")
	legacy.cleanser_timeline_started = true
	migrated = manager.migrate_legacy_state(legacy, "res://scenes/AlchemyRoom.tscn")
	_expect(migrated.accepted[&"make_cleanser"].status == "completed", "Legacy follow-up start proves a confirmed synthesis")
	legacy.cleanser_timeline_started = false
	legacy.unlocked_recipes = {}
	legacy.claimed_interactions = {}
	_expect(manager.migrate_legacy_state(legacy, "res://scenes/world.tscn").accepted.is_empty(), "Unrelated legacy saves do not receive quests before reaching the room")
	var hidden := QuestData.new()
	hidden.quest_id = &"hidden_example"
	hidden.recipe = load("res://data/recipes/experiment_three.tres")
	hidden.recipe_item_id = &"ExperimentBookThree"
	var isolated := QuestManager.new()
	isolated.quests = [hidden]
	root.add_child(isolated)
	isolated.accept_quest(hidden.quest_id)
	var public_materials := isolated.get_public_material_requirements(hidden.quest_id)
	for index in range(2, hidden.recipe.ingredients.size()):
		var hidden_id := hidden.recipe.ingredients[index].item_id
		if hidden_id != &"":
			_expect(not public_materials.has(hidden_id), "Hidden answers never appear in requirement maps")
	var objectives := isolated.get_objectives(hidden.quest_id)
	var material_rows := objectives.filter(func(row: Dictionary) -> bool: return row.stage_id == &"collect_materials")
	_expect(material_rows.size() == public_materials.size(), "Quest objectives display only required public material slots")
	isolated.queue_free()
	# Save/load exercises the real restore order, including scene rebuild and legacy migration.
	save.storage_directory = "user://quest_system_test"
	manager.track_quest(&"make_cleanser")
	manager.set_tracker_collapsed(true)
	var saved: Dictionary = save.save_slot(1)
	_expect(saved.ok, "Quest progress saves through SaveSystem")
	manager.reset_for_new_game()
	var loaded: Dictionary = await save.load_slot(1)
	await _settle()
	_expect(loaded.ok and manager.is_completed(&"make_cleanser") and manager.get_tracked_quest_id() == &"make_cleanser" and manager.is_tracker_collapsed(), "Loading restores quest completion and tracking across scene reconstruction")
	var corrupted := ResourceLoader.load(save._slot_path(1), "", ResourceLoader.CACHE_MODE_IGNORE) as GameSaveData
	corrupted.quests.accepted[&"make_cleanser"].stage_id = &"invalid"
	ResourceSaver.save(corrupted, save._slot_path(2))
	var before := manager.get_save_state()
	var before_inventory := inventory.get_items()
	var before_scene := current_scene
	loaded = await save.load_slot(2)
	_expect(not loaded.ok and manager.get_save_state() == before and inventory.get_items() == before_inventory and current_scene == before_scene, "Invalid quest data is rejected before changing any live subsystem")
	var old_save := ResourceLoader.load(save._slot_path(1), "", ResourceLoader.CACHE_MODE_IGNORE) as GameSaveData
	old_save.quests = {}
	old_save.progress.cleanser_timeline_started = false
	old_save.progress.cleanser_timeline_completed = false
	old_save.progress.rovin_tutorial_completed = true
	ResourceSaver.save(old_save, save._slot_path(3))
	loaded = await save.load_slot(3)
	await _settle()
	_expect(loaded.ok and not manager.is_completed(&"make_cleanser") and manager.get_accepted_quests().size() == 1, "Loading an old room save migrates the task without mistaking skipped hints or owned cleanser for crafting")
	old_save.progress.cleanser_timeline_started = true
	ResourceSaver.save(old_save, save._slot_path(4))
	loaded = await save.load_slot(4)
	await _settle()
	_expect(loaded.ok and manager.is_completed(&"make_cleanser") and _completions == 1, "Loading a legacy confirmed save restores completion without emitting a new completion event")
	for slot in [1, 2, 3, 4]:
		DirAccess.remove_absolute(save._slot_path(slot))
	var new_game: Dictionary = await save.start_new_game()
	await _settle()
	_expect(new_game.ok and manager.get_accepted_quests().is_empty() and manager.get_tracked_quest_id() == &"" and manager.is_tracker_collapsed(), "New game resets progress and starts with the tracker collapsed")
	_expect(not progress.cleanser_timeline_started and not progress.cleanser_timeline_completed and _completions == 1, "Starting a new game never turns dialogue cancellation into quest or story completion")
	await root.get_node("Dialogic").end_timeline(true)
	print("Quest progression and persistence: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 6:
		await process_frame

func _collect(room: Control, id: String) -> void:
	room._hotspots[id].pressed.emit()
	room._message.hide()
	await _settle()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var progress: Node = root.get_node("GameProgress")
	var inventory: InventorySystem = root.get_node("PlayerInventory")
	var quests: Node = root.get_node("QuestSystem")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var room: Control = current_scene
	var view: RovinTutorialUI = room.get_node("TutorialUI")
	_expect(quests.get_accepted_quests() == [&"make_cleanser"], "First room visit accepts the quest exactly once")
	_expect(view.visible and room._tutorial.stage == RovinTutorialController.Stage.GET_RECIPE, "Room highlights follow the current quest stage")
	_expect(view._indicators.size() == 1 and view._targets[0].control == room._hotspots.recipe, "Initial highlight identifies the bookshelf")
	_expect(view._indicators[0].get_global_rect().is_equal_approx((room._hotspots.recipe as Control).get_global_rect()), "Highlight fits the target")
	await _collect(room, "shoe")
	_expect(quests.get_quest_state(&"make_cleanser").stage_id == &"get_recipe", "Early collection does not require following the suggested order")
	await _collect(room, "recipe")
	_expect(room._tutorial.stage == RovinTutorialController.Stage.COLLECT_MATERIALS, "Recipe discovery advances the shared quest stage")
	await _collect(room, "desk")
	await _collect(room, "bedside")
	_expect(room._tutorial.stage == RovinTutorialController.Stage.ENTER_ALCHEMY, "Actual required materials advance to crafting")
	_expect(view._indicators.size() == 1 and view._targets[0].control == room._hotspots.alchemy, "Craft stage highlights the alchemy area")
	var water := inventory.get_amount(&"Water")
	inventory.remove_item(&"Water", water)
	_expect(quests.get_quest_state(&"make_cleanser").stage_id == &"craft", "Completed material stage does not regress after external consumption")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.visible, "Recorded progress never bypasses actual alchemy entry validation")
	room._message.hide()
	inventory.add_item(&"Water", water)
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene is AlchemyUI and not progress.rovin_tutorial_completed, "Entering alchemy does not complete the quest or tutorial")
	_expect(not quests.is_completed(&"make_cleanser"), "Craft confirmation remains required across scenes")
	(current_scene as AlchemyUI)._on_back_pressed()
	await _settle()
	room = current_scene
	view = room.get_node("TutorialUI")
	_expect(quests.get_accepted_quests().size() == 1 and view.visible, "Returning restores guidance without accepting a duplicate quest")
	print("Quest room guidance: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

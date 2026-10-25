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

func _fill(ui: AlchemyUI) -> void:
	for index in ui._recipe.ingredients.size():
		var requirement: IngredientRequirement = ui._recipe.ingredients[index]
		ui._system.select_material(ui._recipe, index, ui._selection, requirement.item_id, requirement.amount)
	ui._refresh()

func _run() -> void:
	var inventory: InventorySystem = root.get_node("PlayerInventory")
	var progress: GameProgressState = root.get_node("GameProgress")
	var quests: QuestManager = root.get_node("QuestSystem")
	var dialogic: Node = root.get_node("Dialogic")
	var saves: Node = root.get_node("SaveSystem")
	var flow: QuestFlowRunner = root.get_node("QuestFlow")
	var accepted: Array[StringName] = []
	var completed: Array[StringName] = []
	quests.quest_accepted.connect(func(id: StringName) -> void: accepted.append(id))
	quests.quest_completed.connect(func(id: StringName) -> void: completed.append(id))
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var room: Control = current_scene
	_expect(accepted.size() == 1 and quests.get_tracked_quest_id() == &"make_cleanser", "First entry accepts and tracks the quest once")
	_expect(room._map_button.visible and room._hotspots.stairs.disabled, "Ordinary map navigation is available while the story stairs remain locked")
	inventory.add_item(&"clear_potion", 1)
	_expect(not quests.is_completed(&"make_cleanser"), "Receiving the output through another source does not complete a craft")
	inventory.remove_item(&"clear_potion", 1)
	for id in ["shoe", "desk", "bedside", "recipe"]:
		room._hotspots[id].pressed.emit()
		room._message.hide()
	_expect(quests.get_quest_state(&"make_cleanser").stage_id == &"craft", "Free-order collection uses actual recipe needs, including combined water slots")
	progress.skip_rovin_tutorial()
	_expect(not room.get_node("TutorialUI").visible and not quests.is_completed(&"make_cleanser"), "Skipping teaching removes highlights and preserves the active quest")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene is AlchemyUI and not quests.is_completed(&"make_cleanser"), "Entering alchemy does not complete the quest")
	var ui: AlchemyUI = current_scene
	var story: AlchemyStoryTrigger = ui.get_node("StoryTrigger")
	var configured_path: String = story.timeline_path
	ui._synthesize()
	ui._result.get_ok_button().pressed.emit()
	await _settle()
	_expect(not quests.is_completed(&"make_cleanser") and dialogic.current_timeline == null, "Failed validation cannot complete the quest or play a story")
	ui._result.show_result({"ok": true, "item_id": &"clear_potion", "amount": 1}, inventory)
	ui._result.get_ok_button().pressed.emit()
	await _settle()
	_expect(not quests.is_completed(&"make_cleanser"), "A display-only popup is not a synthesis business event")
	_fill(ui)
	ui._synthesize()
	_expect(ui._result.visible and inventory.get_amount(&"clear_potion") == 1 and not quests.is_completed(&"make_cleanser"), "Output is awarded before confirmation without prematurely completing the quest")
	_expect(quests.get_quest_state(&"make_cleanser").stage_id == &"craft", "Consuming materials does not roll back completed collection")
	story.timeline_path = ""
	ui._result.get_ok_button().pressed.emit()
	await _settle()
	_expect(quests.is_completed(&"make_cleanser") and completed.size() == 1, "A real confirmed target output completes the quest exactly once")
	_expect(not progress.cleanser_timeline_started and dialogic.current_timeline == null, "Missing optional story configuration leaves the committed quest intact")
	story.timeline_path = "res://tests/fixtures/missing_story.dtl"
	story.resume_pending_story()
	await _settle()
	_expect(ui._result.visible and ui._result.dialog_text.contains("timeline 不存在") and not progress.cleanser_timeline_started, "A missing story reports a retryable failure")
	ui._result.get_ok_button().pressed.emit()
	story.timeline_path = configured_path
	story.resume_pending_story()
	await _settle()
	if dialogic.current_state == DialogicGameHandler.States.ANIMATING:
		await dialogic.Text.text_started
	_expect(story.is_playing and progress.cleanser_timeline_started and not progress.cleanser_timeline_completed, "Story playback starts after quest completion and keeps stairs locked")
	var playing: DialogicTimeline = dialogic.current_timeline
	story.on_result_confirmed({"ok": true, "source": &"alchemy", "recipe_id": &"ClearPotion", "item_id": &"clear_potion", "amount": 1})
	await _settle()
	_expect(dialogic.current_timeline == playing and completed.size() == 1, "Repeated confirmations neither complete twice nor replay the running timeline")
	flow._active_timeline = load("res://tests/fixtures/CP03_save_test.dtl")
	dialogic.signal_event.emit("CheckAndActiveStairs")
	await _settle()
	_expect(not progress.cleanser_timeline_completed and story.is_playing, "An ending signal from a different timeline cannot unlock stairs")
	flow._active_timeline = playing
	dialogic.paused = true
	await dialogic.end_timeline(true)
	dialogic.paused = false
	await _settle()
	_expect(current_scene == ui and not story.is_playing and not progress.cleanser_timeline_completed and ui.get_node("Margin").visible, "Canceling dialogue restores alchemy without completing the story")
	progress.cleanser_timeline_started = true
	saves.is_restoring = true
	story.restore_playback(false)
	saves.is_restoring = false
	saves.restore_finished.emit()
	await _settle()
	_expect(not progress.cleanser_timeline_started and dialogic.current_timeline == null, "Legacy interrupted starts are repaired on restore without replaying dialogue")
	# A previously detached controller can also leave a stale started marker.
	progress.cleanser_timeline_started = true
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	room = current_scene
	_expect(accepted.size() == 1 and not room._hotspots.stairs.visible, "Returning never accepts twice or opens stairs after cancellation")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	ui = current_scene
	story = ui.get_node("StoryTrigger")
	if dialogic.current_state == DialogicGameHandler.States.ANIMATING:
		await dialogic.Text.text_started
	_expect(story.is_playing, "An interrupted pending story can be retried without another craft")
	saves.is_restoring = true
	dialogic.signal_event.emit("CheckAndActiveStairs")
	_expect(not progress.cleanser_timeline_completed, "Restoring a save suppresses narrative completion callbacks")
	saves.is_restoring = false
	dialogic.signal_event.emit("CheckAndActiveStairs")
	await _settle()
	room = current_scene
	_expect(room.name == "RovinRoom" and progress.cleanser_timeline_completed and room._hotspots.stairs.visible and not room._hotspots.stairs.disabled, "Only the configured timeline's authored ending returns home and opens stairs")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene is AlchemyUI and dialogic.current_timeline == null and completed.size() == 1, "A completed story does not replay on later visits")
	print("Quest room / craft / story integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

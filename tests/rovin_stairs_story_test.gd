extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 6:
		await process_frame

func _mouse_click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	var progress := root.get_node("GameProgress") as GameProgressState
	var dialogic = root.get_node("Dialogic")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var room: Control = current_scene
	_expect(not room._hotspots.stairs.visible and room._hotspots.stairs.disabled, "Stairs are unavailable before the cleanser story finishes")
	room._hotspots.stairs.pressed.emit()
	_expect(not progress.stairs_timeline_started and dialogic.current_timeline == null, "Forcing a locked stairs click cannot start dialogue")
	room._message.hide()
	inventory.add_item(&"clear_potion", 1)
	_expect(not room._hotspots.stairs.visible, "Owning cleanser alone does not unlock stairs")
	inventory.remove_item(&"clear_potion", 1)
	for id in ["recipe", "bedside", "shoe", "desk", "calculation"]:
		room._hotspots[id].pressed.emit()
		room._message.hide()
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	var ui: AlchemyUI = current_scene
	var story := ui.get_node("StoryTrigger") as AlchemyStoryTrigger
	_expect(not story.timeline_path.is_empty(), "User-configured cleanser timeline is preserved")
	var expected_story := load(story.timeline_path) as DialogicTimeline
	for index in ui._slots.size():
		ui._activate_slot(index)
		for cell in ui._picker._grid.get_children():
			if cell is Button and not cell.disabled:
				cell.pressed.emit()
				break
	ui._start.pressed.emit()
	ui._result.get_ok_button().pressed.emit()
	await _settle()
	_expect(dialogic.current_timeline == expected_story and progress.cleanser_timeline_started, "Craft confirmation plays the exact configured timeline, including UID references")
	_expect(not progress.cleanser_timeline_completed, "Starting the story does not yet unlock the stairs")
	await dialogic.end_timeline(true)
	await _settle()
	_expect(current_scene.name == "RovinRoom" and progress.cleanser_timeline_completed, "Completing the configured story returns to RovinRoom")
	room = current_scene
	_expect(room._hotspots.stairs.visible and not room._hotspots.stairs.disabled, "The stair hotspot is highlighted and interactive after returning")
	var before := inventory.get_items()
	var configured_stairs: String = room._stairs.timeline_path
	room._stairs.timeline_path = "res://.godot/missing_stairs_story.dtl"
	room._hotspots.stairs.pressed.emit()
	_expect(room.visible and not progress.stairs_timeline_started and room._message.visible, "Bad stair timeline configuration preserves the room and allows retry")
	room._message.hide()
	room._stairs.timeline_path = configured_stairs
	await _settle()
	await _mouse_click((room._hotspots.stairs as Button).get_global_rect().get_center())
	await _settle()
	_expect(dialogic.current_timeline != null and dialogic.current_timeline.resource_path == "res://dialogic/timeline/CP01_EP02_SI03.dtl", "Actual staircase mouse input opens CP01_EP02_SI03")
	_expect(progress.stairs_timeline_started and not room.visible, "Story playback is recorded and room input is hidden")
	var active_timeline: DialogicTimeline = dialogic.current_timeline
	room._hotspots.stairs.pressed.emit()
	room._hotspots.bedside.pressed.emit()
	_expect(dialogic.current_timeline == active_timeline and inventory.get_items() == before, "Repeated input cannot restart the story or collect during playback")
	await dialogic.end_timeline(true)
	await _settle()
	_expect(room.visible and not room._hotspots.stairs.visible, "The room is restored after the stairs story without replaying its hotspot")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	room = current_scene
	_expect(not room._hotspots.stairs.visible and progress.stairs_timeline_started, "Stairs story progress persists across room reloads")
	print("Cleanser story → room → stairs story: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

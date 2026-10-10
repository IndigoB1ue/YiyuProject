extends SceneTree

var _failures = 0

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
	var motion = InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	var inventory = root.get_node("PlayerInventory") as InventorySystem
	var progress = root.get_node("GameProgress")
	var dialogic = root.get_node("Dialogic")
	change_scene_to_file("res://scenes/AcademyMap.tscn")
	await _settle()
	var locked_map: Control = current_scene
	for viewport_size in [Vector2i(960, 540), Vector2i(1440, 900)]:
		root.size = viewport_size
		await _settle()
		var map_area: Control = locked_map.get_node("MapArea")
		var map_canvas: Control = map_area.get_node("MapCanvas")
		_expect(map_area.get_global_rect().grow(0.5).encloses(map_canvas.get_global_rect()), "Map canvas fits the viewport without cropped buildings")
		_expect(map_canvas.get_global_rect().encloses(locked_map.get_node("%RovinDorm").get_global_rect()), "Building hotspots stay inside the scaled map")
	_expect(locked_map.get_node("%Hall").disabled, "Hall is locked before cleanser story completes")
	locked_map.get_node("%Hall").pressed.emit()
	await _settle()
	_expect(dialogic.current_timeline == null and not progress.stairs_timeline_started, "Forced locked hall input cannot bypass the story")
	locked_map.get_node("%RovinDorm").pressed.emit()
	await _settle()
	_expect(current_scene.name == "RovinRoom", "Rovin dorm is always available from map")
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
	var ui: Control = current_scene
	var story = ui.get_node("StoryTrigger")
	_expect(not story.timeline_path.is_empty(), "User-configured cleanser timeline is preserved")
	var expected_story = load(story.timeline_path) as DialogicTimeline
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
	var before = inventory.get_items()
	await _mouse_click((room._hotspots.stairs as Button).get_global_rect().get_center())
	await _settle()
	_expect(current_scene.name == "AcademyMap" and dialogic.current_timeline == null, "Stairs open academy map without starting the hall story")
	_expect(not progress.stairs_timeline_started, "Leaving the room does not claim the hall story")
	var map: Control = current_scene
	_expect(map.get_node("%Teaching").disabled and map.get_node("%StudentDorm").disabled, "Unimplemented buildings stay locked")
	_expect(not map.get_node("%Hall").disabled, "Completing cleanser story unlocks the hall")
	map.get_node("%RovinDorm").pressed.emit()
	await _settle()
	room = current_scene
	_expect(room.name == "RovinRoom" and inventory.get_items() == before, "Map returns to the full room and preserves inventory")
	_expect(room._hotspots.recipe.disabled and room._hotspots.stairs.visible, "Room interaction progress and stairs survive returning")
	room._hotspots.stairs.pressed.emit()
	await _settle()
	map = current_scene
	var valid_path: String = map.hall_timeline_path
	map.hall_timeline_path = "res://.godot/missing_hall.dtl"
	map.get_node("%Hall").pressed.emit()
	_expect(map.visible and not progress.stairs_timeline_started, "Missing hall story allows retry without consuming progress")
	map.hall_timeline_path = valid_path
	await _mouse_click((map.get_node("%Hall") as Button).get_global_rect().get_center())
	await _settle()
	_expect(dialogic.current_timeline != null and dialogic.current_timeline.resource_path == "res://dialogic/timeline/CP01_EP02_SI03.dtl", "Actual hall click opens the requested timeline")
	_expect(progress.stairs_timeline_started and not map.visible, "Hall playback is recorded and map hidden")
	var active_timeline: DialogicTimeline = dialogic.current_timeline
	map.get_node("%Hall").pressed.emit()
	map.get_node("%RovinDorm").pressed.emit()
	_expect(dialogic.current_timeline == active_timeline and current_scene == map, "Repeated input cannot restart dialogue or leave during playback")
	await dialogic.end_timeline(true)
	await _settle()
	_expect(map.visible and map.get_node("%Hall").disabled, "Ended hall story restores map without allowing replay")
	map.get_node("%RovinDorm").pressed.emit()
	await _settle()
	room = current_scene
	_expect(room._hotspots.stairs.visible and progress.stairs_timeline_started, "Map remains accessible after story completion")
	print("Cleanser story -> stairs -> map -> hall: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

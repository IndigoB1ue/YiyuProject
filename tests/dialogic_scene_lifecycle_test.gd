extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 10:
		await process_frame


func _run() -> void:
	var dialogic: Node = root.get_node("Dialogic")
	var progress: Node = root.get_node("GameProgress")
	var save_system: Node = root.get_node("SaveSystem")
	progress.skip_rovin_tutorial()
	progress.unlock_recipe(&"ClearPotion")
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	var story: Node = current_scene.get_node("StoryTrigger")
	story._start_timeline()
	await dialogic.Text.text_started
	await _settle()
	dialogic.signal_event.emit("CheckAndActiveStairs")
	await _settle()
	_expect(current_scene.scene_file_path == "res://scenes/RovinRoom.tscn" and dialogic.current_timeline == null,
		"The authored return signal finishes the timeline before changing rooms")
	progress.cleanser_timeline_started = false
	progress.cleanser_timeline_completed = false
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	story = current_scene.get_node("StoryTrigger")
	story._start_timeline()
	await dialogic.Text.text_started
	await _settle()
	# A different scene switch can arrive while the authored signal awaits cleanup.
	dialogic.signal_event.emit("CheckAndActiveStairs")
	if story.is_inside_tree():
		change_scene_to_file("res://scenes/RovinRoom.tscn")
	_expect(not story.is_inside_tree(), "AlchemyRoom detaches immediately after the return signal")
	_expect(not dialogic.timeline_ended.is_connected(story._on_timeline_ended),
		"Detached alchemy controller stops receiving timeline-ended callbacks")
	_expect(not dialogic.signal_event.is_connected(story._on_dialogic_signal),
		"Detached alchemy controller stops receiving authored timeline signals")
	# An already queued callback must also be harmless before the object is freed.
	story._on_timeline_ended()
	await _settle()
	_expect(current_scene.scene_file_path == "res://scenes/RovinRoom.tscn" and progress.cleanser_timeline_completed,
		"Async timeline completion returns to the room and completes progress once")

	change_scene_to_file("res://scenes/AcademyMap.tscn")
	await _settle()
	var academy: Control = current_scene
	academy.hall_timeline_path = "res://tests/fixtures/CP03_save_test.dtl"
	academy._on_hall_pressed()
	await dialogic.Text.text_started
	await _settle()
	dialogic.paused = true
	# begin end_timeline without awaiting; its one-frame cleanup races scene change
	dialogic.end_timeline(true)
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	_expect(not dialogic.timeline_ended.is_connected(academy._on_timeline_ended),
		"Detached academy map stops receiving late timeline completion")
	academy._on_timeline_ended()
	await _settle()
	dialogic.paused = false
	_expect(current_scene.scene_file_path == "res://scenes/RovinRoom.tscn",
		"Late hall completion does not resurrect an old map or change the new scene")
	_expect(not save_system.is_restoring, "Normal scene exit does not alter the save restoration flag")
	print("Dialogic scene lifecycle: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

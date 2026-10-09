extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	var progress := root.get_node("GameProgress") as GameProgressState
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var room: Control = current_scene
	var view := room.get_node("TutorialUI") as RovinTutorialUI
	var before := inventory.get_items()
	var button := view.get_node("Overlay/Card/Margin/Content/Skip") as Button
	var center := button.get_global_rect().get_center()
	_expect(Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(center), "Skip button is inside the viewport")
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	_expect(progress.rovin_tutorial_skipped and not progress.rovin_tutorial_completed, "Actual mouse click records skipping")
	_expect(not view.visible and view._indicators.is_empty(), "Skipping removes the hint and all tutorial highlights")
	_expect(inventory.get_items() == before and not progress.is_recipe_unlocked(&"ClearPotion"), "Skipping does not grant inventory or recipes")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.visible, "Skipping does not bypass the entrance check")
	room._message.hide()
	for id in ["calculation", "shoe", "bedside", "desk", "recipe"]:
		room._hotspots[id].pressed.emit()
		room._message.hide()
		_expect(not view.visible, "Reward and recipe signals do not reopen skipped guidance")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene is AlchemyUI and progress.rovin_tutorial_skipped, "Normal exploration and alchemy still work after skipping")
	(current_scene as AlchemyUI)._on_back_pressed()
	await _settle()
	room = current_scene
	view = room.get_node("TutorialUI") as RovinTutorialUI
	_expect(not view.visible and view._indicators.is_empty(), "Skipped tutorial remains hidden after returning")
	print("Rovin tutorial skip: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

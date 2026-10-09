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

func _collect(room: Control, id: String) -> void:
	await _mouse_click((room._hotspots[id] as Button).get_global_rect().get_center())
	room._message.hide()
	await _settle()

func _run() -> void:
	var progress := root.get_node("GameProgress") as GameProgressState
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var room: Control = current_scene
	var view := room.get_node("TutorialUI") as RovinTutorialUI
	_expect(view.visible and room._tutorial.stage == RovinTutorialController.Stage.GET_RECIPE, "First room entry shows recipe guidance")
	_expect(view._indicators.size() == 1 and view._targets[0].control == room._hotspots.recipe, "Only the bookshelf is highlighted initially")
	_expect(view._indicators[0].get_global_rect().is_equal_approx((room._hotspots.recipe as Button).get_global_rect()), "Highlight aligns with the real target")
	# Free exploration is allowed even before following the suggested first step.
	await _collect(room, "shoe")
	_expect(inventory.get_amount(&"Water") == 1 and room._tutorial.stage == RovinTutorialController.Stage.GET_RECIPE, "Early material collection works without forcing the recipe step")
	await _collect(room, "recipe")
	_expect(inventory.get_amount(&"clear_potion_recipe") == 1, "Highlighted bookshelf remains clickable through the overlay")
	_expect(room._tutorial.stage == RovinTutorialController.Stage.COLLECT_MATERIALS and view._indicators.size() == 3, "Material stage excludes already collected locations")
	_expect(view._progress_text.text.contains("清水：1 / 3"), "Early progress is reflected in the card")
	var card := view.get_node("Overlay/Card") as Control
	for target in view._targets:
		_expect(not card.get_global_rect().intersects((target.control as Control).get_global_rect()), "Hint card does not obstruct active material targets")
	await _collect(room, "desk")
	_expect(inventory.get_amount(&"Water") == 2 and view._progress_text.text.contains("清水：2 / 3"), "Materials can be collected in any order with live progress")
	# Leaving before completion preserves progress and resumes the correct step.
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	(current_scene as AlchemyUI)._on_back_pressed()
	await _settle()
	room = current_scene
	view = room.get_node("TutorialUI") as RovinTutorialUI
	_expect(view.visible and view._indicators.size() == 2 and not progress.rovin_tutorial_completed, "Incomplete tutorial resumes when returning")
	await _collect(room, "bedside")
	await _collect(room, "calculation")
	_expect(room._tutorial.stage == RovinTutorialController.Stage.ENTER_ALCHEMY, "Complete ingredients advance to the alchemy step")
	_expect(view._indicators.size() == 1 and view._targets[0].control == room._hotspots.alchemy, "Only alchemy is highlighted when ready")
	inventory.remove_item(&"Water", 1)
	_expect(room._tutorial.stage == RovinTutorialController.Stage.COLLECT_MATERIALS and view._progress_text.text.contains("清水：2 / 3"), "External inventory consumption updates guidance")
	inventory.add_item(&"Water", 1)
	_expect(room._tutorial.stage == RovinTutorialController.Stage.ENTER_ALCHEMY, "Restoring stock restores the final step")
	var original_path: String = room.next_scene_path
	room.next_scene_path = ""
	room._hotspots.alchemy.pressed.emit()
	_expect(not progress.rovin_tutorial_completed, "A click without scene entry does not complete the tutorial")
	room.next_scene_path = original_path
	var target := (room._hotspots.alchemy as Button).get_global_rect().get_center()
	await _mouse_click(target)
	await _settle()
	_expect(current_scene is AlchemyUI and progress.rovin_tutorial_completed, "Successful entry completes the tutorial")
	_expect(not progress.rovin_tutorial_skipped, "Completion is distinct from skipping")
	(current_scene as AlchemyUI)._on_back_pressed()
	await _settle()
	room = current_scene
	view = room.get_node("TutorialUI") as RovinTutorialUI
	_expect(not view.visible and view._indicators.is_empty(), "Completed tutorial stays hidden on later room visits")
	print("Rovin tutorial progression: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

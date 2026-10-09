extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 3:
		await process_frame

func _click(position: Vector2) -> void:
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
	var scene: PackedScene = load("res://scenes/RovinRoom.tscn")
	var room = scene.instantiate()
	var canvas: Control = room.get_node("RoomCanvas")
	var hotspot_layer: Control = room.get_node("RoomCanvas/Hotspots")
	var recipe_button: Button = room.get_node("%RecipeHotspot")
	_expect(hotspot_layer.get_child_count() == 7, "All seven hotspots exist before room scripts run")
	_expect(room.get_node("%Status") is Label and room.get_node("%Message") is AcceptDialog, "Status and notice dialog are authored in the scene")
	_expect(room.theme == load("res://themes/rovin_room_theme.tres"), "Room uses the editable room Theme")
	# Designer changes must survive startup and resizing instead of being overwritten.
	recipe_button.position += Vector2(10, 6)
	var designed_position := recipe_button.position
	root.add_child(room)
	current_scene = room
	await _settle()
	_expect(hotspot_layer.get_child_count() == 7 and recipe_button == room._hotspots.recipe, "Startup reuses existing controls without creating duplicates")
	_expect(recipe_button.position.is_equal_approx(designed_position), "Runtime respects editor-authored button positions")
	var expected_scale := minf(room.size.x / 1070.0, room.size.y / 787.0)
	_expect(canvas.scale.is_equal_approx(Vector2.ONE * expected_scale), "Background and hotspots share uniform canvas scaling")
	_expect(room._status.get_theme_font_size("font_size") == 25 and room._status.get_theme_constant("shadow_offset_x") == 5, "Status Theme preserves the current font size and shadow")
	var normal := recipe_button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(normal != null and normal.border_width_left == 3 and is_equal_approx(normal.bg_color.a, 0.16), "Hotspot Theme preserves its highlight style")
	var view = room.get_node("TutorialUI")
	_expect(view._indicators[0].get_global_rect().is_equal_approx(recipe_button.get_global_rect()), "Tutorial tracks scene-authored hotspot geometry")
	root.size = Vector2i(1440, 900)
	await _settle()
	_expect(recipe_button.position.is_equal_approx(designed_position), "Resizing does not reset designer changes")
	_expect(view._indicators[0].get_global_rect().is_equal_approx(recipe_button.get_global_rect()), "Tutorial highlighting stays aligned after window resizing")
	await _click(recipe_button.get_global_rect().get_center())
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	_expect(inventory.get_amount(&"clear_potion_recipe") == 1 and room._message.visible, "Mouse input on the scene button grants the recipe and opens the scene dialog")
	room._message.hide()
	var skip: Button = view.get_node("Overlay/Card/Margin/Content/Skip")
	await _settle()
	await _click(skip.get_global_rect().get_center())
	_expect(not view.visible, "Skip guidance still works with the migrated room layout")
	room._hotspots.alchemy.pressed.emit()
	_expect(room._message.dialog_text.contains("素材不足"), "Alchemy entrance still validates inventory")
	room._message.hide()
	for id in ["bedside", "shoe", "desk", "calculation"]:
		room._hotspots[id].pressed.emit()
		room._message.hide()
		_expect(room._hotspots[id].disabled, "Scene-authored material hotspot is disabled after collection")
	_expect(inventory.get_amount(&"cleaning_powder") == 1 and inventory.get_amount(&"Water") == 3, "Scene signal bindings preserve all exploration rewards")
	var progress := root.get_node("GameProgress") as GameProgressState
	_expect(not room._hotspots.stairs.visible, "Stair hotspot remains hidden before the story condition")
	progress.complete_cleanser_timeline()
	_expect(room._hotspots.stairs.visible and not room._hotspots.stairs.disabled, "Stairs controller operates on the scene-authored button")
	room._stairs.timeline_path = ""
	room._hotspots.stairs.pressed.emit()
	_expect(room._message.visible, "Stair button is connected to its existing story handler")
	room._message.hide()
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene != room and current_scene.name == "AlchemyRoom", "Room still enters alchemy after collecting the requirements")
	current_scene._on_back_pressed()
	await _settle()
	room = current_scene
	_expect(room.name == "RovinRoom" and room.get_node("RoomCanvas/Hotspots").get_child_count() == 7, "Returning reloads the static room interface")
	_expect(room._hotspots.recipe.disabled and room._hotspots.bedside.disabled, "Returning preserves claimed exploration state")
	print("Rovin room scene UI tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

var _failures := 0
var _ui: Node
var _inventory: InventorySystem
var _dialogic: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()


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
	await _settle()


func _slot(id: StringName) -> InventorySlotUI:
	for child: InventorySlotUI in _ui._grid.get_children():
		if child.item_id == id:
			return child
	return null


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/inventory_preview")
	root.get_texture().get_image().save_png("res://.godot/inventory_preview/%s.png" % name)


func _run() -> void:
	_ui = root.get_node("InventoryUI")
	_inventory = root.get_node("PlayerInventory") as InventorySystem
	_dialogic = root.get_node("Dialogic")
	_expect(not _ui.is_open() and not _ui._open_button.visible, "Backpack is hidden outside gameplay")
	_ui.open_inventory()
	_expect(not _ui.is_open(), "Main menu cannot open the gameplay backpack")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	for id in _inventory.get_items():
		_inventory.remove_item(id, _inventory.get_amount(id))
	_inventory.add_item(&"Water", 3)
	_inventory.add_item(&"cleaning_powder", 1)
	_inventory.add_item(&"clear_potion_recipe", 1)
	var before := _inventory.get_items()
	_expect(_ui._open_button.visible, "Room has a backpack entry button")
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(_ui.is_open() and paused and not _ui._details.visible, "Button opens the left panel only and pauses the room")
	_expect(_ui._grid.get_child_count() == 200 and _ui._grid.columns == 5, "Materials and recipes share 200 slots in five columns")
	_expect(_ui._grid.get_child(0).item_id == &"clear_potion_recipe", "Recipe items sort before materials")
	_expect(_slot(&"clear_potion_recipe").theme_type_variation == &"InventoryRecipeCell" and _slot(&"Water").theme_type_variation == &"InventoryMaterialCell",
		"Recipes and materials use separate grey and blue theme variations")
	_expect(_slot(&"Water").get_node("Quantity").text == "×3", "Materials stack with their real inventory count")
	await _capture("bag")
	await _click(_slot(&"clear_potion_recipe").get_global_rect().get_center())
	_expect(_ui._details.visible and _ui._detail_icon.texture != null and _ui._detail_description.text.contains("配方"), "Selecting a recipe shows its icon and introduction")
	_expect(_ui._ingredients.get_child_count() == 2, "Repeated recipe slots aggregate into two material types")
	var requirement_labels: Array[String] = []
	for badge in _ui._ingredients.get_children():
		requirement_labels.append(badge.get_node("Label").text)
	_expect(requirement_labels.has("清水 ×3") and requirement_labels.has("清洗剂粉末 ×1"), "Recipe details show actual icons and combined required amounts")
	await _capture("recipe")
	await _click(_slot(&"Water").get_global_rect().get_center())
	_expect(_ui._detail_description.text == _inventory.get_item(&"Water").description and not _ui._ingredients.visible,
		"Selecting a material shows only its own description")
	await _capture("material")
	_inventory.add_item(&"Water", 1)
	_expect(_slot(&"Water").get_node("Quantity").text == "×4" and _ui._detail_name.text.contains("×4"), "Open view updates on inventory changes")
	_inventory.remove_item(&"Water", 4)
	_expect(not _ui._details.visible and _slot(&"Water") == null, "Removing the selected stack clears its details and slot")
	var room: Control = current_scene
	var powder_before := _inventory.get_amount(&"cleaning_powder")
	await _click(room._hotspots.bedside.get_global_rect().get_center())
	_expect(_inventory.get_amount(&"cleaning_powder") == powder_before, "Backpack clicks cannot collect from the room behind it")
	_ui._scroll.scroll_vertical = 1800
	await _settle()
	_expect(_ui._scroll.scroll_vertical > 0, "All 200 slots are reachable with the vertical scrollbar")
	await _key(KEY_ESCAPE)
	_expect(not _ui.is_open() and not paused, "Escape closes the backpack and resumes the room")
	await _key(KEY_I)
	_expect(_ui.is_open() and not _ui._details.visible and _ui._scroll.scroll_vertical == 0, "I reopens a fresh left-only view")
	await _key(KEY_I)
	_expect(not _ui.is_open() and not paused, "I also closes the backpack")
	paused = true
	_ui.open_inventory()
	_ui.close_inventory()
	_expect(paused, "Closing preserves a pre-existing game pause")
	paused = false
	_ui.open_inventory()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _settle()
	_expect(not _ui._open_button.visible and not _ui.is_open() and not paused,
		"Scene changes close the backpack, release its pause and hide its entry in the menu")
	var timeline := DialogicTimeline.new()
	timeline.from_text("背包暂停测试。\n第二句。\n第三句。")
	_dialogic.start(timeline)
	await create_timer(0.6).timeout
	await _settle()
	_expect(_ui._open_button.visible, "Timelines expose the same backpack button")
	var event_before: int = _dialogic.current_event_idx
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(_ui.is_open() and _dialogic.paused and _dialogic.current_event_idx == event_before, "Opening with the button pauses dialogue without advancing it")
	await _click(Vector2(8, 8))
	await create_timer(0.3).timeout
	_expect(_dialogic.current_event_idx == event_before, "Backdrop clicks do not advance the paused timeline")
	_ui.close_inventory()
	_expect(not _dialogic.paused and not paused, "Closing resumes dialogue and game processing")
	_dialogic.paused = true
	_ui.open_inventory()
	_ui.close_inventory()
	_expect(_dialogic.paused, "Closing preserves a dialogue pause owned by another system")
	_dialogic.paused = false
	_dialogic.Inputs.auto_skip.time_per_event = 0.8
	_dialogic.Inputs.auto_skip.disable_on_user_input = false
	_dialogic.Inputs.auto_skip.enabled = true
	await create_timer(0.05).timeout
	event_before = _dialogic.current_event_idx
	_ui.open_inventory()
	await create_timer(1.0).timeout
	_expect(_dialogic.current_event_idx == event_before, "Fast-forward stops while the backpack is open")
	_ui.close_inventory()
	await create_timer(0.85).timeout
	_expect(_dialogic.current_event_idx > event_before or _dialogic.current_timeline == null, "Fast-forward resumes after closing")
	_dialogic.Inputs.auto_skip.enabled = false
	if _dialogic.current_timeline != null:
		await _dialogic.end_timeline(true)
	await _settle()
	var call_timeline := DialogicTimeline.new()
	call_timeline.from_text("do InventoryUI.open_inventory()\n从背包返回对话。")
	_dialogic.start(call_timeline)
	await _settle()
	_expect(_ui.is_open() and _dialogic.paused, "Dialogic Call event opens the same backpack with no arguments")
	_ui.close_inventory()
	await create_timer(0.6).timeout
	_expect(_dialogic.current_timeline == call_timeline and _dialogic.current_event_idx == 1,
		"Closing a Call-opened backpack resumes at the next timeline event")
	await _dialogic.end_timeline(true)
	await _settle()
	_expect(not _ui.is_open() and not paused, "Dialogue cleanup cannot leave a modal backpack or stuck pause")
	_expect(_inventory.get_amount(&"clear_potion_recipe") == before[&"clear_potion_recipe"], "Browsing never consumes recipes")
	print("Inventory UI integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

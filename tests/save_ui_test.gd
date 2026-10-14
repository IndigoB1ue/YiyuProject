extends SceneTree

var _failures := 0
var _ui: Node
var _system: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 8:
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
	await _settle()


func _key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/save_preview")
	root.get_texture().get_image().save_png("res://.godot/save_preview/%s.png" % name)


func _run() -> void:
	_ui = root.get_node("SaveUI")
	_system = root.get_node("SaveSystem")
	_system.storage_directory = "user://save_ui_test"
	for index in range(1, 121):
		for suffix in ["", ".backup.res", ".pending.res"]:
			var path: String = _system._slot_path(index) + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(1.0).timeout
	await _settle()
	var menu: Control = current_scene
	await _click(menu.menu_buttons[0].get_global_rect().get_center())
	_expect(_ui.is_open() and _ui._mode == _ui.Mode.LOAD and menu.menu_buttons[1].disabled,
		"LoadGame opens the actual read-mode window and blocks the menu")
	_expect(_ui._grid.columns == 4 and _ui._grid.get_child_count() == 12 and _ui._pages.get_child_count() == 10,
		"The window displays three rows of four slots and ten pages")
	_expect(_ui._save_mode.disabled, "Main menu cannot save an inactive game")
	await _capture("empty")
	await _click(_ui._grid.get_child(0).get_global_rect().get_center())
	_expect(_ui._status.text.contains("为空") and not _ui._confirm.visible, "Clicking an empty record shows a clear message")
	await _click(_ui._pages.get_child(9).get_global_rect().get_center())
	_expect(_ui._grid.get_child(0).slot_index == 109 and _ui._grid.get_child(11).slot_index == 120,
		"The tenth page maps to slots 109 through 120")
	await _key(KEY_ESCAPE)
	_expect(not _ui.is_open() and not paused and menu.menu_buttons[0].has_focus() and not root.get_node("SettingsUI").is_open(),
		"Escape closes load UI and restores menu focus without opening settings")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var progress: Node = root.get_node("GameProgress")
	progress.skip_rovin_tutorial()
	var inventory: InventorySystem = root.get_node("PlayerInventory")
	for id in inventory.get_items():
		inventory.remove_item(id, inventory.get_amount(id))
	inventory.add_item(&"Water", 5)
	_system.set_chapter(1)
	_system.play_seconds = 12345.0
	await _settle()
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(_ui.is_open() and _ui._mode == _ui.Mode.SAVE and paused and not _ui._save_mode.disabled,
		"Game entry opens save mode and pauses the room")
	await _key(KEY_I)
	root.get_node("SettingsUI").open_settings()
	_expect(not root.get_node("InventoryUI").is_open() and not root.get_node("SettingsUI").is_open(), "Other global windows cannot open through the save modal")
	await _click(_ui._grid.get_child(0).get_global_rect().get_center())
	_expect(not _ui._confirm.visible and _system.get_slot_record(1).state == "saved", "An empty slot saves immediately")
	var slot: Button = _ui._grid.get_child(0)
	_expect(slot._chapter.visible and slot._chapter_label.text == "第1章" and slot._caption.text.contains("游玩时长 03:25:"),
		"Record places the chapter over the image and the date/play time below it")
	if DisplayServer.get_name() != "headless":
		var stored: Dictionary = _system.get_slot_record(1)
		_expect(stored.texture != null and stored.texture.get_image().get_pixel(240, 135).is_equal_approx(_ui._thumbnail.get_pixel(240, 135)),
			"Stored thumbnail comes from the pre-modal gameplay framebuffer")
	await _capture("saved")
	inventory.add_item(&"Water", 1)
	await _click(slot.get_global_rect().get_center())
	_expect(_ui._confirm.visible and _ui._confirm.title == "确认覆盖", "Existing save requires overwrite confirmation")
	await _key(KEY_ESCAPE)
	_expect(not _ui._confirm.visible and _ui.is_open(), "Escape dismisses confirmation and keeps the save window open")
	await _click(slot.get_global_rect().get_center())
	_ui._confirm.get_cancel_button().pressed.emit()
	await _settle()
	_expect(not _ui._confirm.visible and _ui._pending_slot == -1, "Cancel dismisses overwrite without changing the record")
	var data: GameSaveData = ResourceLoader.load(_system._slot_path(1), "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(data.inventory.items[&"Water"] == 5, "Cancelled overwrite retains the old inventory snapshot")
	await _click(slot.get_global_rect().get_center())
	_ui._confirm.get_ok_button().pressed.emit()
	await _settle()
	data = ResourceLoader.load(_system._slot_path(1), "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(not _ui._confirm.visible and data.inventory.items[&"Water"] == 6, "Confirmed overwrite replaces the record")
	await _click(_ui._pages.get_child(9).get_global_rect().get_center())
	await _click(_ui._grid.get_child(11).get_global_rect().get_center())
	_expect(_system.get_slot_record(120).state == "saved", "Saving on the final page uses slot 120")
	await _capture("page10")
	await _click(_ui._load_mode.get_global_rect().get_center())
	await _click(_ui._pages.get_child(0).get_global_rect().get_center())
	inventory.remove_item(&"Water", 6)
	await _click(_ui._grid.get_child(0).get_global_rect().get_center())
	_expect(_ui._confirm.visible and _ui._confirm.title == "确认读取" and inventory.get_amount(&"Water") == 0,
		"Clicking a nonempty read-mode slot asks before restoring")
	await _capture("confirm")
	_ui._confirm.get_ok_button().pressed.emit()
	await _system.restore_finished
	await _settle()
	_expect(not _ui.is_open() and not paused and inventory.get_amount(&"Water") == 6,
		"Confirmation restores the selected game and closes the modal")
	await _key(KEY_F9)
	_expect(_ui.is_open() and _ui._mode == _ui.Mode.LOAD, "F9 opens read mode during gameplay")
	await _key(KEY_ESCAPE)
	await _key(KEY_F5)
	_expect(_ui.is_open() and _ui._mode == _ui.Mode.SAVE, "F5 opens save mode during gameplay")
	_expect(root.get_visible_rect().grow(1).encloses(_ui._overlay.get_node("Canvas").get_global_rect()),
		"The complete save canvas fits the game viewport")
	_ui.close_window()
	var dialogic: Node = root.get_node("Dialogic")
	dialogic.start("res://tests/fixtures/CP03_save_test.dtl")
	await dialogic.Text.text_started
	await _settle()
	var event_index: int = dialogic.current_event_idx
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(dialogic.paused and dialogic.current_event_idx == event_index, "Save entry does not advance the timeline")
	await _click(_ui._grid.get_child(1).get_global_rect().get_center())
	_expect(_system.get_slot_record(2).state == "saved" and _system.get_slot_record(2).chapter == "第3章", "Timeline save contains its chapter and current frame")
	await _capture("timeline")
	_ui.close_window()
	dialogic.paused = true
	await dialogic.end_timeline(true)
	dialogic.paused = false
	print("Save-window integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

var _failures := 0


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


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/settings_preview")
	root.get_texture().get_image().save_png("res://.godot/settings_preview/%s.png" % name)


func _run() -> void:
	var settings: Node = root.get_node("GameSettings")
	for section: String in settings.DEFAULTS:
		settings.reset_section(section)
	change_scene_to_file("res://scenes/main_menu.tscn")
	await create_timer(1.0).timeout
	await _settle()
	var menu: Control = current_scene
	var panel: Control = root.get_node("SettingsUI/Panel")
	_expect(not panel.visible, "Options page starts hidden")
	await _click(menu.menu_buttons[3].get_global_rect().get_center())
	_expect(panel.visible and panel._pages[0].visible, "Actual menu click opens the text settings page")
	_expect(menu.menu_buttons[1].disabled and not menu.notice_layer.visible, "Settings replaces the placeholder and blocks menu actions")
	await create_timer(0.4).timeout
	await _capture("text")
	var slider: HSlider = panel.get_node("%TextSpeed/Slider")
	var slider_position := slider.get_global_rect().position + Vector2(slider.size.x * 0.3, slider.size.y * 0.5)
	await _click(slider_position)
	_expect(settings.get_value("text", "speed") < 10 and panel.get_node("%TextSpeed/Value").text != "10", "Mouse slider changes real reading speed and its number")
	var chosen_speed: int = settings.get_value("text", "speed")
	await _click(panel.get_node("%AudioTab").get_global_rect().get_center())
	_expect(panel._pages[2].visible and not panel._pages[0].visible, "Right-side tabs switch pages")
	await _capture("audio")
	panel.get_node("%MusicVolume/Slider").value = 1
	panel.get_node("Canvas/Frame/Content/Footer/Restore").pressed.emit()
	_expect(settings.get_value("audio", "music") == 3 and settings.get_value("text", "speed") == chosen_speed,
		"Restoring defaults affects only the selected category")
	await _click(panel.get_node("%GraphicsTab").get_global_rect().get_center())
	_expect(panel._pages[1].visible, "Graphics tab is available")
	await _capture("graphics")
	if DisplayServer.get_name() == "headless":
		panel.get_node("%Fullscreen").pressed.emit()
		_expect(settings.get_value("graphics", "fullscreen") and panel._resolution.disabled, "Fullscreen selects its policy and shows desktop resolution")
		panel.get_node("%Windowed").pressed.emit()
		_expect(not panel._resolution.disabled, "Windowed mode allows resolution selection")
		root.size = Vector2i(960, 540)
		await _settle()
		_expect(root.get_visible_rect().grow(1).encloses(panel.get_node("Canvas").get_global_rect()), "Settings canvas fits a smaller viewport")
	var resolution_index: int = panel._resolutions.find(Vector2i(960, 540))
	panel._resolution.item_selected.emit(resolution_index)
	await _settle()
	_expect(settings.get_value("graphics", "resolution") == Vector2i(960, 540), "Resolution selection is saved")
	if DisplayServer.get_name() != "headless":
		_expect(root.size == Vector2i(960, 540), "Windowed resolution changes the actual OS window")
	panel._fps.item_selected.emit(panel._fps.get_item_index(120))
	_expect(Engine.max_fps == 120, "Frame limit menu controls actual engine limit")
	var dropdown: PopupMenu = panel._fps.get_popup()
	dropdown.popup()
	await _settle()
	var popup_escape := InputEventKey.new()
	popup_escape.keycode = KEY_ESCAPE
	popup_escape.physical_keycode = KEY_ESCAPE
	popup_escape.pressed = true
	root.push_input(popup_escape, true)
	await _settle()
	_expect(panel.visible, "Escape on an open dropdown does not close the entire settings panel")
	dropdown.hide()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await _settle()
	_expect(not panel.visible and not menu.menu_buttons[3].disabled, "Escape closes settings and restores menu input")
	menu.menu_buttons[3].pressed.emit()
	await _settle()
	_expect(panel.visible and panel._pages[0].visible and settings.get_value("text", "speed") == chosen_speed, "Reopening retains saved values and defaults to the text page")
	panel.get_node("Canvas/Frame/Content/Header/Close").pressed.emit()
	_expect(not panel.visible and menu.menu_buttons[3].has_focus(), "Close button returns keyboard focus to Options")
	for section: String in settings.DEFAULTS:
		settings.reset_section(section)
	if DisplayServer.get_name() != "headless":
		# Restore windowed mode in the same frame, before drawing a fullscreen test frame.
		settings.set_value("graphics", "fullscreen", true)
		_expect(root.mode == Window.MODE_FULLSCREEN and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
			"Fullscreen setting reaches the native window")
		settings.set_value("graphics", "fullscreen", false)
		await _settle()
		_expect(root.mode == Window.MODE_WINDOWED, "Windowed mode restores the native window")
	print("Main-menu settings UI: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

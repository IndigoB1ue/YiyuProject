extends SceneTree

const Fixture = preload("res://tests/alchemy_test_fixture.gd")

var _failures := 0
var _ui: Node
var _settings: Node
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
	DirAccess.make_dir_recursive_absolute("res://.godot/settings_context_preview")
	root.get_texture().get_image().save_png("res://.godot/settings_context_preview/%s.png" % name)


func _start(timeline: DialogicTimeline) -> void:
	_dialogic.start(timeline)
	await _dialogic.Text.text_started
	await _settle()


func _run() -> void:
	_ui = root.get_node("SettingsUI")
	_settings = root.get_node("GameSettings")
	_dialogic = root.get_node("Dialogic")
	var inventory: InventorySystem = root.get_node("PlayerInventory")
	var bag: Node = root.get_node("InventoryUI")
	var progress: Node = root.get_node("GameProgress")
	_dialogic.History.reset_visited_history()
	for section: String in _settings.DEFAULTS:
		_settings.reset_section(section)
	_expect(not _ui.is_open() and not _ui._open_button.visible, "Global settings starts hidden without a context")
	change_scene_to_file("res://scenes/AcademyMap.tscn")
	await _settle()
	_expect(_ui._open_button.visible, "First-level academy map has a settings entry")
	await _capture("academy_map")
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(_ui.is_open() and paused, "Mouse opens the shared settings panel and pauses the map")
	await _click(_ui._panel.get_node("%AudioTab").get_global_rect().get_center())
	_ui._panel.get_node("%MusicVolume/Slider").value = 5
	_expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.5),
		"Audio volume changes immediately while the map is paused")
	await _click(current_scene.get_node("%RovinDorm").get_global_rect().get_center())
	_expect(current_scene.scene_file_path == "res://scenes/AcademyMap.tscn", "Settings clicks cannot enter the map behind it")
	await _key(KEY_ESCAPE)
	_expect(not _ui.is_open() and not paused, "Escape closes settings and resumes the first-level map")
	await _key(KEY_ESCAPE)
	_expect(_ui.is_open(), "Escape opens settings from a gameplay map")
	_ui.close_settings()
	progress.skip_rovin_tutorial()
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_expect(_ui._open_button.visible, "Second-level room map has the same entry")
	await _capture("room")
	var room: Control = current_scene
	var items_before := inventory.get_items()
	await _click(_ui._open_button.get_global_rect().get_center())
	await _key(KEY_I)
	bag.open_inventory()
	_expect(not bag.is_open(), "Settings blocks both keyboard and scripted backpack opening")
	await _click(room._hotspots.bedside.get_global_rect().get_center())
	_expect(inventory.get_items() == items_before, "Settings prevents collecting room materials behind it")
	_ui.close_settings()
	await _key(KEY_I)
	_expect(bag.is_open(), "Backpack remains usable after closing settings")
	await _key(KEY_ESCAPE)
	_expect(not bag.is_open() and not _ui.is_open() and not paused, "Escape closes the backpack without opening settings")
	room._message.popup_centered()
	_ui.open_settings()
	_expect(not _ui.is_open(), "Confirmation windows retain priority over global settings")
	room._message.hide()
	paused = true
	_ui.open_settings()
	_ui.close_settings()
	_expect(paused, "Closing settings preserves a pre-existing scene pause")
	paused = false

	Fixture.prepare_inventory(inventory)
	var recipe := Fixture.potion_recipe()
	progress.unlock_recipe(recipe.recipe_id)
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	var alchemy: Control = current_scene
	var alchemy_recipes: Array[AlchemyRecipe] = [recipe]
	alchemy.recipes = alchemy_recipes
	alchemy._rebuild_recipe_list()
	await _settle()
	for index in [0, 0, 1]:
		alchemy._activate_slot(index)
		await _settle()
		var cell := alchemy._picker._grid.get_child(0) as Button
		await _click(cell.get_global_rect().get_center())
	_expect(not alchemy._start.disabled, "Alchemy has a complete selection before opening settings")
	var selection_before: Array = alchemy._selection.duplicate(true)
	await _capture("alchemy")
	await _key(KEY_ESCAPE)
	_expect(_ui.is_open() and paused, "Alchemy opens the shared settings with Escape")
	await _key(KEY_BACKSPACE)
	await _key(KEY_Q)
	await _key(KEY_E)
	_expect(alchemy._selection == selection_before, "Alchemy shortcuts cannot alter selected materials through settings")
	_ui._panel.get_node("%TextSpeed/Slider").value = 3
	await _key(KEY_ESCAPE)
	_expect(alchemy._selection == selection_before and not alchemy._start.disabled, "Closing preserves all selected materials and craft availability")
	alchemy._start.pressed.emit()
	_expect(inventory.get_amount(&"Potion") == 1 and inventory.get_amount(&"Herb") == 3,
		"Craft still completes correctly after changing settings")
	_ui.open_settings()
	_expect(not _ui.is_open(), "Alchemy result confirmation is not covered by settings")
	alchemy._result.hide()

	var timeline := DialogicTimeline.new()
	timeline.from_text("剧情中调整文字速度。".repeat(30) + "\n第二句。\n第三句。")
	timeline.take_over_path("res://.godot/settings_active_timeline_test.dtl")
	await _start(timeline)
	var text_node: Control = get_nodes_in_group("dialogic_dialog_text")[0]
	var event_before: int = _dialogic.current_event_idx
	await _click(_ui._open_button.get_global_rect().get_center())
	_expect(_ui.is_open() and _dialogic.paused and _dialogic.current_event_idx == event_before,
		"Timeline entry click pauses dialogue without advancing it")
	var characters_before: int = text_node.visible_characters
	await create_timer(0.3).timeout
	_expect(text_node.visible_characters == characters_before, "Text reveal pauses while settings are open")
	_ui._panel.get_node("%TextSpeed/Slider").value = 2
	_expect(is_equal_approx(text_node.active_speed, 0.05), "Setting applies directly to the active dialogue text")
	await _capture("timeline_settings")
	_ui.close_settings()
	await create_timer(0.2).timeout
	_expect(not paused and not _dialogic.paused and text_node.visible_characters > characters_before,
		"Closing resumes the same text with the new speed")
	_dialogic.paused = true
	_ui.open_settings()
	_ui.close_settings()
	_expect(_dialogic.paused, "Closing preserves a dialogue pause owned by another system")
	_dialogic.paused = false
	_dialogic.Text.skip_text_reveal()
	await _settle()
	_settings.set_value("text", "auto_delay", 7)
	_settings.toggle_auto_advance()
	await _settle()
	event_before = _dialogic.current_event_idx
	_ui.open_settings()
	_ui._panel.get_node("%AutoDelay/Slider").value = 1
	await _settle()
	_expect(is_equal_approx(_dialogic.Inputs.auto_advance.get_time(), 1.0),
		"Changing the auto interval replaces the current pending timer immediately")
	await create_timer(1.2).timeout
	_expect(_dialogic.current_event_idx == event_before, "Automatic playback waits while settings are open")
	_ui.close_settings()
	await create_timer(1.2).timeout
	_expect(_dialogic.current_event_idx > event_before, "Automatic playback resumes using the new interval")
	_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	await _dialogic.end_timeline(true)
	await _settle()

	var policy_timeline := DialogicTimeline.new()
	policy_timeline.from_text("切换为仅已读时保护当前未读行。\n第二句。")
	policy_timeline.take_over_path("res://.godot/settings_policy_timeline_test.dtl")
	await _start(policy_timeline)
	_settings.set_value("text", "skip_unread", true)
	_settings.toggle_fast_forward()
	_ui.open_settings()
	event_before = _dialogic.current_event_idx
	_ui._panel.get_node("%SkipRead").pressed.emit()
	_ui.close_settings()
	await create_timer(0.3).timeout
	_expect(not _dialogic.Inputs.auto_skip.enabled and _dialogic.current_event_idx == event_before,
		"Changing to read-only while paused stops active fast-forward on the current unread line")
	await _dialogic.end_timeline(true)
	await _settle()

	var skip_timeline := DialogicTimeline.new()
	skip_timeline.from_text("快进暂停测试。\n第二句。\n第三句。\n第四句。")
	skip_timeline.take_over_path("res://.godot/settings_skip_timeline_test.dtl")
	await _start(skip_timeline)
	_settings.set_value("text", "skip_unread", true)
	_settings.toggle_fast_forward()
	_ui.open_settings()
	event_before = _dialogic.current_event_idx
	await create_timer(0.3).timeout
	_expect(_dialogic.current_event_idx == event_before, "Fast-forward pauses during settings")
	_ui.close_settings()
	await create_timer(0.25).timeout
	_expect(_dialogic.current_event_idx > event_before or _dialogic.current_timeline == null,
		"Fast-forward continues after settings closes")
	_dialogic.Inputs.auto_skip.enabled = false
	if _dialogic.current_timeline != null:
		await _dialogic.end_timeline(true)
	await _settle()

	var call_timeline := DialogicTimeline.new()
	call_timeline.from_text("do SettingsUI.open_settings()\n从设置继续剧情。")
	call_timeline.take_over_path("res://.godot/settings_call_timeline_test.dtl")
	_dialogic.start(call_timeline)
	await _settle()
	_expect(_ui.is_open() and _dialogic.paused, "Dialogic Call event can open settings without arguments")
	_ui.close_settings()
	await create_timer(0.7).timeout
	_expect(_dialogic.current_timeline == call_timeline and _dialogic.current_event_idx == 1,
		"Closing Call-opened settings continues at the next timeline event")
	_ui.open_settings()
	await _dialogic.end_timeline(true)
	await _settle()
	_expect(not _ui.is_open() and not paused and not _dialogic.paused,
		"Ending a timeline externally cleans up the settings modal and its pause")

	_ui.open_settings()
	change_scene_to_file("res://scenes/main_menu.tscn")
	await _settle()
	_expect(not _ui.is_open() and not paused and not _ui._open_button.visible,
		"Scene changes close settings, release its pause and hide the gameplay entry in the menu")
	var future_map := PackedScene.new()
	var map_root := Control.new()
	map_root.add_to_group("settings_context", true)
	future_map.pack(map_root)
	map_root.free()
	change_scene_to_packed(future_map)
	await _settle()
	_expect(_ui._open_button.visible, "Additional map scenes opt in through the settings_context group")
	for section: String in _settings.DEFAULTS:
		_settings.reset_section(section)
	print("Global settings integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

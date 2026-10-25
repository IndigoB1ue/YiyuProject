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
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await _settle()

func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/quest_preview")
	root.get_texture().get_image().save_png("res://.godot/quest_preview/%s.png" % name)

func _check_tracker_layout(ui: Node, quests: Node) -> void:
	var original: Dictionary = quests.get_save_state()
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		var stages: Array = quests.get_quest(&"make_cleanser").stage_ids
		for phase in stages.size():
			var state: Dictionary = original.duplicate(true)
			state.accepted[&"make_cleanser"].stage_id = stages[phase]
			state.accepted[&"make_cleanser"].completed_stages = stages.slice(0, phase)
			quests.restore_save_state(state)
			await _settle()
			var tracker_rect: Rect2 = ui._tracker.get_global_rect()
			_expect(tracker_rect.position.x < viewport_size.x * 0.1 and tracker_rect.position.y < viewport_size.y * 0.2, "The room keeps the tracker at the upper left")
			print("Tracker layout: room ", root.get_visible_rect().size, " / ", stages[phase], " ", tracker_rect)
			# The tracker floats over the scene; it does not reserve layout space.
			_expect(root.get_visible_rect().encloses(tracker_rect), "Tracker stays within %s / %s" % [viewport_size, stages[phase]])
	quests.restore_save_state(original)
	await _settle()

func _run() -> void:
	var ui: Node = root.get_node("QuestUI")
	var quests: Node = root.get_node("QuestSystem")
	var progress: Node = root.get_node("GameProgress")
	var dialogic: Node = root.get_node("Dialogic")
	var pause_manager: Node = root.get_node("OverlayPauseManager")
	_expect(ui._objective_text({"text": "与角色交谈", "completed": false, "has_count": false}) == "○ 与角色交谈", "Event objectives do not require an artificial counter")
	_expect(ui._objective_text({"text": "收集素材", "completed": false, "has_count": true, "current": 1, "required": 3}).contains("1 / 3"), "Counted objectives display the shared view's quantities")
	quests.reset_for_new_game()
	progress.reset_for_new_game()
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	_expect(ui._open_button.visible and ui._tracker.visible, "Accepted task provides list entry and tracker")
	_expect(quests.is_tracker_collapsed() and not ui._tracker_body.visible, "The floating tracker starts collapsed")
	await _check_tracker_layout(ui, quests)
	await _capture("tracker")
	await _click(ui._collapse.get_global_rect().get_center())
	await _capture("tracker_expanded")
	await _key(KEY_J)
	_expect(ui.is_open() and paused, "J opens task list and pauses gameplay")
	_expect(ui._quest_list.get_child_count() == 1 and ui._detail_title.text.contains("制作清洗剂"), "List and details display the accepted task")
	await _capture("list")
	ui._on_track_pressed()
	_expect(quests.get_tracked_quest_id() == &"" and quests.get_accepted_quests().size() == 1, "Cancel tracking preserves task")
	ui._on_track_pressed()
	var active_state: Dictionary = quests.get_save_state()
	var active_progress: Dictionary = progress.get_save_state()
	var completed_state: Dictionary = active_state.duplicate(true)
	completed_state.accepted[&"make_cleanser"].status = "completed"
	completed_state.accepted[&"make_cleanser"].stage_id = &"craft"
	completed_state.accepted[&"make_cleanser"].completed_stages = quests.get_quest(&"make_cleanser").stage_ids.duplicate()
	quests.restore_save_state(completed_state)
	ui._set_filter(true)
	_expect(ui._quest_list.get_child_count() == 1 and ui._detail_title.text.contains("已完成"), "Completed tab retains task description and completed objectives")
	quests.restore_save_state(active_state)
	progress.restore_save_state(active_progress)
	ui._set_filter(false)
	await _key(KEY_ESCAPE)
	_expect(not ui.is_open() and not paused, "Escape closes task list and restores gameplay")
	quests.set_tracker_collapsed(false)
	ui._on_collapse_pressed()
	await _settle()
	_expect(quests.is_tracker_collapsed() and not ui._tracker_body.visible, "Tracker collapses independently of task")
	ui._on_skip_pressed()
	_expect(progress.rovin_tutorial_skipped and not quests.is_completed(&"make_cleanser"), "Skipping tutorial leaves task active")
	ui._on_collapse_pressed()
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	_expect(not ui._tracker.visible and ui._open_button.visible, "Alchemy hides the tracker while retaining the task entry")
	progress.unlock_recipe(&"ClearPotion")
	await _settle()
	var margin: Control = current_scene.get_node("Margin")
	_expect(is_zero_approx(margin.anchor_left) and is_zero_approx(margin.offset_top) and is_equal_approx(margin.offset_right, -462.0), "Alchemy retains its original layout beneath the floating tracker")
	for collapsed in [true, false]:
		quests.set_tracker_collapsed(collapsed)
		await _settle()
		_expect(not ui._tracker.visible and ui._open_button.visible, "Changing the collapsed setting never shows the alchemy tracker")
		await _click(ui._open_button.get_global_rect().get_center())
		_expect(ui.is_open() and not ui._tracker.visible, "Alchemy task button opens the complete log")
		await _key(KEY_J)
		_expect(not ui.is_open() and ui._open_button.visible and not ui._tracker.visible, "J closes the alchemy task log")
		await _key(KEY_J)
		_expect(ui.is_open() and not ui._tracker.visible, "J opens the alchemy task log")
		await _key(KEY_J)
		_expect(not ui.is_open() and not ui._tracker.visible, "Closing the alchemy log keeps the tracker hidden")
		_expect(quests.is_tracker_collapsed() == collapsed, "Alchemy task log preserves the collapsed setting")
		change_scene_to_file("res://scenes/RovinRoom.tscn")
		await _settle()
		_expect(ui._tracker.visible and ui._tracker_body.visible == not collapsed and quests.is_tracker_collapsed() == collapsed, "Returning to the room restores the tracker with its saved collapsed setting")
		change_scene_to_file("res://scenes/AlchemyRoom.tscn")
		await _settle()
		_expect(not ui._tracker.visible and ui._open_button.visible, "Returning to alchemy hides only the tracker")
	await _capture("alchemy")
	var timeline := DialogicTimeline.new()
	timeline.from_text("任务暂停测试。\n第二句。\n第三句。")
	dialogic.start(timeline)
	await _settle()
	var index: int = dialogic.current_event_idx
	await _click(ui._open_button.get_global_rect().get_center())
	_expect(ui.is_open() and dialogic.paused and dialogic.current_event_idx == index, "Task entry click pauses dialogue without advancing")
	var lease_owner := Node.new()
	root.add_child(lease_owner)
	pause_manager.acquire(lease_owner)
	ui.close_quests()
	_expect(paused and dialogic.paused, "Closing one modal preserves another pause owner")
	pause_manager.release(lease_owner)
	lease_owner.free()
	_expect(not paused and not dialogic.paused, "Final pause owner restores the original state")
	dialogic.paused = true
	ui.open_quests()
	ui.close_quests()
	_expect(dialogic.paused, "Task list preserves an existing dialogue pause")
	dialogic.paused = false
	await dialogic.end_timeline(true)
	await _settle()
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	ui.open_quests()
	await _settle()
	_expect(root.get_visible_rect().grow(1).encloses(ui.get_node("Overlay/Canvas").get_global_rect()), "Task list fits a smaller viewport")
	ui.close_quests()
	print("Quest UI: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

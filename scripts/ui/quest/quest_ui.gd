extends CanvasLayer

signal window_opened
signal window_closed

var _selected_id: StringName = &""
var _show_completed := false
var _previous_focus: WeakRef

@onready var _quests: Node = get_node("/root/QuestSystem")
@onready var _dialogic: Node = get_node("/root/Dialogic")
@onready var _pause: Node = get_node("/root/OverlayPauseManager")
@onready var _overlay: Control = %Overlay
@onready var _open_button: Button = %OpenButton
@onready var _tracker: PanelContainer = %Tracker
@onready var _tracker_body: VBoxContainer = %TrackerBody
@onready var _tracker_title: Label = %TrackerTitle
@onready var _tracker_goal: Label = %TrackerGoal
@onready var _tracker_counts: Label = %TrackerCounts
@onready var _collapse: Button = %Collapse
@onready var _skip: Button = %SkipTutorial
@onready var _quest_list: VBoxContainer = %QuestList
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_description: Label = %DetailDescription
@onready var _detail_objectives: Label = %DetailObjectives
@onready var _track_button: Button = %TrackButton
@onready var _empty: Label = %Empty
@onready var _close: Button = %Close

func _ready() -> void:
	_overlay.hide()
	_quests.quests_changed.connect(_refresh)
	_dialogic.timeline_started.connect(_on_context_changed)
	_dialogic.timeline_ended.connect(_on_context_changed)
	get_tree().scene_changed.connect(_on_context_changed)
	get_viewport().size_changed.connect(_layout_tracker)
	var progress := get_node("/root/GameProgress")
	progress.guidance_changed.connect(_on_guidance_changed)
	for entry in [["InventoryUI", "inventory_opened", "inventory_closed"], ["SettingsUI", "settings_opened", "settings_closed"], ["SaveUI", "window_opened", "window_closed"]]:
		var ui := get_node_or_null("/root/" + entry[0])
		if ui != null:
			ui.connect(entry[1], _refresh)
			ui.connect(entry[2], _refresh)
			window_opened.connect(ui._refresh_entry)
			window_closed.connect(ui._refresh_entry)
	_refresh.call_deferred()

func is_open() -> bool:
	return _overlay.visible

func open_quests() -> void:
	if is_open() or not _can_open() or _has_popup():
		return
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	_selected_id = _quests.get_tracked_quest_id()
	if _selected_id != &"":
		_show_completed = _quests.get_quest_state(_selected_id).get("status", "") == "completed"
	_pause.acquire(self)
	_overlay.show()
	_refresh()
	_close.grab_focus()
	get_viewport().set_input_as_handled()
	window_opened.emit()

func close_quests() -> void:
	if not is_open():
		return
	_overlay.hide()
	_pause.release(self)
	get_viewport().set_input_as_handled()
	if _previous_focus != null:
		var focus = _previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree() and focus.can_process():
			focus.grab_focus()
	_previous_focus = null
	_refresh()
	window_closed.emit()

func toggle_quests() -> void:
	if is_open():
		close_quests()
	else:
		open_quests()

func _refresh() -> void:
	if not is_node_ready():
		return
	_open_button.visible = not is_open() and _can_open()
	var scene := get_tree().current_scene
	var is_alchemy := scene != null and scene is AlchemyUI
	_open_button.offset_left = -164.0 if is_alchemy else -590.0
	_open_button.offset_right = -20.0 if is_alchemy else -466.0
	_refresh_tracker()
	if is_open():
		_rebuild_list()

func _refresh_tracker() -> void:
	var id: StringName = _quests.get_tracked_quest_id()
	var scene := get_tree().current_scene
	_tracker.visible = not scene is AlchemyUI and id != &"" and _is_gameplay_context() and _dialogic.current_timeline == null and not is_open() and not _other_window_open()
	if not _tracker.visible:
		return
	var quest = _quests.get_quest(id)
	var state: Dictionary = _quests.get_quest_state(id)
	if quest == null or state.is_empty():
		_tracker.hide()
		return
	var completed: bool = state.get("status", "") == "completed"
	_tracker_title.text = "[%s] %s%s" % [quest.category, quest.display_name, " · 已完成" if completed else ""]
	var collapsed: bool = _quests.is_tracker_collapsed()
	_tracker_body.visible = not collapsed
	_collapse.text = "展开" if collapsed else "收起"
	_tracker_goal.text = "任务已完成" if completed else "当前目标：" + quest.get_stage_title(StringName(state.stage_id))
	if not completed and quest.get_stage(StringName(state.stage_id)).match_mode == &"any":
		_tracker_goal.text += "（任一目标达成）"
	if not completed:
		_tracker_goal.text += "\n" + quest.get_stage_description(StringName(state.stage_id))
	var lines := PackedStringArray()
	for objective: Dictionary in _quests.get_objectives(id):
		if str(objective.stage_id) == str(state.stage_id):
			lines.append(_objective_text(objective))
	_tracker_counts.text = "\n".join(lines)
	_skip.visible = quest.guidance_id != &"" and get_node("/root/GameProgress").should_show_guidance(quest.guidance_id) and not completed
	_layout_tracker.call_deferred()

func _layout_tracker() -> void:
	if not is_node_ready():
		return
	_tracker.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var ratio := minf(1.0, minf(viewport_size.x / 1280.0, viewport_size.y / 720.0))
	_tracker.scale = Vector2.ONE * ratio
	var margin := 20.0 * ratio
	_tracker.position = Vector2(margin, 80.0 * ratio)

func _rebuild_list() -> void:
	for child in _quest_list.get_children():
		_quest_list.remove_child(child)
		child.queue_free()
	var ids: Array[StringName] = []
	for id: StringName in _quests.get_accepted_quests():
		var state: Dictionary = _quests.get_quest_state(id)
		if (state.get("status", "") == "completed") == _show_completed:
			ids.append(id)
	if not ids.has(_selected_id):
		_selected_id = ids[0] if not ids.is_empty() else &""
	for id: StringName in ids:
		var quest = _quests.get_quest(id)
		var button := Button.new()
		button.text = "[%s] %s%s" % [quest.category, quest.display_name, "  ◇" if id == _quests.get_tracked_quest_id() else ""]
		button.toggle_mode = true
		button.button_pressed = id == _selected_id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 54
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_select_quest.bind(id))
		_quest_list.add_child(button)
	_empty.visible = ids.is_empty()
	_empty.text = "暂无已完成的任务" if _show_completed else "暂无进行中的任务"
	(%ActiveTab as Button).set_pressed_no_signal(not _show_completed)
	(%CompletedTab as Button).set_pressed_no_signal(_show_completed)
	_refresh_details()

func _refresh_details() -> void:
	var quest = _quests.get_quest(_selected_id)
	_track_button.visible = quest != null
	if quest == null:
		_detail_title.text = "任务日志"
		_detail_description.text = "选择一项任务查看说明与目标。"
		_detail_objectives.text = ""
		return
	var state: Dictionary = _quests.get_quest_state(_selected_id)
	_detail_title.text = "[%s] %s · %s" % [quest.category, quest.display_name, "已完成" if state.get("status", "") == "completed" else "进行中"]
	_detail_description.text = quest.description
	var lines := PackedStringArray()
	var last_stage: StringName = &""
	for objective: Dictionary in _quests.get_objectives(_selected_id):
		var stage_id := StringName(objective.stage_id)
		if stage_id != last_stage:
			var rule := "（任一目标达成）" if quest.get_stage(stage_id).match_mode == &"any" else ""
			lines.append("◆ " + quest.get_stage_title(stage_id) + rule)
			last_stage = stage_id
		lines.append(_objective_text(objective))
	_detail_objectives.text = "\n\n".join(lines)
	_track_button.text = "取消追踪" if _quests.get_tracked_quest_id() == _selected_id else "追踪此任务"

func _objective_text(objective: Dictionary) -> String:
	if objective.get("skipped", false):
		return "— %s · 已通过其他目标达成" % objective.get("text", "")
	if not objective.get("has_count", false):
		return "%s %s" % ["✓" if objective.get("completed", false) else "○", objective.get("text", "")]
	if objective.completed and int(objective.current) < int(objective.required):
		return "✓ %s · 已达成（当前 %d / %d）" % [objective.text, objective.current, objective.required]
	return "%s %s  %d / %d" % ["✓" if objective.completed else "○", objective.text, objective.current, objective.required]

func _select_quest(id: StringName) -> void:
	_selected_id = id
	_rebuild_list()

func _set_filter(completed: bool) -> void:
	_show_completed = completed
	_rebuild_list()

func _on_track_pressed() -> void:
	_quests.track_quest(&"" if _quests.get_tracked_quest_id() == _selected_id else _selected_id)

func _on_collapse_pressed() -> void:
	_quests.set_tracker_collapsed(not _quests.is_tracker_collapsed())

func _on_skip_pressed() -> void:
	var quest = _quests.get_quest(_quests.get_tracked_quest_id())
	if quest != null and quest.guidance_id != &"":
		get_node("/root/GameProgress").skip_guidance(quest.guidance_id)

func _on_guidance_changed(_guidance_id: StringName) -> void:
	_refresh()

func _is_gameplay_context() -> bool:
	var scene := get_tree().current_scene
	return _dialogic.current_timeline != null or (scene != null and scene.is_in_group("settings_context"))

func _other_window_open() -> bool:
	for name in ["InventoryUI", "SettingsUI", "SaveUI"]:
		var ui := get_node_or_null("/root/" + name)
		if ui != null and ui.is_open():
			return true
	return false

func _can_open() -> bool:
	return _is_gameplay_context() and not _other_window_open() and not get_node("/root/SaveSystem").is_restoring and not _quests.get_accepted_quests().is_empty()

func _has_popup() -> bool:
	for popup: Window in get_tree().root.find_children("*", "Window", true, false):
		if popup.visible and (popup is AcceptDialog or popup is PopupMenu or popup.exclusive):
			return true
	return false

func _on_context_changed() -> void:
	close_quests()
	_refresh.call_deferred()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not is_open() and _can_open():
		for button in [_open_button, %TrackerList]:
			if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				open_quests()
				return
		# Tracker controls must not pass their clicks through to the room.
		for button in [_collapse, _skip]:
			if button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				button.pressed.emit()
				return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_J:
		var focus := get_viewport().gui_get_focus_owner()
		if not is_open() and (focus is LineEdit or focus is TextEdit):
			return
		if is_open() or _can_open():
			get_viewport().set_input_as_handled()
			toggle_quests()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_quests()

func _unhandled_input(_event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()

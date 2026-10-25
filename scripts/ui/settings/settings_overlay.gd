extends CanvasLayer

signal settings_opened
signal settings_closed

@export_file("*.tscn") var main_menu_path := "res://scenes/main_menu.tscn"

var _previous_focus: WeakRef

@onready var _dialogic: Node = get_node("/root/Dialogic")
@onready var _inventory_ui: Node = get_node("/root/InventoryUI")
@onready var _panel: SettingsPanel = $Panel
@onready var _open_button: Button = $OpenButton


func _ready() -> void:
	_panel.closed.connect(_on_panel_closed)
	_dialogic.timeline_started.connect(_on_context_changed)
	_dialogic.timeline_ended.connect(_on_context_changed)
	get_tree().scene_changed.connect(_on_context_changed)
	_inventory_ui.inventory_opened.connect(_refresh_entry)
	_inventory_ui.inventory_closed.connect(_refresh_entry)
	_refresh_entry.call_deferred()


func is_open() -> bool:
	return _panel.visible


## Shared entry point for menu buttons and Dialogic Call events.
func open_settings() -> void:
	if is_open() or not _can_open() or _has_modal_window():
		return
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	get_node("/root/OverlayPauseManager").acquire(self)
	_panel.open_settings()
	_open_button.hide()
	settings_opened.emit()


func close_settings() -> void:
	if is_open():
		_panel.close_settings()


func _on_panel_closed() -> void:
	get_viewport().set_input_as_handled()
	get_node("/root/OverlayPauseManager").release(self)
	if _dialogic.current_timeline != null:
		_dialogic.Inputs.block_input(0.15)
	if _previous_focus != null:
		var focus = _previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree() and focus.can_process():
			focus.grab_focus()
	_previous_focus = null
	_refresh_entry()
	settings_closed.emit()


func _input(event: InputEvent) -> void:
	# Handle the entry before Dialogic can treat its click as dialogue advance.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_open() and _open_button.visible and _open_button.get_global_rect().has_point(event.position):
			if _can_open() and not _has_modal_window():
				get_viewport().set_input_as_handled()
				open_settings()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open():
		if _has_modal_window():
			return
		get_viewport().set_input_as_handled()
		close_settings()
	elif _is_gameplay_context() and _can_open() and not _has_modal_window():
		get_viewport().set_input_as_handled()
		open_settings()


func _unhandled_input(_event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	var quest_ui := get_node_or_null("/root/QuestUI")
	if quest_ui != null and quest_ui.is_open():
		return false
	if _inventory_ui.is_open():
		return false
	var save_ui := get_node_or_null("/root/SaveUI")
	if save_ui != null and save_ui.is_open():
		return false
	var scene := get_tree().current_scene
	return _is_gameplay_context() or (scene != null and scene.scene_file_path == main_menu_path)


func _is_gameplay_context() -> bool:
	var scene := get_tree().current_scene
	return _dialogic.current_timeline != null or (scene != null and scene.is_in_group("settings_context"))


func _has_modal_window() -> bool:
	# Confirmation popups keep their original Escape/confirmation behaviour.
	for popup: Window in get_tree().root.find_children("*", "Window", true, false):
		if popup.visible and (popup is AcceptDialog or popup is PopupMenu or popup.exclusive):
			return true
	return false


func _refresh_entry() -> void:
	_open_button.visible = not is_open() and _is_gameplay_context() and _can_open()


func _on_context_changed() -> void:
	close_settings()
	_refresh_entry.call_deferred()

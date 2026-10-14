extends CanvasLayer

signal window_opened
signal window_closed

enum Mode {LOAD, SAVE}

@export var slot_scene: PackedScene

var _mode := Mode.LOAD
var _page := 0
var _pending_slot := -1
var _busy := false
var _thumbnail: Image
var _tree_was_paused := false
var _dialogue_was_paused := false
var _paused_dialogue := false
var _previous_focus: WeakRef

@onready var _system: Node = get_node("/root/SaveSystem")
@onready var _dialogic: Node = get_node("/root/Dialogic")
@onready var _settings_ui: Node = get_node("/root/SettingsUI")
@onready var _inventory_ui: Node = get_node("/root/InventoryUI")
@onready var _overlay: Control = %Overlay
@onready var _open_button: Button = %OpenButton
@onready var _grid: GridContainer = %Slots
@onready var _pages: HBoxContainer = %Pages
@onready var _heading: Label = %Heading
@onready var _status: Label = %Status
@onready var _save_mode: Button = %SaveMode
@onready var _load_mode: Button = %LoadMode
@onready var _close: Button = %Close
@onready var _confirm: ConfirmationDialog = $Confirm


func _ready() -> void:
	_overlay.hide()
	for index in _system.PAGE_SIZE:
		var slot := slot_scene.instantiate()
		_grid.add_child(slot)
		slot.slot_chosen.connect(_on_slot_chosen)
	for index in _pages.get_child_count():
		_pages.get_child(index).pressed.connect(_select_page.bind(index))
	_system.slots_changed.connect(_refresh_slots)
	_system.restore_finished.connect(_refresh_entry)
	_dialogic.timeline_started.connect(_on_context_changed)
	_dialogic.timeline_ended.connect(_on_context_changed)
	get_tree().scene_changed.connect(_on_context_changed)
	_settings_ui.settings_opened.connect(_refresh_entry)
	_settings_ui.settings_closed.connect(_refresh_entry)
	_inventory_ui.inventory_opened.connect(_refresh_entry)
	_inventory_ui.inventory_closed.connect(_refresh_entry)
	window_opened.connect(_settings_ui._refresh_entry)
	window_closed.connect(_settings_ui._refresh_entry)
	_refresh_entry.call_deferred()


func is_open() -> bool:
	return _overlay.visible


func open_load() -> void:
	_open(Mode.LOAD)


func open_save() -> void:
	if _system.is_gameplay_context():
		_open(Mode.SAVE)


func _open(mode: Mode) -> void:
	if is_open() or _busy or _system.is_restoring or _settings_ui.is_open() or _inventory_ui.is_open() or _has_popup():
		return
	# Capture the gameplay framebuffer before showing the modal window.
	_thumbnail = _system.capture_thumbnail() if _system.can_save().ok else null
	_mode = mode
	_page = 0
	_pending_slot = -1
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	_tree_was_paused = get_tree().paused
	_dialogue_was_paused = _dialogic.paused
	_paused_dialogue = _dialogic.current_timeline != null
	if _paused_dialogue and not _dialogue_was_paused:
		_dialogic.paused = true
	get_tree().paused = true
	_overlay.show()
	_open_button.hide()
	_refresh_mode()
	_load_mode.grab_focus()
	window_opened.emit()


func close_window() -> void:
	if not is_open():
		return
	_confirm.hide()
	_overlay.hide()
	_pending_slot = -1
	_thumbnail = null
	get_viewport().set_input_as_handled()
	get_tree().paused = _tree_was_paused
	if _paused_dialogue:
		if _dialogic.paused != _dialogue_was_paused:
			_dialogic.paused = _dialogue_was_paused
		if not _dialogic.paused and _dialogic.Inputs.auto_skip.enabled:
			_dialogic.Inputs.set_process(true)
	_paused_dialogue = false
	if _dialogic.current_timeline != null:
		_dialogic.Inputs.block_input(0.15)
	if _previous_focus != null:
		var focus = _previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree() and focus.can_process():
			focus.grab_focus()
	_previous_focus = null
	_refresh_entry()
	window_closed.emit()


func _refresh_mode() -> void:
	var check: Dictionary = _system.can_save()
	_save_mode.disabled = not check.ok
	_save_mode.tooltip_text = check.error
	_load_mode.set_pressed_no_signal(_mode == Mode.LOAD)
	_save_mode.set_pressed_no_signal(_mode == Mode.SAVE)
	_heading.text = "读取存档" if _mode == Mode.LOAD else "保存存档"
	_status.text = "点击存档记录后确认读取；空存档不能读取。" if _mode == Mode.LOAD else ("点击空槽保存；已有记录会询问是否覆盖。" if check.ok else check.error)
	_refresh_slots()


func _refresh_slots() -> void:
	if not is_open():
		return
	for index in _grid.get_child_count():
		var slot_index: int = _page * _system.PAGE_SIZE + index + 1
		_grid.get_child(index).display(slot_index, _system.get_slot_record(slot_index))
	for index in _pages.get_child_count():
		_pages.get_child(index).set_pressed_no_signal(index == _page)


func _select_page(index: int) -> void:
	if _busy:
		return
	_page = index
	_refresh_slots()


func _on_mode_pressed(mode: Mode) -> void:
	if _busy or (mode == Mode.SAVE and not _system.can_save().ok):
		return
	_mode = mode
	_refresh_mode()


func _on_slot_chosen(index: int) -> void:
	if _busy or _confirm.visible:
		return
	var record: Dictionary = _system.get_slot_record(index)
	_pending_slot = index
	if _mode == Mode.LOAD:
		if record.state != "saved":
			_status.text = "该存档为空。" if record.state == "empty" else record.error
			_pending_slot = -1
			return
		_confirm.title = "确认读取"
		_confirm.ok_button_text = "读取"
		_confirm.dialog_text = "是否读取存档 %03d？\n%s  %s\n游玩时长 %s" % [index, record.chapter, record.saved_at, record.play_time]
	elif not _system.can_save().ok:
		_status.text = _system.can_save().error
		_pending_slot = -1
		return
	elif record.state == "empty":
		_store(index)
		return
	else:
		_confirm.title = "确认覆盖"
		_confirm.ok_button_text = "覆盖"
		_confirm.dialog_text = "存档 %03d 已有记录，是否替换原存档？" % index
	_confirm.popup_centered(Vector2i(460, 190))


func _store(index: int) -> void:
	var result: Dictionary = _system.save_slot(index, _thumbnail)
	_status.text = "存档 %03d 已保存。" % index if result.ok else result.error
	_pending_slot = -1


func _on_confirmed() -> void:
	var index := _pending_slot
	_pending_slot = -1
	if index < 1:
		return
	if _mode == Mode.SAVE:
		_store(index)
	else:
		_busy = true
		_close.disabled = true
		var result: Dictionary = await _system.load_slot(index)
		_busy = false
		_close.disabled = false
		if not result.ok:
			_status.text = result.error
		_refresh_entry()


func _on_canceled() -> void:
	_pending_slot = -1


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_open() and _open_button.visible and _open_button.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			open_save()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_open() and event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			return
		get_viewport().set_input_as_handled()
		if not _busy:
			close_window()
	elif event.physical_keycode in [KEY_F5, KEY_F9] and not is_open() and _open_button.visible:
		get_viewport().set_input_as_handled()
		if event.physical_keycode == KEY_F5:
			open_save()
		else:
			open_load()


func _unhandled_input(_event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()


func _has_popup() -> bool:
	for popup: Window in get_tree().root.find_children("*", "Window", true, false):
		if popup.visible and (popup is AcceptDialog or popup is PopupMenu or popup.exclusive):
			return true
	return false


func _refresh_entry() -> void:
	_open_button.visible = not is_open() and not _busy and not _system.is_restoring and _system.is_gameplay_context() and not _settings_ui.is_open() and not _inventory_ui.is_open()


func _on_context_changed() -> void:
	close_window()
	_refresh_entry.call_deferred()

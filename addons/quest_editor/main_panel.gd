@tool
extends VBoxContainer

signal resources_saved

const Store = preload("res://addons/quest_editor/resource_store.gd")
var _store
var _page := 0
var _original: Resource
var _new := false
var _history: Array[Resource] = []
var _cursor := -1
var _clean_cursor := 0
var _loading := false
var _pending := Callable()

@onready var _form = %QuestForm
@onready var _list: ItemList = %Entries
@onready var _search: LineEdit = %Search
@onready var _issues: ItemList = %Issues
@onready var _preview: Label = %Preview
@onready var _status: Label = %Status

func _ready() -> void:
	%Pages.tab_changed.connect(_on_page_changed)
	_list.item_selected.connect(_on_entry_selected)
	_search.text_changed.connect(func(_text): _refresh_list())
	%New.pressed.connect(func(): _request_change(_create))
	%Copy.pressed.connect(func(): _request_change(_copy))
	%Reload.pressed.connect(func(): _request_change(reload_catalogs))
	%Save.pressed.connect(_save_current)
	%Undo.pressed.connect(_undo)
	%Redo.pressed.connect(_redo)
	%Revert.pressed.connect(func(): %Confirm.popup_centered(Vector2i(430, 180)))
	%Confirm.confirmed.connect(_discard)
	%CheckAll.pressed.connect(_check_all)
	_form.changed.connect(_changed)
	%Unsaved.confirmed.connect(_save_and_continue)
	%Unsaved.add_button("放弃更改并继续", false, "discard")
	%Unsaved.custom_action.connect(func(action):
		if action == &"discard":
			%Unsaved.hide()
			_discard()
			_continue())
	%Unsaved.canceled.connect(func(): _pending = Callable(); _refresh_list())
	_issues.item_activated.connect(_locate_issue)
	reload_catalogs()

func setup(store) -> void:
	_store = store
	_form.bind_data(_store)
	_select_first()

func reload_catalogs() -> void:
	var store = Store.new()
	var check: Dictionary = store.load_catalogs()
	if not check.ok:
		_status.text = check.error
		return
	setup(store)
	_status.text = "已载入任务目录。编辑工作副本后，点击保存才写入项目。"

func has_unsaved_changes() -> bool:
	return _cursor >= 0 and _cursor != _clean_cursor

func _on_page_changed(page: int) -> void:
	if _loading or page == _page:
		return
	_loading = true
	%Pages.current_tab = _page
	_loading = false
	_request_change(func(): _page = page; _search.text = ""; _select_first())

func _on_entry_selected(index: int) -> void:
	if _loading:
		return
	var entry: Resource = _list.get_item_metadata(index)
	if entry != _original or _new:
		_request_change(_open.bind(entry, false))

func _request_change(action: Callable) -> void:
	if not has_unsaved_changes():
		action.call()
		return
	_pending = action
	%Unsaved.dialog_text = "当前配置有未保存更改。保存并继续，或放弃更改。"
	%Unsaved.popup_centered(Vector2i(520, 180))

func _save_and_continue() -> void:
	if _save_current():
		_continue()

func _continue() -> void:
	var action := _pending
	_pending = Callable()
	if action.is_valid():
		action.call()

func _select_first() -> void:
	var entries: Array = _store.entries(_page)
	_open(entries[0] if not entries.is_empty() else null, false)

func _open(entry: Resource, is_new: bool) -> void:
	_loading = true
	_original = null if is_new else entry
	_new = is_new
	%Pages.current_tab = _page
	%Copy.disabled = entry == null
	_form.visible = entry != null
	_form.edit_resource(entry, is_new, _page)
	_history.clear()
	_cursor = -1
	_clean_cursor = -1 if is_new else 0
	if entry != null:
		_history.append(_form.get_resource().duplicate(true))
		_cursor = 0
	_loading = false
	_refresh_list()
	_refresh_draft()

func _changed() -> void:
	if _loading or _form.get_resource() == null:
		return
	while _history.size() > _cursor + 1:
		_history.pop_back()
	_history.append(_form.get_resource().duplicate(true))
	_cursor += 1
	_refresh_draft()

func _refresh_list() -> void:
	if _store == null:
		return
	_loading = true
	_list.clear()
	var query := _search.text.strip_edges().to_lower()
	for entry: Resource in _store.entries(_page):
		if entry == null:
			continue
		var id: String = str(entry.get(_store.id_field(_page)))
		var title: String = entry.display_name if _page == 0 else id
		if not query.is_empty() and not (title + id).to_lower().contains(query):
			continue
		var prefix := "✓ "
		for issue: Dictionary in _store.validate_entry(entry, entry, _page):
			if issue.get("severity", "error") == "error":
				prefix = "! "
		var index := _list.add_item("%s%s  ·  %s" % [prefix, title, id])
		_list.set_item_metadata(index, entry)
		if entry == _original:
			_list.select(index)
	_loading = false

func _refresh_draft() -> void:
	%Undo.disabled = _cursor <= 0
	%Redo.disabled = _cursor < 0 or _cursor >= _history.size() - 1
	%Save.disabled = not has_unsaved_changes()
	%Revert.disabled = not has_unsaved_changes()
	%Dirty.text = "● 未保存" if has_unsaved_changes() else "已保存"
	if _cursor < 0:
		_preview.text = "选择配置或新建。"
		_issues.clear()
		return
	var draft: Resource = _form.get_resource()
	_preview.text = _store.public_preview(draft, _page)
	_show_issues(_store.validate_entry(draft, _original, _page))

func _show_issues(issues: Array) -> void:
	_issues.clear()
	if issues.is_empty():
		_issues.add_item("✓ 配置检查通过")
		_issues.set_item_disabled(0, true)
	for issue: Dictionary in issues:
		var index := _issues.add_item("%s：%s" % ["提示" if issue.get("severity") == "warning" else "错误", issue.message])
		_issues.set_item_metadata(index, issue)
		_issues.set_item_tooltip(index, str(issue.get("field", "")))

func _check_all() -> void:
	_show_issues(_store.validate_project())
	_status.text = "已检查任务、阶段、目标、条件、动作及剧情引用。双击问题定位。"

func _locate_issue(index: int) -> void:
	var issue: Variant = _issues.get_item_metadata(index)
	if not issue is Dictionary:
		return
	var entry: Resource = issue.get("resource", _original)
	var page: int = issue.get("page", _page)
	var field: String = issue.get("field", "")
	if entry == null or entry == _original or entry == _form.get_resource():
		_form.focus_field(field)
	else:
		_request_change(func(): _page = page; _open(entry, false); _form.focus_field(field))

func _create() -> void:
	var entry: Resource = _store.create_entry(_page)
	_open(entry, true)

func _copy() -> void:
	if _cursor < 0:
		return
	var copy: Resource = _form.get_resource().duplicate(true)
	var field: String = _store.id_field(_page)
	copy.set(field, _store.suggest_id(str(copy.get(field)) + "_copy", _page))
	if _page == 0:
		copy.display_name += "（副本）"
	_open(copy, true)

func _save_current() -> bool:
	if _cursor < 0:
		return false
	var result: Dictionary = _store.save_entry(_form.get_resource(), _original, _page)
	if not result.ok:
		_status.text = "保存失败：" + str(result.error)
		_show_issues(_store.validate_entry(_form.get_resource(), _original, _page))
		return false
	_form.bind_data(_store)
	_open(result.resource, false)
	_status.text = "已保存资源并登记到任务目录。ID 保持稳定，运行时无需修改脚本列表。"
	resources_saved.emit()
	return true

func _discard() -> void:
	if _new:
		_select_first()
	else:
		_open(_original, false)

func _undo() -> void:
	if _cursor > 0:
		_cursor -= 1
		_restore_history()

func _redo() -> void:
	if _cursor >= 0 and _cursor < _history.size() - 1:
		_cursor += 1
		_restore_history()

func _restore_history() -> void:
	_loading = true
	_form.edit_resource(_history[_cursor], _new, _page, false)
	_loading = false
	_refresh_draft()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed:
		return
	match event.keycode:
		KEY_S: _save_current()
		KEY_Z: _redo() if event.shift_pressed else _undo()
		KEY_Y: _redo()
		_: return
	get_viewport().set_input_as_handled()

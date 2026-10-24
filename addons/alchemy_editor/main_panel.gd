@tool
extends VBoxContainer

signal resources_saved

const Store = preload("res://addons/alchemy_editor/resource_store.gd")
enum ItemFilter { ALL, ITEMS, RECIPE_BOOKS }
var _store
var _page := 0
var _item_filter := ItemFilter.ALL
var _original: Resource
var _new := false
var _history: Array[Resource] = []
var _cursor := -1
var _clean_cursor := 0
var _loading := false
var _pending := Callable()
var _confirmed_action := Callable()
var _quick_field := ""

@onready var _tabs: TabBar = %Pages
@onready var _list: ItemList = %Entries
@onready var _search: LineEdit = %Search
@onready var _item_filter_option: OptionButton = %ItemFilter
@onready var _recipe_form = %RecipeForm
@onready var _item_form = %ItemForm
@onready var _common_form = %CommonForm
@onready var _preview = %Preview
@onready var _issues: ItemList = %Issues
@onready var _status: Label = %Status

func _ready() -> void:
	_tabs.tab_changed.connect(_on_page_changed)
	_list.item_selected.connect(_on_entry_selected)
	_search.text_changed.connect(func(_text): _refresh_list())
	_item_filter_option.item_selected.connect(_on_item_filter_selected)
	%New.pressed.connect(func(): _request_change(_create))
	%Copy.pressed.connect(func(): _request_change(_copy))
	%Delete.pressed.connect(_delete)
	%Save.pressed.connect(_save_current)
	%Revert.pressed.connect(_revert)
	%Undo.pressed.connect(_undo)
	%Redo.pressed.connect(_redo)
	%Reload.pressed.connect(func(): _request_change(reload_catalogs))
	%CheckAll.pressed.connect(_check_all)
	_recipe_form.changed.connect(_changed)
	_item_form.changed.connect(_changed)
	_common_form.changed.connect(_changed)
	_recipe_form.create_item_requested.connect(_quick_create)
	%Unsaved.confirmed.connect(_save_and_continue)
	%Unsaved.custom_action.connect(_unsaved_action)
	%Unsaved.canceled.connect(func(): _pending = Callable(); _refresh_list())
	%Unsaved.add_button("放弃更改并继续", false, "discard")
	%ActionConfirm.confirmed.connect(func():
		if _confirmed_action.is_valid():
			_confirmed_action.call()
		_confirmed_action = Callable())
	%QuickCreate.confirmed.connect(_save_quick_item)
	_issues.item_activated.connect(_locate_issue)
	reload_catalogs()

## Optional injection lets tests exercise the entire UI against temporary catalogs.
func setup(store) -> void:
	_store = store
	_bind_data()
	_select_first()

func reload_catalogs() -> void:
	var store = Store.new()
	var loaded: Dictionary = store.load_catalogs()
	if not loaded.ok:
		_status.text = loaded.error
		return
	setup(store)
	_status.text = "已载入项目资源。编辑工作副本后，点击保存才会写入项目。"

func _bind_data() -> void:
	_recipe_form.bind_data(_store.items, _store.items.categories, _store.recipes.recipes)
	_item_form.bind_data(_store.items, _store.items.categories, _store.recipes.recipes)
	%QuickItemForm.bind_data(_store.items, _store.items.categories, _store.recipes.recipes)
	_preview.bind_data(_store.items)

func has_unsaved_changes() -> bool:
	return _cursor >= 0 and _cursor != _clean_cursor

func _form():
	return [_recipe_form, _item_form, _common_form][_page]

func _on_page_changed(page: int) -> void:
	if _loading or page == _page:
		return
	_loading = true
	_tabs.current_tab = _page
	_loading = false
	_request_change(func(): _page = page; _search.text = ""; _select_first())

func _on_entry_selected(index: int) -> void:
	if _loading:
		return
	var entry: Resource = _list.get_item_metadata(index)
	if entry == _original and not _new:
		return
	_request_change(func(): _open(entry, false))

func _on_item_filter_selected(filter: int) -> void:
	if _loading or filter == _item_filter:
		return
	# Commit navigation only after resolving a draft that would leave the list.
	_item_filter_option.select(_item_filter)
	var current: ItemData = _item_form.get_resource() if _page == 1 and _cursor >= 0 else null
	var keep_current := current != null and _matches_item_filter(current, filter)
	var apply := _apply_item_filter.bind(filter, keep_current)
	if keep_current:
		apply.call()
	else:
		_request_change(apply)

func _apply_item_filter(filter: int, keep_current: bool) -> void:
	_item_filter = filter
	_item_filter_option.select(filter)
	if keep_current:
		_refresh_list()
	else:
		_select_first()

func _matches_item_filter(item: ItemData, filter: int) -> bool:
	if item == null:
		return false
	match filter:
		ItemFilter.ITEMS: return item.alchemy_recipe == null
		ItemFilter.RECIPE_BOOKS: return item.alchemy_recipe != null
		_: return true

func _filtered_items() -> Array[ItemData]:
	var entries: Array[ItemData] = []
	var query := _search.text.strip_edges().to_lower()
	for item in _store.items.items:
		if _matches_item_filter(item, _item_filter) and (query.is_empty() or (item.display_name + str(item.item_id)).to_lower().contains(query)):
			entries.append(item)
	return entries

func _request_change(action: Callable) -> void:
	if not has_unsaved_changes():
		action.call()
		return
	_pending = action
	%Unsaved.dialog_text = "当前配置有未保存的更改。保存后继续，或放弃更改。"
	%Unsaved.popup_centered()

func _save_and_continue() -> void:
	if _save_current():
		_continue()

func _unsaved_action(action: StringName) -> void:
	if action == &"discard":
		%Unsaved.hide()
		if _new:
			_select_first()
		else:
			_open(_original, false)
		_continue()

func _continue() -> void:
	var action := _pending
	_pending = Callable()
	if action.is_valid():
		action.call()

func _select_first() -> void:
	if _page == 2:
		_open(_store.items, false)
	elif _page == 0:
		_open(_store.recipes.recipes[0] if not _store.recipes.recipes.is_empty() else null, false)
	else:
		var entries := _filtered_items()
		_open(entries[0] if not entries.is_empty() else null, false)

func _open(resource: Resource, is_new: bool) -> void:
	_loading = true
	_original = null if is_new else resource
	_new = is_new
	_tabs.current_tab = _page
	_item_filter_option.visible = _page == 1
	# Saving a changed association, or locating an issue, must keep its item reachable.
	if _page == 1 and resource != null and not _matches_item_filter(resource, _item_filter):
		_item_filter = ItemFilter.ALL
	_item_filter_option.select(_item_filter)
	_recipe_form.visible = _page == 0 and resource != null
	_item_form.visible = _page == 1 and resource != null
	_common_form.visible = _page == 2 and resource != null
	%Empty.visible = resource == null
	%New.disabled = _page == 2
	%Copy.disabled = _page == 2 or resource == null
	%Delete.disabled = _page == 2 or resource == null or is_new
	%Search.editable = _page != 2
	_history.clear()
	_cursor = -1
	_clean_cursor = -1 if is_new else 0
	if resource != null:
		_form().edit_resource(resource, is_new)
		_lock_category_ids()
		_history.append(_form().get_resource().duplicate(true))
		_cursor = 0
	_loading = false
	_refresh_list()
	_refresh_draft()

func _lock_category_ids() -> void:
	if _page != 2:
		return
	var ids: Array[StringName] = []
	for category in _store.items.categories:
		if category != null:
			ids.append(category.category_id)
	_common_form.set_locked_ids(ids)

func _changed() -> void:
	if _loading:
		return
	while _history.size() > _cursor + 1:
		_history.pop_back()
	_history.append(_form().get_resource().duplicate(true))
	_cursor += 1
	_refresh_draft()

func _refresh_draft() -> void:
	%Undo.disabled = _cursor <= 0
	%Redo.disabled = _cursor < 0 or _cursor >= _history.size() - 1
	%Save.disabled = _cursor < 0 or not has_unsaved_changes()
	%Revert.disabled = not has_unsaved_changes()
	%Dirty.text = "● 未保存" if has_unsaved_changes() else "已保存"
	if _cursor < 0:
		_preview.clear_preview()
		_issues.clear()
		return
	var draft: Resource = _form().get_resource()
	if _page == 0:
		_preview.display_recipe(draft)
	elif _page == 1:
		_preview.display_item(draft)
	else:
		_preview.clear_preview()
	_show_issues(_draft_issues())

func _draft_issues() -> Array:
	if _cursor < 0:
		return []
	var draft: Resource = _form().get_resource()
	match _page:
		0: return _store.validate_recipe(draft, _original)
		1: return _store.validate_item(draft, _original)
		_: return _store.validate_common(draft.categories, draft.alchemy_waste_item_id)

func _refresh_list() -> void:
	if _store == null:
		return
	_loading = true
	_list.clear()
	var entries: Array = _store.recipes.recipes if _page == 0 else (_filtered_items() if _page == 1 else [_store.items])
	var query := _search.text.strip_edges().to_lower()
	for entry in entries:
		if entry == null:
			continue
		var id: String = str(entry.recipe_id if _page == 0 else (entry.item_id if _page == 1 else "Common"))
		var title: String = entry.display_name if _page < 2 else "类型与统一异质"
		if not query.is_empty() and not (title + id).to_lower().contains(query):
			continue
		var problems: Array = _store.validate_recipe(entry, entry) if _page == 0 else (_store.validate_item(entry, entry) if _page == 1 else _store.validate_common(entry.categories, entry.alchemy_waste_item_id))
		var prefix := "✓ "
		for problem in problems:
			if problem.get("severity", "error") == "error":
				prefix = "! "
		var index := _list.add_item("%s%s  ·  %s" % [prefix, title, id], entry.icon if _page < 2 else null)
		_list.set_item_metadata(index, entry)
		_list.set_item_tooltip(index, "%s\n%s" % [title, id])
		if entry == _original:
			_list.select(index)
	_loading = false

func _show_issues(issues: Array) -> void:
	_issues.clear()
	if issues.is_empty():
		_issues.add_item("✓ 配置检查通过")
		_issues.set_item_disabled(0, true)
	for issue in issues:
		var prefix := "错误" if issue.get("severity", "error") == "error" else "提示"
		var index := _issues.add_item("%s：%s" % [prefix, issue.message])
		_issues.set_item_metadata(index, issue)
		_issues.set_item_tooltip(index, "%s\n双击定位：%s" % [issue.message, issue.get("field", "")])

func _check_all() -> void:
	_show_issues(_store.validate_project())
	_status.text = "已检查目录中的全部配方、物品与通用配置。双击问题可定位。"

func _locate_issue(index: int) -> void:
	var issue: Variant = _issues.get_item_metadata(index)
	if not issue is Dictionary:
		return
	var resource: Resource = issue.get("resource", _store.items if issue.get("kind") == "common" else null)
	var field: String = issue.get("field", "")
	if resource == null or resource == _original or resource == _form().get_resource():
		_form().focus_field(field)
		return
	_request_change(func():
		_page = 0 if resource is AlchemyRecipe else (1 if resource is ItemData else 2)
		_open(resource, false)
		_form().focus_field(field))

func _create() -> void:
	if _page == 0:
		var recipe := AlchemyRecipe.new()
		recipe.recipe_id = _store.suggest_id("Recipe")
		recipe.display_name = "新配方"
		recipe.formula_mode = AlchemyRecipe.FormulaMode.EXPERIMENTAL
		for index in 4:
			recipe.ingredients.append(IngredientRequirement.new())
		_open(recipe, true)
	elif _page == 1:
		var item := ItemData.new()
		item.item_id = _store.suggest_id("Item")
		item.display_name = "新物品"
		_open(item, true)

func _copy() -> void:
	if _cursor < 0 or _page == 2:
		return
	var copy: Resource = _form().get_resource().duplicate(true)
	if copy is AlchemyRecipe:
		copy.recipe_id = _store.suggest_id(str(copy.recipe_id) + "Copy")
	else:
		copy.item_id = _store.suggest_id(str(copy.item_id) + "Copy")
	copy.display_name += "（副本）"
	_open(copy, true)

func _save_current() -> bool:
	if _cursor < 0:
		return false
	var draft: Resource = _form().get_resource()
	var result: Dictionary
	match _page:
		0: result = _store.save_recipe(draft, _original)
		1: result = _store.save_item(draft, _original)
		_: result = _store.save_common(draft.categories, draft.alchemy_waste_item_id)
	if not result.ok:
		_status.text = "保存失败：%s" % result.error
		_show_issues(_draft_issues())
		return false
	var saved: Resource = result.get("resource", _store.items if _page == 2 else _original)
	_bind_data()
	_open(saved, false)
	_status.text = "保存成功，项目资源与配方目录已更新。配方获取仍由剧情配置。"
	resources_saved.emit()
	return true

func _revert() -> void:
	%ActionConfirm.dialog_text = "还原当前未保存的更改？"
	_confirmed_action = func():
		if _new:
			_select_first()
		else:
			_open(_original, false)
	%ActionConfirm.popup_centered()

func _undo() -> void:
	if _cursor > 0:
		_cursor -= 1
		_restore_history()

func _redo() -> void:
	if _cursor < _history.size() - 1:
		_cursor += 1
		_restore_history()

func _restore_history() -> void:
	_loading = true
	_form().edit_resource(_history[_cursor], _new)
	_lock_category_ids()
	_loading = false
	_refresh_draft()

func _delete() -> void:
	_request_change(_confirm_delete)

func _confirm_delete() -> void:
	if _original == null or _page == 2:
		return
	%ActionConfirm.dialog_text = "删除所选配置？已知目录引用会阻止删除。剧情脚本和 timeline 中的字符串引用请自行确认。"
	_confirmed_action = func():
		var result: Dictionary = _store.delete_recipe(_original) if _page == 0 else _store.delete_item(_original)
		_status.text = "已删除。" if result.ok else "无法删除：%s" % result.error
		if result.ok:
			_bind_data()
			_select_first()
			resources_saved.emit()
	%ActionConfirm.popup_centered()

func _quick_create(field: String) -> void:
	_quick_field = field
	var item := ItemData.new()
	item.item_id = _store.suggest_id("Item")
	item.display_name = "新物品"
	%QuickItemForm.edit_resource(item, true)
	%QuickError.text = ""
	%QuickCreate.popup_centered(Vector2i(600, 670))

func _save_quick_item() -> void:
	var result: Dictionary = _store.save_item(%QuickItemForm.get_resource())
	if not result.ok:
		%QuickError.text = result.error
		%QuickCreate.popup_centered(Vector2i(600, 670))
		return
	_bind_data()
	_recipe_form.set_item_for_field(_quick_field, result.resource.item_id)
	_refresh_list()
	_status.text = "新物品已保存，并填入当前配方；配方的未保存更改已保留。"
	resources_saved.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed:
		return
	if event.keycode == KEY_S:
		_save_current()
	elif event.keycode == KEY_Z:
		_redo() if event.shift_pressed else _undo()
	elif event.keycode == KEY_Y:
		_redo()
	else:
		return
	get_viewport().set_input_as_handled()

@tool
extends VBoxContainer

signal changed
signal create_item_requested

var _items: ItemCatalog
var _categories: Array[ItemCategory] = []
var _draft: IngredientRequirement
var _index := 0
var _hidden := false
var _unknown := false
var _experimental := false
var _updating := false


func _ready() -> void:
	%Amount.value_changed.connect(func(value):
		if not _updating and _draft != null:
			_draft.amount = int(value)
			changed.emit())
	%PickItem.pressed.connect(func(): %Picker.open_picker(_items, _draft.item_id, _experimental))
	%NewItem.pressed.connect(func(): create_item_requested.emit())
	%Picker.item_chosen.connect(set_item_id)
	%StandardCategory.item_selected.connect(func(index):
		if not _updating:
			_draft.category = %StandardCategory.get_item_metadata(index)
			if _draft.category != &"":
				_draft.item_id = &""
			_refresh()
			changed.emit())
	%HintType.item_selected.connect(_on_hint_type_selected)
	%HintName.text_changed.connect(func(text):
		if not _updating:
			_draft.hint_name = text
			changed.emit())
	%HintIcon.changed.connect(func():
		if not _updating:
			_draft.hint_icon = %HintIcon.texture
			changed.emit())
	%Candidate.item_selected.connect(func(index):
		if not _updating:
			_draft.candidate_category = %Candidate.get_item_metadata(index)
			changed.emit())
	_refresh()


func bind_data(items: ItemCatalog, categories: Array[ItemCategory]) -> void:
	_items = items
	_categories = categories
	if is_node_ready():
		_refresh()


func edit_requirement(requirement: IngredientRequirement, index: int, hidden: bool, unknown: bool = false, experimental: bool = false) -> void:
	_draft = requirement.duplicate(true) if requirement != null else IngredientRequirement.new()
	_index = index
	_hidden = hidden
	_unknown = unknown
	_experimental = experimental
	if is_node_ready():
		_refresh()


func get_resource() -> IngredientRequirement:
	return _draft


func set_item_id(item_id: StringName) -> void:
	if _draft == null:
		return
	_draft.item_id = item_id
	if not _hidden:
		_draft.category = &""
	_refresh()
	changed.emit()


func focus_field(field: String) -> void:
	if field.contains("amount"):
		%Amount.get_line_edit().grab_focus()
	elif field.contains("hint"):
		%HintName.grab_focus()
	elif field.contains("candidate"):
		%Candidate.grab_focus()
	else:
		%PickItem.grab_focus()


func _refresh() -> void:
	if _draft == null:
		return
	_updating = true
	%Title.text = "第%d槽 · %s" % [_index + 1, "未知尝试槽（正确公式不使用）" if _unknown else ("隐藏答案 / 类型提示" if _hidden else "明示素材")]
	%Amount.value = _draft.amount
	%ItemRow.visible = not _unknown
	%ItemLabel.text = "正确答案（仅策划可见）" if _hidden else "所需物品"
	%StandardRow.visible = not _experimental
	%HiddenSettings.visible = _hidden and not _unknown
	%UnknownNote.visible = _unknown
	var item := _items.find_item(_draft.item_id) if _items != null else null
	%PickItem.text = "%s  [%s]" % [item.display_name, item.item_id] if item != null else ("选择物品…" if _draft.item_id == &"" else "无效物品 [%s]" % _draft.item_id)
	%PickItem.icon = item.icon if item != null else null
	%PickItem.expand_icon = true
	_fill_categories(%StandardCategory, _draft.category, "按具体物品（不使用类型）")
	_fill_categories(%HintType, _draft.candidate_category, "选择类型以填入提示")
	_fill_categories(%Candidate, _draft.candidate_category, "请选择候选类型")
	%HintName.text = _draft.hint_name
	%HintIcon.texture = _draft.hint_icon
	_updating = false


func _fill_categories(option: OptionButton, selected: StringName, empty_name: String) -> void:
	option.clear()
	option.add_item(empty_name)
	option.set_item_metadata(0, &"")
	var found := selected == &""
	for category in _categories:
		if category == null:
			continue
		option.add_icon_item(category.icon, "%s [%s]" % [category.display_name, category.category_id])
		var index := option.item_count - 1
		option.set_item_metadata(index, category.category_id)
		if category.category_id == selected:
			option.select(index)
			found = true
	if not found:
		option.add_item("未登记类型 [%s]" % selected)
		option.set_item_metadata(option.item_count - 1, selected)
		option.select(option.item_count - 1)


func _on_hint_type_selected(index: int) -> void:
	if _updating or _draft == null:
		return
	var category_id: StringName = %HintType.get_item_metadata(index)
	for category in _categories:
		if category != null and category.category_id == category_id:
			_draft.hint_name = category.display_name
			_draft.hint_icon = category.icon
			_draft.candidate_category = category.category_id
			_refresh()
			changed.emit()
			return

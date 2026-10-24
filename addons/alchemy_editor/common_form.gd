@tool
extends VBoxContainer

signal changed

var _draft: ItemCatalog
var _locked_ids: Array[StringName] = []
var _active := -1
var _loading := false

@onready var _list: ItemList = %CategoryList
@onready var _id: LineEdit = %CategoryID
@onready var _name: LineEdit = %CategoryName
@onready var _icon = %CategoryIcon
@onready var _waste: Button = %WasteItem
@onready var _picker = $ItemPicker

func _ready() -> void:
	_list.item_selected.connect(_select)
	%AddCategory.pressed.connect(_add)
	%RemoveCategory.pressed.connect(_remove)
	_id.text_changed.connect(_update.unbind(1))
	_name.text_changed.connect(_update.unbind(1))
	_icon.changed.connect(_update)
	_waste.pressed.connect(func(): _picker.open_picker(_draft, _draft.alchemy_waste_item_id, true))
	_picker.item_chosen.connect(func(id: StringName):
		_draft.alchemy_waste_item_id = id
		_refresh_waste()
		changed.emit())

func edit_resource(catalog: ItemCatalog, _is_new: bool = false) -> void:
	_draft = catalog.duplicate(true)
	_locked_ids.clear()
	# The main panel supplies the saved category IDs so new drafts stay editable.
	for category in catalog.categories:
		if category != null:
			_locked_ids.append(category.category_id)
	_refresh_list()
	_refresh_waste()
	_select(0 if not _draft.categories.is_empty() else -1)

func set_locked_ids(ids: Array[StringName]) -> void:
	_locked_ids = ids.duplicate()
	_select(_active)

func get_resource() -> ItemCatalog:
	return _draft

func focus_field(field: String) -> void:
	if field.begins_with("categories."):
		var parts := field.split(".")
		if parts.size() > 1 and parts[1].is_valid_int():
			_select(int(parts[1]))
		_id.grab_focus()
	else:
		_waste.grab_focus()

func _refresh_list() -> void:
	_list.clear()
	for category in _draft.categories:
		if category == null:
			_list.add_item("空类型（点击修复）")
		else:
			_list.add_item("%s [%s]" % [category.display_name, category.category_id], category.icon)

func _select(index: int) -> void:
	_active = index if index >= 0 and index < _draft.categories.size() else -1
	_loading = true
	var valid := _active >= 0
	%CategoryFields.visible = valid
	%RemoveCategory.disabled = not valid
	if valid:
		if _draft.categories[_active] == null:
			_draft.categories[_active] = ItemCategory.new()
		var category := _draft.categories[_active]
		_list.select(_active)
		_id.text = category.category_id
		_id.editable = not _locked_ids.has(category.category_id)
		_name.text = category.display_name
		_icon.texture = category.icon
	_loading = false

func _update() -> void:
	if _loading or _active < 0:
		return
	var category := _draft.categories[_active]
	category.category_id = StringName(_id.text.strip_edges())
	category.display_name = _name.text
	category.icon = _icon.texture
	_list.set_item_text(_active, "%s [%s]" % [category.display_name, category.category_id])
	_list.set_item_icon(_active, category.icon)
	changed.emit()

func _add() -> void:
	var category := ItemCategory.new()
	var number := _draft.categories.size() + 1
	var ids: Array[StringName] = []
	for entry in _draft.categories:
		ids.append(entry.category_id)
	while ids.has(StringName("Category%d" % number)):
		number += 1
	category.category_id = StringName("Category%d" % number)
	category.display_name = "新类型"
	_draft.categories.append(category)
	_refresh_list()
	_select(_draft.categories.size() - 1)
	changed.emit()

func _remove() -> void:
	if _active < 0:
		return
	_draft.categories.remove_at(_active)
	_refresh_list()
	_select(mini(_active, _draft.categories.size() - 1))
	changed.emit()

func _refresh_waste() -> void:
	var item := _draft.find_item(_draft.alchemy_waste_item_id)
	_waste.text = "%s [%s]" % [item.display_name, item.item_id] if item != null else "选择统一异质物品"
	_waste.icon = item.icon if item != null else null

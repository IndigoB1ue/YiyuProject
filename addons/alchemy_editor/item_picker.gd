@tool
extends ConfirmationDialog

signal item_chosen(item_id: StringName)

var _catalog: ItemCatalog
var _material_only := false
var _selected: StringName
var _visible_ids: Array[StringName] = []


func _ready() -> void:
	%Search.text_changed.connect(func(_text): _refresh())
	%Items.item_selected.connect(func(index): _selected = _visible_ids[index]; get_ok_button().disabled = false)
	%Items.item_activated.connect(func(index): _selected = _visible_ids[index]; _choose(); hide())
	confirmed.connect(_choose)
	get_ok_button().text = "选择此物品"
	get_cancel_button().text = "取消"


func open_picker(items: ItemCatalog, selected: StringName = &"", material_only: bool = false) -> void:
	_catalog = items
	_selected = selected
	_material_only = material_only
	%Search.text = ""
	_refresh()
	popup_centered(Vector2i(650, 560))
	%Search.grab_focus()


func _refresh() -> void:
	%Items.clear()
	_visible_ids.clear()
	get_ok_button().disabled = true
	if _catalog == null:
		return
	var query: String = %Search.text.strip_edges().to_lower()
	for item in _catalog.items:
		if item == null or (_material_only and item.alchemy_recipe != null):
			continue
		if not query.is_empty() and not (item.display_name.to_lower().contains(query) or str(item.item_id).to_lower().contains(query)):
			continue
		var index: int = %Items.add_item("%s  [%s]" % [item.display_name, item.item_id], item.icon)
		_visible_ids.append(item.item_id)
		%Items.set_item_tooltip(index, item.description)
		if item.item_id == _selected:
			%Items.select(index)
			get_ok_button().disabled = false
	%Count.text = "共 %d 项；仅能选择物品目录中已存在的物品" % _visible_ids.size()


func _choose() -> void:
	if _catalog != null and _visible_ids.has(_selected) and _catalog.find_item(_selected) != null:
		item_chosen.emit(_selected)

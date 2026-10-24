@tool
extends VBoxContainer

const SLOT_SCENE := preload("res://addons/alchemy_editor/preview_slot.tscn")

var _catalog: ItemCatalog
var _recipe: AlchemyRecipe
var _stock_controls: Dictionary = {}
var _selection_rows: Array[Control] = []
var _selection: Array[Dictionary] = []
var _preview_inventory: InventorySystem
var _public_preview: Dictionary = {}

@onready var _tabs: TabContainer = $Tabs
@onready var _player: VBoxContainer = $Tabs/Player/Content
@onready var _stock_rows: VBoxContainer = $Tabs/Trial/Content/StockRows
@onready var _trial_rows: VBoxContainer = $Tabs/Trial/Content/SelectionRows
@onready var _result: Label = $Tabs/Trial/Content/Result


func _ready() -> void:
	_tabs.set_tab_title(0, "玩家预览")
	_tabs.set_tab_title(1, "炼金验证")
	$Tabs/Trial/Content/ResetStock.pressed.connect(_reset_stock)
	$Tabs/Trial/Content/StockHeading.toggled.connect(_toggle_stock)
	$Tabs/Trial/Content/ClearSelection.pressed.connect(_clear_selection)
	$Tabs/Trial/Content/Run.pressed.connect(run_trial)
	clear_preview()


func _exit_tree() -> void:
	if is_instance_valid(_preview_inventory):
		_preview_inventory.free()
		_preview_inventory = null


func bind_data(items: ItemCatalog) -> void:
	var previous_stock := get_trial_stock()
	_catalog = items
	if not is_node_ready():
		return
	_clear_children(_stock_rows)
	_stock_controls.clear()
	if _catalog == null:
		return
	for item in _catalog.items:
		if item == null or item.alchemy_recipe != null:
			continue
		var row := $Templates/StockRow.duplicate() as HBoxContainer
		_stock_rows.add_child(row)
		row.show()
		row.get_node("Icon").texture = item.icon
		row.get_node("Name").text = item.display_name
		row.tooltip_text = "%s (%s)" % [item.display_name, item.item_id]
		var amount := row.get_node("Amount") as SpinBox
		amount.value = int(previous_stock.get(item.item_id, 10))
		_stock_controls[item.item_id] = amount
	if _recipe != null:
		display_recipe(_recipe)


func display_recipe(recipe: AlchemyRecipe) -> void:
	if not is_node_ready():
		await ready
	if recipe == null or _catalog == null:
		clear_preview()
		return
	var keep_selection := _recipe != null and _recipe.recipe_id == recipe.recipe_id and _selection.size() == recipe.ingredients.size()
	_recipe = recipe
	if not keep_selection:
		_selection.clear()
		for requirement in recipe.ingredients:
			_selection.append({})
	_renew_preview_inventory()
	var system := AlchemySystem.new(_preview_inventory)
	_player.get_node("Icon").texture = recipe.icon
	_player.get_node("Name").text = recipe.display_name
	_player.get_node("Description").text = recipe.description
	var public_slots: Array[Dictionary] = []
	_clear_children(_player.get_node("Slots"))
	for index in recipe.ingredients.size():
		var requirement := recipe.ingredients[index]
		if requirement == null:
			continue
		var public_data := recipe.get_slot_display(index, _catalog)
		public_slots.append(public_data.duplicate())
		var slot := SLOT_SCENE.instantiate() as IngredientSlotUI
		_player.get_node("Slots").add_child(slot)
		slot.display(requirement, {}, _preview_inventory, system, false, public_data, recipe.is_hidden_slot(index))
		# These are presentation components. Selection is edited in the trial tab.
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.focus_mode = Control.FOCUS_NONE
	_public_preview = {"name": recipe.display_name, "description": recipe.description, "icon": recipe.icon, "slots": public_slots}
	_tabs.set_tab_disabled(1, false)
	_rebuild_trial_rows()


func display_item(item: ItemData) -> void:
	if item == null:
		clear_preview()
		return
	if item.alchemy_recipe != null and _catalog != null:
		display_recipe(item.alchemy_recipe)
		_player.get_node("Icon").texture = item.icon
		_player.get_node("Name").text = item.display_name
		_player.get_node("Description").text = item.description
		_public_preview["name"] = item.display_name
		_public_preview["description"] = item.description
		_public_preview["icon"] = item.icon
		return
	clear_preview()
	_player.get_node("Icon").texture = item.icon
	_player.get_node("Name").text = item.display_name
	_player.get_node("Description").text = item.description
	_public_preview = {"name": item.display_name, "description": item.description, "icon": item.icon, "slots": []}


func clear_preview() -> void:
	_recipe = null
	_selection.clear()
	_public_preview.clear()
	if not is_node_ready():
		return
	_player.get_node("Icon").texture = null
	_player.get_node("Name").text = "请选择配置"
	_player.get_node("Description").text = ""
	_clear_children(_player.get_node("Slots"))
	_clear_children(_trial_rows)
	_selection_rows.clear()
	_tabs.set_tab_disabled(1, true)
	_tabs.current_tab = 0
	_result.text = "选择配方后可以进行炼金验证。"


func get_public_preview() -> Dictionary:
	return _public_preview.duplicate(true)


func get_trial_stock() -> Dictionary:
	var stock: Dictionary = {}
	for id in _stock_controls:
		var control: SpinBox = _stock_controls[id]
		if is_instance_valid(control) and int(control.value) > 0:
			stock[id] = int(control.value)
	return stock


func set_trial_stock(stock: Dictionary) -> void:
	for id in _stock_controls:
		_stock_controls[id].value = int(stock.get(id, 0))


func set_trial_selection(selection: Array[Dictionary]) -> void:
	_selection = selection.duplicate(true)
	_refresh_selected_labels()


## Every run starts from the configured snapshot and calls the game's core system.
func run_trial() -> Dictionary:
	if _recipe == null or _catalog == null:
		return {"ok": false, "error": "请先选择配方。"}
	var inventory := InventorySystem.new()
	inventory.catalog = _catalog
	var before := get_trial_stock()
	var restored := inventory.restore_save_state({"capacity": 999, "items": before}, false)
	var system := AlchemySystem.new(inventory)
	var validation := system.validate(_recipe, _selection) if restored.ok else restored
	var result := system.synthesize(_recipe, _selection) if validation.ok else validation.duplicate()
	result["before"] = before.duplicate()
	result["after"] = inventory.get_items()
	result["costs"] = validation.get("costs", {}).duplicate()
	var lines := PackedStringArray()
	if result.ok:
		var item := _catalog.find_item(result.item_id)
		var outcome_name := {&"base": "A · 基础成品", &"advanced": "B · 高级成品", &"waste": "X · 异质"}.get(result.outcome, "成品")
		lines.append("验证通过：%s" % outcome_name)
		lines.append("获得：%s ×%d" % [item.display_name, result.amount])
		lines.append("扣除：%s" % _describe_stock(result.costs))
	else:
		lines.append("验证失败：%s" % result.error)
		lines.append("未扣除任何素材。")
	lines.append("剩余：%s" % _describe_stock(result.after))
	_result.text = "\n".join(lines)
	inventory.free()
	return result


func _renew_preview_inventory() -> void:
	if is_instance_valid(_preview_inventory):
		_preview_inventory.free()
	_preview_inventory = InventorySystem.new()
	_preview_inventory.catalog = _catalog


func _rebuild_trial_rows() -> void:
	_clear_children(_trial_rows)
	_selection_rows.clear()
	for index in _recipe.ingredients.size():
		var row := $Templates/SelectionRow.duplicate() as VBoxContainer
		_trial_rows.add_child(row)
		row.show()
		_selection_rows.append(row)
		var requirement := _recipe.ingredients[index]
		var public_data := _recipe.get_slot_display(index, _catalog)
		row.get_node("Name").text = "第%d槽 · %s（需要 %d）" % [index + 1, public_data.name, requirement.amount if requirement != null else 0]
		var picker := row.get_node("Material") as OptionButton
		picker.add_theme_constant_override("icon_max_width", 24)
		picker.get_popup().add_theme_constant_override("icon_max_width", 24)
		picker.add_item("请选择素材")
		picker.set_item_metadata(0, &"")
		for item in _catalog.items:
			if item != null and _recipe.accepts_material(index, item):
				picker.add_icon_item(item.icon, "%s (%s)" % [item.display_name, item.item_id])
				picker.set_item_metadata(picker.item_count - 1, item.item_id)
		row.get_node("Actions/Amount").max_value = maxi(1, requirement.amount) if requirement != null else 999
		row.get_node("Actions/Add").pressed.connect(_add_material.bind(index))
		row.get_node("Actions/Clear").pressed.connect(_clear_slot.bind(index))
	_refresh_selected_labels()


func _add_material(index: int) -> void:
	var row := _selection_rows[index]
	var picker := row.get_node("Material") as OptionButton
	var id := StringName(picker.get_selected_metadata())
	if id == &"":
		_result.text = "请先选择本槽要投入的素材。"
		return
	var inventory := InventorySystem.new()
	inventory.catalog = _catalog
	var restored := inventory.restore_save_state({"capacity": 999, "items": get_trial_stock()}, false)
	var system := AlchemySystem.new(inventory)
	var check := system.select_material(_recipe, index, _selection, id, int(row.get_node("Actions/Amount").value)) if restored.ok else restored
	_result.text = "已记录投入；起始库存将在执行炼金验证时扣除。" if check.ok else check.error
	inventory.free()
	_refresh_selected_labels()


func _clear_slot(index: int) -> void:
	if index >= 0 and index < _selection.size():
		_selection[index].clear()
	_refresh_selected_labels()


func _clear_selection() -> void:
	for selected in _selection:
		selected.clear()
	_refresh_selected_labels()


func _reset_stock() -> void:
	for control in _stock_controls.values():
		control.value = 10


func _toggle_stock(expanded: bool) -> void:
	_stock_rows.visible = expanded
	$Tabs/Trial/Content/ResetStock.visible = expanded


func _refresh_selected_labels() -> void:
	for index in mini(_selection_rows.size(), _selection.size()):
		_selection_rows[index].get_node("Selected").text = "已投入：%s" % _describe_stock(_selection[index])


func _describe_stock(stock: Dictionary) -> String:
	var entries := PackedStringArray()
	for id in stock:
		var item := _catalog.find_item(StringName(id)) if _catalog != null else null
		entries.append("%s ×%d" % [item.display_name if item != null else str(id), stock[id]])
	return "、".join(entries) if not entries.is_empty() else "无"


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

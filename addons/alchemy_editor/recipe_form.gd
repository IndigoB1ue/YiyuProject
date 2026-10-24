@tool
extends VBoxContainer

signal changed
signal create_item_requested(field: String)

const INGREDIENT_FORM = preload("res://addons/alchemy_editor/ingredient_form.tscn")
var _items: ItemCatalog
var _categories: Array[ItemCategory] = []
var _recipes: Array[AlchemyRecipe] = []
var _draft: AlchemyRecipe
var _is_new := false
var _updating := false
var _picker_field := ""
var _slot_forms: Array[Control] = []


func _ready() -> void:
	%RecipeID.text_changed.connect(func(text):
		if not _updating and _draft != null:
			_draft.recipe_id = StringName(text); _changed())
	%DisplayName.text_changed.connect(func(text):
		if not _updating and _draft != null:
			_draft.display_name = text; _changed())
	%Description.text_changed.connect(func():
		if not _updating and _draft != null:
			_draft.description = %Description.text; _changed())
	%DesignerNotes.text_changed.connect(func():
		if not _updating and _draft != null:
			_draft.designer_notes = %DesignerNotes.text; _changed())
	%Icon.changed.connect(func():
		if not _updating and _draft != null:
			_draft.icon = %Icon.texture; _changed())
	%Mode.item_selected.connect(_on_mode_selected)
	%AdvancedCount.item_selected.connect(_on_advanced_selected)
	%AdvancedConfirm.confirmed.connect(func(): _apply_advanced_count(3))
	%AdvancedConfirm.canceled.connect(func(): %AdvancedCount.select(1))
	%ModeConfirm.confirmed.connect(func(): _apply_mode(AlchemyRecipe.FormulaMode.EXPERIMENTAL))
	%ModeConfirm.canceled.connect(func(): %Mode.select(0))
	%PickA.pressed.connect(func(): _pick_item("result_item_id"))
	%PickB.pressed.connect(func(): _pick_item("advanced_result_item_id"))
	%NewA.pressed.connect(func(): create_item_requested.emit("result_item_id"))
	%NewB.pressed.connect(func(): create_item_requested.emit("advanced_result_item_id"))
	%AmountA.value_changed.connect(func(value):
		if not _updating and _draft != null:
			_draft.result_amount = int(value); _changed())
	%AmountB.value_changed.connect(func(value):
		if not _updating and _draft != null:
			_draft.advanced_result_amount = int(value); _changed())
	%AmountX.value_changed.connect(func(value):
		if not _updating and _draft != null:
			_draft.waste_result_amount = int(value); _changed())
	%Picker.item_chosen.connect(func(id): set_item_for_field(_picker_field, id))
	%AddIngredient.pressed.connect(func():
		if _draft != null:
			_draft.ingredients.append(IngredientRequirement.new()); _rebuild_slots(); _changed())
	%RemoveIngredient.pressed.connect(func():
		if _draft != null and not _draft.ingredients.is_empty():
			_draft.ingredients.pop_back(); _rebuild_slots(); _changed())
	_refresh()


func bind_data(items: ItemCatalog, categories: Array[ItemCategory], recipes: Array[AlchemyRecipe]) -> void:
	_items = items
	_categories = categories
	_recipes = recipes
	if is_node_ready():
		_refresh()


func edit_resource(recipe: AlchemyRecipe, is_new: bool) -> void:
	_draft = recipe.duplicate(true) if recipe != null else AlchemyRecipe.new()
	_is_new = is_new
	if is_node_ready():
		_refresh()


func get_resource() -> AlchemyRecipe:
	return _draft


func focus_field(field: String) -> void:
	var index := _field_index(field)
	if index >= 0 and index < _slot_forms.size():
		_slot_forms[index].focus_field(field)
		return
	if field.contains("recipe_id"):
		%RecipeID.grab_focus()
	elif field.contains("advanced_result"):
		%PickB.grab_focus()
	elif field.contains("result"):
		%PickA.grab_focus()
	elif field.contains("description"):
		%Description.grab_focus()
	else:
		%DisplayName.grab_focus()


func set_item_for_field(field: String, item_id: StringName) -> void:
	if _draft == null:
		return
	var index := _field_index(field)
	if index >= 0 and index < _slot_forms.size():
		_slot_forms[index].set_item_id(item_id)
		return
	if field == "advanced_result_item_id":
		_draft.advanced_result_item_id = item_id
	elif field == "result_item_id":
		_draft.result_item_id = item_id
	_refresh_item_buttons()
	_changed()


func _field_index(field: String) -> int:
	if not field.contains("ingredient") and not field.contains("slot"):
		return -1
	var regex := RegEx.new()
	regex.compile("[0-9]+")
	var found := regex.search(field)
	return int(found.get_string()) if found != null else -1


func _refresh() -> void:
	if _draft == null:
		return
	_updating = true
	%RecipeID.text = _draft.recipe_id
	%RecipeID.editable = _is_new
	%RecipeID.tooltip_text = "已有配方的 RecipeID 保持稳定；修改显示名称不会改变 ID。" if not _is_new else "保存前可以调整；保存后保持稳定。"
	%DisplayName.text = _draft.display_name
	%Description.text = _draft.description
	%DesignerNotes.text = _draft.designer_notes
	%Icon.texture = _draft.icon
	%Mode.select(int(_draft.formula_mode))
	%AdvancedCount.select(0 if _draft.advanced_slot_count == 3 else 1)
	%Experimental.visible = _draft.is_experimental()
	%StandardControls.visible = not _draft.is_experimental()
	%AmountA.value = _draft.result_amount
	%AmountB.value = _draft.advanced_result_amount
	%AmountX.value = _draft.waste_result_amount
	var waste := _items.find_item(_items.alchemy_waste_item_id) if _items != null else null
	%WasteName.text = "%s [%s]（全局统一）" % [waste.display_name, waste.item_id] if waste != null else "请在通用配置中指定异质物品"
	_refresh_item_buttons()
	_rebuild_slots()
	_updating = false
	_refresh_summary()


func _refresh_item_buttons() -> void:
	_set_item_button(%PickA, _draft.result_item_id)
	_set_item_button(%PickB, _draft.advanced_result_item_id)


func _set_item_button(button: Button, item_id: StringName) -> void:
	var item := _items.find_item(item_id) if _items != null else null
	button.text = "%s [%s]" % [item.display_name, item_id] if item != null else ("选择物品…" if item_id == &"" else "无效物品 [%s]" % item_id)
	button.icon = item.icon if item != null else null


func _rebuild_slots() -> void:
	for child in _slot_forms:
		%Ingredients.remove_child(child)
		child.queue_free()
	_slot_forms.clear()
	for index in _draft.ingredients.size():
		var form := INGREDIENT_FORM.instantiate()
		%Ingredients.add_child(form)
		form.bind_data(_items, _categories)
		form.edit_requirement(_draft.ingredients[index], index, _draft.is_hidden_slot(index), _draft.is_experimental() and _draft.advanced_slot_count == 3 and index == 3, _draft.is_experimental())
		_draft.ingredients[index] = form.get_resource()
		form.changed.connect(func(): _draft.ingredients[index] = form.get_resource(); _changed())
		form.create_item_requested.connect(func(): create_item_requested.emit("ingredient_%d" % index))
		_slot_forms.append(form)


func _pick_item(field: String) -> void:
	_picker_field = field
	%Picker.open_picker(_items, _draft.get(field))


func _on_mode_selected(index: int) -> void:
	if _updating or _draft == null or index == int(_draft.formula_mode):
		return
	if index == AlchemyRecipe.FormulaMode.EXPERIMENTAL and _draft.ingredients.size() > 4:
		%ModeConfirm.popup_centered()
		return
	_apply_mode(index)


func _apply_mode(value: int) -> void:
	_draft.formula_mode = value
	if _draft.is_experimental():
		while _draft.ingredients.size() < 4:
			_draft.ingredients.append(IngredientRequirement.new())
		_draft.ingredients.resize(4)
		for index in 4:
			if _draft.ingredients[index] == null:
				_draft.ingredients[index] = IngredientRequirement.new()
		if _draft.advanced_slot_count == 3:
			_draft.ingredients[3].item_id = &""
	_refresh()
	_changed()


func _on_advanced_selected(index: int) -> void:
	if _updating or _draft == null:
		return
	var count := index + 3
	if count == 3 and _draft.advanced_slot_count == 4:
		%AdvancedConfirm.popup_centered()
		return
	_apply_advanced_count(count)


func _apply_advanced_count(count: int) -> void:
	_draft.advanced_slot_count = count
	if count == 3 and _draft.ingredients.size() > 3 and _draft.ingredients[3] != null:
		_draft.ingredients[3].item_id = &""
		_draft.ingredients[3].candidate_category = &""
	_refresh()
	_changed()


func _changed() -> void:
	_refresh_summary()
	changed.emit()


func _item_name(item_id: StringName) -> String:
	var item := _items.find_item(item_id) if _items != null else null
	return item.display_name if item != null else ("未配置" if item_id == &"" else str(item_id))


func _formula(count: int) -> String:
	var parts := PackedStringArray()
	for index in mini(count, _draft.ingredients.size()):
		var requirement := _draft.ingredients[index]
		parts.append("%s×%d" % [_item_name(requirement.item_id), requirement.amount] if requirement != null else "无效槽")
	return " ＋ ".join(parts)


func _refresh_summary() -> void:
	if _draft == null:
		return
	var base_count := 2 if _draft.is_experimental() else _draft.ingredients.size()
	var summary := "基础：%s → %s×%d" % [_formula(base_count), _item_name(_draft.result_item_id), _draft.result_amount]
	if _draft.is_experimental():
		summary += "\n高级：%s → %s×%d\n其他合法追加尝试 → 异质×%d\n所有实际投入素材均消耗。此处为策划视图，玩家预览不显示隐藏答案。" % [_formula(_draft.advanced_slot_count), _item_name(_draft.advanced_result_item_id), _draft.advanced_result_amount, _draft.waste_result_amount]
	%Summary.text = summary

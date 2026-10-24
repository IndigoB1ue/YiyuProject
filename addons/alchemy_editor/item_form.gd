@tool
extends VBoxContainer

signal changed

var _items: ItemCatalog
var _categories: Array[ItemCategory] = []
var _recipes: Array[AlchemyRecipe] = []
var _draft: ItemData
var _is_new := false
var _updating := false


func _ready() -> void:
	%ItemID.text_changed.connect(func(text):
		if not _updating and _draft != null:
			_draft.item_id = StringName(text); changed.emit())
	%DisplayName.text_changed.connect(func(text):
		if not _updating and _draft != null:
			_draft.display_name = text; changed.emit())
	%Description.text_changed.connect(func():
		if not _updating and _draft != null:
			_draft.description = %Description.text; changed.emit())
	%Icon.changed.connect(func():
		if not _updating and _draft != null:
			_draft.icon = %Icon.texture; changed.emit())
	%Category.item_selected.connect(func(index):
		if not _updating and _draft != null:
			_draft.category = %Category.get_item_metadata(index); changed.emit())
	%Recipe.item_selected.connect(func(index):
		if not _updating and _draft != null:
			_draft.alchemy_recipe = %Recipe.get_item_metadata(index)
			%RecipeNote.text = _recipe_note()
			changed.emit())
	_refresh()


func bind_data(items: ItemCatalog, categories: Array[ItemCategory], recipes: Array[AlchemyRecipe]) -> void:
	_items = items
	_categories = categories
	_recipes = recipes
	if is_node_ready():
		_refresh()


func edit_resource(item: ItemData, is_new: bool) -> void:
	_draft = item.duplicate(true) if item != null else ItemData.new()
	# A recipe item must keep the shared recipe resource, not a cloned formula.
	if item != null:
		_draft.alchemy_recipe = item.alchemy_recipe
	_is_new = is_new
	if is_node_ready():
		_refresh()


func get_resource() -> ItemData:
	return _draft


func focus_field(field: String) -> void:
	if field.contains("item_id"):
		%ItemID.grab_focus()
	elif field.contains("category"):
		%Category.grab_focus()
	elif field.contains("recipe"):
		%Recipe.grab_focus()
	elif field.contains("description"):
		%Description.grab_focus()
	else:
		%DisplayName.grab_focus()


func _refresh() -> void:
	if _draft == null:
		return
	_updating = true
	%ItemID.text = _draft.item_id
	%ItemID.editable = _is_new
	%DisplayName.text = _draft.display_name
	%Description.text = _draft.description
	%Icon.texture = _draft.icon
	%Category.clear()
	%Category.add_item("未分类")
	%Category.set_item_metadata(0, &"")
	var found := _draft.category == &""
	for category in _categories:
		if category == null:
			continue
		%Category.add_icon_item(category.icon, "%s [%s]" % [category.display_name, category.category_id])
		var index: int = %Category.item_count - 1
		%Category.set_item_metadata(index, category.category_id)
		if category.category_id == _draft.category:
			%Category.select(index)
			found = true
	if not found:
		%Category.add_item("未登记类型 [%s]" % _draft.category)
		%Category.set_item_metadata(%Category.item_count - 1, _draft.category)
		%Category.select(%Category.item_count - 1)
	%Recipe.clear()
	%Recipe.add_item("普通物品 / 素材（不关联配方）")
	%Recipe.set_item_metadata(0, null)
	var recipe_found := _draft.alchemy_recipe == null
	for recipe in _recipes:
		if recipe == null:
			continue
		%Recipe.add_icon_item(recipe.icon, "%s [%s]" % [recipe.display_name, recipe.recipe_id])
		var index: int = %Recipe.item_count - 1
		%Recipe.set_item_metadata(index, recipe)
		if _draft.alchemy_recipe != null and recipe.recipe_id == _draft.alchemy_recipe.recipe_id:
			%Recipe.select(index)
			recipe_found = true
	if not recipe_found:
		%Recipe.add_item("未登记配方 [%s]" % _draft.alchemy_recipe.recipe_id)
		%Recipe.set_item_metadata(%Recipe.item_count - 1, _draft.alchemy_recipe)
		%Recipe.select(%Recipe.item_count - 1)
	%RecipeNote.text = _recipe_note()
	_updating = false


func _recipe_note() -> String:
	return "该物品为配方道具：获得方式仍由剧情或房间配置；不会作为推理炼金素材。" if _draft.alchemy_recipe != null else "普通物品可作为素材或炼金成品。初始背包数量请在 data/items/catalog.tres 的 Inspector 中修改 initial_inventory。"

class_name AlchemySystem
extends RefCounted

var inventory: InventorySystem

func _init(player_inventory: InventorySystem) -> void:
	inventory = player_inventory

func check_recipe(recipe: AlchemyRecipe) -> Dictionary:
	if recipe == null or recipe.recipe_id == &"" or recipe.ingredients.is_empty():
		return _error("配方无效：缺少 RecipeID 或素材需求。")
	if inventory.get_item(recipe.result_item_id) == null or recipe.result_amount <= 0:
		return _error("成品 ItemID 无效或数量不合法：%s" % recipe.result_item_id)
	for requirement in recipe.ingredients:
		if requirement == null or requirement.amount <= 0:
			return _error("配方的素材需求无效。")
		if requirement.item_id != &"":
			if inventory.get_item(requirement.item_id) == null:
				return _error("素材 ItemID 无效：%s" % requirement.item_id)
		elif requirement.category == &"":
			return _error("素材需求缺少 ItemID 或分类。")
	return {"ok": true, "error": ""}

## Check stock before opening alchemy; this does not select or consume materials.
func check_material_availability(recipe: AlchemyRecipe) -> Dictionary:
	var recipe_check := check_recipe(recipe)
	if not recipe_check.ok:
		return recipe_check
	var required_items: Dictionary = {}
	var required_categories: Dictionary = {}
	for requirement in recipe.ingredients:
		if requirement.item_id != &"":
			required_items[requirement.item_id] = int(required_items.get(requirement.item_id, 0)) + requirement.amount
		else:
			required_categories[requirement.category] = int(required_categories.get(requirement.category, 0)) + requirement.amount
	var shortages: PackedStringArray = []
	for id in required_items:
		var needed := int(required_items[id])
		var available := inventory.get_amount(id)
		if available < needed:
			shortages.append("%s：需要 %d，现有 %d，还缺 %d。" % [inventory.get_item(id).display_name, needed, available, needed - available])
	# Reserve exact ItemID requirements before checking category totals.
	for category in required_categories:
		var available := 0
		for id in inventory.get_items():
			if inventory.get_item(id).category == category:
				available += maxi(0, inventory.get_amount(id) - int(required_items.get(id, 0)))
		var needed := int(required_categories[category])
		if available < needed:
			shortages.append("%s 类素材：需要 %d，现有可用 %d，还缺 %d。" % [category, needed, available, needed - available])
	if not shortages.is_empty():
		return _error("素材不足：\n" + "\n".join(shortages))
	return {"ok": true, "error": ""}

func create_selection(recipe: AlchemyRecipe) -> Array[Dictionary]:
	var selection: Array[Dictionary] = []
	for requirement in recipe.ingredients:
		selection.append({})
	return selection

func selected_amount(slot: Dictionary) -> int:
	var total := 0
	for amount in slot.values():
		total += int(amount)
	return total

func _reserved(selection: Array[Dictionary]) -> Dictionary:
	var reserved: Dictionary = {}
	for slot in selection:
		for id in slot:
			reserved[id] = int(reserved.get(id, 0)) + int(slot[id])
	return reserved

func candidates(recipe: AlchemyRecipe, slot_index: int, selection: Array[Dictionary]) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not check_recipe(recipe).ok or slot_index < 0 or slot_index >= recipe.ingredients.size() or selection.size() != recipe.ingredients.size():
		return options
	var reserved := _reserved(selection)
	for id in inventory.get_items():
		var item := inventory.get_item(StringName(id))
		var available := inventory.get_amount(StringName(id)) - int(reserved.get(id, 0))
		if recipe.ingredients[slot_index].accepts(item) and available > 0:
			options.append({"item": item, "amount": available})
	return options

func select_material(recipe: AlchemyRecipe, slot_index: int, selection: Array[Dictionary], item_id: StringName, amount: int) -> Dictionary:
	var recipe_check := check_recipe(recipe)
	if not recipe_check.ok:
		return recipe_check
	if selection.size() != recipe.ingredients.size() or slot_index < 0 or slot_index >= selection.size() or amount <= 0:
		return _error("素材槽或选择数量无效。")
	var requirement := recipe.ingredients[slot_index]
	if not requirement.accepts(inventory.get_item(item_id)):
		return _error("所选物品不符合当前素材需求。")
	if selected_amount(selection[slot_index]) + amount > requirement.amount:
		return _error("选择数量超出当前素材槽需求。")
	var reserved := _reserved(selection)
	if inventory.get_amount(item_id) - int(reserved.get(item_id, 0)) < amount:
		return _error("可用素材不足，背包可能已经发生变化。")
	selection[slot_index][item_id] = int(selection[slot_index].get(item_id, 0)) + amount
	return {"ok": true, "error": ""}

func validate(recipe: AlchemyRecipe, selection: Array[Dictionary]) -> Dictionary:
	var recipe_check := check_recipe(recipe)
	if not recipe_check.ok:
		return recipe_check
	if selection.size() != recipe.ingredients.size():
		return _error("素材槽数量与配方不一致。")
	for index in selection.size():
		var requirement := recipe.ingredients[index]
		for id in selection[index]:
			if not selection[index][id] is int or selection[index][id] <= 0:
				return _error("所选素材数量必须是正整数。")
			if not requirement.accepts(inventory.get_item(StringName(id))):
				return _error("素材 ItemID 无效或不符合配方：%s" % id)
		if selected_amount(selection[index]) != requirement.amount:
			return _error("请先选择足够的素材（素材槽 %d）。" % (index + 1))
	var costs := _reserved(selection)
	for id in costs:
		if inventory.get_amount(StringName(id)) < costs[id]:
			return _error("%s 数量不足：需要 %d，背包剩余 %d。" % [inventory.get_item(StringName(id)).display_name, costs[id], inventory.get_amount(StringName(id))])
	return {"ok": true, "error": "", "costs": costs}

func synthesize(recipe: AlchemyRecipe, selection: Array[Dictionary]) -> Dictionary:
	var validation := validate(recipe, selection)
	if not validation.ok:
		return validation
	var result := inventory.exchange(validation.costs, recipe.result_item_id, recipe.result_amount)
	if result.ok:
		result["item_id"] = recipe.result_item_id
		result["amount"] = recipe.result_amount
	return result

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

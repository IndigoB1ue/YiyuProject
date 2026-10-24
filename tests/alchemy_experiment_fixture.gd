extends RefCounted


static func recipe(advanced_slots: int = 3) -> AlchemyRecipe:
	var result := AlchemyRecipe.new()
	result.recipe_id = StringName("TestExperiment%d" % advanced_slots)
	result.display_name = "测试推理配方"
	result.description = "从叙事中寻找追加素材。"
	result.formula_mode = AlchemyRecipe.FormulaMode.EXPERIMENTAL
	result.result_item_id = &"BasePotion"
	result.advanced_result_item_id = &"AdvancedPotion"
	result.advanced_result_amount = 2
	result.advanced_slot_count = advanced_slots
	result.waste_result_amount = 2 if advanced_slots == 4 else 1
	for index in 4:
		var requirement := IngredientRequirement.new()
		requirement.amount = 2 if index in [0, 2] else 1
		result.ingredients.append(requirement)
	result.ingredients[0].item_id = &"BaseHerb"
	result.ingredients[1].item_id = &"BaseWater"
	result.ingredients[2].item_id = &"SecretLeaf"
	result.ingredients[2].hint_name = "植物"
	result.ingredients[2].hint_icon = load("res://asserts/image/icon/category_plant.svg")
	result.ingredients[2].candidate_category = &"Plant"
	if advanced_slots == 4:
		result.ingredients[3].item_id = &"SecretOre"
		result.ingredients[3].hint_name = "矿物"
		result.ingredients[3].hint_icon = load("res://asserts/image/icon/category_mineral.svg")
		result.ingredients[3].candidate_category = &"Mineral"
	return result


static func catalog(formula: AlchemyRecipe) -> ItemCatalog:
	var result := ItemCatalog.new()
	for definition in [
		[&"BaseHerb", "基础药草", &"Plant"], [&"BaseWater", "基础清水", &"Liquid"],
		[&"SecretLeaf", "隐藏答案叶", &"Plant"], [&"WrongLeaf", "其他植物", &"Plant"],
		[&"SecretOre", "隐藏答案矿", &"Mineral"], [&"WrongOre", "其他矿物", &"Mineral"],
		[&"BasePotion", "基础成品", &""], [&"AdvancedPotion", "高级成品", &""],
		[&"Heterogeneity", "异质", &""]]:
		var item := ItemData.new()
		item.item_id = definition[0]
		item.display_name = definition[1]
		item.category = definition[2]
		item.description = "测试物品说明"
		item.icon = load("res://asserts/image/icon/ingredient/water.svg")
		result.items.append(item)
	var book := ItemData.new()
	book.item_id = &"RecipeBook"
	book.display_name = "测试配方道具"
	book.alchemy_recipe = formula
	result.items.append(book)
	return result


static func inventory(formula: AlchemyRecipe) -> InventorySystem:
	var result := InventorySystem.new()
	result.catalog = catalog(formula)
	for id in [&"BaseHerb", &"BaseWater", &"SecretLeaf", &"WrongLeaf", &"SecretOre", &"WrongOre"]:
		result.add_item(id, 10)
	result.add_item(&"RecipeBook", 1)
	return result


static func base_selection(system: AlchemySystem, formula: AlchemyRecipe) -> Array[Dictionary]:
	var selection := system.create_selection(formula)
	system.select_material(formula, 0, selection, &"BaseHerb", 2)
	system.select_material(formula, 1, selection, &"BaseWater", 1)
	return selection

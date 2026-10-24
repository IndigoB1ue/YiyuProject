extends SceneTree

const STORE := preload("res://addons/alchemy_editor/resource_store.gd")
const PICKER := preload("res://addons/alchemy_editor/item_picker.tscn")
const ICON := preload("res://asserts/image/icon/ingredient/herb.svg")
const TYPE_ICON := preload("res://asserts/image/icon/category_plant.svg")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _recipe(id: StringName = &"SourceRecipe") -> AlchemyRecipe:
	var recipe := AlchemyRecipe.new()
	recipe.recipe_id = id
	recipe.display_name = String(id)
	recipe.icon = ICON
	recipe.designer_notes = "产物继续作为素材的隔离回归测试。"
	recipe.formula_mode = AlchemyRecipe.FormulaMode.EXPERIMENTAL
	recipe.advanced_slot_count = 3
	recipe.result_item_id = &"OutputA"
	recipe.result_amount = 2
	recipe.advanced_result_item_id = &"OutputB"
	recipe.advanced_result_amount = 2
	recipe.waste_result_amount = 3
	for item_id in [&"Feed", &"Water", &"SecretLeaf", &""]:
		var requirement := IngredientRequirement.new()
		requirement.item_id = item_id
		requirement.amount = 1
		recipe.ingredients.append(requirement)
	recipe.ingredients[2].hint_name = "植物"
	recipe.ingredients[2].hint_icon = TYPE_ICON
	recipe.ingredients[2].candidate_category = &"Plant"
	return recipe


func _catalog(source: AlchemyRecipe) -> ItemCatalog:
	var catalog := ItemCatalog.new()
	var category := ItemCategory.new()
	category.category_id = &"Plant"
	category.display_name = "植物"
	category.icon = TYPE_ICON
	catalog.categories.append(category)
	catalog.alchemy_waste_item_id = &"Waste"
	for id in [&"Feed", &"Water", &"SecretLeaf", &"WrongLeaf", &"OutputA", &"OutputB", &"Waste", &"NextA", &"NextB"]:
		var item := ItemData.new()
		item.item_id = id
		item.display_name = "异质" if id == &"Waste" else String(id)
		item.icon = ICON
		item.category = &"Plant" if id in [&"Feed", &"SecretLeaf", &"WrongLeaf", &"OutputA", &"OutputB"] else &""
		catalog.items.append(item)
	var book := ItemData.new()
	book.item_id = &"RecipeBook"
	book.display_name = "配方道具"
	book.icon = ICON
	book.category = &"Plant"
	book.alchemy_recipe = source
	catalog.items.append(book)
	return catalog


func _inventory(catalog: ItemCatalog) -> InventorySystem:
	var inventory := InventorySystem.new()
	inventory.catalog = catalog
	for id in [&"Feed", &"Water", &"SecretLeaf", &"WrongLeaf"]:
		_expect(inventory.add_item(id, 10).ok, "Fixture can seed ordinary materials")
	_expect(inventory.add_item(&"RecipeBook", 1).ok, "Fixture can own a recipe book without treating it as a material")
	return inventory


func _base(system: AlchemySystem, recipe: AlchemyRecipe) -> Array[Dictionary]:
	var selection := system.create_selection(recipe)
	for index in 2:
		var requirement := recipe.ingredients[index]
		_expect(system.select_material(recipe, index, selection, requirement.item_id, requirement.amount).ok, "Base selection accepts %s" % requirement.item_id)
	return selection


func _produce(system: AlchemySystem, source: AlchemyRecipe, outcome: StringName) -> Dictionary:
	var selection := _base(system, source)
	if outcome != &"base":
		var id := &"SecretLeaf" if outcome == &"advanced" else &"WrongLeaf"
		_expect(system.select_material(source, 2, selection, id, 1).ok, "Source accepts a legal additional attempt")
	var result := system.synthesize(source, selection)
	_expect(result.ok and result.get("outcome") == outcome, "Source actually synthesizes the requested %s output" % outcome)
	return result


func _errors(issues: Array[Dictionary]) -> PackedStringArray:
	var errors := PackedStringArray()
	for issue in issues:
		if issue.get("severity", "error") == "error":
			errors.append(issue.message)
	return errors


func _validate_editor_recipe(catalog: ItemCatalog, source: AlchemyRecipe, next: AlchemyRecipe) -> void:
	var store := STORE.new()
	store.items = catalog
	store.recipes = AlchemyCatalog.new()
	store.recipes.recipes = [source]
	var errors := _errors(store.validate_recipe(next))
	_expect(errors.is_empty(), "Editor validation accepts an ordinary produced item as an ingredient: %s" % "; ".join(errors))


func _base_output_chains(source: AlchemyRecipe, catalog: ItemCatalog) -> void:
	for outcome: StringName in [&"base", &"advanced", &"waste"]:
		var inventory := _inventory(catalog)
		var system := AlchemySystem.new(inventory)
		var produced := _produce(system, source, outcome)
		if not produced.ok:
			inventory.free()
			continue
		var output_id := StringName(produced.item_id)
		_expect(inventory.get_amount(output_id) == produced.amount, "Synthesized %s enters the same inventory" % outcome)
		var next := _recipe(StringName("Consume_" + String(outcome)))
		next.result_item_id = &"NextA"
		next.advanced_result_item_id = &"NextB"
		next.ingredients[0].item_id = output_id
		next.ingredients[0].amount = produced.amount
		_validate_editor_recipe(catalog, source, next)
		var selection := _base(system, next)
		var validation := system.validate(next, selection)
		_expect(validation.ok and validation.get("costs", {}).get(output_id) == produced.amount, "Next recipe accounts for the produced %s stack in its transaction" % outcome)
		var result := system.synthesize(next, selection)
		_expect(result.ok and result.get("item_id") == &"NextA", "Produced %s can synthesize a later recipe's result" % outcome)
		_expect(inventory.get_amount(output_id) == 0 and inventory.get_amount(&"NextA") == next.result_amount, "Later recipe consumes all actual %s output and adds its own product" % outcome)
		_expect(inventory.get_amount(&"Feed") == 9 and inventory.get_amount(&"Water") == 8, "A two-recipe chain consumes only the specified ordinary inputs")
		inventory.free()


func _hidden_output_chain(source: AlchemyRecipe, catalog: ItemCatalog) -> void:
	var inventory := _inventory(catalog)
	var system := AlchemySystem.new(inventory)
	_produce(system, source, &"base")
	_produce(system, source, &"advanced")
	var next := _recipe(&"HiddenOutputRecipe")
	next.result_item_id = &"NextA"
	next.advanced_result_item_id = &"NextB"
	next.ingredients[2].item_id = &"OutputB"
	next.ingredients[2].amount = 2
	_validate_editor_recipe(catalog, source, next)
	var selection := _base(system, next)
	var candidates: Array[StringName] = []
	for candidate in system.candidates(next, 2, selection):
		candidates.append(candidate.item.item_id)
	_expect(candidates.has(&"OutputB") and candidates.has(&"OutputA") and candidates.has(&"WrongLeaf"), "Typed hidden candidates include produced B and wrong items of the same type")
	_expect(not candidates.has(&"Water") and not candidates.has(&"RecipeBook"), "Typed hidden candidates exclude unrelated types and recipe books")
	_expect(system.select_material(next, 2, selection, &"OutputB", 2).ok, "A produced B stack can fill a matching typed hidden slot")
	var correct := system.synthesize(next, selection)
	_expect(correct.ok and correct.get("outcome") == &"advanced" and inventory.get_amount(&"OutputB") == 0, "Correct produced hidden answer yields B and is consumed")
	selection = _base(system, next)
	_expect(system.select_material(next, 2, selection, &"OutputA", 2).ok, "Wrong produced item of the same type remains a legal attempt")
	var wrong := system.synthesize(next, selection)
	_expect(wrong.ok and wrong.get("outcome") == &"waste" and inventory.get_amount(&"OutputA") == 0, "Wrong produced hidden answer yields waste and is consumed")
	inventory.free()


func _picker_outputs(catalog: ItemCatalog) -> void:
	var picker := PICKER.instantiate()
	root.add_child(picker)
	picker.open_picker(catalog, &"", true)
	for id in [&"OutputA", &"OutputB", &"Waste"]:
		_expect(picker._visible_ids.has(id), "Shared material picker includes ordinary output %s" % id)
	_expect(not picker._visible_ids.has(&"RecipeBook"), "Shared material picker excludes recipe books")
	picker.hide()
	picker.queue_free()


func _run() -> void:
	var player_inventory := root.get_node_or_null("PlayerInventory")
	var player_before: Dictionary = player_inventory.get_items() if player_inventory != null else {}
	var source := _recipe()
	var catalog := _catalog(source)
	_base_output_chains(source, catalog)
	_hidden_output_chain(source, catalog)
	_picker_outputs(catalog)
	_expect(player_inventory == null or player_inventory.get_items() == player_before, "Output reuse regression never changes the real player inventory")
	await process_frame
	print("alchemy_output_reuse_test: PASS" if _failures == 0 else "alchemy_output_reuse_test: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)

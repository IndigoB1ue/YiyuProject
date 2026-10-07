extends SceneTree

const Fixture = preload("res://tests/alchemy_test_fixture.gd")

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _filled(system: AlchemySystem, recipe: AlchemyRecipe) -> Array[Dictionary]:
	var selection := system.create_selection(recipe)
	_expect(system.select_material(recipe, 0, selection, &"Herb", 2).ok, "Select two herbs")
	_expect(system.select_material(recipe, 1, selection, &"Water", 1).ok, "Select one water")
	return selection

func _run() -> void:
	var inventory := InventorySystem.new()
	root.add_child(inventory)
	Fixture.prepare_inventory(inventory)
	var system := AlchemySystem.new(inventory)
	var recipe: AlchemyRecipe = Fixture.potion_recipe()
	_expect(inventory.get_amount(&"Herb") == 5 and inventory.get_amount(&"Water") == 3, "Initial inventory")
	_expect(system.check_material_availability(recipe).ok, "Stock check works before selecting materials")
	var selection := system.create_selection(recipe)
	_expect(not system.validate(recipe, selection).ok, "Incomplete selection must fail")
	var options := system.candidates(recipe, 0, selection)
	_expect(options.size() == 1 and options[0].item.item_id == &"Herb", "Exact ID filtering")
	_expect(not system.select_material(recipe, 0, selection, &"Water", 1).ok, "Reject mismatched material")
	_expect(not system.select_material(recipe, 0, selection, &"Herb", 3).ok, "Reject excess quantity")
	selection = _filled(system, recipe)
	_expect(inventory.get_amount(&"Herb") == 5, "Selection must not consume inventory")
	_expect(system.validate(recipe, selection).ok, "Complete selection")
	var notifications: Array[int] = []
	inventory.inventory_changed.connect(func() -> void: notifications.append(inventory.get_amount(&"Potion")))
	_expect(system.synthesize(recipe, selection).ok, "Successful synthesis")
	_expect(inventory.get_amount(&"Herb") == 3 and inventory.get_amount(&"Water") == 2 and inventory.get_amount(&"Potion") == 1, "Correct final quantities")
	_expect(notifications.size() == 1 and notifications[0] == 1, "Observers see one complete transaction")
	selection = _filled(system, recipe)
	inventory.remove_item(&"Herb", 2)
	_expect(not system.check_material_availability(recipe).ok, "Stock check detects external consumption")
	var before := inventory.get_items()
	_expect(not system.synthesize(recipe, selection).ok, "Reject externally consumed ingredients")
	_expect(inventory.get_items() == before, "Failed synthesis leaves all inventory unchanged")
	var invalid: AlchemyRecipe = recipe.duplicate(true)
	invalid.result_item_id = &"Missing"
	_expect(not system.synthesize(invalid, selection).ok, "Reject invalid output ItemID")
	_expect(inventory.get_items() == before, "Invalid output cannot consume materials")
	invalid = recipe.duplicate(true)
	invalid.ingredients[0].item_id = &"Missing"
	_expect(not system.check_recipe(invalid).ok, "Reject invalid requirement ItemID")
	_expect(not inventory.add_item(&"Missing", 1).ok, "Reject unknown inventory item")
	_expect(not inventory.remove_item(&"Water", -1).ok, "Reject negative removal")
	_expect(not inventory.exchange({&"Water": 1}, &"Missing", 1).ok, "Exchange validates output before consuming")
	_expect(inventory.get_items() == before, "Failed exchange is atomic")
	inventory.add_item(&"Herb", 2)
	var repeated: AlchemyRecipe = recipe.duplicate(true)
	repeated.ingredients[1].item_id = &"Herb"
	repeated.ingredients[1].amount = 2
	var repeated_selection := system.create_selection(repeated)
	system.select_material(repeated, 0, repeated_selection, &"Herb", 2)
	_expect(not system.select_material(repeated, 1, repeated_selection, &"Herb", 2).ok, "Reservations apply across slots")
	repeated_selection[1] = {&"Herb": 2}
	_expect(not system.validate(repeated, repeated_selection).ok, "Final check aggregates duplicate ingredients")
	_expect(not system.check_material_availability(repeated).ok, "Entry stock check aggregates duplicate ingredients")
	var category_recipe: AlchemyRecipe = recipe.duplicate(true)
	category_recipe.ingredients[0].item_id = &""
	category_recipe.ingredients[0].category = &"Herb"
	_expect(system.candidates(category_recipe, 0, system.create_selection(category_recipe)).size() == 1, "Simple category extension")
	_expect(system.check_material_availability(category_recipe).ok, "Entry stock check supports a simple category")
	var mixed: AlchemyRecipe = repeated.duplicate(true)
	mixed.ingredients[1].item_id = &""
	mixed.ingredients[1].category = &"Herb"
	_expect(not system.check_material_availability(mixed).ok, "Exact and category needs cannot reuse the same units")
	selection[0] = {&"Herb": -2}
	_expect(not system.validate(recipe, selection).ok, "Reject malformed selection")
	print("Alchemy tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	inventory.queue_free()
	quit(0 if _failures == 0 else 1)

extends SceneTree

const Fixture = preload("res://tests/alchemy_experiment_fixture.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _outcomes() -> void:
	for advanced_slots in [3, 4]:
		for third in 3:
			for fourth in 3:
				var recipe := Fixture.recipe(advanced_slots)
				var inventory := Fixture.inventory(recipe)
				var system := AlchemySystem.new(inventory)
				var selection := Fixture.base_selection(system, recipe)
				var costs := {&"BaseHerb": 2, &"BaseWater": 1}
				if third > 0:
					var id := &"SecretLeaf" if third == 1 else &"WrongLeaf"
					_expect(system.select_material(recipe, 2, selection, id, 2).ok, "A plant candidate can be used regardless of its correctness")
					costs[id] = 2
				if fourth > 0:
					var id := &"SecretOre" if fourth == 1 else &"WrongOre"
					_expect(system.select_material(recipe, 3, selection, id, 1).ok, "The fourth slot remains usable for a three-slot formula")
					costs[id] = 1
				_expect(system.validate(recipe, selection).ok, "All filled-slot combinations are submittable after the base is filled")
				var before := inventory.get_items()
				var expected_id := &"Heterogeneity"
				var expected_amount := recipe.waste_result_amount
				if third == 0 and fourth == 0:
					expected_id = &"BasePotion"
					expected_amount = 1
				elif third == 1 and ((advanced_slots == 3 and fourth == 0) or (advanced_slots == 4 and fourth == 1)):
					expected_id = &"AdvancedPotion"
					expected_amount = 2
				var notifications: Array[int] = []
				inventory.inventory_changed.connect(func() -> void: notifications.append(inventory.get_amount(expected_id)))
				var result := system.synthesize(recipe, selection)
				_expect(result.ok and result.item_id == expected_id and result.amount == expected_amount,
					"Formula %d, third %d, fourth %d produces the expected A/B/waste" % [advanced_slots, third, fourth])
				var expected := before.duplicate()
				for id in costs:
					expected[id] -= costs[id]
				expected[expected_id] = int(expected.get(expected_id, 0)) + expected_amount
				_expect(inventory.get_items() == expected, "Every actually selected unit is consumed, including wrong or extra materials")
				_expect(notifications.size() == 1 and notifications[0] == expected_amount, "Observers see one atomic completed transaction")
				inventory.free()


func _validation_and_candidates() -> void:
	var recipe := Fixture.recipe(4)
	var inventory := Fixture.inventory(recipe)
	var system := AlchemySystem.new(inventory)
	var selection := system.create_selection(recipe)
	_expect(not system.validate(recipe, selection).ok, "Empty base slots cannot synthesize")
	selection = Fixture.base_selection(system, recipe)
	var candidate_ids: Array[StringName] = []
	for entry in system.candidates(recipe, 2, selection):
		candidate_ids.append(entry.item.item_id)
	_expect(candidate_ids.has(&"SecretLeaf") and candidate_ids.has(&"WrongLeaf") and candidate_ids.has(&"BaseHerb"), "Hidden candidates include all available plants, not just the secret answer")
	_expect(not candidate_ids.has(&"SecretOre") and not candidate_ids.has(&"RecipeBook"), "Candidates obey category and exclude recipe items")
	_expect(not system.select_material(recipe, 2, selection, &"SecretOre", 2).ok, "An out-of-category item cannot be selected")
	system.select_material(recipe, 2, selection, &"SecretLeaf", 1)
	_expect(not system.validate(recipe, selection).ok, "A used additional slot still requires its configured unit quantity")
	system.select_material(recipe, 2, selection, &"WrongLeaf", 1)
	_expect(system.validate(recipe, selection).ok, "A full mixed hidden slot is a valid attempt")
	var result := system.synthesize(recipe, selection)
	_expect(result.ok and result.item_id == &"Heterogeneity", "A mixed answer produces waste rather than a partial match")

	selection = Fixture.base_selection(system, recipe)
	inventory.remove_item(&"SecretLeaf", inventory.get_amount(&"SecretLeaf"))
	inventory.remove_item(&"WrongLeaf", inventory.get_amount(&"WrongLeaf"))
	inventory.remove_item(&"SecretOre", inventory.get_amount(&"SecretOre"))
	_expect(system.check_material_availability(recipe).ok and system.validate(recipe, selection).ok, "Missing secret materials do not prevent the base formula")
	var before := inventory.get_items()
	inventory.remove_item(&"BaseWater", inventory.get_amount(&"BaseWater"))
	before = inventory.get_items()
	_expect(not system.synthesize(recipe, selection).ok and inventory.get_items() == before, "External consumption aborts without consuming other inputs")
	selection[0] = {&"BaseHerb": -1}
	_expect(not system.validate(recipe, selection).ok, "Malformed quantities are rejected")
	selection[0] = {42: 2}
	_expect(not system.validate(recipe, selection).ok, "Malformed item keys are rejected safely")
	var invalid: AlchemyRecipe = recipe.duplicate(true)
	invalid.ingredients[2].item_id = &"MissingSecret"
	_expect(not system.check_recipe(invalid).ok and not system.check_recipe(invalid).error.contains("MissingSecret"), "Invalid hidden configuration is explained without revealing its answer")
	invalid = recipe.duplicate(true)
	invalid.advanced_result_item_id = &"Missing"
	_expect(not system.synthesize(invalid, selection).ok and inventory.get_items() == before, "Invalid output configuration never consumes materials")
	invalid = recipe.duplicate(true)
	invalid.ingredients[0].item_id = &"RecipeBook"
	_expect(not system.check_recipe(invalid).ok, "A recipe book cannot be configured as an experimental base material")
	invalid = recipe.duplicate(true)
	invalid.waste_result_amount = 0
	_expect(not system.check_recipe(invalid).ok, "A recipe cannot configure a non-positive waste amount")
	inventory.free()

	var three := Fixture.recipe(3)
	inventory = Fixture.inventory(three)
	system = AlchemySystem.new(inventory)
	selection = Fixture.base_selection(system, three)
	_expect(system.select_material(three, 3, selection, &"BaseWater", 1).ok, "The unused fourth slot accepts materials from any category")
	selection[3].clear()
	_expect(not system.select_material(three, 3, selection, &"RecipeBook", 1).ok, "The unknown fourth slot still excludes recipe items")
	inventory.remove_item(&"BaseHerb", 7)
	selection[2] = {&"BaseHerb": 2}
	_expect(not system.validate(three, selection).ok, "Reservations cannot reuse base units in an additional slot")
	inventory.free()


func _capacity_and_reuse() -> void:
	for path in ["base", "advanced", "waste"]:
		var recipe := Fixture.recipe(3)
		var inventory := Fixture.inventory(recipe)
		inventory.capacity = inventory.get_occupied_slots()
		var system := AlchemySystem.new(inventory)
		var selection := Fixture.base_selection(system, recipe)
		if path != "base":
			system.select_material(recipe, 2, selection, &"SecretLeaf" if path == "advanced" else &"WrongLeaf", 2)
		var before := inventory.get_items()
		_expect(not system.synthesize(recipe, selection).ok and inventory.get_items() == before, "A full backpack aborts the %s outcome atomically" % path)
		inventory.free()
	var ultimate := Fixture.recipe(3)
	ultimate.ingredients[0].item_id = &"Heterogeneity"
	var inventory := Fixture.inventory(ultimate)
	inventory.add_item(&"Heterogeneity", 3)
	var system := AlchemySystem.new(inventory)
	var selection := system.create_selection(ultimate)
	system.select_material(ultimate, 0, selection, &"Heterogeneity", 2)
	system.select_material(ultimate, 1, selection, &"BaseWater", 1)
	_expect(system.synthesize(ultimate, selection).ok and inventory.get_amount(&"Heterogeneity") == 1, "Later recipes can consume waste as an ordinary ingredient")
	inventory.free()


func _run() -> void:
	_outcomes()
	_validation_and_candidates()
	_capacity_and_reuse()
	print("Alchemy experiment core: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

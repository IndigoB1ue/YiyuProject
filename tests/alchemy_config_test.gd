extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/AlchemyRoom.tscn")
	var ui: AlchemyUI = scene.instantiate()
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	var progress := root.get_node("GameProgress") as GameProgressState
	# Configuration checks explicitly learn recipes and seed required materials.
	# Real exploration and its empty starting materials are tested separately.
	for recipe in ui.recipes:
		progress.unlock_recipe(recipe.recipe_id)
		var required: Dictionary = {}
		for requirement in recipe.ingredients:
			required[requirement.item_id] = int(required.get(requirement.item_id, 0)) + requirement.amount
		for id in required:
			var deficit := int(required[id]) - inventory.get_amount(id)
			if deficit > 0:
				inventory.add_item(id, deficit)
	root.add_child(ui)
	await process_frame
	_expect(not ui.recipes.is_empty(), "AlchemyRoom has configured recipes")
	_expect(ui._recipe_list._dropdown.item_count == ui.recipes.size(), "All configured recipe names appear")
	for index in ui.recipes.size():
		var recipe := ui.recipes[index]
		ui._recipe_list.select_recipe(index)
		var check := ui._system.check_recipe(recipe)
		_expect(check.ok, "%s: %s" % [recipe.display_name, check.error])
		_expect(ui._slots.size() == recipe.ingredients.size(), "%s displays every requirement" % recipe.display_name)
		if not check.ok:
			continue
		for slot_index in recipe.ingredients.size():
			ui._activate_slot(slot_index)
			var available_units := 0
			for candidate in ui._system.candidates(recipe, slot_index, ui._selection):
				available_units += int(candidate.amount)
			var cell_count := 0
			for cell in ui._picker._grid.get_children():
				if cell is Button:
					cell_count += 1
			_expect(cell_count == available_units, "Grid shows actual available units for each requirement")
	# A typo must be explained alongside the recipe, before the material grid.
	var invalid: AlchemyRecipe = ui.recipes[0].duplicate(true)
	invalid.ingredients[0].item_id = &"cleaning_power"
	ui._select_recipe(invalid)
	_expect(ui._description.text.contains("配方配置错误") and ui._description.text.contains("cleaning_power"), "Invalid ID appears in the recipe explanation")
	_expect(ui._start.disabled, "Invalid recipe cannot synthesize")
	# Exercise all configured slots, including repeated Water requirements.
	ui._recipe_list.select_recipe(0)
	var before := inventory.get_items()
	var costs: Dictionary = {}
	for index in ui._recipe.ingredients.size():
		var requirement := ui._recipe.ingredients[index]
		costs[requirement.item_id] = int(costs.get(requirement.item_id, 0)) + requirement.amount
		ui._activate_slot(index)
		for unit in requirement.amount:
			var buttons: Array[Button] = []
			for child in ui._picker._grid.get_children():
				if child is Button and not child.disabled:
					buttons.append(child)
			_expect(not buttons.is_empty(), "Seeded test inventory can satisfy this recipe")
			if not buttons.is_empty():
				buttons[0].pressed.emit()
	_expect(not ui._start.disabled, "All configured requirements enable synthesis")
	var result_id := ui._recipe.result_item_id
	var result_amount := ui._recipe.result_amount
	ui._start.pressed.emit()
	_expect(ui._result.visible and ui._result.title == "炼金成功！", "Configured recipe synthesizes successfully")
	for id in costs:
		var expected := int(before.get(id, 0)) - int(costs[id])
		if id == result_id:
			expected += result_amount
		_expect(inventory.get_amount(id) == expected, "Configured inputs are consumed exactly once")
	_expect(inventory.get_amount(result_id) == int(before.get(result_id, 0)) - int(costs.get(result_id, 0)) + result_amount, "Configured result is added")
	ui.queue_free()
	await process_frame
	print("Alchemy configuration tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

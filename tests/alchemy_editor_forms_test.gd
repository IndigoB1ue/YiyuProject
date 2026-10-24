extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var items := load("res://data/items/catalog.tres") as ItemCatalog
	var three := load("res://data/recipes/experiment_three.tres") as AlchemyRecipe
	var four := load("res://data/recipes/experiment_four.tres") as AlchemyRecipe
	var standard := load("res://data/recipes/potion.tres") as AlchemyRecipe
	if standard == null:
		standard = AlchemyRecipe.new()
		standard.recipe_id = &"StandardFormTest"
		standard.ingredients = [IngredientRequirement.new(), IngredientRequirement.new()]
	var categories: Array[ItemCategory] = items.categories
	var recipes: Array[AlchemyRecipe] = [three, four, standard]
	var form: Node = load("res://addons/alchemy_editor/recipe_form.tscn").instantiate()
	root.add_child(form)
	form.bind_data(items, categories, recipes)
	form.edit_resource(three, false)
	_expect(form.get_resource() != three, "Recipe form uses a separate working resource")
	_expect(form.get_resource().ingredients[2] != three.ingredients[2], "Ingredient answers are isolated working copies")
	_expect(not form.get_node("RecipeID").editable, "Existing recipe IDs are stable")
	_expect(form._slot_forms.size() == 4, "Experimental forms contain four editable slots")
	_expect(form._slot_forms[3].get_node("UnknownNote").visible, "Three-slot fourth shows unknown-material guidance")
	_expect(not form._slot_forms[3].get_node("ItemRow").visible, "Three-slot fourth has no hidden answer field")
	form.set_item_for_field("ingredient_2", &"Herb")
	_expect(form.get_resource().ingredients[2].item_id == &"Herb", "Quick creation routes an item into its requested ingredient")
	_expect(three.ingredients[2].item_id == &"ExperimentLeaf", "Editing ingredient preserves original resource")
	form.set_item_for_field("advanced_result_item_id", &"Potion")
	_expect(form.get_resource().advanced_result_item_id == &"Potion", "Quick creation routes B product correctly")
	form.edit_resource(four, true)
	_expect(form.get_node("RecipeID").editable, "Unsaved IDs can be adjusted")
	form._on_advanced_selected(0)
	_expect(form.get_node("AdvancedConfirm").visible and form.get_resource().advanced_slot_count == 4, "Four-to-three conversion waits for confirmation")
	form.get_node("AdvancedConfirm").confirmed.emit()
	form.get_node("AdvancedConfirm").hide()
	_expect(form.get_resource().advanced_slot_count == 3 and form.get_resource().ingredients[3].item_id == &"", "Confirmed conversion clears only the draft fourth answer")
	_expect(four.ingredients[3].item_id == &"MagicCrystal", "Advanced conversion does not mutate original recipe")
	var legacy := standard.duplicate(true) as AlchemyRecipe
	for index in 5:
		legacy.ingredients.append(IngredientRequirement.new())
	form.edit_resource(legacy, false)
	_expect(form._slot_forms.size() == legacy.ingredients.size(), "STANDARD mode preserves arbitrary requirement count")
	var item_form: Node = load("res://addons/alchemy_editor/item_form.tscn").instantiate()
	root.add_child(item_form)
	item_form.bind_data(items, categories, recipes)
	var book := items.find_item(&"ExperimentBookThree")
	item_form.edit_resource(book, false)
	_expect(item_form.get_resource() != book, "Item form isolates edits")
	_expect(item_form.get_resource().alchemy_recipe == book.alchemy_recipe, "Recipe item retains the shared recipe resource")
	_expect(not item_form.get_node("ItemID").editable, "Existing item ID is readonly")
	var picker: Node = load("res://addons/alchemy_editor/item_picker.tscn").instantiate()
	root.add_child(picker)
	picker.open_picker(items, &"Herb", true)
	_expect(picker._visible_ids.has(&"Herb") and not picker._visible_ids.has(&"ExperimentBookThree"), "Material picker excludes recipe tools")
	picker.get_node("Content/Search").text = "ExperimentLeaf"
	picker._refresh()
	_expect(picker._visible_ids == [&"ExperimentLeaf"], "Picker searches by ItemID")
	picker.hide()
	picker.queue_free()
	item_form.queue_free()
	form.queue_free()
	await process_frame
	print("alchemy_editor_forms_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)

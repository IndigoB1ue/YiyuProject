extends SceneTree

const FIXTURE := preload("res://tests/alchemy_experiment_fixture.gd")
const PREVIEW := preload("res://addons/alchemy_editor/preview_panel.tscn")
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(420, 940)
	var panel := PREVIEW.instantiate()
	root.add_child(panel)
	panel.size = Vector2(390, 900)
	var player_inventory := root.get_node_or_null("PlayerInventory")
	var original_stock: Dictionary = player_inventory.get_items() if player_inventory != null else {}
	for advanced_count in [3, 4]:
		var recipe := FIXTURE.recipe(advanced_count)
		recipe.designer_notes = "内部秘密备注"
		var catalog := FIXTURE.catalog(recipe)
		catalog.find_item(&"BaseHerb").icon = load("res://asserts/image/icon/ingredient/熏香草.png")
		panel.bind_data(catalog)
		panel.display_recipe(recipe)
		await process_frame
		await process_frame
		_expect(not panel._player.has_node("InventoryHeading") and not panel._player.has_node("InventoryIngredients"), "Preview has a single group of ingredient slots")
		for width in [310, 490]:
			panel.size.x = width
			await process_frame
			await process_frame
			for slot in panel._player.get_node("Slots").get_children():
				for child_path in ["Layout/Icon", "Layout/IngredientName", "Layout/Count"]:
					var content: Control = slot.get_node(child_path)
					_expect(slot.get_global_rect().grow(-7.0).encloses(content.get_global_rect()), "Preview slot keeps icon and text inside its padding at width %d" % width)
		panel.size.x = 390
		var presentation: Dictionary = panel.get_public_preview()
		_expect(presentation.slots.size() == 4, "Preview keeps all four slots for either formula")
		_expect(presentation.slots[2].name == "植物", "Hidden slot uses its public category name")
		_expect(presentation.slots[3].name == ("未知素材" if advanced_count == 3 else "矿物"), "Fourth preview follows the public presentation")
		_expect(not str(presentation).contains("内部秘密备注") and not str(presentation).contains("隐藏答案"), "Public preview omits designer notes and hidden item names")
		var stock := {&"BaseHerb": 10, &"BaseWater": 10, &"SecretLeaf": 10, &"WrongLeaf": 10, &"SecretOre": 10, &"WrongOre": 10}
		panel.set_trial_stock(stock)
		var inventory := FIXTURE.inventory(recipe)
		var system := AlchemySystem.new(inventory)
		var candidate_ids: Array = []
		var picker: OptionButton = panel._selection_rows[2].get_node("Material")
		for index in picker.item_count:
			candidate_ids.append(picker.get_item_metadata(index))
		_expect(candidate_ids.has(&"SecretLeaf") and candidate_ids.has(&"WrongLeaf") and not candidate_ids.has(&"WrongOre"), "Trial candidates use category filtering, never answer filtering")
		var base_picker: OptionButton = panel._selection_rows[0].get_node("Material")
		base_picker.select(1)
		panel._selection_rows[0].get_node("Actions/Amount").value = 2
		panel._selection_rows[0].get_node("Actions/Add").pressed.emit()
		_expect(panel._selection[0].get(&"BaseHerb") == 2, "Manual trial controls select materials through the shared core")
		var selection := FIXTURE.base_selection(system, recipe)
		panel.set_trial_selection(selection)
		var base: Dictionary = panel.run_trial()
		_expect(base.ok and base.outcome == &"base", "Base trial calls shared core and yields A")
		_expect(base.after.get(&"BaseHerb") == 8 and base.after.get(&"BasePotion") == 1, "Trial reports material costs and resulting inventory")
		var repeat: Dictionary = panel.run_trial()
		_expect(repeat.after == base.after and panel.get_trial_stock() == stock, "Every run resets to the starting snapshot")
		system.select_material(recipe, 2, selection, &"SecretLeaf", 2)
		if advanced_count == 4:
			system.select_material(recipe, 3, selection, &"SecretOre", 1)
		panel.set_trial_selection(selection)
		var advanced: Dictionary = panel.run_trial()
		_expect(advanced.ok and advanced.outcome == &"advanced" and advanced.amount == 2, "Correct fixed advanced formula yields B")
		selection[2] = {&"WrongLeaf": 2}
		panel.set_trial_selection(selection)
		var waste: Dictionary = panel.run_trial()
		_expect(waste.ok and waste.outcome == &"waste" and waste.amount == recipe.waste_result_amount, "Wrong hidden material yields recipe-configured waste quantity")
		_expect(waste.costs.get(&"WrongLeaf") == 2, "Waste consumes all actual selected materials")
		selection[2] = {&"SecretLeaf": 2}
		selection[3] = {} if advanced_count == 4 else {&"WrongOre": 1}
		panel.set_trial_selection(selection)
		var mismatch: Dictionary = panel.run_trial()
		_expect(mismatch.ok and mismatch.outcome == &"waste", "Extra or missing fourth slot is submitted and yields waste")
		selection[0] = {&"BaseHerb": 1}
		panel.set_trial_selection(selection)
		var partial: Dictionary = panel.run_trial()
		_expect(not partial.ok and partial.before == partial.after, "Incomplete slot fails without spending inventory")
		selection[0] = {&"BaseHerb": 2}
		panel.set_trial_selection(selection)
		panel.set_trial_stock({&"BaseHerb": 1, &"BaseWater": 10, &"SecretLeaf": 10, &"WrongOre": 10})
		var shortage: Dictionary = panel.run_trial()
		_expect(not shortage.ok and shortage.before == shortage.after, "Stock shortage fails without spending inventory")
		panel.set_trial_stock(stock)
		selection[0] = {&"MissingItem": 2}
		panel.set_trial_selection(selection)
		var invalid: Dictionary = panel.run_trial()
		_expect(not invalid.ok and invalid.before == invalid.after, "Unknown item fails without spending inventory")
		inventory.free()
	_expect(player_inventory == null or player_inventory.get_items() == original_stock, "Editor trial does not modify the game autoload inventory")
	if OS.get_cmdline_user_args().has("--capture"):
		panel.get_node("Tabs").current_tab = 0
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/alchemy_editor_preview")
		root.get_texture().get_image().save_png("res://.godot/alchemy_editor_preview/player.png")
		panel.get_node("Tabs").current_tab = 1
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/alchemy_editor_preview/trial.png")
	panel.queue_free()
	await process_frame
	print("alchemy_editor_preview_test: PASS" if _failures == 0 else "alchemy_editor_preview_test: FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)

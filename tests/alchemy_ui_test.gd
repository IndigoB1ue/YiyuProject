extends SceneTree

const Fixture = preload("res://tests/alchemy_test_fixture.gd")

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _cells(ui: AlchemyUI) -> Array[Button]:
	var cells: Array[Button] = []
	for child in ui._picker._grid.get_children():
		if child is Button:
			cells.append(child)
	return cells

func _choose(ui: AlchemyUI, index: int, amount: int) -> void:
	ui._slots[index].pressed.emit()
	for unit in amount:
		var cells := _cells(ui)
		_expect(not cells.is_empty() and not cells[0].disabled, "Matching material cell is available")
		if not cells.is_empty():
			cells[0].pressed.emit()

func _mouse_click(position: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = button
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280, 800)
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	Fixture.prepare_inventory(inventory)
	var recipe: AlchemyRecipe = Fixture.potion_recipe()
	(root.get_node("GameProgress") as GameProgressState).unlock_recipe(recipe.recipe_id)
	var scene: PackedScene = load("res://scenes/AlchemyRoom.tscn")
	var ui: AlchemyUI = scene.instantiate()
	# Keep the baseline test independent of extra recipes configured in the editor.
	ui.recipes = [recipe]
	_expect(ui.has_node("Margin/Columns/ContentScroll/Page/Header/Back"), "Static interface exists in the PackedScene before running scripts")
	_expect(ui.get_node("%IngredientSlots").get_child_count() == 2, "Ingredient preview slots are editable scene instances")
	_expect(ui.theme == load("res://themes/alchemy_theme.tres"), "Scene uses the shared Theme resource")
	root.add_child(ui)
	await process_frame
	await process_frame
	_expect(ui._slots.size() == 2 and ui._active_slot == 0, "First recipe and requirement are selected automatically")
	_expect(ui._slot_container.get_child_count() == 2, "Runtime replaces previews instead of duplicating them")
	_expect(ui._slots[0].scene_file_path == "res://scenes/ui/alchemy/ingredient_slot_ui.tscn", "Runtime requirements use the editable slot template")
	_expect(_cells(ui)[0].scene_file_path == "res://scenes/ui/alchemy/material_cell_ui.tscn", "Runtime units use the editable cell template")
	_expect(ui._start.disabled, "Start disabled before selection")
	_expect(_cells(ui).size() == 5, "Five herbs produce five separate cells")
	_expect(ui._picker._grid.get_child_count() >= 24, "Empty grid cells preserve material layout")
	_expect(ui._recipe_list._previous.disabled and ui._recipe_list._next.disabled, "One recipe disables previous and next")
	var first_cell := _cells(ui)[0]
	await _mouse_click(first_cell.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	_expect(ui._system.selected_amount(ui._selection[0]) == 1, "Actual mouse input selects one material cell")
	await _mouse_click(ui._slots[0].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	_expect(ui._selection[0].is_empty(), "Actual right mouse input clears the requirement")
	ui._slots[1].mouse_entered.emit()
	_expect(ui._active_slot == 1 and _cells(ui).size() == 3, "Hovering water filters grid to three waters")
	ui._slots[0].focus_entered.emit()
	_expect(ui._active_slot == 0 and _cells(ui).size() == 5, "Keyboard focus filters grid")
	_choose(ui, 0, 1)
	_expect(ui._system.selected_amount(ui._selection[0]) == 1 and _cells(ui).size() == 4, "One cell selects exactly one unit")
	_choose(ui, 0, 1)
	_expect(ui._system.selected_amount(ui._selection[0]) == 2 and _cells(ui).size() == 3, "Second unit fills herb requirement")
	_expect(_cells(ui)[0].disabled and ui._start.disabled, "Full requirement disables extra units, incomplete recipe cannot start")
	_expect(inventory.get_amount(&"Herb") == 5, "Selecting grid cells does not consume inventory")
	_choose(ui, 1, 1)
	_expect(not ui._start.disabled, "Complete selection enables start")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	ui._slots[0].gui_input.emit(right_click)
	_expect(ui._selection[0].is_empty() and _cells(ui).size() == 5 and ui._start.disabled, "Right click clears the requirement and restores units")
	_choose(ui, 0, 2)
	ui._start.pressed.emit()
	_expect(ui._result.visible and ui._result.title == "炼金成功！", "Success result opens")
	_expect(inventory.get_amount(&"Herb") == 3 and inventory.get_amount(&"Water") == 2 and inventory.get_amount(&"Potion") == 1, "UI craft consumes inputs and adds output")
	_expect(ui._start.disabled and ui._selection[0].is_empty() and _cells(ui).size() == 3, "Success clears selection and refreshes grid")
	ui._result.hide()
	# Test an additional recipe without adding extra production recipes or item data.
	var alternate: AlchemyRecipe = ui.recipes[0].duplicate(true)
	alternate.recipe_id = &"TestAlternate"
	alternate.display_name = "测试配方"
	alternate.ingredients.resize(1)
	alternate.ingredients[0].item_id = &"Water"
	alternate.ingredients[0].amount = 1
	ui._recipe_list.display([ui.recipes[0], alternate])
	_choose(ui, 0, 1)
	ui._recipe_list._next.pressed.emit()
	_expect(ui._recipe == alternate and ui._slots.size() == 1 and _cells(ui).size() == 2, "Next recipe rebuilds requirements and resets reservations")
	ui._recipe_list._dropdown.item_selected.emit(0)
	_expect(ui._slots.size() == 2 and ui._selection[0].is_empty(), "Dropdown switches recipe")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.pressed = true
	ui._unhandled_key_input(key)
	_expect(ui._recipe == alternate, "Q cycles to previous recipe")
	key.physical_keycode = KEY_E
	ui._unhandled_key_input(key)
	_expect(ui._recipe == ui.recipes[0], "E cycles to next recipe")
	_choose(ui, 0, 2)
	_choose(ui, 1, 1)
	inventory.remove_item(&"Herb", 2)
	_expect(ui._start.disabled and ui._status.text.contains("数量不足"), "External inventory changes disable start and explain shortage")
	var before := inventory.get_items()
	ui._start.pressed.emit()
	_expect(ui._result.title == "无法炼金" and inventory.get_items() == before, "Stale action fails without consumption")
	ui._result.hide()
	ui._activate_slot(0)
	key.physical_keycode = KEY_BACKSPACE
	ui._unhandled_key_input(key)
	_expect(ui._selection[0].is_empty() and _cells(ui).size() == 1, "Backspace clears selected requirement")
	ui.queue_free()
	await process_frame
	ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	_expect(inventory.get_items() == before, "Reopening alchemy preserves inventory")
	ui._recipe_list.display([])
	_expect(ui._recipe_list._dropdown.disabled, "Empty recipe selector is disabled")
	ui.queue_free()
	await process_frame
	ui = scene.instantiate()
	ui.recipes = []
	root.add_child(ui)
	await process_frame
	_expect(ui._slot_container.get_child_count() == 0 and ui._description.text.is_empty(), "Empty recipe configuration removes editor preview data")
	_expect(ui._start.disabled and ui._recipe_list._dropdown.disabled, "Empty configuration prevents synthesis")
	ui.queue_free()
	await process_frame
	print("Alchemy UI tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

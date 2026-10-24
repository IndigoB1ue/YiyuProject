extends SceneTree

var _failures := 0
var _ui: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 10:
		await process_frame


func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/experiment_preview")
	root.get_texture().get_image().save_png("res://.godot/experiment_preview/%s.png" % name)


func _choose(index: int, item_id: StringName) -> void:
	_ui._activate_slot(index)
	var name: String = _ui._inventory.get_item(item_id).display_name
	for cell in _ui._picker._grid.get_children():
		if cell is Button and not cell.disabled and cell.tooltip_text.begins_with(name + "\n"):
			cell.pressed.emit()
			return
	_expect(false, "A selectable cell exists for %s in slot %d" % [item_id, index + 1])


func _base() -> void:
	_choose(0, &"Herb")
	_choose(1, &"Water")


func _dismiss() -> void:
	_ui._result.confirmed.emit()
	_ui._result.hide()


func _run() -> void:
	var inventory: Node = root.get_node("PlayerInventory")
	var progress: Node = root.get_node("GameProgress")
	var save_system: Node = root.get_node("SaveSystem")
	progress.skip_rovin_tutorial()
	for id in inventory.get_items():
		inventory.remove_item(id, inventory.get_amount(id))
	for id in [&"Herb", &"Water", &"ExperimentLeaf", &"MagicCrystal", &"cleaning_powder"]:
		inventory.add_item(id, 20)
	inventory.add_item(&"ExperimentBookThree", 1)
	inventory.add_item(&"ExperimentBookFour", 1)
	progress.unlock_recipe(&"ExperimentThree")
	progress.unlock_recipe(&"ExperimentFour")
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	_ui = current_scene
	_expect(_ui._recipe.recipe_id == &"ExperimentThree" and _ui._slots.size() == 4, "An unlocked experimental recipe displays four slots")
	_expect(_ui._slots[2]._name_label.text == "植物" and _ui._slots[3]._name_label.text == "未知素材", "Hidden slots show type hints and the unused fourth remains unknown")
	_expect(_ui._slots[2]._icon.texture == load("res://data/items/category_plant.svg"), "A type icon replaces the secret item's icon")
	_ui._activate_slot(2)
	_expect(_ui._picker._heading.text.begins_with("植物"), "The candidate heading does not expose the secret item")
	var names: Array[String] = []
	for cell in _ui._picker._grid.get_children():
		if cell is Button:
			names.append(cell.tooltip_text.get_slice("\n", 0))
	_expect(names.has("熏香草") and names.has("试验叶") and not names.has("清水"), "The picker includes wrong plants while filtering unrelated categories")
	_base()
	_expect(not _ui._start.disabled, "Only the two base slots enable synthesis")
	await _settle()
	_expect(_ui._start.get_global_rect().end.y <= root.get_visible_rect().end.y, "The craft action remains visible at the default window size")
	await _capture("base_ready")
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"ExperimentBase") == 1, "The UI obtains A with no additional materials")
	_dismiss()
	_base()
	_choose(2, &"ExperimentLeaf")
	_expect(not _ui._start.disabled, "A correct three-slot attempt enables synthesis")
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"ExperimentAdvanced") == 1, "The three-slot formula obtains B")
	_dismiss()
	_base()
	_choose(2, &"ExperimentLeaf")
	_choose(3, &"MagicCrystal")
	_expect(not _ui._start.disabled, "An extra fourth material is not blocked")
	var before: Dictionary = inventory.get_items()
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"Heterogeneity") == 1 and inventory.get_amount(&"MagicCrystal") == before[&"MagicCrystal"] - 1,
		"An overfilled formula produces waste and consumes the extra item")
	_expect(_ui._result.title == "炼金完成" and _ui._result.dialog_text.contains("异质"), "Waste has an ordinary result confirmation, not a cancelled transaction")
	await _capture("waste")
	_dismiss()

	_ui._recipe_list.select_recipe(1)
	_base()
	_choose(2, &"ExperimentLeaf")
	_expect(not _ui._start.disabled and _ui._selection[3].is_empty(), "A missing fourth formula slot still permits submission")
	await _capture("four_slot_attempt")
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"Heterogeneity") == 3, "An incomplete advanced formula uses this recipe's waste amount")
	_dismiss()
	_base()
	_choose(2, &"ExperimentLeaf")
	_choose(3, &"MagicCrystal")
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"ExperimentAdvanced") == 2, "The four-slot formula obtains B")
	_dismiss()

	_base()
	_choose(2, &"Herb")
	_ui._activate_slot(3)
	var selected: Array = _ui._selection.duplicate(true)
	before = inventory.get_items()
	var result: Dictionary = save_system.save_slot(110)
	_expect(result.ok, "A wrong but legal hidden selection can be saved")
	_ui._clear_slot(2)
	result = await save_system.load_slot(110)
	await _settle()
	_ui = current_scene
	_expect(result.ok and _ui._selection == selected and _ui._active_slot == 3 and not _ui._start.disabled,
		"Loading restores wrong/empty additional slots without checking the hidden answer")
	_expect(inventory.get_items() == before, "Saving and loading selected units does not consume them")
	_ui._start.pressed.emit()
	_expect(inventory.get_amount(&"Heterogeneity") == 5, "A restored wrong attempt still yields the configured waste amount")
	_dismiss()

	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var bag: Node = root.get_node("InventoryUI")
	bag.open_inventory()
	bag._select_item(&"ExperimentBookFour")
	_expect(bag.is_open() and bag._ingredients.get_child_count() == 4, "Backpack recipe details preserve the four public slots")
	var labels: Array[String] = []
	for badge in bag._ingredients.get_children():
		labels.append(badge.get_node("Label").text)
	_expect(labels == ["熏香草 ×1", "清水 ×1", "植物 ×1", "矿物 ×1"], "Backpack recipe details do not leak secret material names")
	await _capture("backpack")
	bag.close_inventory()

	var player_before: Dictionary = inventory.get_items()
	var progress_before: Dictionary = progress.get_save_state()
	change_scene_to_file("res://scenes/AlchemyExperimentDemo.tscn")
	await _settle()
	_ui = current_scene
	_expect(_ui._inventory != inventory and _ui._progress != progress, "The F6 demo owns its inventory and unlocks")
	_expect(not save_system.can_save().ok, "The F6 demo cannot overwrite a normal save")
	await _capture("demo")
	_base()
	_ui._start.pressed.emit()
	_expect(_ui._inventory.get_amount(&"ExperimentBase") == 1 and inventory.get_items() == player_before and progress.get_save_state() == progress_before,
		"Demo crafting leaves real player inventory and progress unchanged")
	_dismiss()
	print("Alchemy experiment UI/save integration: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

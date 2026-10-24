extends AlchemyUI


func _ready() -> void:
	# F6-only demonstration: data and unlocks belong to this scene, not the player.
	remove_from_group("settings_context")
	$StoryTrigger.timeline_path = ""
	_inventory = InventorySystem.new()
	add_child(_inventory)
	for id in _inventory.get_items():
		_inventory.remove_item(id, _inventory.get_amount(id))
	for id in [&"Herb", &"Water", &"ExperimentLeaf", &"MagicCrystal", &"cleaning_powder"]:
		_inventory.add_item(id, 12)
	_progress = GameProgressState.new()
	add_child(_progress)
	for recipe in recipes:
		_progress.unlock_recipe(recipe.recipe_id)
	super._ready()


func _on_back_pressed() -> void:
	get_tree().quit()

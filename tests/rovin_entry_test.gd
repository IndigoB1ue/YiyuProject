extends SceneTree

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	# The learned flag alone must not replace an actual backpack recipe item.
	(root.get_node("GameProgress") as GameProgressState).unlock_recipe(&"ClearPotion")
	var cases: Array[Dictionary] = [
		{"name": "Empty backpack", "items": {}, "allowed": false},
		{"name": "Only three waters", "items": {&"Water": 3}, "allowed": false},
		{"name": "Only recipe item", "items": {&"clear_potion_recipe": 1}, "allowed": false},
		{"name": "Recipe and two waters", "items": {&"clear_potion_recipe": 1, &"Water": 2}, "allowed": false},
		{"name": "Recipe and three waters without powder", "items": {&"clear_potion_recipe": 1, &"Water": 3}, "allowed": true},
		{"name": "Recipe and excess water", "items": {&"clear_potion_recipe": 1, &"Water": 4}, "allowed": true},
		{"name": "Only completed cleanser", "items": {&"clear_potion": 1}, "allowed": true},
		{"name": "Completed cleanser and insufficient water", "items": {&"clear_potion": 1, &"Water": 1}, "allowed": true},
		{"name": "Completed cleanser without configured recipe", "items": {&"clear_potion": 1}, "allowed": true, "clear_config": true},
	]
	for entry in cases:
		change_scene_to_file("res://scenes/RovinRoom.tscn")
		await _settle()
		var room: Control = current_scene
		for id in inventory.get_items():
			inventory.remove_item(id, inventory.get_amount(id))
		for id in entry.items:
			inventory.add_item(id, entry.items[id])
		if entry.get("clear_config", false):
			room.found_recipe = null
		var before := inventory.get_items()
		room._hotspots.alchemy.pressed.emit()
		await _settle()
		if entry.allowed:
			_expect(current_scene is AlchemyUI, "%s should enter alchemy" % entry.name)
		else:
			_expect(current_scene == room, "%s must stay in RovinRoom" % entry.name)
			if current_scene == room:
				_expect(room._message.visible and not room._message.dialog_text.is_empty(), "%s has a clear rejection message" % entry.name)
		_expect(inventory.get_items() == before, "%s must not consume inventory at the entrance" % entry.name)
	print("Rovin entry conditions: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

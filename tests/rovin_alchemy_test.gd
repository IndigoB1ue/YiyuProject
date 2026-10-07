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

func _collect(room: Control, hotspot: String) -> void:
	room._hotspots[hotspot].pressed.emit()
	room._message.hide()

func _run() -> void:
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	var progress := root.get_node("GameProgress") as GameProgressState
	var herb_amount := inventory.get_amount(&"Herb")
	_expect(inventory.get_amount(&"Water") == 0 and inventory.get_amount(&"cleaning_powder") == 0, "Exploration materials are not granted initially")
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	var ui: AlchemyUI = current_scene
	_expect(ui._recipe == null and ui._slots.is_empty() and ui._start.disabled, "No recipes are usable before discovery")
	_expect(ui._status.text.contains("书柜"), "Empty alchemy interface directs the player to the bookshelf")
	ui._on_back_pressed()
	await _settle()
	var room: Control = current_scene
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.dialog_text.contains("配方") and room._message.dialog_text.contains("书柜"), "Missing recipe blocks the room alchemy entrance")
	room._message.hide()
	inventory.add_item(&"cleaning_powder", 1)
	inventory.add_item(&"Water", 3)
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.dialog_text.contains("配方"), "Enough stock cannot bypass the recipe requirement")
	room._message.hide()
	inventory.remove_item(&"cleaning_powder", 1)
	inventory.remove_item(&"Water", 3)
	# Bad data cannot permanently consume an exploration reward.
	var original_recipe: AlchemyRecipe = room.found_recipe
	room.found_recipe = original_recipe.duplicate(true)
	room.found_recipe.result_item_id = &"Missing"
	_collect(room, "recipe")
	_expect(not progress.is_interaction_claimed(&"RovinRoom/recipe") and not progress.is_recipe_unlocked(&"ClearPotion"), "Invalid recipe reward is not claimed")
	room.found_recipe = original_recipe
	_collect(room, "recipe")
	_expect(progress.is_recipe_unlocked(&"ClearPotion") and room._hotspots.recipe.disabled, "Bookshelf unlocks the cleanser recipe once")
	_collect(room, "recipe")
	var original_reward: Dictionary = room.material_rewards.bedside.duplicate()
	room.material_rewards.bedside = {"item_id": &"Missing", "amount": 1}
	_collect(room, "bedside")
	_expect(not progress.is_interaction_claimed(&"RovinRoom/bedside") and not room._hotspots.bedside.disabled, "Failed item reward remains collectible")
	room.material_rewards.bedside = original_reward
	_collect(room, "bedside")
	_collect(room, "bedside")
	_expect(inventory.get_amount(&"cleaning_powder") == 1, "Bedside gives exactly one powder despite repeated input")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.dialog_text.contains("清水") and room._message.dialog_text.contains("需要 3"), "Partial collection blocks entry and aggregates the three water slots")
	room._message.hide()
	# Direct scene loading checks state persistence separately from room entry gating.
	change_scene_to_file("res://scenes/AlchemyRoom.tscn")
	await _settle()
	ui = current_scene
	_expect(ui._recipe_list._recipes.size() == 1 and ui._recipe.recipe_id == &"ClearPotion", "Only the discovered recipe appears after changing scenes")
	_expect(ui._slots.size() == 4, "Cleanser has powder and three water slots")
	_expect(inventory.get_amount(&"Water") == 0, "Partial exploration does not grant missing materials")
	ui._on_back_pressed()
	await _settle()
	room = current_scene
	_expect(room._hotspots.recipe.disabled and room._hotspots.bedside.disabled, "Explored locations stay disabled after returning")
	for id in ["shoe", "desk", "calculation"]:
		var before_water := inventory.get_amount(&"Water")
		_collect(room, id)
		_expect(inventory.get_amount(&"Water") == before_water + 1, "%s gives one water" % id)
		_collect(room, id)
		_expect(inventory.get_amount(&"Water") == before_water + 1, "%s cannot be collected twice" % id)
		if inventory.get_amount(&"Water") < 3:
			room._hotspots.alchemy.pressed.emit()
			await _settle()
			_expect(current_scene == room and room._message.dialog_text.contains("素材不足"), "One or two waters cannot satisfy three water requirements")
			room._message.hide()
	_expect(inventory.get_amount(&"Water") == 3 and inventory.get_amount(&"cleaning_powder") == 1, "All exploration rewards match the cleanser recipe")
	inventory.remove_item(&"Water", 1)
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.dialog_text.contains("现有 2") and room._message.dialog_text.contains("还缺 1"), "Previously collected materials consumed elsewhere still block entry")
	room._message.hide()
	inventory.add_item(&"Water", 1)
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	ui = current_scene
	for index in ui._slots.size():
		ui._slots[index].select_requested.emit()
		var cell: Button = null
		for child in ui._picker._grid.get_children():
			if child is Button and not child.disabled:
				cell = child
				break
		_expect(cell != null, "Collected material is available for slot %d" % index)
		if cell != null:
			cell.pressed.emit()
	_expect(not ui._start.disabled, "Collected materials enable synthesis")
	ui._start.pressed.emit()
	_expect(ui._result.title == "炼金成功！" and ui._result.dialog_text.contains("清洗剂"), "Synthesis displays the correct result")
	_expect(inventory.get_amount(&"clear_potion") == 1 and inventory.get_amount(&"Water") == 0 and inventory.get_amount(&"cleaning_powder") == 0, "Synthesis consumes all gathered ingredients and creates one cleanser")
	_expect(inventory.get_amount(&"Herb") == herb_amount, "Unrelated inventory is preserved")
	ui._result.hide()
	ui._on_back_pressed()
	await _settle()
	room = current_scene
	for id in ["recipe", "bedside", "shoe", "desk", "calculation"]:
		_expect(room._hotspots[id].disabled, "Claimed hotspot remains disabled after crafting")
		_collect(room, id)
	_expect(inventory.get_amount(&"Water") == 0 and inventory.get_amount(&"cleaning_powder") == 0, "Returning after crafting cannot refill ingredients")
	_expect(progress.is_recipe_unlocked(&"ClearPotion"), "Crafting does not consume the learned recipe")
	room._hotspots.alchemy.pressed.emit()
	await _settle()
	_expect(current_scene == room and room._message.dialog_text.contains("素材不足"), "Spent ingredients block reentry even though every location was collected")
	room._message.hide()
	print("Rovin exploration → alchemy tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

class_name AlchemyUI
extends Control

@export var recipes: Array[AlchemyRecipe] = []
@export var ingredient_slot_scene: PackedScene

var _inventory: InventorySystem
var _progress: GameProgressState
var _system: AlchemySystem
var _recipe: AlchemyRecipe
var _selection: Array[Dictionary] = []
var _active_slot := -1
var _slots: Array[IngredientSlotUI] = []

@onready var _recipe_list: RecipeListUI = %RecipeList
@onready var _description: Label = %RecipeDescription
@onready var _slot_container: HBoxContainer = %IngredientSlots
@onready var _start: Button = %StartAlchemy
@onready var _clear: Button = %ClearSlot
@onready var _status: Label = %Status
@onready var _picker: IngredientSelectUI = %IngredientSelect
@onready var _result: AlchemyResultUI = %Result
@onready var _story: AlchemyStoryTrigger = $StoryTrigger

func _ready() -> void:
	_inventory = get_node("/root/PlayerInventory") as InventorySystem
	_progress = get_node("/root/GameProgress") as GameProgressState
	_system = AlchemySystem.new(_inventory)
	_recipe_list.recipe_selected.connect(_select_recipe)
	_picker.material_selected.connect(_select_material)
	_inventory.inventory_changed.connect(_refresh)
	_progress.recipes_changed.connect(_rebuild_recipe_list)
	_rebuild_recipe_list()

func _rebuild_recipe_list() -> void:
	_recipe = null
	_selection.clear()
	_active_slot = -1
	_clear_slots()
	var available: Array[AlchemyRecipe] = []
	for recipe in recipes:
		if recipe != null and _progress.is_recipe_unlocked(recipe.recipe_id):
			available.append(recipe)
	_recipe_list.display(available)
	_refresh()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RovinRoom.tscn")

func _on_clear_pressed() -> void:
	_clear_slot(_active_slot)

func _select_recipe(recipe: AlchemyRecipe) -> void:
	_recipe = recipe
	_selection = _system.create_selection(recipe)
	_active_slot = -1
	_clear_slots()
	var output := _inventory.get_item(recipe.result_item_id)
	_description.text = "%s  ·  成品：%s ×%d" % [recipe.description, output.display_name if output != null else str(recipe.result_item_id), recipe.result_amount]
	var recipe_check := _system.check_recipe(recipe)
	if recipe_check.ok:
		for index in recipe.ingredients.size():
			var slot := ingredient_slot_scene.instantiate() as IngredientSlotUI
			_slot_container.add_child(slot)
			slot.select_requested.connect(_activate_slot.bind(index))
			slot.clear_requested.connect(_clear_slot.bind(index))
			_slots.append(slot)
		_active_slot = 0
	else:
		_description.text += "\n配方配置错误：%s" % recipe_check.error
	_picker.reset_scroll()
	_refresh()

func _clear_slots() -> void:
	for slot in _slot_container.get_children():
		_slot_container.remove_child(slot)
		slot.queue_free()
	_slots.clear()

func _activate_slot(index: int) -> void:
	if index == _active_slot or index < 0 or index >= _slots.size():
		return
	_active_slot = index
	_picker.reset_scroll()
	_refresh()

func _clear_slot(index: int) -> void:
	if index < 0 or index >= _selection.size():
		return
	_active_slot = index
	_selection[index].clear()
	_refresh()

func _select_material(item_id: StringName, amount: int) -> void:
	var result := _system.select_material(_recipe, _active_slot, _selection, item_id, amount)
	_refresh()
	if not result.ok:
		_result.show_result(result, _inventory)

func _refresh() -> void:
	_start.disabled = true
	_clear.disabled = true
	if _recipe == null:
		_description.text = ""
		_status.text = "尚未获取配方。请先返回房间，在书柜中寻找配方。"
		_picker.display([], 0, "")
		return
	for index in _slots.size():
		_slots[index].display(_recipe.ingredients[index], _selection[index], _inventory, _system, index == _active_slot)
	var validation := _system.validate(_recipe, _selection)
	_start.disabled = not validation.ok
	_status.text = "素材齐备，可以炼金。" if validation.ok else str(validation.error)
	if _active_slot >= 0:
		var requirement := _recipe.ingredients[_active_slot]
		var item := _inventory.get_item(requirement.item_id)
		var ingredient_name := item.display_name if item != null else str(requirement.category)
		_clear.disabled = _selection[_active_slot].is_empty()
		_picker.display(_system.candidates(_recipe, _active_slot, _selection), requirement.amount - _system.selected_amount(_selection[_active_slot]), ingredient_name)
	else:
		_picker.display([], 0, "")

func _synthesize() -> void:
	var result := _system.synthesize(_recipe, _selection)
	if result.ok:
		_selection = _system.create_selection(_recipe)
	_refresh()
	_result.show_result(result, _inventory)

func _unhandled_key_input(event: InputEvent) -> void:
	if _story.is_playing or _result.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_Q:
			_recipe_list.cycle(-1)
		KEY_E:
			_recipe_list.cycle(1)
		KEY_BACKSPACE:
			_clear_slot(_active_slot)
		_:
			return
	get_viewport().set_input_as_handled()

func _on_story_playback_failed(message: String) -> void:
	_result.show_result({"ok": false, "error": message}, _inventory)

extends Control

## 炼金区域打开独立的炼金界面。
@export_file("*.tscn") var next_scene_path: String = "res://scenes/AlchemyRoom.tscn"
@export var found_recipe: AlchemyRecipe
@export var recipe_item_id: StringName = &"clear_potion_recipe"
@export var material_rewards: Dictionary = {}
@export var introductory_quest_id: StringName = &"make_cleanser"

var _inventory: InventorySystem
var _progress: GameProgressState
var _quests: Node
@onready var _hotspots: Dictionary = {
	"recipe": %RecipeHotspot,
	"bedside": %BedsideHotspot,
	"shoe": %ShoeHotspot,
	"desk": %DeskHotspot,
	"calculation": %CalculationHotspot,
	"alchemy": %AlchemyHotspot,
	"stairs": %StairsHotspot,
}
#@onready var _status: Label = %Status
@onready var _message: AcceptDialog = %Message
@onready var _tutorial: RovinTutorialController = $TutorialController
@onready var _stairs: RovinStairsTrigger = $StairsTrigger
@onready var _map_button: Button = $MapButton

func _ready() -> void:
	_inventory = get_node("/root/PlayerInventory") as InventorySystem
	_progress = get_node("/root/GameProgress") as GameProgressState
	_quests = get_node("/root/QuestSystem")
	if not get_node("/root/SaveSystem").is_restoring:
		_quests.report_event(&"scene_entered", {"scene_path": scene_file_path}, "scene:%d" % get_instance_id())
	_update_status()
	_stairs.setup(_progress, _hotspots.stairs)
	_tutorial.setup(_inventory, _progress, found_recipe, recipe_item_id, material_rewards, _hotspots, introductory_quest_id)
	_refresh_map_button()

func _refresh_map_button() -> void:
	# Ordinary navigation is independent from the optional teaching assistance.
	_map_button.show()

func _on_map_pressed() -> void:
	if _map_button.visible and not _message.visible:
		SceneManager.open_map()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		_on_map_pressed()
		get_viewport().set_input_as_handled()

func _on_room_canvas_layout_updated() -> void:
	if is_instance_valid(_tutorial):
		_tutorial.update_highlight_positions()


func _on_hotspot_pressed(id: String) -> void:
	if _stairs.is_playing:
		return
	if id == "stairs":
		_stairs.activate()
		return
	if id == "alchemy":
		var entry_check := _check_alchemy_entry()
		if not entry_check.ok:
			_show_message(entry_check.error)
			return
		if found_recipe != null and _inventory.get_amount(recipe_item_id) >= 1:
			_progress.unlock_recipe(found_recipe.recipe_id)
		if not next_scene_path.is_empty():
			var scene_error := get_tree().change_scene_to_file(next_scene_path)
			if scene_error == OK:
				_tutorial.on_alchemy_entered()
			else:
				_show_message("无法打开炼金界面，场景加载失败。")
		return
	if id == "recipe":
		if _progress.is_interaction_claimed(_interaction_id(id)):
			return
		var recipe_check := AlchemySystem.new(_inventory).check_recipe(found_recipe)
		if not recipe_check.ok:
			_show_message("无法获取配方：%s" % recipe_check.error)
			return
		if not _progress.claim_interaction(_interaction_id(id)):
			return
		var reward_result := _inventory.add_item(recipe_item_id, 1)
		if not reward_result.ok:
			_progress.release_interaction(_interaction_id(id))
			_show_message("无法获取配方：%s" % reward_result.error)
			return
		_progress.unlock_recipe(found_recipe.recipe_id)
		_show_message("获得：%s ×1" % _inventory.get_item(recipe_item_id).display_name)
	else:
		if not material_rewards.has(id) or _progress.is_interaction_claimed(_interaction_id(id)):
			return
		var reward: Dictionary = material_rewards[id]
		var item_id := StringName(reward.get("item_id", ""))
		var amount := int(reward.get("amount", 0))
		if not _progress.claim_interaction(_interaction_id(id)):
			return
		var result := _inventory.add_item(item_id, amount)
		if not result.ok:
			_progress.release_interaction(_interaction_id(id))
			_show_message("无法获得素材：%s" % result.error)
			return
		_show_message("获得：%s ×%d" % [_inventory.get_item(item_id).display_name, amount])
	_update_status()
	_tutorial.refresh()


func _update_status() -> void:
	#var material_count := 0
	#for id in material_rewards:
		#if _progress.is_interaction_claimed(_interaction_id(str(id))):
			#material_count += 1
	#var has_recipe := _inventory.get_amount(recipe_item_id) >= 1 or (found_recipe != null and _progress.is_recipe_unlocked(found_recipe.recipe_id))
	#_status.text = "清洗剂配方：%s    已搜集：%d / %d处" % ["已获得" if has_recipe else "未获得", material_count, material_rewards.size()]
	for id in _hotspots:
		if id == "stairs":
			continue
		var button: Button = _hotspots[id]
		button.disabled = id != "alchemy" and _progress.is_interaction_claimed(_interaction_id(str(id)))
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND
	_stairs.refresh()


func _check_alchemy_entry() -> Dictionary:
	# A completed craft remains complete after the materials or output are spent.
	if _quests.is_completed(introductory_quest_id) or _progress.cleanser_timeline_completed:
		return {"ok": true, "error": ""}
	var system := AlchemySystem.new(_inventory)
	var check := system.check_recipe(found_recipe)
	if not check.ok:
		return check
	if _inventory.get_amount(recipe_item_id) < 1 and not _progress.is_recipe_unlocked(found_recipe.recipe_id):
		return {"ok": false, "error": "尚未获得清洗剂配方，请先检查书柜。"}
	return system.check_material_availability(found_recipe)


func _interaction_id(id: String) -> StringName:
	return StringName("RovinRoom/" + id)


func _show_message(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered()

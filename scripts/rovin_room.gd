extends Control

## 炼金区域打开独立的炼金界面。
@export_file("*.tscn") var next_scene_path: String = "res://scenes/AlchemyRoom.tscn"
@export var found_recipe: AlchemyRecipe
@export var material_rewards: Dictionary = {}

var _inventory: InventorySystem
var _progress: GameProgressState
var _hotspots: Dictionary = {}
var _status: Label
var _message: AcceptDialog

# 坐标以房间原图为基准，与背景一起等比缩放、居中。
const IMAGE_SIZE := Vector2(1070, 787)
const REGIONS := {
	"recipe": Rect2(503, 84, 97, 162),
	"bedside": Rect2(296, 22, 35, 252),
	"shoe": Rect2(470, 655, 40, 117),
	"desk": Rect2(15, 229, 49, 154),
	"calculation": Rect2(607, 560, 330, 65),
	"alchemy": Rect2(807, 17, 248, 193),
}
const REGION_NAMES := {
	"recipe": "书柜", "bedside": "床头柜", "shoe": "鞋柜",
	"desk": "书桌", "calculation": "测算长桌", "alchemy": "炼金区域",
}


func _ready() -> void:
	_inventory = get_node("/root/PlayerInventory") as InventorySystem
	_progress = get_node("/root/GameProgress") as GameProgressState
	for id: String in REGIONS:
		var button := Button.new()
		button.name = id.capitalize() + "Hotspot"
		button.tooltip_text = REGION_NAMES[id]
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal", _highlight(Color(1.0, 0.75, 0.15, 0.16)))
		button.add_theme_stylebox_override("hover", _highlight(Color(1.0, 0.85, 0.3, 0.35)))
		button.add_theme_stylebox_override("pressed", _highlight(Color(1.0, 0.85, 0.3, 0.5)))
		button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		button.pressed.connect(_on_hotspot_pressed.bind(id))
		add_child(button)
		_hotspots[id] = button
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_color_override("font_color", Color.WHITE)
	_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_x", 2)
	_status.add_theme_constant_override("shadow_offset_y", 2)
	_status.add_theme_font_size_override("font_size", 22)
	add_child(_status)
	_message = AcceptDialog.new()
	_message.title = "提示"
	_message.ok_button_text = "确定"
	add_child(_message)
	resized.connect(_layout_hotspots)
	_layout_hotspots()
	_update_status()


func _highlight(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(1.0, 0.7, 0.1)
	style.set_border_width_all(3)
	return style


func _layout_hotspots() -> void:
	var ratio: float = minf(size.x / IMAGE_SIZE.x, size.y / IMAGE_SIZE.y)
	var origin := (size - IMAGE_SIZE * ratio) / 2.0
	for id: String in _hotspots:
		var region: Rect2 = REGIONS[id]
		var button: Button = _hotspots[id]
		button.position = origin + region.position * ratio
		button.size = region.size * ratio
	if is_instance_valid(_status):
		_status.position = Vector2(16, 12)


func _on_hotspot_pressed(id: String) -> void:
	if id == "alchemy":
		if found_recipe == null:
			_show_message("无法打开炼金界面：房间尚未配置配方。")
			return
		if not _progress.is_recipe_unlocked(found_recipe.recipe_id):
			_show_message("尚未获得「%s」配方，请先检查书柜。" % found_recipe.display_name)
			return
		var material_check := AlchemySystem.new(_inventory).check_material_availability(found_recipe)
		if not material_check.ok:
			_show_message(material_check.error)
			return
		if not next_scene_path.is_empty():
			get_tree().change_scene_to_file(next_scene_path)
		return
	if id == "recipe":
		if _progress.is_interaction_claimed(_interaction_id(id)):
			return
		var recipe_check := AlchemySystem.new(_inventory).check_recipe(found_recipe)
		if not recipe_check.ok:
			_show_message("无法获取配方：%s" % recipe_check.error)
			return
		_progress.claim_interaction(_interaction_id(id))
		_progress.unlock_recipe(found_recipe.recipe_id)
		_show_message("获得配方：%s" % found_recipe.display_name)
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


func _update_status() -> void:
	var material_count := 0
	for id in material_rewards:
		if _progress.is_interaction_claimed(_interaction_id(str(id))):
			material_count += 1
	var has_recipe := found_recipe != null and _progress.is_recipe_unlocked(found_recipe.recipe_id)
	_status.text = "清洗剂配方：%s    已搜集：%d / %d处" % ["已获得" if has_recipe else "未获得", material_count, material_rewards.size()]
	for id in _hotspots:
		var button: Button = _hotspots[id]
		button.disabled = id != "alchemy" and _progress.is_interaction_claimed(_interaction_id(str(id)))
		button.mouse_default_cursor_shape = Control.CURSOR_ARROW if button.disabled else Control.CURSOR_POINTING_HAND


func _interaction_id(id: String) -> StringName:
	return StringName("RovinRoom/" + id)


func _show_message(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered()

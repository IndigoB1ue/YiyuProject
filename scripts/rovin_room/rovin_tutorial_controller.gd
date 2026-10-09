class_name RovinTutorialController
extends Node

enum Stage { GET_RECIPE, COLLECT_MATERIALS, ENTER_ALCHEMY }

@export_node_path("CanvasLayer") var tutorial_ui_path: NodePath = ^"../TutorialUI"

var stage: Stage = Stage.GET_RECIPE
var _inventory: InventorySystem
var _progress: GameProgressState
var _recipe: AlchemyRecipe
var _recipe_item_id: StringName
var _rewards: Dictionary
var _hotspots: Dictionary
var _required_materials: Dictionary = {}
var _view: RovinTutorialUI
var _configured := false

func setup(inventory: InventorySystem, progress: GameProgressState, recipe: AlchemyRecipe, recipe_item_id: StringName, rewards: Dictionary, hotspots: Dictionary) -> void:
	_inventory = inventory
	_progress = progress
	_recipe = recipe
	_recipe_item_id = recipe_item_id
	_rewards = rewards
	_hotspots = hotspots
	_view = get_node(tutorial_ui_path) as RovinTutorialUI
	if _recipe != null:
		for requirement in _recipe.ingredients:
			if requirement != null and requirement.item_id != &"":
				_required_materials[requirement.item_id] = int(_required_materials.get(requirement.item_id, 0)) + requirement.amount
	_inventory.inventory_changed.connect(refresh)
	_progress.recipes_changed.connect(refresh)
	_progress.rovin_tutorial_changed.connect(refresh)
	_view.skip_requested.connect(_progress.skip_rovin_tutorial)
	_configured = true
	refresh()

func refresh() -> void:
	if not _configured:
		return
	if not _progress.should_show_rovin_tutorial():
		_view.hide_tutorial()
		return
	# A player who already owns the result has passed this introductory task.
	if _inventory.get_amount(&"clear_potion") >= 1:
		_progress.complete_rovin_tutorial()
		return
	var counts: PackedStringArray = ["清洗剂配方：%d / 1" % _inventory.get_amount(_recipe_item_id)]
	for id in _required_materials:
		var item := _inventory.get_item(id)
		counts.append("%s：%d / %d" % [item.display_name if item != null else str(id), _inventory.get_amount(id), _required_materials[id]])
	var targets: Array[Dictionary] = []
	if _inventory.get_amount(_recipe_item_id) < 1:
		stage = Stage.GET_RECIPE
		var instruction := "先检查高亮的书柜，寻找清洗剂配方。"
		if not _progress.is_interaction_claimed(&"RovinRoom/recipe"):
			_add_target(targets, "recipe", "获取配方")
		else:
			instruction = "背包中已没有配方物品，请补充配方后继续。"
		_view.show_step("第一步 · 寻找配方", instruction, "\n".join(counts), targets)
		return
	var stock_check := AlchemySystem.new(_inventory).check_material_availability(_recipe)
	if not stock_check.ok:
		stage = Stage.COLLECT_MATERIALS
		for id in _rewards:
			var reward: Dictionary = _rewards[id]
			var item_id := StringName(reward.get("item_id", ""))
			if _inventory.get_amount(item_id) < int(_required_materials.get(item_id, 0)) and not _progress.is_interaction_claimed(StringName("RovinRoom/" + str(id))):
				_add_target(targets, str(id), "搜集素材")
		var instruction := "搜寻高亮地点，按下方数量准备素材。可以自由选择搜集顺序。"
		if targets.is_empty():
			instruction = "当前素材仍不足，请补充背包后继续。\n" + str(stock_check.error)
		_view.show_step("第二步 · 收集素材", instruction, "\n".join(counts), targets)
		return
	stage = Stage.ENTER_ALCHEMY
	_add_target(targets, "alchemy", "开始制作")
	_view.show_step("第三步 · 前往炼金", "配方和素材已准备好！点击高亮的炼金区域，开始制作清洗剂。", "\n".join(counts), targets)

func on_alchemy_entered() -> void:
	if _configured:
		_progress.complete_rovin_tutorial()

func update_highlight_positions() -> void:
	if _configured:
		_view.update_highlight_positions()

func _add_target(targets: Array[Dictionary], id: String, label: String) -> void:
	if _hotspots.has(id) and not (_hotspots[id] as Button).disabled:
		var button: Button = _hotspots[id]
		targets.append({"control": button, "label": "%s · %s" % [button.tooltip_text, label]})

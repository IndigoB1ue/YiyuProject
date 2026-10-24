@tool
class_name AlchemyRecipe
extends Resource

@export var recipe_id: StringName
@export var display_name: String
@export_multiline var description: String
## Editor-only notes about narrative clues. Public presentation never reads this.
@export_multiline var designer_notes: String
@export var icon: Texture2D
@export var result_item_id: StringName
@export_range(1, 999) var result_amount: int = 1
@export var ingredients: Array[IngredientRequirement] = []

enum FormulaMode { STANDARD, EXPERIMENTAL }

@export_group("叙事推理公式")
## Standard keeps existing recipes and their saved selections compatible.
@export var formula_mode: FormulaMode = FormulaMode.STANDARD
@export_range(3, 4) var advanced_slot_count: int = 3
@export var advanced_result_item_id: StringName
@export_range(1, 999) var advanced_result_amount: int = 1
## The item is global, but each recipe controls how much waste it produces.
@export_range(1, 999) var waste_result_amount: int = 1


func is_experimental() -> bool:
	return formula_mode == FormulaMode.EXPERIMENTAL


func is_hidden_slot(index: int) -> bool:
	return is_experimental() and index >= 2 and index < ingredients.size()


func accepts_material(index: int, item: ItemData) -> bool:
	if index < 0 or index >= ingredients.size() or ingredients[index] == null:
		return false
	if is_experimental() and item != null and item.alchemy_recipe != null:
		return false
	if not is_hidden_slot(index):
		return ingredients[index].accepts(item)
	if advanced_slot_count == 3 and index == 3:
		return item != null and item.alchemy_recipe == null
	return ingredients[index].accepts_candidate(item)


## One public presentation is shared by alchemy slots and backpack details.
func get_slot_display(index: int, catalog: ItemCatalog) -> Dictionary:
	if index < 0 or index >= ingredients.size() or ingredients[index] == null:
		return {"name": "无效素材槽", "icon": null, "amount": 0}
	if is_hidden_slot(index) and advanced_slot_count == 3 and index == 3:
		return {"name": "未知素材", "icon": preload("res://asserts/image/icon/question_mark.svg"), "amount": ingredients[index].amount}
	return ingredients[index].get_display_data(catalog, is_hidden_slot(index))

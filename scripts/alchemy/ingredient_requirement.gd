@tool
class_name IngredientRequirement
extends Resource

## A specific ID takes precedence. Category is a simple optional extension point.
@export var item_id: StringName
@export var category: StringName
@export_range(1, 999) var amount: int = 1

@export_group("隐藏槽提示与候选")
## item_id is the hidden answer; these fields never filter by that answer.
@export var hint_name: String
@export var hint_icon: Texture2D
@export var candidate_category: StringName

func accepts(item: ItemData) -> bool:
	if item == null:
		return false
	if item_id != &"":
		return item.item_id == item_id
	return category != &"" and item.category == category


func accepts_candidate(item: ItemData) -> bool:
	return item != null and item.alchemy_recipe == null and (candidate_category == &"" or item.category == candidate_category)


func get_display_data(catalog: ItemCatalog, concealed: bool = false) -> Dictionary:
	if concealed:
		return {"name": hint_name if not hint_name.is_empty() else "未知素材", "icon": hint_icon if hint_icon != null else preload("res://asserts/image/icon/question_mark.svg"), "amount": amount}
	var item := catalog.find_item(item_id)
	return {"name": item.display_name if item != null else str(category), "icon": item.icon if item != null else null, "amount": amount}

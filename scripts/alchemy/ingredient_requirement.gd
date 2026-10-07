class_name IngredientRequirement
extends Resource

## A specific ID takes precedence. Category is a simple optional extension point.
@export var item_id: StringName
@export var category: StringName
@export_range(1, 999) var amount: int = 1

func accepts(item: ItemData) -> bool:
	if item == null:
		return false
	if item_id != &"":
		return item.item_id == item_id
	return category != &"" and item.category == category

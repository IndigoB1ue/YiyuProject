@tool
class_name ItemCatalog
extends Resource

@export var items: Array[ItemData] = []
@export var categories: Array[ItemCategory] = []
@export var initial_inventory: Dictionary = {}

@export_group("炼金通用配置")
## All experimental recipes share one waste item, also usable by later recipes.
@export var alchemy_waste_item_id: StringName = &"Heterogeneity"

func find_item(item_id: StringName) -> ItemData:
	for item in items:
		if item != null and item.item_id == item_id:
			return item
	return null

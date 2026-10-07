class_name ItemCatalog
extends Resource

@export var items: Array[ItemData] = []
@export var initial_inventory: Dictionary = {}

func find_item(item_id: StringName) -> ItemData:
	for item in items:
		if item != null and item.item_id == item_id:
			return item
	return null

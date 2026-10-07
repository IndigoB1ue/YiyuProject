class_name InventorySystem
extends Node

signal inventory_changed

@export var catalog: ItemCatalog = preload("res://data/items/catalog.tres")
var _items: Dictionary = {}

func _ready() -> void:
	for id in catalog.initial_inventory:
		add_item(StringName(id), int(catalog.initial_inventory[id]))

func get_item(item_id: StringName) -> ItemData:
	return catalog.find_item(item_id)

func get_amount(item_id: StringName) -> int:
	return int(_items.get(item_id, 0))

func get_items() -> Dictionary:
	return _items.duplicate()

func add_item(item_id: StringName, amount: int) -> Dictionary:
	return exchange({}, item_id, amount)

func remove_item(item_id: StringName, amount: int) -> Dictionary:
	if amount <= 0:
		return _error("减少数量必须是正整数。")
	return exchange({item_id: amount})

## Validate the entire change before committing; observers see only the final inventory.
func exchange(costs: Dictionary, result_id: StringName = &"", result_amount: int = 0) -> Dictionary:
	if result_id != &"" and (get_item(result_id) == null or result_amount <= 0):
		return _error("成品 ItemID 无效或成品数量不合法：%s" % result_id)
	if result_id == &"" and result_amount != 0:
		return _error("缺少成品 ItemID。")
	for id in costs:
		var item := get_item(StringName(id))
		if item == null:
			return _error("素材 ItemID 无效：%s" % id)
		if not costs[id] is int or costs[id] <= 0:
			return _error("素材数量必须是正整数：%s" % id)
		if get_amount(StringName(id)) < costs[id]:
			return _error("%s 数量不足，需要 %d，背包剩余 %d。" % [item.display_name, costs[id], get_amount(StringName(id))])
	var updated := _items.duplicate()
	for id in costs:
		var key := StringName(id)
		updated[key] = get_amount(key) - int(costs[id])
		if updated[key] == 0:
			updated.erase(key)
	if result_id != &"":
		updated[result_id] = int(updated.get(result_id, 0)) + result_amount
	_items = updated
	inventory_changed.emit()
	return {"ok": true, "error": ""}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

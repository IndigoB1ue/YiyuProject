class_name QuestDeliveryService
extends RefCounted

var _manager: Node
var _inventory: InventorySystem


func _init(manager: Node = null, inventory: InventorySystem = null) -> void:
	set_dependencies(manager, inventory)


func set_dependencies(manager: Node, inventory: InventorySystem) -> void:
	_manager = manager
	_inventory = inventory


func can_deliver(quest_id: StringName, objective_id: StringName, recipient_id: StringName) -> Dictionary:
	if _manager == null or _inventory == null or not _manager.can_process_events():
		return _error("当前不能交付任务物品。")
	var objective: QuestObjectiveData = _manager.get_active_objective(quest_id, objective_id)
	if objective == null or objective.kind != &"delivery":
		return _error("这项目标尚未开启或已经完成。")
	if objective.actor_id == &"" or objective.actor_id != recipient_id:
		return _error("请向任务指定的对象交付物品。")
	if objective.items.is_empty():
		return _error("交付目标尚未配置所需物品。")
	var costs: Dictionary = {}
	var missing: PackedStringArray = []
	for id in objective.items:
		if not (id is String or id is StringName) or not objective.items[id] is int or objective.items[id] < 1:
			return _error("交付目标的物品配置无效。")
		var item_id := StringName(id)
		var item := _inventory.get_item(item_id)
		if item == null:
			return _error("交付目标包含不存在的物品。")
		var amount: int = objective.items[id]
		costs[item_id] = amount
		if _inventory.get_amount(item_id) < amount:
			missing.append("%s：需要 %d，现有 %d。" % [item.display_name, amount, _inventory.get_amount(item_id)])
	if not missing.is_empty():
		return _error("交付物品不足：\n" + "\n".join(missing))
	return {"ok": true, "error": "", "items": costs, "stage_id": _manager.get_active_stage(quest_id).stage_id}


## One inventory transaction credits only the explicitly selected objective.
func deliver(quest_id: StringName, objective_id: StringName, recipient_id: StringName) -> Dictionary:
	var check := can_deliver(quest_id, objective_id, recipient_id)
	if not check.ok:
		return check
	_manager.begin_transaction()
	var result := _inventory.exchange(check.items)
	if not result.ok:
		_manager.end_transaction()
		return result
	var id := "delivery:%d:%d" % [_inventory.get_instance_id(), Time.get_ticks_usec()]
	_manager.report_event(&"delivery", {"quest_id": quest_id, "objective_id": objective_id, "stage_id": check.stage_id,
		"actor_id": recipient_id, "items": check.items.duplicate(), "delivery_id": id}, id)
	_manager.end_transaction()
	return {"ok": true, "error": "", "items": check.items.duplicate(), "delivery_id": id}


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

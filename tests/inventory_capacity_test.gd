extends SceneTree

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var inventory := InventorySystem.new()
	var catalog := ItemCatalog.new()
	for index in 201:
		var item := ItemData.new()
		item.item_id = StringName("CapacityTest%d" % index)
		item.display_name = str(item.item_id)
		catalog.items.append(item)
	inventory.catalog = catalog
	root.add_child(inventory)
	for index in 200:
		_expect(inventory.add_item(StringName("CapacityTest%d" % index), 1).ok, "Fill all 200 slots")
	_expect(inventory.get_occupied_slots() == 200, "All occupied slots are counted")
	_expect(inventory.add_item(&"CapacityTest0", 2).ok, "Stacking an existing ID succeeds in a full bag")
	_expect(inventory.get_occupied_slots() == 200 and inventory.get_amount(&"CapacityTest0") == 3, "Stacks do not need extra slots")
	var notifications: Array[int] = []
	inventory.inventory_changed.connect(func() -> void: notifications.append(1))
	var before := inventory.get_items()
	var rejected := inventory.add_item(&"CapacityTest200", 1)
	_expect(not rejected.ok and rejected.error.contains("背包已满"), "New types fail with a clear capacity error")
	_expect(inventory.get_items() == before and notifications.is_empty(), "Rejected additions leave data and observers untouched")
	rejected = inventory.exchange({&"CapacityTest0": 1}, &"CapacityTest200", 1)
	_expect(not rejected.ok and inventory.get_items() == before, "Failed crafting cannot consume a partial stack")
	_expect(inventory.exchange({&"CapacityTest0": 3}, &"CapacityTest200", 1).ok, "Crafting can use a freed ingredient slot for its output")
	_expect(inventory.get_amount(&"CapacityTest0") == 0 and inventory.get_amount(&"CapacityTest200") == 1 and inventory.get_occupied_slots() == 200,
		"The full exchange commits as one transaction")
	_expect(notifications.size() == 1, "Successful exchange emits only one update")
	inventory.queue_free()
	await process_frame
	print("Inventory capacity: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

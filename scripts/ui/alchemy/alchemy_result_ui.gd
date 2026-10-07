class_name AlchemyResultUI
extends AcceptDialog

func show_result(result: Dictionary, inventory: InventorySystem) -> void:
	if result.ok:
		title = "炼金成功！"
		var item := inventory.get_item(result.item_id)
		dialog_text = "获得：\n%s ×%d" % [item.display_name, result.amount]
	else:
		title = "无法炼金"
		dialog_text = result.error
	popup_centered()

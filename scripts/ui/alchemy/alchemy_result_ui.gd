class_name AlchemyResultUI
extends AcceptDialog

signal result_confirmed(result: Dictionary)

var _last_result: Dictionary = {}

func show_result(result: Dictionary, inventory: InventorySystem) -> void:
	_last_result = result.duplicate()
	if result.ok:
		title = "炼金完成" if result.get("outcome", &"") == &"waste" else "炼金成功！"
		var item := inventory.get_item(result.item_id)
		dialog_text = "获得：\n%s ×%d" % [item.display_name, result.amount]
		if result.get("outcome", &"") == &"waste":
			dialog_text += "\n\n本次调和产生了异质，投入的素材已消耗。"
	else:
		title = "无法炼金"
		dialog_text = result.error
	popup_centered()

func _on_result_dismissed() -> void:
	if _last_result.is_empty():
		return
	var result := _last_result
	_last_result = {}
	result_confirmed.emit(result)

func _on_result_canceled() -> void:
	# Closing a popup is not a confirmation of the synthesized output.
	_last_result = {}

class_name InventorySlotUI
extends Button

signal item_selected(item_id: StringName)

var item_id: StringName = &""

@onready var _icon: TextureRect = $Icon
@onready var _quantity: Label = $Quantity


func display(item: ItemData, amount: int, selected: bool) -> void:
	item_id = item.item_id if item != null else &""
	disabled = item == null
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	set_pressed_no_signal(selected and item != null)
	_icon.texture = item.icon if item != null else null
	_quantity.text = "×%d" % amount if item != null else ""
	tooltip_text = "%s ×%d\n%s" % [item.display_name, amount, item.description] if item != null else ""
	if item == null:
		theme_type_variation = &"InventoryEmptyCell"
	else:
		theme_type_variation = &"InventoryRecipeCell" if item.alchemy_recipe != null else &"InventoryMaterialCell"
		if item.icon == null:
			_icon.texture = preload("res://data/items/question_mark.svg")


func _on_pressed() -> void:
	if item_id != &"":
		item_selected.emit(item_id)

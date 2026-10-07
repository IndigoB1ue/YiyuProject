class_name IngredientSlotUI
extends Button

signal select_requested
signal clear_requested

@onready var _icon: TextureRect = $Layout/Icon
@onready var _name_label: Label = $Layout/IngredientName
@onready var _count: Label = $Layout/Count

func _on_pressed() -> void:
	set_pressed_no_signal(true)
	select_requested.emit()

func _on_activated() -> void:
	select_requested.emit()

func display(requirement: IngredientRequirement, selected: Dictionary, inventory: InventorySystem, system: AlchemySystem, active: bool) -> void:
	var item := inventory.get_item(requirement.item_id)
	var ingredient_name := item.display_name if item != null else str(requirement.category)
	_icon.texture = item.icon if item != null else null
	_name_label.text = ingredient_name
	_count.text = "%d / %d" % [system.selected_amount(selected), requirement.amount]
	set_pressed_no_signal(active)
	tooltip_text = "%s：需要 %d 个\n悬停或点击查看素材；右键清空已选素材" % [ingredient_name, requirement.amount]

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		clear_requested.emit()
		accept_event()

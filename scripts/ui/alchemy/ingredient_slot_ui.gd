@tool
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

func display(requirement: IngredientRequirement, selected: Dictionary, inventory: InventorySystem, system: AlchemySystem, active: bool, public_data: Dictionary = {}, optional: bool = false) -> void:
	var presentation := requirement.get_display_data(inventory.catalog) if public_data.is_empty() else public_data
	var ingredient_name: String = presentation.name
	_icon.texture = presentation.icon
	_name_label.text = ingredient_name
	_count.text = "%d / %d" % [system.selected_amount(selected), requirement.amount]
	set_pressed_no_signal(active)
	tooltip_text = "%s：%s，每槽 %d 个\n悬停或点击查看素材；右键清空已选素材" % [ingredient_name, "选填" if optional else "必填", requirement.amount]

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		clear_requested.emit()
		accept_event()

extends CanvasLayer

signal inventory_opened
signal inventory_closed

@export var slot_scene: PackedScene
@export var requirement_scene: PackedScene
@export_file("*.tscn") var room_scene_path := "res://scenes/RovinRoom.tscn"

var _inventory: InventorySystem
var _dialogic: Node
var _selected_id: StringName = &""
var _owned_items: Array[ItemData] = []
var _previous_focus: WeakRef

@onready var _overlay: Control = %Overlay
@onready var _open_button: Button = %OpenButton
@onready var _grid: GridContainer = %Grid
@onready var _scroll: ScrollContainer = %ItemScroll
@onready var _capacity_label: Label = %CapacityLabel
@onready var _details: PanelContainer = %Details
@onready var _detail_icon: TextureRect = %DetailIcon
@onready var _detail_name: Label = %DetailName
@onready var _detail_description: Label = %DetailDescription
@onready var _ingredients_heading: Label = %IngredientsHeading
@onready var _ingredients: GridContainer = %Ingredients
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_inventory = get_node("/root/PlayerInventory") as InventorySystem
	_dialogic = get_node("/root/Dialogic")
	_overlay.hide()
	_open_button.hide()
	_details.hide()
	_inventory.inventory_changed.connect(_on_inventory_changed)
	_dialogic.timeline_started.connect(_on_context_changed)
	_dialogic.timeline_ended.connect(_on_context_changed)
	get_tree().scene_changed.connect(_on_context_changed)
	_rebuild_slots()
	_refresh_entry.call_deferred()


func is_open() -> bool:
	return _overlay.visible


## No arguments: usable from a Dialogic Call event or a room button.
func open_inventory() -> void:
	if is_open() or not _can_open():
		return
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus != null else null
	_selected_id = &""
	_details.hide()
	_rebuild_slots()
	_scroll.scroll_vertical = 0
	_overlay.show()
	_open_button.hide()
	get_node("/root/OverlayPauseManager").acquire(self)
	_close_button.grab_focus()
	inventory_opened.emit()


func close_inventory() -> void:
	if not is_open():
		return
	_overlay.hide()
	get_viewport().set_input_as_handled()
	get_node("/root/OverlayPauseManager").release(self)
	if _dialogic.current_timeline != null:
		_dialogic.Inputs.block_input(0.15)
	if _previous_focus != null:
		var focus = _previous_focus.get_ref()
		if is_instance_valid(focus) and focus.is_visible_in_tree():
			focus.grab_focus()
	_previous_focus = null
	_refresh_entry()
	inventory_closed.emit()


func toggle_inventory() -> void:
	if is_open():
		close_inventory()
	else:
		open_inventory()


func _input(event: InputEvent) -> void:
	if _settings_are_open():
		return
	# Catch the entry click before Dialogic treats it as a dialogue advance.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_open() and _open_button.visible and _open_button.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			open_inventory()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("inventory_toggle"):
		var focus := get_viewport().gui_get_focus_owner()
		if not is_open() and (focus is LineEdit or focus is TextEdit):
			return
		if is_open() or _can_open():
			get_viewport().set_input_as_handled()
			toggle_inventory()
	elif is_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_inventory()


func _unhandled_input(_event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()


func _can_open() -> bool:
	if _settings_are_open():
		return false
	var scene := get_tree().current_scene
	return _dialogic.current_timeline != null or (scene != null and scene.scene_file_path == room_scene_path)


func _settings_are_open() -> bool:
	var settings_ui := get_node_or_null("/root/SettingsUI")
	var save_ui := get_node_or_null("/root/SaveUI")
	var quest_ui := get_node_or_null("/root/QuestUI")
	return (settings_ui != null and settings_ui.is_open()) or (save_ui != null and save_ui.is_open()) or (quest_ui != null and quest_ui.is_open())


func _refresh_entry() -> void:
	_open_button.visible = not is_open() and _can_open()


func _on_context_changed() -> void:
	close_inventory()
	_refresh_entry.call_deferred()


func _on_inventory_changed() -> void:
	if is_open():
		_rebuild_slots()


func _rebuild_slots() -> void:
	_owned_items.clear()
	for id in _inventory.get_items():
		var item := _inventory.get_item(StringName(id))
		if item != null:
			_owned_items.append(item)
	_owned_items.sort_custom(func(a: ItemData, b: ItemData) -> bool:
		if (a.alchemy_recipe != null) != (b.alchemy_recipe != null):
			return a.alchemy_recipe != null
		var name_order := a.display_name.naturalnocasecmp_to(b.display_name)
		return name_order < 0 if name_order != 0 else str(a.item_id) < str(b.item_id)
	)
	while _grid.get_child_count() > _inventory.capacity:
		var old := _grid.get_child(-1)
		_grid.remove_child(old)
		old.queue_free()
	while _grid.get_child_count() < _inventory.capacity:
		_grid.add_child(slot_scene.instantiate())
	for index in _grid.get_child_count():
		var slot := _grid.get_child(index) as InventorySlotUI
		if not slot.item_selected.is_connected(_select_item):
			slot.item_selected.connect(_select_item)
		var item: ItemData = _owned_items[index] if index < _owned_items.size() else null
		slot.display(item, _inventory.get_amount(item.item_id) if item != null else 0,
			item != null and item.item_id == _selected_id)
	_capacity_label.text = "%d / %d 格" % [_inventory.get_occupied_slots(), _inventory.capacity]
	if _selected_id != &"" and _inventory.get_amount(_selected_id) > 0:
		_show_details(_inventory.get_item(_selected_id))
	else:
		_selected_id = &""
		_details.hide()


func _select_item(item_id: StringName) -> void:
	if _inventory.get_amount(item_id) <= 0:
		return
	_selected_id = item_id
	for slot: InventorySlotUI in _grid.get_children():
		slot.set_pressed_no_signal(slot.item_id == item_id)
	_show_details(_inventory.get_item(item_id))


func _show_details(item: ItemData) -> void:
	_details.show()
	_detail_icon.texture = item.icon if item.icon != null else preload("res://asserts/image/icon/question_mark.svg")
	_detail_name.text = "%s  ×%d" % [item.display_name, _inventory.get_amount(item.item_id)]
	_detail_description.text = item.description
	for child in _ingredients.get_children():
		_ingredients.remove_child(child)
		child.queue_free()
	_ingredients_heading.visible = item.alchemy_recipe != null
	_ingredients.visible = item.alchemy_recipe != null
	if item.alchemy_recipe == null:
		return
	if item.alchemy_recipe.is_experimental():
		# Preserve four public slots; combining by the hidden ItemID would expose answers.
		for index in item.alchemy_recipe.ingredients.size():
			var presentation := item.alchemy_recipe.get_slot_display(index, _inventory.catalog)
			var badge := requirement_scene.instantiate()
			_ingredients.add_child(badge)
			badge.display(presentation.icon, "%s ×%d" % [presentation.name, presentation.amount])
		return
	# Alchemy slots may repeat an ItemID; show the combined requirement in the bag.
	var required := {}
	for requirement in item.alchemy_recipe.ingredients:
		if requirement == null:
			continue
		var key := str(requirement.item_id) if requirement.item_id != &"" else "category:" + str(requirement.category)
		required[key] = int(required.get(key, 0)) + requirement.amount
	for key: String in required:
		var material := _inventory.get_item(StringName(key))
		var title := material.display_name if material != null else key.trim_prefix("category:")
		var badge := requirement_scene.instantiate()
		_ingredients.add_child(badge)
		badge.display(material.icon if material != null else null, "%s ×%d" % [title, required[key]])

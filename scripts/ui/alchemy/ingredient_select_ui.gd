class_name IngredientSelectUI
extends VBoxContainer

signal material_selected(item_id: StringName, amount: int)

@export var minimum_cells: int = 24
@export var material_cell_scene: PackedScene
@export var empty_cell_scene: PackedScene

@onready var _heading: Label = $Heading
@onready var _hint: Label = $Hint
@onready var _scroll: ScrollContainer = $Scroll
@onready var _grid: GridContainer = $Scroll/Grid

## Each available unit is represented by one cell; inventory itself stays count based.
func display(options: Array[Dictionary], remaining: int, ingredient_name: String) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var available := 0
	for option in options:
		available += int(option.amount)
	_heading.text = "%s · 可选素材 %d 个" % [ingredient_name, available]
	if ingredient_name.is_empty():
		_heading.text = "背包素材"
		_hint.text = "选择配方和素材需求后，在这里查看可用素材。"
	elif remaining <= 0:
		_hint.text = "此槽已选满。可切换其他需求，或清空此槽重新选择。"
	elif options.is_empty():
		_hint.text = "背包中没有可用的匹配素材，当前槽还需 %d 个。" % remaining
	else:
		_hint.text = "每格代表 1 个素材，点击选入；当前槽还需 %d 个。" % remaining
	for option in options:
		var item: ItemData = option.item
		for unit in int(option.amount):
			var cell := material_cell_scene.instantiate() as Button
			cell.icon = item.icon
			cell.tooltip_text = "%s\n%s\n点击选择 1 个" % [item.display_name, item.description]
			if item.icon == null:
				cell.text = item.display_name
			cell.disabled = remaining <= 0
			cell.pressed.connect(func() -> void: material_selected.emit(item.item_id, 1))
			_grid.add_child(cell)
	for index in maxi(0, minimum_cells - available):
		_grid.add_child(empty_cell_scene.instantiate())
	_resize_grid()

func _resize_grid() -> void:
	if not is_node_ready() or _grid.get_child_count() == 0:
		return
	var cell: Control = _grid.get_child(0)
	var gap := _grid.get_theme_constant("h_separation")
	var scrollbar_width := _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	_grid.columns = maxi(1, int((_scroll.size.x - scrollbar_width + gap) / maxf(1, cell.get_combined_minimum_size().x + gap)))

func reset_scroll() -> void:
	_scroll.scroll_vertical = 0

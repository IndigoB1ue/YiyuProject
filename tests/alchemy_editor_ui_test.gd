extends SceneTree

const PANEL = preload("res://addons/alchemy_editor/main_panel.tscn")
const Store = preload("res://addons/alchemy_editor/resource_store.gd")
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var base := "user://alchemy_editor_ui_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base.path_join("recipes")))
	# Use disposable catalogs. Every save below is outside project content.
	var items := (load("res://data/items/catalog.tres") as ItemCatalog).duplicate(true) as ItemCatalog
	for item in items.items:
		item.alchemy_recipe = null
	var recipes := AlchemyCatalog.new()
	var formula := (load("res://data/recipes/experiment_three.tres") as AlchemyRecipe).duplicate(true) as AlchemyRecipe
	ResourceSaver.save(formula, base.path_join("recipes/formula.tres"))
	formula.take_over_path(base.path_join("recipes/formula.tres"))
	recipes.recipes.append(formula)
	ResourceSaver.save(items, base.path_join("items.tres"))
	ResourceSaver.save(recipes, base.path_join("recipes/catalog.tres"))
	var store = Store.new()
	_expect(store.load_catalogs(base.path_join("items.tres"), base.path_join("recipes/catalog.tres")).ok, "Disposable catalogs load")
	var live_inventory := (root.get_node("PlayerInventory") as InventorySystem).get_items()
	var panel = PANEL.instantiate()
	root.add_child(panel)
	await process_frame
	panel.setup(store)
	await process_frame
	_expect(not panel.has_unsaved_changes(), "Opening a recipe creates a clean draft")
	_expect(panel._recipe_form.get_resource() != store.recipes.recipes[0], "Recipe form works on an isolated copy")
	var name_field: LineEdit = panel._recipe_form.get_node("%DisplayName")
	name_field.text = "编辑器验收配方"
	name_field.text_changed.emit(name_field.text)
	_expect(panel.has_unsaved_changes(), "Typing makes draft dirty")
	_expect(store.recipes.recipes[0].display_name != name_field.text, "Typing does not mutate live resources")
	panel._undo()
	_expect(not panel.has_unsaved_changes() and name_field.text == formula.display_name, "Undo returns to saved state")
	panel._redo()
	_expect(panel.has_unsaved_changes() and name_field.text == "编辑器验收配方", "Redo restores draft")
	panel._tabs.current_tab = 1
	_expect(panel.get_node("%Unsaved").visible and panel._page == 0, "Switching dirty page asks for a decision")
	panel.get_node("%Unsaved").hide()
	panel._unsaved_action(&"discard")
	_expect(panel._page == 1 and not panel.has_unsaved_changes(), "Discard continues without saving draft")
	_expect(store.recipes.recipes[0].display_name == formula.display_name, "Discard preserves saved resource")
	panel._tabs.current_tab = 0
	panel._copy()
	var duplicate: AlchemyRecipe = panel._recipe_form.get_resource()
	_expect(panel._new and duplicate.recipe_id != formula.recipe_id, "Copy generates a distinct stable ID")
	_expect(panel._save_current(), "Copied recipe saves through editor")
	_expect(store.recipes.recipes.size() == 2 and not panel.has_unsaved_changes(), "New recipe registered and draft cleaned")
	var draft_id: StringName = panel._recipe_form.get_resource().recipe_id
	panel._quick_create("result_item_id")
	var item_form = panel.get_node("%QuickItemForm")
	var item: ItemData = item_form.get_resource()
	item.display_name = ""
	panel.get_node("%QuickCreate").get_ok_button().pressed.emit()
	await process_frame
	_expect(panel.get_node("%QuickCreate").visible and not panel.get_node("%QuickError").text.is_empty(), "Invalid quick creation stays open with a clear error")
	item.display_name = "快速创建成品"
	item.icon = load("res://data/items/potion.svg")
	var new_id := item.item_id
	panel._save_quick_item()
	panel.get_node("%QuickCreate").hide()
	_expect(store.items.find_item(new_id) != null, "Quick-created item is saved in shared catalog")
	_expect(panel._recipe_form.get_resource().recipe_id == draft_id and panel._recipe_form.get_resource().result_item_id == new_id, "Quick create returns to same recipe draft and chosen field")
	_expect(panel.has_unsaved_changes(), "Quick-create assignment is undoable unsaved recipe edit")
	_expect(panel._save_current(), "Recipe can save with newly created item")
	# Author a new formula from its empty four-slot form, then exercise the saved data.
	panel._create()
	var authored: AlchemyRecipe = panel._recipe_form.get_resource()
	authored.display_name = "全新推理配方"
	panel._recipe_form.set_item_for_field("result_item_id", new_id)
	panel._recipe_form.set_item_for_field("advanced_result_item_id", &"ExperimentAdvanced")
	panel._recipe_form.set_item_for_field("ingredient_0", &"Herb")
	panel._recipe_form.set_item_for_field("ingredient_1", &"Water")
	panel._recipe_form.set_item_for_field("ingredient_2", &"ExperimentLeaf")
	panel._recipe_form._slot_forms[2]._on_hint_type_selected(1)
	_expect(panel._save_current(), "New formula saves after filling choices, quantities and type hints")
	panel._preview.set_trial_stock({&"Herb": 5, &"Water": 5, &"ExperimentLeaf": 5})
	var selection: Array[Dictionary] = [{&"Herb": 1}, {&"Water": 1}, {}, {}]
	panel._preview.set_trial_selection(selection)
	var outcome: Dictionary = panel._preview.run_trial()
	_expect(outcome.ok and outcome.item_id == new_id, "Newly authored formula produces its newly created A item")
	selection[2] = {&"ExperimentLeaf": 1}
	panel._preview.set_trial_selection(selection)
	outcome = panel._preview.run_trial()
	_expect(outcome.ok and outcome.outcome == &"advanced", "New formula's correct hidden answer yields B")
	selection[2] = {&"Herb": 1}
	panel._preview.set_trial_selection(selection)
	outcome = panel._preview.run_trial()
	_expect(outcome.ok and outcome.item_id == &"Heterogeneity", "New formula's wrong allowed material yields the global waste")
	panel._tabs.current_tab = 2
	var common = panel._common_form
	common._select(0)
	_expect(not common._id.editable, "Saved category IDs are locked")
	common._add()
	_expect(common._id.editable, "New category ID is editable")
	panel._undo()
	_expect(common.get_resource().categories.size() == store.items.categories.size(), "Category creation supports undo")
	panel._redo()
	common._select(common.get_resource().categories.size() - 1)
	_expect(common._id.editable, "Undo history preserves new-category ID editability")
	panel._request_change(func(): panel._page = 0; panel._select_first())
	panel.get_node("%Unsaved").hide()
	panel._unsaved_action(&"discard")
	panel._check_all()
	_expect(panel._issues.item_count > 0, "Project-wide validation is available")
	_expect((root.get_node("PlayerInventory") as InventorySystem).get_items() == live_inventory, "Authoring and trial never touch game inventory")
	var room: AlchemyUI = load("res://scenes/AlchemyRoom.tscn").instantiate()
	_expect(room.recipe_catalog != null and room.recipes == room.recipe_catalog.recipes, "Runtime alchemy reads shared recipe catalog before mounting")
	var packed := PackedScene.new()
	packed.pack(room)
	var state := packed.get_state()
	var baked_override := false
	for index in state.get_node_property_count(0):
		baked_override = baked_override or state.get_node_property_name(0, index) == &"recipes"
	_expect(not baked_override, "Packing a catalog-backed scene does not bake a stale recipe list")
	room.recipes = []
	_expect(room.recipes.is_empty(), "Explicit empty recipe override remains supported")
	room.free()
	panel.queue_free()
	await process_frame
	print("Alchemy editor UI tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

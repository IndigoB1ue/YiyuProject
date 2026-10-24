extends SceneTree

const PANEL := preload("res://addons/alchemy_editor/main_panel.tscn")
const STORE := preload("res://addons/alchemy_editor/resource_store.gd")
const ICON := preload("res://asserts/image/icon/ingredient/herb.svg")
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _ids(panel) -> Array[StringName]:
	var ids: Array[StringName] = []
	for index in panel._list.item_count:
		ids.append(panel._list.get_item_metadata(index).item_id)
	return ids

func _choose_filter(panel, index: int) -> void:
	panel._item_filter_option.select(index)
	panel._item_filter_option.item_selected.emit(index)

func _search(panel, query: String) -> void:
	panel._search.text = query
	panel._search.text_changed.emit(query)

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var base := "user://alchemy_editor_filter_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base.path_join("recipes")))
	var recipe := AlchemyRecipe.new()
	recipe.recipe_id = &"FilterRecipe"
	recipe.display_name = "筛选测试公式"
	recipe.result_item_id = &"OutputA"
	recipe.icon = ICON
	var requirement := IngredientRequirement.new()
	requirement.item_id = &"Herb"
	recipe.ingredients.append(requirement)
	var recipe_file := base.path_join("recipes/formula.tres")
	ResourceSaver.save(recipe, recipe_file)
	recipe.take_over_path(recipe_file)
	var catalog := ItemCatalog.new()
	for id in [&"Herb", &"OutputA", &"OutputB", &"Heterogeneity", &"RecipeBook"]:
		var item := ItemData.new()
		item.item_id = id
		item.display_name = "异质" if id == &"Heterogeneity" else String(id)
		item.icon = ICON
		if id == &"RecipeBook":
			item.alchemy_recipe = recipe
		catalog.items.append(item)
	var recipes := AlchemyCatalog.new()
	recipes.recipes.append(recipe)
	ResourceSaver.save(catalog, base.path_join("items.tres"))
	ResourceSaver.save(recipes, base.path_join("recipes/catalog.tres"))
	var store = STORE.new()
	_expect(store.load_catalogs(base.path_join("items.tres"), base.path_join("recipes/catalog.tres")).ok, "Disposable catalogs load")
	var inventory := root.get_node("PlayerInventory") as InventorySystem
	var before := inventory.get_items()
	var panel = PANEL.instantiate()
	root.add_child(panel)
	await process_frame
	panel.setup(store)
	_expect(not panel._item_filter_option.visible, "Item filter is hidden on formula page")
	panel._tabs.current_tab = 1
	_expect(panel._item_filter_option.visible and _ids(panel).size() == 5, "All lists both ordinary items and recipe books")
	_choose_filter(panel, 1)
	_expect(_ids(panel) == [&"Herb", &"OutputA", &"OutputB", &"Heterogeneity"], "Items includes ingredients, A/B outputs and waste")
	_choose_filter(panel, 2)
	_expect(_ids(panel) == [&"RecipeBook"] and panel._original.item_id == &"RecipeBook", "Recipe-book filter selects only associated inventory items")
	_search(panel, "missing")
	_expect(_ids(panel).is_empty(), "Search combines with the active kind filter")
	_search(panel, "RecipeBook")
	_expect(_ids(panel) == [&"RecipeBook"], "Search still finds a matching recipe book")
	_search(panel, "")
	var field: LineEdit = panel._item_form.get_node("%DisplayName")
	field.text = "尚未保存的配方道具"
	field.text_changed.emit(field.text)
	_choose_filter(panel, 1)
	_expect(panel.get_node("%Unsaved").visible and panel._item_filter_option.selected == 2 and panel._item_filter == 2, "Leaving an excluded dirty item prompts before committing filter")
	panel.get_node("%Unsaved").hide()
	panel.get_node("%Unsaved").canceled.emit()
	_expect(panel.has_unsaved_changes() and panel._item_form.get_resource().display_name == field.text, "Cancel preserves draft and original filter")
	_choose_filter(panel, 0)
	_expect(panel.has_unsaved_changes() and not panel.get_node("%Unsaved").visible, "Widening filter keeps the current draft without a destructive navigation")
	_choose_filter(panel, 1)
	panel.get_node("%Unsaved").hide()
	panel._unsaved_action(&"discard")
	_expect(panel._item_filter == 1 and not panel.has_unsaved_changes() and panel._original.item_id == &"Herb", "Discard completes filtering and selects a matching item")
	_choose_filter(panel, 2)
	field.text = "已保存的配方道具"
	field.text_changed.emit(field.text)
	_choose_filter(panel, 1)
	panel.get_node("%Unsaved").hide()
	panel._save_and_continue()
	_expect(panel._item_filter == 1 and not panel.has_unsaved_changes(), "Save-and-continue completes the requested filter")
	_expect(store.items.find_item(&"RecipeBook").display_name == "已保存的配方道具", "Filter navigation saved to the isolated catalog")
	panel._tabs.current_tab = 0
	_expect(not panel._item_filter_option.visible, "Formula page hides the filter")
	panel._tabs.current_tab = 1
	_expect(panel._item_filter_option.selected == 1 and _ids(panel).size() == 4, "Returning to item page remembers its filter")
	# A catalog without recipe books has a valid empty filtered state.
	for item in store.items.items:
		item.alchemy_recipe = null
	_choose_filter(panel, 2)
	_expect(_ids(panel).is_empty() and panel._cursor == -1 and panel.get_node("%Empty").visible, "No matching books clears the form and preview safely")
	_expect(panel.get_node("%Save").disabled and panel.get_node("%Delete").disabled, "Empty filter disables invalid actions")
	_expect(inventory.get_items() == before, "Filtering and saving editor catalogs do not touch game inventory")
	if OS.get_cmdline_user_args().has("--capture"):
		_choose_filter(panel, 1)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/alchemy_editor_filter.png")
	panel.queue_free()
	await process_frame
	print("Alchemy editor filter tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

const Store = preload("res://addons/alchemy_editor/resource_store.gd")
var _failures := 0
var _base: String
var _store: AlchemyEditorStore

class FailingStore extends AlchemyEditorStore:
	var install_count := 0
	func _install_staged_file(stage: String, target: String) -> Error:
		install_count += 1
		if install_count == 2:
			return ERR_CANT_CREATE
		return super._install_staged_file(stage, target)

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _has_error(issues: Array[Dictionary], field: String = "") -> bool:
	for issue in issues:
		if issue.severity == "error" and (field.is_empty() or String(issue.field).begins_with(field)):
			return true
	return false

func _run() -> void:
	var production := Store.new()
	_expect(production.load_catalogs().ok, "Project catalogs load through the editor backend")
	_expect(not _has_error(production.validate_project()), "Existing standard and experimental recipes remain valid")
	_base = "user://alchemy_editor_store_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base.path_join("recipes")))
	var catalog := ItemCatalog.new()
	var category := ItemCategory.new()
	category.category_id = &"Plant"
	category.display_name = "植物"
	category.icon = load("res://data/items/category_plant.svg")
	catalog.categories.append(category)
	for id in [&"Herb", &"Water", &"Leaf", &"OutputA", &"OutputB", &"Waste", &"Spare"]:
		var item := ItemData.new()
		item.item_id = id
		item.display_name = "异质" if id == &"Waste" else String(id)
		item.category = &"Plant" if id in [&"Herb", &"Leaf"] else &""
		item.icon = category.icon
		catalog.items.append(item)
	catalog.alchemy_waste_item_id = &"Waste"
	catalog.initial_inventory = {&"Herb": 3, &"Water": 2}
	var initial := catalog.initial_inventory.duplicate()
	var recipe_catalog := AlchemyCatalog.new()
	var item_path := _base.path_join("items.tres")
	var recipe_path := _base.path_join("recipes/catalog.tres")
	_expect(ResourceSaver.save(catalog, item_path) == OK, "Fixture item catalog saves")
	_expect(ResourceSaver.save(recipe_catalog, recipe_path) == OK, "Fixture recipe catalog saves")
	_store = Store.new()
	_expect(_store.load_catalogs(item_path, recipe_path).ok, "Catalogs load without touching production resources")
	var draft := _recipe()
	_expect(not _has_error(_store.validate_recipe(draft)), "Three-slot formula accepts empty unknown fourth slot")
	var created := _store.save_recipe(draft)
	_expect(created.ok, "New recipe and its catalog save together: %s" % created.get("error", ""))
	if not created.ok:
		_finish()
		return
	var recipe: AlchemyRecipe = created.resource
	var recipe_uid := ResourceUID.create_id()
	_expect(ResourceSaver.set_uid(ProjectSettings.globalize_path(recipe.resource_path), recipe_uid) == OK, "Fixture assigns a persistent recipe UID")
	_expect(FileAccess.get_file_as_string(recipe.resource_path).contains(ResourceUID.id_to_text(recipe_uid)), "Assigned UID is stored in the actual resource file")
	if ResourceUID.has_id(recipe_uid):
		ResourceUID.set_id(recipe_uid, recipe.resource_path)
	else:
		ResourceUID.add_id(recipe_uid, recipe.resource_path)
	_expect(recipe.resource_path == _base.path_join("recipes/TestRecipe.tres"), "New recipe uses stable final resource path")
	_expect(_store.recipes.recipes.has(recipe), "New recipe is registered automatically")
	var reloaded := ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as AlchemyCatalog
	_expect(reloaded != null and reloaded.recipes.size() == 1, "Catalog registration survives disk reload")
	if reloaded != null and not reloaded.recipes.is_empty():
		_expect(reloaded.recipes[0].recipe_id == &"TestRecipe" and reloaded.recipes[0].ingredients[2].item_id == &"Leaf", "Saved recipe preserves hidden answer and external reference")
	_expect(_has_error(_store.validate_recipe(draft), "recipe_id"), "Duplicate RecipeID is rejected")
	var invalid := recipe.duplicate(true) as AlchemyRecipe
	invalid.ingredients[2].item_id = &"Water"
	_expect(_has_error(_store.validate_recipe(invalid, recipe), "ingredients.2.item_id"), "Answer outside the allowed category is identified at its slot")
	invalid = recipe.duplicate(true)
	invalid.ingredients[3].item_id = &"Leaf"
	_expect(_has_error(_store.validate_recipe(invalid, recipe), "ingredients.3.item_id"), "Three-slot fourth answer is rejected")
	invalid = recipe.duplicate(true)
	invalid.waste_result_amount = 0
	_expect(_has_error(_store.validate_recipe(invalid, recipe), "waste_result_amount"), "Per-recipe waste quantity must be positive")
	invalid = recipe.duplicate(true)
	invalid.recipe_id = &"ChangedID"
	_expect(_has_error(_store.validate_recipe(invalid, recipe), "recipe_id"), "Existing RecipeID stays stable")
	var before_recipe := FileAccess.get_file_as_string(recipe.resource_path)
	_expect(not _store.save_recipe(invalid, recipe).ok, "Invalid recipe cannot save")
	_expect(FileAccess.get_file_as_string(recipe.resource_path) == before_recipe, "Validation failure leaves disk unchanged")
	var changed := recipe.duplicate(true) as AlchemyRecipe
	changed.display_name = "修改后的配方"
	changed.waste_result_amount = 4
	var saved := _store.save_recipe(changed, recipe)
	_expect(saved.ok and saved.resource == recipe and recipe.display_name == changed.display_name, "Editing preserves existing shared resource identity")
	_expect(ResourceLoader.get_resource_uid(recipe.resource_path) == recipe_uid and ResourceUID.get_id_path(recipe_uid) == recipe.resource_path, "Transaction preserves recipe UID and final UID path")
	reloaded = ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_expect(reloaded.recipes[0].waste_result_amount == 4, "Changed waste quantity survives catalog reload")
	var unused := ItemData.new()
	unused.item_id = &"NewMaterial"
	unused.display_name = "新素材"
	unused.category = &"Plant"
	unused.icon = category.icon
	var item_result := _store.save_item(unused)
	_expect(item_result.ok and _store.items.find_item(unused.item_id) != null, "New item saves into the one shared item catalog")
	var item_identity: ItemData = item_result.resource
	var changed_item := item_identity.duplicate(true) as ItemData
	changed_item.description = "策划填写的说明"
	item_result = _store.save_item(changed_item, item_identity)
	_expect(item_result.ok and item_result.resource == item_identity and item_identity.description == changed_item.description, "Editing an embedded item preserves identity")
	var changed_answer := _store.items.find_item(&"Leaf").duplicate(false) as ItemData
	changed_answer.category = &""
	_expect(_has_error(_store.validate_item(changed_answer, _store.items.find_item(&"Leaf")), "category"), "Changing a material type cannot silently invalidate hidden answers")
	var categories: Array[ItemCategory] = []
	_expect(_has_error(_store.validate_common(categories, &"Waste"), "categories"), "Referenced material type cannot be removed")
	categories.append(category.duplicate(false))
	categories[0].display_name = "植物类"
	_expect(_store.save_common(categories, &"Waste").ok, "Type display metadata can be edited")
	_expect(_store.items.initial_inventory == initial, "Authoring operations preserve initial inventory")
	var reloaded_items := ResourceLoader.load(item_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ItemCatalog
	_expect(reloaded_items.initial_inventory == initial and reloaded_items.find_item(&"NewMaterial").description == changed_item.description, "Stock and edited item metadata survive disk reload")
	_expect(not _store.delete_item(_store.items.find_item(&"Herb")).ok, "Initial inventory and recipe references block material deletion")
	_expect(not _store.delete_item(_store.items.find_item(&"Leaf")).ok, "Hidden correct answer references block deletion")
	_expect(not _store.delete_item(_store.items.find_item(&"Waste")).ok, "Shared waste reference blocks deletion")
	_expect(_store.delete_item(item_identity).ok and _store.items.find_item(&"NewMaterial") == null, "Unused item can be removed from the shared catalog")
	var book := ItemData.new()
	book.item_id = &"RecipeBook"
	book.display_name = "配方书"
	book.icon = category.icon
	# Forms use deep working copies; the backend must reconnect books to the saved recipe.
	book.alchemy_recipe = recipe.duplicate(true)
	var book_saved := _store.save_item(book)
	_expect(book_saved.ok and book_saved.resource.alchemy_recipe == recipe, "Recipe book points to the canonical registered resource")
	reloaded_items = ResourceLoader.load(item_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_expect(reloaded_items.find_item(&"RecipeBook").alchemy_recipe.resource_path == recipe.resource_path, "Book reload follows an external recipe resource rather than an embedded copy")
	_expect(not _store.delete_recipe(recipe).ok, "Recipe book reference blocks recipe deletion")
	_test_external_reload(item_path, recipe_path, recipe, book_saved.resource)
	var project_issues := _store.validate_project()
	_expect(not _has_error(project_issues), "The finished fixture passes full project validation")
	_expect(_store.suggest_id("TestRecipe") != &"TestRecipe", "Generated IDs do not reuse existing entries")
	_test_rollback(item_path, recipe_path, recipe)
	_test_new_registration_rollback(item_path, recipe_path)
	_expect(_store.delete_item(book_saved.resource).ok, "Unused recipe book can be removed")
	_expect(_store.delete_recipe(recipe).ok and not FileAccess.file_exists(recipe.resource_path), "Unreferenced recipe removes its file and catalog registration together")
	_expect(_store.items.initial_inventory == initial, "Deletion preserves initial inventory")
	_finish()

func _test_external_reload(item_path: String, recipe_path: String, recipe: AlchemyRecipe, book: ItemData) -> void:
	var water := _store.items.find_item(&"Water")
	var catalog_identity := _store.items
	var external := ResourceLoader.load(item_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as ItemCatalog
	external.find_item(&"Water").description = "外部磁盘修改的说明"
	_expect(ResourceSaver.save(external, item_path) == OK, "Fixture writes an external catalog change")
	_expect(water.description != "外部磁盘修改的说明", "External save does not silently modify the cached editor item")
	_expect(_store.load_catalogs(item_path, recipe_path).ok, "Reload refreshes catalogs from disk")
	_expect(_store.items == catalog_identity and _store.items.find_item(&"Water") == water and water.description == "外部磁盘修改的说明", "Reload applies external metadata while preserving catalog and item identity")
	_expect(_store.recipes.find_recipe(recipe.recipe_id) == recipe and _store.items.find_item(book.item_id) == book and book.alchemy_recipe == recipe, "Reload preserves recipe books and their canonical recipe links")

func _test_rollback(item_path: String, recipe_path: String, recipe: AlchemyRecipe) -> void:
	var failing := FailingStore.new()
	_expect(failing.load_catalogs(item_path, recipe_path).ok, "Rollback fixture uses the same catalogs")
	var before_recipe := FileAccess.get_file_as_string(recipe.resource_path)
	var before_catalog := FileAccess.get_file_as_string(recipe_path)
	var old_name := recipe.display_name
	var recipe_uid := ResourceLoader.get_resource_uid(recipe.resource_path)
	var changed := recipe.duplicate(true) as AlchemyRecipe
	changed.display_name = "不可提交的配方"
	var result := failing.save_recipe(changed, recipe)
	_expect(not result.ok and result.error.contains("回滚"), "Second-file installation failure is reported as rollback")
	_expect(FileAccess.get_file_as_string(recipe.resource_path) == before_recipe and FileAccess.get_file_as_string(recipe_path) == before_catalog, "Partial commit restores both original files exactly")
	_expect(recipe.display_name == old_name, "Failed commit leaves shared resource untouched")
	_expect(ResourceUID.get_id_path(recipe_uid) == recipe.resource_path, "Rollback restores UID bookkeeping to the real file")
	for file in DirAccess.get_files_at(recipe_path.get_base_dir()):
		_expect(not file.contains(".alchemy-"), "Rollback removes temporary stages and completed backups")

func _test_new_registration_rollback(item_path: String, recipe_path: String) -> void:
	var failing := FailingStore.new()
	_expect(failing.load_catalogs(item_path, recipe_path).ok, "New recipe rollback loads catalogs")
	var before_catalog := FileAccess.get_file_as_string(recipe_path)
	var draft := _recipe()
	draft.recipe_id = &"CannotCommit"
	var result := failing.save_recipe(draft)
	_expect(not result.ok, "Registration failure does not report successful creation")
	_expect(not FileAccess.file_exists(recipe_path.get_base_dir().path_join("CannotCommit.tres")), "Registration failure removes the newly installed recipe file")
	_expect(FileAccess.get_file_as_string(recipe_path) == before_catalog and failing.recipes.find_recipe(&"CannotCommit") == null, "Registration failure leaves no dangling catalog entry")

func _recipe() -> AlchemyRecipe:
	var recipe := AlchemyRecipe.new()
	recipe.recipe_id = &"TestRecipe"
	recipe.display_name = "测试推理配方"
	recipe.icon = load("res://data/items/potion.svg")
	recipe.designer_notes = "仅用于隔离测试"
	recipe.formula_mode = AlchemyRecipe.FormulaMode.EXPERIMENTAL
	recipe.advanced_slot_count = 3
	recipe.result_item_id = &"OutputA"
	recipe.advanced_result_item_id = &"OutputB"
	for id in [&"Herb", &"Water", &"Leaf", &""]:
		var requirement := IngredientRequirement.new()
		requirement.item_id = id
		requirement.amount = 1
		recipe.ingredients.append(requirement)
	recipe.ingredients[2].candidate_category = &"Plant"
	recipe.ingredients[2].hint_name = "植物"
	recipe.ingredients[2].hint_icon = load("res://data/items/category_plant.svg")
	return recipe

func _finish() -> void:
	print("Alchemy editor store tests: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

@tool
class_name AlchemyEditorStore
extends RefCounted

## The editor works on copies; these shared resources change only after every file commits.
var items: ItemCatalog
var recipes: AlchemyCatalog
var _item_path := "res://data/items/catalog.tres"
var _recipe_path := "res://data/recipes/catalog.tres"

func load_catalogs(item_path: String = "res://data/items/catalog.tres", recipe_path: String = "res://data/recipes/catalog.tres") -> Dictionary:
	if not FileAccess.file_exists(item_path) or not FileAccess.file_exists(recipe_path):
		return _error("无法读取物品目录或配方目录，请检查资源路径。")
	# Newly saved embedded resources may not have their eventual subresource path yet.
	# Preserve their business identities before a deep disk refresh replaces the array.
	var cached_items := ResourceLoader.load(item_path) as ItemCatalog
	var cached_recipes := ResourceLoader.load(recipe_path) as AlchemyCatalog
	var old_items: Array[ItemData] = cached_items.items.duplicate() if cached_items != null else []
	var old_categories: Array[ItemCategory] = cached_items.categories.duplicate() if cached_items != null else []
	var old_recipes: Array[AlchemyRecipe] = cached_recipes.recipes.duplicate() if cached_recipes != null else []
	# Refresh from disk while retaining cached resource identities held by the editor.
	var loaded_items := ResourceLoader.load(item_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as ItemCatalog
	var loaded_recipes := ResourceLoader.load(recipe_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP) as AlchemyCatalog
	if loaded_items == null or loaded_recipes == null:
		return _error("无法读取物品目录或配方目录，请检查资源路径。")
	for index in loaded_recipes.recipes.size():
		var refreshed := loaded_recipes.recipes[index]
		if refreshed == null:
			continue
		for previous in old_recipes:
			if previous != null and previous.recipe_id == refreshed.recipe_id:
				if previous != refreshed:
					_copy_stored_properties(refreshed, previous)
				loaded_recipes.recipes[index] = previous
				break
	for index in loaded_items.items.size():
		var refreshed := loaded_items.items[index]
		if refreshed == null:
			continue
		if refreshed.alchemy_recipe != null:
			var canonical := loaded_recipes.find_recipe(refreshed.alchemy_recipe.recipe_id)
			if canonical != null:
				refreshed.alchemy_recipe = canonical
		for previous in old_items:
			if previous != null and previous.item_id == refreshed.item_id:
				if previous != refreshed:
					_copy_stored_properties(refreshed, previous)
				loaded_items.items[index] = previous
				break
	for index in loaded_items.categories.size():
		var refreshed := loaded_items.categories[index]
		if refreshed == null:
			continue
		for previous in old_categories:
			if previous != null and previous.category_id == refreshed.category_id:
				if previous != refreshed:
					_copy_stored_properties(refreshed, previous)
				loaded_items.categories[index] = previous
				break
	items = loaded_items
	recipes = loaded_recipes
	_item_path = item_path
	_recipe_path = recipe_path
	return _success()

func validate_recipe(draft: AlchemyRecipe, original: AlchemyRecipe = null) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if draft == null or items == null or recipes == null:
		_add(issues, "配方或目录尚未加载。", "recipe_id")
		return issues
	_validate_id(issues, String(draft.recipe_id), "RecipeID", "recipe_id")
	if original != null and draft.recipe_id != original.recipe_id:
		_add(issues, "已有配方的 RecipeID 不能修改；请复制为新配方。", "recipe_id")
	for entry in recipes.recipes:
		if entry != null and not _same_resource(entry, original) and entry.recipe_id == draft.recipe_id:
			_add(issues, "RecipeID 已被配方“%s”使用。" % entry.display_name, "recipe_id")
	if draft.display_name.strip_edges().is_empty():
		_add(issues, "请填写配方名称。", "display_name")
	if draft.icon == null:
		_add(issues, "尚未选择配方图标。", "icon", "warning")
	if draft.is_experimental() and draft.designer_notes.strip_edges().is_empty():
		_add(issues, "可在策划备注中记录剧情线索与推理依据。", "designer_notes", "warning")
	_append(issues, _validate_recipe_data(draft, items))
	return issues

func validate_item(draft: ItemData, original: ItemData = null) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if draft == null or items == null or recipes == null:
		_add(issues, "物品或目录尚未加载。", "item_id")
		return issues
	if original != null and not items.items.has(original):
		_add(issues, "原物品已不在当前目录中，请重新选择。", "item_id")
	_validate_id(issues, String(draft.item_id), "ItemID", "item_id")
	if original != null and draft.item_id != original.item_id:
		_add(issues, "已有物品的 ItemID 不能修改；请复制为新物品。", "item_id")
	for entry in items.items:
		if entry != null and not _same_resource(entry, original) and entry.item_id == draft.item_id:
			_add(issues, "ItemID 已被物品“%s”使用。" % entry.display_name, "item_id")
	if draft.display_name.strip_edges().is_empty():
		_add(issues, "请填写物品名称。", "display_name")
	if draft.icon == null:
		_add(issues, "尚未选择物品图标。", "icon", "warning")
	if draft.category != &"" and not _has_category(items.categories, draft.category):
		_add(issues, "物品类型不存在：%s。" % draft.category, "category")
	if draft.alchemy_recipe != null and recipes.find_recipe(draft.alchemy_recipe.recipe_id) == null:
		_add(issues, "关联配方没有登记在配方目录中。", "alchemy_recipe")
	if draft.item_id == items.alchemy_waste_item_id and (draft.display_name != "异质" or draft.alchemy_recipe != null):
		_add(issues, "通用错误产物必须是名为“异质”的普通物品。", "display_name")
	# Changing a type or turning a material into a recipe book must not invalidate saved answers.
	if original != null:
		var proposed := _catalog_with_item(draft, original)
		for recipe in _known_recipes():
			var previous_errors: PackedStringArray = []
			for previous in _validate_recipe_data(recipe, items):
				if previous.severity == "error":
					previous_errors.append(previous.message)
			for issue in _validate_recipe_data(recipe, proposed):
				if issue.severity == "error" and not previous_errors.has(issue.message):
					_add(issues, "此修改影响配方“%s”：%s" % [recipe.display_name, issue.message], "category")
	return issues

func validate_common(categories: Array[ItemCategory], waste_id: StringName) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var ids: Dictionary = {}
	for index in categories.size():
		var category := categories[index]
		var field := "categories.%d" % index
		if category == null:
			_add(issues, "存在空的类型条目。", field)
			continue
		_validate_id(issues, String(category.category_id), "类型ID", field)
		if ids.has(category.category_id):
			_add(issues, "类型ID重复：%s。" % category.category_id, field)
		ids[category.category_id] = true
		if category.display_name.strip_edges().is_empty() or category.icon == null:
			_add(issues, "类型需要显示名称和通用图标。", field)
	if items == null or recipes == null:
		_add(issues, "目录尚未加载。", "categories")
		return issues
	for item in items.items:
		if item != null and item.category != &"" and not ids.has(item.category):
			_add(issues, "物品“%s”仍引用类型 %s，不能移除或更改此类型ID。" % [item.display_name, item.category], "categories")
	for recipe in _known_recipes():
		for index in recipe.ingredients.size():
			var requirement := recipe.ingredients[index]
			if requirement == null:
				continue
			for category_id in [requirement.category, requirement.candidate_category]:
				if category_id != &"" and not ids.has(category_id):
					_add(issues, "配方“%s”第%d槽仍引用类型 %s。" % [recipe.display_name, index + 1, category_id], "categories")
	var waste := items.find_item(waste_id)
	if waste == null or waste.display_name != "异质" or waste.alchemy_recipe != null:
		_add(issues, "请选择名为“异质”的普通物品作为通用错误产物。", "alchemy_waste_item_id")
	for recipe in _known_recipes():
		if recipe.is_experimental() and waste_id in [recipe.result_item_id, recipe.advanced_result_item_id]:
			_add(issues, "配方“%s”的A/B产物与所选异质重复。" % recipe.display_name, "alchemy_waste_item_id")
	return issues

func validate_project() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if items == null or recipes == null:
		_add(issues, "目录尚未加载。", "")
		return issues
	for recipe in recipes.recipes:
		for issue in validate_recipe(recipe, recipe):
			issue["resource"] = recipe
			issue["kind"] = "recipe"
			issue.message = "%s / %s" % [recipe.display_name if recipe != null else "空配方", issue.message]
			issues.append(issue)
	for item in items.items:
		for issue in validate_item(item, item):
			issue["resource"] = item
			issue["kind"] = "item"
			issue.message = "%s / %s" % [item.display_name if item != null else "空物品", issue.message]
			issues.append(issue)
	for issue in validate_common(items.categories, items.alchemy_waste_item_id):
		issue["kind"] = "common"
		issues.append(issue)
	return issues

func save_recipe(draft: AlchemyRecipe, original: AlchemyRecipe = null) -> Dictionary:
	var issues := validate_recipe(draft, original)
	if _has_errors(issues):
		return _issues_error(issues)
	var target := original.resource_path if original != null else ""
	if target.is_empty() or target.contains("::"):
		target = _recipe_path.get_base_dir().path_join(String(draft.recipe_id) + ".tres")
	if original == null and FileAccess.file_exists(target):
		return _error("目标文件已经存在，不能覆盖未登记的配方：%s" % target)
	var saved := draft.duplicate(true) as AlchemyRecipe
	var proposed := recipes.duplicate(false) as AlchemyCatalog
	proposed.recipes = recipes.recipes.duplicate()
	if original == null:
		# The staged catalog must reference the final path, not the temporary filename.
		saved.resource_path = target
		proposed.recipes.append(saved)
	elif not proposed.recipes.has(original):
		proposed.recipes.append(original)
	var result := _commit_files([{"path": target, "resource": saved}, {"path": _recipe_path, "resource": proposed}])
	if not result.ok:
		if original == null:
			saved.resource_path = ""
		return result
	if original != null:
		_copy_stored_properties(saved, original)
		saved = original
	else:
		saved.take_over_path(target)
	if not recipes.recipes.has(saved):
		recipes.recipes.append(saved)
	recipes.emit_changed()
	return {"ok": true, "error": "", "resource": saved, "issues": issues}

func save_item(draft: ItemData, original: ItemData = null) -> Dictionary:
	var issues := validate_item(draft, original)
	if _has_errors(issues):
		return _issues_error(issues)
	var saved := draft.duplicate(false) as ItemData
	if saved.alchemy_recipe != null:
		saved.alchemy_recipe = recipes.find_recipe(saved.alchemy_recipe.recipe_id)
	var proposed := _catalog_with_item(saved, original)
	var result := _commit_files([{"path": _item_path, "resource": proposed}])
	if not result.ok:
		return result
	if original != null:
		_copy_stored_properties(saved, original)
		saved = original
	else:
		items.items.append(saved)
	items.emit_changed()
	return {"ok": true, "error": "", "resource": saved, "issues": issues}

func save_common(categories: Array[ItemCategory], waste_id: StringName) -> Dictionary:
	var issues := validate_common(categories, waste_id)
	if _has_errors(issues):
		return _issues_error(issues)
	var proposed := items.duplicate(false) as ItemCatalog
	proposed.categories = []
	for category in categories:
		proposed.categories.append(category.duplicate(false))
	proposed.alchemy_waste_item_id = waste_id
	var result := _commit_files([{"path": _item_path, "resource": proposed}])
	if not result.ok:
		return result
	items.categories = proposed.categories
	items.alchemy_waste_item_id = waste_id
	items.emit_changed()
	return {"ok": true, "error": "", "resource": items, "issues": issues}

func delete_item(item: ItemData) -> Dictionary:
	if item == null or items == null or not items.items.has(item):
		return _error("物品不在当前目录中。")
	var references := _item_references(item.item_id)
	if not references.is_empty():
		return _error("不能删除“%s”，仍被以下配置引用：\n%s" % [item.display_name, "\n".join(references)])
	var proposed := items.duplicate(false) as ItemCatalog
	proposed.items = items.items.duplicate()
	proposed.items.erase(item)
	var result := _commit_files([{"path": _item_path, "resource": proposed}])
	if result.ok:
		items.items.erase(item)
		items.emit_changed()
		result["warning"] = "仅检查项目目录、配方及初始库存；脚本、场景和timeline中的字符串引用请另行确认。"
	return result

func delete_recipe(recipe: AlchemyRecipe) -> Dictionary:
	if recipe == null or recipes == null or not recipes.recipes.has(recipe):
		return _error("配方不在当前目录中。")
	for item in items.items:
		if item != null and item.alchemy_recipe != null and item.alchemy_recipe.recipe_id == recipe.recipe_id:
			return _error("不能删除配方“%s”：配方道具“%s”仍引用它。" % [recipe.display_name, item.display_name])
	var proposed := recipes.duplicate(false) as AlchemyCatalog
	proposed.recipes = recipes.recipes.duplicate()
	proposed.recipes.erase(recipe)
	var files: Array[Dictionary] = [{"path": _recipe_path, "resource": proposed}]
	if not recipe.resource_path.is_empty() and not recipe.resource_path.contains("::"):
		files.append({"path": recipe.resource_path, "delete": true})
	var result := _commit_files(files)
	if result.ok:
		recipes.recipes.erase(recipe)
		recipes.emit_changed()
		result["warning"] = "仅检查配方道具引用；剧情中的RecipeID字符串、解锁记录和场景配置请另行确认。"
	return result

func suggest_id(prefix: String) -> StringName:
	var expression := RegEx.new()
	expression.compile("[^A-Za-z0-9_]")
	var clean := expression.sub(prefix, "", true)
	if clean.is_empty():
		clean = "NewResource"
	var index := 1
	while _id_exists(StringName(clean + str(index))):
		index += 1
	return StringName(clean + str(index))

func _validate_recipe_data(recipe: AlchemyRecipe, catalog: ItemCatalog) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	_check_output(issues, catalog, recipe.result_item_id, recipe.result_amount, "基础产物", "result_item_id")
	if recipe.ingredients.is_empty():
		_add(issues, "请至少配置一个素材槽。", "ingredients")
	if recipe.formula_mode not in [AlchemyRecipe.FormulaMode.STANDARD, AlchemyRecipe.FormulaMode.EXPERIMENTAL]:
		_add(issues, "公式模式无效。", "formula_mode")
	if recipe.is_experimental():
		if recipe.ingredients.size() != 4:
			_add(issues, "推理配方必须保留四个素材槽。", "ingredients")
		if recipe.advanced_slot_count not in [3, 4]:
			_add(issues, "高级公式必须选择使用前三槽或全部四槽。", "advanced_slot_count")
		_check_output(issues, catalog, recipe.advanced_result_item_id, recipe.advanced_result_amount, "高级产物", "advanced_result_item_id")
		_check_output(issues, catalog, catalog.alchemy_waste_item_id, recipe.waste_result_amount, "通用异质", "waste_result_amount")
		if recipe.result_item_id == recipe.advanced_result_item_id or catalog.alchemy_waste_item_id in [recipe.result_item_id, recipe.advanced_result_item_id]:
			_add(issues, "基础产物、高级产物和异质必须是不同物品。", "advanced_result_item_id")
	for index in recipe.ingredients.size():
		var requirement := recipe.ingredients[index]
		var field := "ingredients.%d" % index
		var label := "第%d槽" % (index + 1)
		if requirement == null:
			_add(issues, "%s没有配置素材需求。" % label, field)
			continue
		if requirement.amount <= 0:
			_add(issues, "%s数量必须是正整数。" % label, field + ".amount")
		if recipe.is_hidden_slot(index):
			if recipe.advanced_slot_count == 3 and index == 3:
				if requirement.item_id != &"":
					_add(issues, "三槽高级公式的第4槽不能配置正确答案。", field + ".item_id")
				continue
			if requirement.hint_name.strip_edges().is_empty() or requirement.hint_icon == null:
				_add(issues, "%s需要公开的类型名称和类型图标。" % label, field + ".hint_name")
			if requirement.candidate_category == &"" or not _has_category(catalog.categories, requirement.candidate_category):
				_add(issues, "%s需要有效的候选类型。" % label, field + ".candidate_category")
			var answer := catalog.find_item(requirement.item_id)
			if answer == null:
				_add(issues, "%s的正确素材不存在：%s。" % [label, requirement.item_id], field + ".item_id")
			elif not requirement.accepts_candidate(answer):
				_add(issues, "%s：正确素材“%s”不在允许的素材类型中，或为配方道具。" % [label, answer.display_name], field + ".item_id")
		elif requirement.item_id != &"":
			var material := catalog.find_item(requirement.item_id)
			if material == null:
				_add(issues, "%s的素材不存在：%s。" % [label, requirement.item_id], field + ".item_id")
			elif recipe.is_experimental() and material.alchemy_recipe != null:
				_add(issues, "%s不能使用配方道具作为素材。" % label, field + ".item_id")
		elif recipe.is_experimental() or requirement.category == &"" or not _has_category(catalog.categories, requirement.category):
			_add(issues, "%s没有有效的明示素材。" % label, field + ".item_id")
	# Keep the final authority in the same core used by the running game.
	if not _has_errors(issues):
		var inventory := InventorySystem.new()
		inventory.catalog = catalog
		var check := AlchemySystem.new(inventory).check_recipe(recipe)
		inventory.free()
		if not check.ok:
			_add(issues, check.error, "ingredients")
	return issues

func _check_output(issues: Array[Dictionary], catalog: ItemCatalog, id: StringName, amount: int, label: String, field: String) -> void:
	if catalog.find_item(id) == null:
		_add(issues, "%s的物品不存在：%s。" % [label, id], field)
	if amount <= 0:
		_add(issues, "%s数量必须是正整数。" % label, field.replace("_item_id", "_amount"))

func _catalog_with_item(draft: ItemData, original: ItemData) -> ItemCatalog:
	var proposed := items.duplicate(false) as ItemCatalog
	proposed.items = items.items.duplicate()
	if original != null:
		var index := proposed.items.find(original)
		if index >= 0:
			proposed.items[index] = draft
	else:
		proposed.items.append(draft)
	return proposed

func _known_recipes() -> Array[AlchemyRecipe]:
	var known: Array[AlchemyRecipe] = []
	if recipes != null:
		for recipe in recipes.recipes:
			if recipe != null:
				known.append(recipe)
	_scan_recipe_directory(_recipe_path.get_base_dir(), known)
	return known

func _scan_recipe_directory(path: String, known: Array[AlchemyRecipe]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file in directory.get_files():
		var candidate := path.path_join(file)
		if file.ends_with(".tres") and candidate != _recipe_path and not file.contains(".alchemy-stage-"):
			var recipe := ResourceLoader.load(candidate) as AlchemyRecipe
			if recipe != null and not known.has(recipe):
				known.append(recipe)
	for child in directory.get_directories():
		if not child.begins_with("."):
			_scan_recipe_directory(path.path_join(child), known)

func _item_references(id: StringName) -> PackedStringArray:
	var references: PackedStringArray = []
	if id == items.alchemy_waste_item_id:
		references.append("通用异质配置")
	for initial_id in items.initial_inventory:
		if StringName(initial_id) == id:
			references.append("初始背包数量")
	for recipe in _known_recipes():
		if recipe.result_item_id == id:
			references.append("%s / 基础产物" % recipe.display_name)
		if recipe.is_experimental() and recipe.advanced_result_item_id == id:
			references.append("%s / 高级产物" % recipe.display_name)
		for index in recipe.ingredients.size():
			if recipe.ingredients[index] != null and recipe.ingredients[index].item_id == id:
				references.append("%s / 第%d槽" % [recipe.display_name, index + 1])
	return references

## Stage writes first, back up every target, then install. A later failure restores earlier files.
func _commit_files(files: Array[Dictionary]) -> Dictionary:
	var token := str(Time.get_ticks_usec())
	var records: Array[Dictionary] = []
	for file in files:
		var path: String = file.path
		var record := {"path": path, "stage": path.get_basename() + ".alchemy-stage-" + token + ".tres", "backup": path + ".alchemy-backup-" + token, "existed": FileAccess.file_exists(path), "installed": false, "backed_up": false, "delete": file.get("delete", false), "uid": ResourceUID.INVALID_ID}
		records.append(record)
		if record.delete:
			continue
		var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if error != OK:
			_cleanup_stages(records)
			return _error("无法创建资源目录：%s（%s）。" % [path.get_base_dir(), error_string(error)])
		error = ResourceSaver.save(file.resource, record.stage)
		if error != OK:
			_cleanup_stages(records)
			return _error("资源写入失败：%s（%s），原文件未修改。" % [path, error_string(error)])
		record.uid = ResourceLoader.get_resource_uid(path) if record.existed else ResourceLoader.get_resource_uid(record.stage)
		if record.uid != ResourceUID.INVALID_ID:
			# Absolute paths also work for isolated user:// fixtures; set_uid's rename
			# otherwise treats that virtual prefix as a project resource path.
			error = ResourceSaver.set_uid(ProjectSettings.globalize_path(record.stage), record.uid)
			if error != OK:
				_cleanup_stages(records)
				return _error("无法保留资源UID：%s。" % path)
	for record in records:
		if record.existed:
			var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(record.path), ProjectSettings.globalize_path(record.backup))
			if error != OK:
				return _rollback(records, "无法备份 %s（%s）。" % [record.path, error_string(error)])
			record.backed_up = true
		if not record.delete:
			var error := _install_staged_file(record.stage, record.path)
			if error != OK:
				return _rollback(records, "无法提交 %s（%s）。" % [record.path, error_string(error)])
			record.installed = true
	for record in records:
		if record.backed_up:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(record.backup))
		if not record.delete and record.uid != ResourceUID.INVALID_ID:
			if ResourceUID.has_id(record.uid):
				ResourceUID.set_id(record.uid, record.path)
			else:
				ResourceUID.add_id(record.uid, record.path)
	return _success()

func _install_staged_file(stage: String, target: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(stage), ProjectSettings.globalize_path(target))

func _rollback(records: Array[Dictionary], reason: String) -> Dictionary:
	var recovery: PackedStringArray = []
	for index in range(records.size() - 1, -1, -1):
		var record := records[index]
		if record.installed:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(record.path))
		if record.backed_up:
			var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(record.backup), ProjectSettings.globalize_path(record.path))
			if error != OK:
				recovery.append(record.backup)
	_cleanup_stages(records)
	if not recovery.is_empty():
		return _error(reason + "\n回滚未完成，请保留这些恢复文件：\n" + "\n".join(recovery))
	return _error(reason + "\n本次写入已回滚，项目配置保持原状。")

func _cleanup_stages(records: Array[Dictionary]) -> void:
	for record in records:
		if FileAccess.file_exists(record.stage):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(record.stage))
		# set_uid() may update editor UID bookkeeping; failures must restore that too.
		if record.uid != ResourceUID.INVALID_ID and ResourceUID.has_id(record.uid):
			if record.existed:
				ResourceUID.set_id(record.uid, record.path)
			elif ResourceUID.get_id_path(record.uid) in [record.stage, record.path]:
				ResourceUID.remove_id(record.uid)

func _copy_stored_properties(source: Resource, target: Resource) -> void:
	for property in source.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path"]:
			target.set(property.name, source.get(property.name))
	target.emit_changed()

func _id_exists(id: StringName) -> bool:
	return (items != null and items.find_item(id) != null) or (recipes != null and recipes.find_recipe(id) != null) or FileAccess.file_exists(_recipe_path.get_base_dir().path_join(String(id) + ".tres"))

func _validate_id(issues: Array[Dictionary], id: String, label: String, field: String) -> void:
	if id.is_empty() or id != id.strip_edges() or id in [".", ".."] or not id.is_valid_filename():
		_add(issues, "%s不能为空，且不能含路径符号或首尾空格。" % label, field)

func _same_resource(first: Resource, second: Resource) -> bool:
	if first == null or second == null:
		return false
	return first == second or (not first.resource_path.is_empty() and first.resource_path == second.resource_path)

func _has_category(categories: Array[ItemCategory], id: StringName) -> bool:
	for category in categories:
		if category != null and category.category_id == id:
			return true
	return false

func _add(issues: Array[Dictionary], message: String, field: String, severity: String = "error") -> void:
	issues.append({"message": message, "field": field, "severity": severity})

func _append(target: Array[Dictionary], source: Array[Dictionary]) -> void:
	for issue in source:
		target.append(issue)

func _has_errors(issues: Array[Dictionary]) -> bool:
	for issue in issues:
		if issue.severity == "error":
			return true
	return false

func _issues_error(issues: Array[Dictionary]) -> Dictionary:
	var messages: PackedStringArray = []
	for issue in issues:
		if issue.severity == "error":
			messages.append(issue.message)
	return {"ok": false, "error": "\n".join(messages), "issues": issues}

func _success() -> Dictionary:
	return {"ok": true, "error": ""}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

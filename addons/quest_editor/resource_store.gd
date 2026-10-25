@tool
extends RefCounted

## A dedicated authoring store. Drafts never mutate the catalog before Save.
var catalog: Resource
var items: ItemCatalog
var recipes: AlchemyCatalog
var _catalog_path := "res://data/quests/catalog.tres"

const OBJECTIVE_KINDS := ["have_item", "recipe_known", "recipe_materials", "craft_confirmed", "talk", "delivery", "story_completed", "fact"]
const KIND_LABELS := {"have_item": "持有物品", "recipe_known": "解锁配方", "recipe_materials": "准备配方公开必需素材", "craft_confirmed": "制作结果确认", "talk": "与角色交谈", "delivery": "交付物品", "story_completed": "指定剧情正常完成", "fact": "事实条件"}

func load_catalogs(catalog_path: String = "res://data/quests/catalog.tres", item_path: String = "res://data/items/catalog.tres", recipe_path: String = "res://data/recipes/catalog.tres") -> Dictionary:
	_catalog_path = catalog_path
	if not FileAccess.file_exists(catalog_path) or not FileAccess.file_exists(item_path) or not FileAccess.file_exists(recipe_path):
		return _error("任务、物品或配方目录尚未建立，请检查资源路径。")
	catalog = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	items = ResourceLoader.load(item_path) as ItemCatalog
	recipes = ResourceLoader.load(recipe_path) as AlchemyCatalog
	if catalog == null or items == null or recipes == null:
		return _error("无法读取任务、物品或配方目录。请检查目录资源路径。")
	return _success()

func entries(page: int) -> Array:
	return catalog.get("quests" if page == 0 else "stories") if catalog != null else []

func id_field(page: int) -> String:
	return "quest_id" if page == 0 else "story_id"

func suggest_id(prefix: String, page: int = 0) -> StringName:
	var result := prefix
	var suffix := 1
	var used: Array[String] = []
	for entry: Resource in entries(page): used.append(str(entry.get(id_field(page))))
	while used.has(result):
		result = "%s_%d" % [prefix, suffix]
		suffix += 1
	return StringName(result)

func create_entry(page: int) -> Resource:
	var entry: Resource = load("res://scripts/quest/" + ("quest_data.gd" if page == 0 else "quest_story_data.gd")).new()
	entry.set(id_field(page), suggest_id("quest" if page == 0 else "story", page))
	if page == 0:
		entry.set("display_name", "新任务")
		var stages: Array = entry.get("stages")
		if stages.is_empty():
			var stage: Resource = load("res://scripts/quest/quest_stage_data.gd").new()
			stage.set("stage_id", &"stage_1")
			stages.append(stage)
	return entry

func field_choices(resource: Resource, field: String) -> Array:
	var result: Array = []
	var script_path: String = resource.get_script().resource_path
	if field == "item_id":
		result.append({"label": "选择物品…", "value": &""})
		for item: ItemData in items.items:
			if item != null: result.append({"label": "%s [%s]" % [item.display_name, item.item_id], "value": item.item_id})
	elif field in ["recipe_id", "recipe"]:
		result.append({"label": "选择配方…", "value": null if field == "recipe" else &""})
		for recipe: AlchemyRecipe in recipes.recipes:
			if recipe != null: result.append({"label": "%s [%s]" % [recipe.display_name, recipe.recipe_id], "value": recipe if field == "recipe" else recipe.recipe_id})
	elif field == "story_id" and not script_path.ends_with("/quest_story_data.gd"):
		result.append({"label": "选择剧情…", "value": &""})
		for story: Resource in entries(1):
			result.append({"label": str(story.get("story_id")), "value": story.get("story_id")})
	elif field == "quest_id" and not script_path.ends_with("/quest_data.gd"):
		result.append({"label": "选择任务…", "value": &""})
		for quest: Resource in entries(0):
			result.append({"label": "%s [%s]" % [quest.get("display_name"), quest.get("quest_id")], "value": quest.get("quest_id")})
	elif field == "target_id" and _has(resource, "kind"):
		var reference := _target_reference(str(resource.get("kind")))
		if reference == "item_id":
			result.append({"label": "选择物品…", "value": &""})
			for item: ItemData in items.items:
				if item != null: result.append({"label": "%s [%s]" % [item.display_name, item.item_id], "value": item.item_id})
		elif reference == "recipe_id":
			result.append({"label": "选择配方…", "value": &""})
			for recipe: AlchemyRecipe in recipes.recipes:
				if recipe != null: result.append({"label": "%s [%s]" % [recipe.display_name, recipe.recipe_id], "value": recipe.recipe_id})
		elif reference in ["story_id", "quest_id"]:
			result.append({"label": "选择引用…", "value": &""})
			for entry: Resource in entries(1 if reference == "story_id" else 0):
				result.append({"label": str(entry.get(reference)), "value": entry.get(reference)})
	elif field == "match_mode":
		result = [{"label": "全部目标达成（ALL）", "value": &"all"}, {"label": "任一目标达成（ANY）", "value": &"any"}]
	elif field == "kind":
		var kinds: Array = OBJECTIVE_KINDS
		if script_path.ends_with("quest_condition_data.gd"): kinds = ["quest_completed", "fact", "have_item", "recipe_known", "story_completed", "scene"]
		elif script_path.ends_with("quest_action_data.gd"): kinds = ["request_story", "accept_quest", "grant_item"]
		for kind in kinds:
			result.append({"label": KIND_LABELS.get(kind, {"quest_completed": "前置任务完成", "request_story": "请求播放剧情", "accept_quest": "接取后续任务", "grant_item": "发放物品", "scene": "当前所在场景"}.get(kind, kind)), "value": StringName(kind)})
	else:
		for property in resource.get_property_list():
			if property.name == field and property.hint == PROPERTY_HINT_ENUM:
				var options: PackedStringArray = str(property.hint_string).split(",")
				for index in options.size():
					var value: Variant = options[index].get_slice(":", 0)
					if property.type == TYPE_INT:
						value = int(options[index].get_slice(":", 1)) if options[index].contains(":") else index
					elif property.type == TYPE_STRING_NAME: value = StringName(value)
					result.append({"label": KIND_LABELS.get(options[index], options[index]), "value": value})
				break
		if result.is_empty() and field == "kind" and script_path.ends_with("quest_objective_data.gd"):
			for kind in OBJECTIVE_KINDS: result.append({"label": KIND_LABELS[kind], "value": StringName(kind)})
	return result

func validate_entry(entry: Resource, original: Resource = null, page: int = 0) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if entry == null:
		_issue(issues, "配置为空。", "")
		return issues
	var id: String = str(entry.get(id_field(page)))
	_validate_id(issues, id, id_field(page))
	if original != null and entry.get(id_field(page)) != original.get(id_field(page)):
		_issue(issues, "已有 ID 不能修改；请复制为新配置。", id_field(page))
	for existing: Resource in entries(page):
		if existing != original and str(existing.get(id_field(page))) == id:
			_issue(issues, "ID 已在目录中使用。", id_field(page))
	if page == 1:
		_validate_story(entry, issues)
		return issues
	if str(entry.get("display_name")).strip_edges().is_empty(): _issue(issues, "请填写任务名称。", "display_name")
	var stages: Array = entry.get("stages")
	if stages.is_empty(): _issue(issues, "任务至少需要一个阶段。", "stages")
	var stage_ids: Dictionary = {}
	for index in stages.size():
		var stage: Resource = stages[index]
		var prefix := "stages.%d" % index
		if stage == null:
			_issue(issues, "阶段不能为空。", prefix)
			continue
		var stage_id: String = str(stage.get("stage_id"))
		_validate_id(issues, stage_id, prefix + ".stage_id")
		if stage_ids.has(stage_id): _issue(issues, "阶段 ID 重复。", prefix + ".stage_id")
		stage_ids[stage_id] = true
		var goals: Array = stage.get("objectives")
		if goals.is_empty(): _issue(issues, "阶段至少需要一个目标。", prefix + ".objectives")
		var goal_ids: Dictionary = {}
		for goal_index in goals.size():
			var goal: Resource = goals[goal_index]
			var goal_prefix := "%s.objectives.%d" % [prefix, goal_index]
			if goal == null:
				_issue(issues, "目标不能为空。", goal_prefix)
				continue
			var goal_id: String = str(goal.get("objective_id"))
			_validate_id(issues, goal_id, goal_prefix + ".objective_id")
			if goal_ids.has(goal_id): _issue(issues, "同阶段目标 ID 重复。", goal_prefix + ".objective_id")
			goal_ids[goal_id] = true
			_validate_parameters(goal, issues, goal_prefix)
		_validate_arrays(stage, issues, prefix)
	_validate_arrays(entry, issues, "")
	if original != null:
		for old_stage: Resource in original.get("stages"):
			if old_stage != null and not stage_ids.has(str(old_stage.get("stage_id"))):
				_issue(issues, "已删除旧阶段 %s；发布前需确认旧存档迁移策略。" % old_stage.get("stage_id"), "stages", "warning")
	var candidate: Resource = catalog.duplicate(false)
	var candidates: Array = entries(0).duplicate()
	var candidate_index := candidates.find(original) if original != null else -1
	if candidate_index >= 0: candidates[candidate_index] = entry
	else: candidates.append(entry)
	candidate.set("quests", candidates)
	var manager: Node = load("res://scripts/quest/quest_system.gd").new()
	var inventory := InventorySystem.new()
	inventory.catalog = items
	if manager.has_method("set_dependencies"): manager.set_dependencies(inventory, null)
	if manager.has_method("validate_catalog"):
		var validation: Dictionary = manager.validate_catalog(candidate)
		if not validation.get("ok", false): _issue(issues, str(validation.get("error", "任务目录验证失败。")), "")
	manager.free()
	inventory.free()
	return issues

func _validate_arrays(resource: Resource, issues: Array[Dictionary], prefix: String) -> void:
	for field: String in ["accept_conditions", "completion_actions"]:
		if not _has(resource, field): continue
		var values: Array = resource.get(field)
		for index in values.size():
			var path := (prefix + "." if not prefix.is_empty() else "") + "%s.%d" % [field, index]
			if values[index] is Resource: _validate_parameters(values[index], issues, path)
			else: _issue(issues, "存在空条件或动作。", path)

func _validate_parameters(resource: Resource, issues: Array[Dictionary], prefix: String) -> void:
	var kind := str(resource.get("kind")) if _has(resource, "kind") else ""
	var goal: bool = resource.get_script().resource_path.ends_with("quest_objective_data.gd")
	if goal and not OBJECTIVE_KINDS.has(kind): _issue(issues, "目标类型无效。", prefix + ".kind")
	if _has(resource, "amount") and int(resource.get("amount")) < 1:
		_issue(issues, "数量必须大于零。", prefix + ".amount")
	if _has(resource, "target_id"):
		var id := StringName(resource.get("target_id"))
		var reference := _target_reference(kind)
		if kind not in ["recipe_materials", "delivery", "talk"] and id == &"": _issue(issues, "请选择或填写目标。", prefix + ".target_id")
		if id != &"" and not reference.is_empty() and not _reference_exists(reference, id): _issue(issues, "目标未登记在目录中：%s。" % id, prefix + ".target_id")
		if kind == "scene" and id != &"" and (not ResourceLoader.exists(str(id)) or not load(str(id)) is PackedScene): _issue(issues, "请选择有效的场景文件。", prefix + ".target_id")
	if _has(resource, "recipe") and kind in ["recipe_materials", "craft_confirmed"]:
		var recipe: AlchemyRecipe = resource.get("recipe")
		if (kind == "recipe_materials" and recipe == null) or (recipe != null and recipes.find_recipe(recipe.recipe_id) == null): _issue(issues, "请选择已登记的配方。", prefix + ".recipe")
	if kind in ["talk", "delivery"]:
		for field in (["actor_id", "topic_id"] if kind == "talk" else ["actor_id"]):
			if _has(resource, field) and str(resource.get(field)).is_empty(): _issue(issues, "交谈目标需要对象和主题 ID。", prefix + "." + field)
	if kind == "delivery":
		var costs: Dictionary = resource.get("items")
		if costs.is_empty(): _issue(issues, "请添加交付物品。", prefix + ".items")
		for id in costs:
			if items.find_item(StringName(id)) == null or not costs[id] is int or int(costs[id]) < 1: _issue(issues, "交付物品或数量无效。", prefix + ".items")
	if _has(resource, "action_id"): _validate_id(issues, str(resource.get("action_id")), prefix + ".action_id")
	if _has(resource, "text") and bool(resource.get("visible")) and str(resource.get("text")).strip_edges().is_empty(): _issue(issues, "公开目标需要填写玩家可见的文本。", prefix + ".text")

func _validate_story(story: Resource, issues: Array[Dictionary]) -> void:
	var path := str(story.get("timeline_path"))
	if path.is_empty() or not ResourceLoader.exists(path) or not load(path) is DialogicTimeline: _issue(issues, "请选择有效的 Dialogic 剧情文件。", "timeline_path")
	if str(story.get("completion_signal")).is_empty(): _issue(issues, "需要配置正常结束信号，避免外部终止被误判完成。", "completion_signal")
	for field in ["return_scene_path", "allowed_scene_path"]:
		var scene_path := str(story.get(field))
		if not scene_path.is_empty() and (not ResourceLoader.exists(scene_path) or not load(scene_path) is PackedScene): _issue(issues, "场景文件无效。", field)

func validate_project() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for page in 2:
		for entry: Resource in entries(page):
			for issue: Dictionary in validate_entry(entry, entry, page):
				issue.resource = entry
				issue.page = page
				issue.message = "%s / %s" % [entry.get(id_field(page)), issue.message]
				result.append(issue)
	return result

func public_preview(entry: Resource, page: int = 0) -> String:
	if entry == null: return ""
	if page == 1:
		return "剧情衔接：%s\n\n玩家不会看到配置键和编辑备注。\n对应剧情正常结束后报告完成；中途退出不算完成。" % entry.get("story_id")
	var lines := PackedStringArray(["[%s] %s" % [entry.get("category"), entry.get("display_name")], str(entry.get("description")), ""])
	var manager: Node = load("res://scripts/quest/quest_system.gd").new()
	var preview_catalog: Resource = catalog.duplicate(false)
	var preview_quests: Array = entries(0).duplicate()
	preview_quests.clear()
	preview_quests.append(entry)
	preview_catalog.set("quests", preview_quests)
	manager.set("catalog", preview_catalog)
	var inventory := InventorySystem.new()
	inventory.catalog = items
	manager.set_dependencies(inventory, null)
	for stage: Resource in entry.get("stages"):
		if stage == null: continue
		var rows: Array[Dictionary] = []
		for goal: Resource in stage.get("objectives"):
			if goal != null: rows.append_array(manager.build_objective_view(entry.get("quest_id"), stage.get("stage_id"), goal.get("objective_id")))
		if rows.is_empty(): continue
		var rule := "（任一目标达成）" if stage.get("match_mode") == &"any" else ""
		lines.append("◆ " + _public_title(stage) + rule)
		for row: Dictionary in rows:
			var text := "○ " + str(row.get("text", ""))
			if row.get("has_count", false): text += "  %d / %d" % [row.get("current", 0), row.get("required", 0)]
			lines.append(text)
		lines.append("")
	manager.free()
	inventory.free()
	return "\n".join(lines)

func save_entry(draft: Resource, original: Resource = null, page: int = 0) -> Dictionary:
	for issue: Dictionary in validate_entry(draft, original, page):
		if issue.get("severity", "error") == "error": return _error(str(issue.message))
	var id := str(draft.get(id_field(page)))
	var path := original.resource_path if original != null else ""
	if not path.begins_with("res://") or path.contains("::"):
		path = _catalog_path.get_base_dir().path_join(("story_" if page == 1 else "") + id + ".tres")
	if original == null and FileAccess.file_exists(path): return _error("同名资源文件已存在，请使用其他 ID。")
	var directory_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if directory_error != OK: return _error("无法建立配置目录：" + error_string(directory_error))
	var candidate: Resource = draft.duplicate(true)
	if page == 0:
		# A task references the real recipe; a draft copy must not fork its ingredients.
		if candidate.get("recipe") != null:
			candidate.set("recipe", recipes.find_recipe(candidate.get("recipe").recipe_id))
		for stage: Resource in candidate.get("stages"):
			for objective: Resource in stage.get("objectives"):
				if objective.get("recipe") != null:
					objective.set("recipe", recipes.find_recipe(objective.get("recipe").recipe_id))
	var pending := path.get_basename() + ".pending.tres"
	var previous: Variant = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	var error := _write_pending(candidate, pending, path)
	if error != OK: return _error("无法写入配置：" + error_string(error))
	error = _replace(pending, path)
	if error != OK: return _error("无法替换配置：" + error_string(error))
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null:
		_restore_file(path, previous)
		return _error("配置无法重新读取，已保留原文件。")
	var next_catalog: Resource = catalog.duplicate(false)
	var list: Array = entries(page).duplicate()
	var index := list.find(original) if original != null else -1
	if index >= 0: list[index] = saved
	else: list.append(saved)
	next_catalog.set("quests" if page == 0 else "stories", list)
	var catalog_pending := _catalog_path.get_basename() + ".pending.tres"
	error = _write_pending(next_catalog, catalog_pending, _catalog_path)
	if error == OK: error = _replace(catalog_pending, _catalog_path)
	if error != OK:
		_restore_file(path, previous)
		return _error("无法更新任务目录，已还原配置：" + error_string(error))
	if original != null:
		for property in saved.get_property_list():
			if (property.usage & PROPERTY_USAGE_STORAGE) and property.name not in ["script", "resource_path"]: original.set(property.name, saved.get(property.name))
		list[index] = original
		saved = original
	catalog.set("quests" if page == 0 else "stories", list)
	return {"ok": true, "error": "", "resource": saved}

func _write_pending(resource: Resource, pending: String, path: String) -> Error:
	var uid := _resource_uid(path) if FileAccess.file_exists(path) else ResourceUID.INVALID_ID
	var error := ResourceSaver.save(resource, pending)
	if error != OK: return error
	if uid != ResourceUID.INVALID_ID:
		error = ResourceSaver.set_uid(ProjectSettings.globalize_path(pending), uid)
		# set_uid can point editor bookkeeping at the temporary file. The stable
		# resource must keep its original identity throughout a save or rollback.
		_bind_uid(uid, path)
	return error

func _resource_uid(path: String) -> int:
	# Newly created test/draft resources may not be in the editor's UID cache.
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var header := file.get_line()
		if header.contains(' uid="uid://'):
			return ResourceUID.text_to_id(header.get_slice(' uid="', 1).get_slice('"', 0))
	return ResourceLoader.get_resource_uid(path)

func _bind_uid(uid: int, path: String) -> void:
	if uid == ResourceUID.INVALID_ID: return
	if ResourceUID.has_id(uid): ResourceUID.set_id(uid, path)
	else: ResourceUID.add_id(uid, path)

func _replace(pending: String, path: String) -> Error:
	var backup := path + ".editor-backup"
	if FileAccess.file_exists(backup): return ERR_ALREADY_EXISTS
	var had_original := FileAccess.file_exists(path)
	var uid := _resource_uid(pending)
	if had_original:
		var error := DirAccess.rename_absolute(path, backup)
		if error != OK: return error
	var error := DirAccess.rename_absolute(pending, path)
	if error != OK and had_original: DirAccess.rename_absolute(backup, path)
	elif error == OK and had_original: DirAccess.remove_absolute(backup)
	if error == OK: _bind_uid(uid, path)
	return error

func _restore_file(path: String, bytes: Variant) -> void:
	if bytes == null:
		var uid := _resource_uid(path)
		DirAccess.remove_absolute(path)
		if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) == path:
			ResourceUID.remove_id(uid)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null: file.store_buffer(bytes)

func _reference_exists(field: String, id: StringName) -> bool:
	if field == "item_id": return items.find_item(id) != null
	if field == "recipe_id": return recipes.find_recipe(id) != null
	for entry: Resource in entries(1 if field == "story_id" else 0):
		if entry.get(field) == id: return true
	return false

func _target_reference(kind: String) -> String:
	if kind in ["have_item", "craft_confirmed", "grant_item"]: return "item_id"
	if kind == "recipe_known": return "recipe_id"
	if kind in ["story_completed", "request_story", "talk"]: return "story_id"
	if kind in ["quest_completed", "accept_quest"]: return "quest_id"
	return ""

func _public_title(resource: Resource) -> String:
	for field in ["title", "display_name", "text"]:
		if _has(resource, field) and not str(resource.get(field)).is_empty(): return str(resource.get(field))
	return ""

func _has(resource: Resource, field: String) -> bool:
	for property in resource.get_property_list():
		if property.name == field: return true
	return false

func _validate_id(issues: Array[Dictionary], id: String, field: String) -> void:
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z][A-Za-z0-9_/-]*$")
	if pattern.search(id) == null: _issue(issues, "ID 需要以字母开头，只用字母、数字、下划线、斜线或连字符。", field)

func _issue(issues: Array[Dictionary], message: String, field: String, severity: String = "error") -> void:
	issues.append({"message": message, "field": field, "severity": severity})

func _success() -> Dictionary:
	return {"ok": true, "error": ""}

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

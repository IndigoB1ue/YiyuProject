extends SceneTree

const Store = preload("res://addons/quest_editor/resource_store.gd")
const PANEL = preload("res://addons/quest_editor/main_panel.tscn")
const DIRECTORY := "res://.godot/quest_editor_tests"
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 8: await process_frame

func _resource(script: String) -> Resource:
	return load("res://scripts/quest/" + script + ".gd").new()

func _field(form: Control, path: String, value: Variant) -> void:
	var control: Control = form.get_field(path)
	_expect(control != null, "Form exposes editable field " + path)
	if control is LineEdit:
		control.text = str(value)
		control.text_changed.emit(control.text)
	elif control is TextEdit:
		control.text = str(value)
		control.text_changed.emit()
	elif control is OptionButton:
		for index in control.item_count:
			if control.get_item_metadata(index) == value:
				control.select(index)
				control.item_selected.emit(index)
				return
		_expect(false, "Directory choice exists for " + str(value))
	elif control is SpinBox: control.value = value
	elif control is CheckBox: control.button_pressed = value

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	for name in ["editor_only_task.tres", "editor_only_task_copy.tres", "editor_recipe_link.tres", "story_editor_story.tres"]:
		var path := DIRECTORY.path_join(name)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var catalog := _resource("quest_catalog")
	var catalog_path := DIRECTORY.path_join("catalog.tres")
	_expect(ResourceSaver.save(catalog, catalog_path) == OK, "Create a temporary test catalog")
	var store = Store.new()
	_expect(store.load_catalogs(catalog_path).ok, "Authoring store reads the selected catalog")
	var story := _resource("quest_story_data")
	story.set("story_id", &"editor_story")
	story.set("timeline_path", "res://tests/fixtures/CP03_save_test.dtl")
	story.set("completion_signal", &"EditorStoryFinished")
	var story_saved: Dictionary = store.save_entry(story, null, 1)
	_expect(story_saved.ok and store.entries(1).size() == 1, "The story form's catalog stores timeline and normal completion configuration")
	var quest := _resource("quest_data")
	quest.set("quest_id", &"editor_only_task")
	quest.set("display_name", "编辑器独立测试")
	quest.set("description", "此配置只写入临时目录。")
	var first := _resource("quest_stage_data")
	first.set("stage_id", &"prepare")
	first.set("title", "准备材料")
	var goal := _resource("quest_objective_data")
	goal.set("objective_id", &"water")
	goal.set("kind", &"have_item")
	goal.set("target_id", &"Water")
	goal.set("amount", 2)
	goal.set("text", "准备清水")
	first.get("objectives").append(goal)
	var secret := _resource("quest_objective_data")
	secret.set("objective_id", &"hidden_fact")
	secret.set("kind", &"fact")
	secret.set("target_id", &"secret_answer")
	secret.set("text", "SECRET_NEVER_PUBLISH")
	secret.set("visible", false)
	first.get("objectives").append(secret)
	quest.get("stages").append(first)
	var second := _resource("quest_stage_data")
	second.set("stage_id", &"talk")
	second.set("title", "与测试对象交谈")
	var conversation := _resource("quest_objective_data")
	conversation.set("objective_id", &"conversation")
	conversation.set("kind", &"talk")
	conversation.set("actor_id", &"editor_actor")
	conversation.set("topic_id", &"editor_topic")
	conversation.set("text", "询问下一步")
	second.get("objectives").append(conversation)
	quest.get("stages").append(second)
	var reward := _resource("quest_action_data")
	reward.set("action_id", &"reward_water")
	reward.set("kind", &"grant_item")
	reward.set("target_id", &"Water")
	quest.get("completion_actions").append(reward)
	var saved: Dictionary = store.save_entry(quest)
	_expect(saved.ok, "Persist a task and register it in the catalog: " + str(saved.error))
	if not saved.ok:
		quit(1)
		return
	var task_uid := ResourceUID.create_id()
	var catalog_uid := ResourceUID.create_id()
	_expect(ResourceSaver.set_uid(ProjectSettings.globalize_path(saved.resource.resource_path), task_uid) == OK, "Seed the task's stable resource UID")
	_expect(ResourceSaver.set_uid(ProjectSettings.globalize_path(catalog_path), catalog_uid) == OK, "Seed the catalog's stable resource UID")
	var reopened = Store.new()
	_expect(reopened.load_catalogs(catalog_path).ok and reopened.entries(0).size() == 1, "Reopen the persisted catalog")
	var disk_catalog: Resource = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_expect(disk_catalog.get("quests")[0].get("stages").size() == 2, "Catalog stores the configured ordered stages on disk")
	var invalid: Resource = saved.resource.duplicate(true)
	invalid.set("quest_id", &"changed_id")
	_expect(not store.save_entry(invalid, saved.resource).ok, "Existing task IDs cannot change")
	invalid = saved.resource.duplicate(true)
	invalid.get("stages")[0].get("objectives")[0].set("target_id", &"missing_item")
	_expect(not store.save_entry(invalid, saved.resource).ok, "Unknown item references cannot be saved")
	var preview: String = store.public_preview(saved.resource)
	_expect(preview.contains("准备清水") and preview.contains("询问下一步") and not preview.contains("SECRET_NEVER_PUBLISH") and not preview.contains("secret_answer"), "Public preview uses the shared redacted objective view")
	var experimental: Resource = saved.resource.duplicate(true)
	var materials := _resource("quest_objective_data")
	materials.set("objective_id", &"public_materials")
	materials.set("kind", &"recipe_materials")
	materials.set("text", "准备公开配方素材")
	materials.set("recipe", store.recipes.find_recipe(&"ExperimentThree"))
	experimental.get("stages")[0].get("objectives").append(materials)
	preview = store.public_preview(experimental)
	var hidden_item: ItemData = store.items.find_item(&"ExperimentLeaf")
	_expect(not preview.contains("ExperimentLeaf") and (hidden_item == null or not preview.contains(hidden_item.display_name)), "Public preview excludes experimental hidden ingredient answers")
	var canvas := Control.new()
	root.add_child(canvas)
	current_scene = canvas
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel = PANEL.instantiate()
	canvas.add_child(panel)
	panel.setup(store)
	await _settle()
	_expect(not panel.has_unsaved_changes() and panel._list.item_count == 1, "The dedicated form starts from a clean selected resource")
	_expect(not (panel._form.get_field("quest_id") as LineEdit).editable, "Existing task IDs are locked in the form")
	_expect(not (panel._form.get_field("stages.0.stage_id") as LineEdit).editable, "Existing stage IDs are locked in the form")
	panel._form._add_stage()
	panel._form._add_objective()
	var additional_goal: Resource = panel._form.get_resource().get("stages")[2].get("objectives")[0]
	additional_goal.set("objective_id", &"water")
	panel._form._rebuild()
	_expect((panel._form.get_field("stages.2.objectives.0.objective_id") as LineEdit).editable, "A new goal can use a scoped ID that already exists in a different stage")
	panel._discard()
	_field(panel._form, "display_name", "经表单修改的任务")
	_expect(panel.has_unsaved_changes() and store.entries(0)[0].get("display_name") == "编辑器独立测试", "Form edits a draft, leaving the project resource unchanged")
	panel._undo()
	_expect(panel._form.get_resource().get("display_name") == "编辑器独立测试", "Undo restores the working copy")
	panel._redo()
	_expect(panel._form.get_resource().get("display_name") == "经表单修改的任务", "Redo reapplies the working copy change")
	panel._form._stage_index = 1
	panel._form._move_stage(-1)
	_expect(panel._form.get_resource().get("stages")[0].get("stage_id") == &"talk", "Stage order is editable")
	panel._undo()
	_expect(panel._form.get_resource().get("stages")[0].get("stage_id") == &"prepare", "Undo restores stage order")
	panel._form.focus_field("stages.1.objectives.0.kind")
	_field(panel._form, "stages.1.objectives.0.kind", &"delivery")
	await _settle()
	_field(panel._form, "stages.1.objectives.0.actor_id", &"editor_actor")
	var delivery: Resource = panel._form.get_resource().get("stages")[1].get("objectives")[0]
	delivery.set("items", {&"Water": 1})
	panel._changed()
	panel._form._rebuild()
	_expect(panel._form.get_field("stages.1.objectives.0.items.Water") is SpinBox, "Delivery has a dedicated catalog-based cost and quantity form")
	_expect(panel._save_current(), "Save writes the form's changed task")
	_expect(ResourceLoader.get_resource_uid(saved.resource.resource_path) == task_uid and ResourceLoader.get_resource_uid(catalog_path) == catalog_uid, "Replacing a task and catalog preserves their existing resource UIDs")
	_expect(ResourceUID.get_id_path(task_uid) == saved.resource.resource_path and ResourceUID.get_id_path(catalog_uid) == catalog_path, "UID references point to the saved files instead of temporary staging files")
	disk_catalog = ResourceLoader.load(catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	_expect(disk_catalog.get("quests")[0].get("display_name") == "经表单修改的任务" and disk_catalog.get("quests")[0].get("stages")[1].get("objectives")[0].get("items").get(&"Water") == 1, "Edited task data survives a fresh disk reload")
	panel._search.text = "不存在的名称"
	panel._search.text_changed.emit(panel._search.text)
	_expect(panel._list.item_count == 0, "The task list searches names and IDs")
	panel._search.text = ""
	panel._search.text_changed.emit(panel._search.text)
	_field(panel._form, "description", "未保存的修改")
	panel._request_change(panel._copy)
	_expect(panel.get_node("%Unsaved").visible and panel._form.get_resource().get("quest_id") == &"editor_only_task", "Navigation preserves the draft until the unsaved dialog is resolved")
	panel.get_node("%Unsaved").custom_action.emit(&"discard")
	_expect(panel._new and (panel._form.get_field("quest_id") as LineEdit).editable and panel._form.get_resource().get("quest_id") != &"editor_only_task", "Copy creates an independently editable task ID")
	panel._discard()
	panel._form.focus_field("stages.0.objectives.0.kind")
	panel._check_all()
	var preview_snapshot: String = panel._preview.text
	panel._page = 1
	panel._open(store.entries(1)[0], false)
	_expect(panel._form.get_field("timeline_path") is LineEdit and panel._form.get_field("completion_signal") is LineEdit, "Story configuration has timeline and completion-signal fields")
	panel._page = 0
	panel._open(store.entries(0)[0], false)
	_expect(panel._preview.text == preview_snapshot, "Switching forms preserves the configured quest and its public preview")
	var linked: Resource = experimental.duplicate(true)
	linked.set("quest_id", &"editor_recipe_link")
	linked.set("recipe", store.recipes.find_recipe(&"ExperimentThree").duplicate(true))
	var link_result: Dictionary = store.save_entry(linked)
	_expect(link_result.ok, "A copied task with recipe references can be saved")
	if link_result.ok:
		var linked_recipe: AlchemyRecipe = link_result.resource.get("stages")[0].get("objectives")[-1].get("recipe")
		_expect(linked_recipe.resource_path == "res://data/recipes/experiment_three.tres" and link_result.resource.get("recipe").resource_path == linked_recipe.resource_path, "Task copies keep external canonical recipe links instead of embedded ingredient snapshots")
	var before_task := FileAccess.get_file_as_bytes(saved.resource.resource_path)
	var before_catalog := FileAccess.get_file_as_bytes(catalog_path)
	var rollback_draft: Resource = saved.resource.duplicate(true)
	rollback_draft.set("description", "This edit must roll back when the catalog cannot be replaced.")
	var lock_path := catalog_path + ".editor-backup"
	var lock := FileAccess.open(lock_path, FileAccess.WRITE)
	lock.store_string("test replacement lock")
	lock.close()
	var rollback_result: Dictionary = store.save_entry(rollback_draft, saved.resource)
	_expect(not rollback_result.ok and FileAccess.get_file_as_bytes(saved.resource.resource_path) == before_task and FileAccess.get_file_as_bytes(catalog_path) == before_catalog, "A later catalog failure restores the task file and leaves the catalog unchanged")
	_expect(ResourceUID.get_id_path(task_uid) == saved.resource.resource_path and store._resource_uid(saved.resource.resource_path) == task_uid, "A failed save also preserves the old task UID and its reference")
	DirAccess.remove_absolute(lock_path)
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/quest_editor_preview.png")
	print("Quest editor persistence and forms: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

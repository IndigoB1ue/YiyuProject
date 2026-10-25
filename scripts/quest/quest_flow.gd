class_name QuestFlowRunner
extends Node

signal story_started(story_id: StringName)
signal story_finished(story_id: StringName, completed: bool)
signal playback_failed(message: String)
signal flow_changed

var is_restoring := false
var _manager: Node
var _inventory: InventorySystem
var _progress: Node
var _dialogic: Node
var _stories: Dictionary = {}
var _overrides: Dictionary = {}
var _active_story_id: StringName = &""
var _active_timeline: DialogicTimeline
var _next_run_id := 1
var _generation := 0
var _finishing := false
var _executing := false
var _scheduled := false
var _suppress_schedule := false
var _interrupted: Dictionary = {}
var _action_errors: Dictionary = {}


func set_dependencies(manager: Node, inventory: InventorySystem, progress: Node) -> void:
	if is_instance_valid(_manager) and _manager.quests_changed.is_connected(_schedule_actions):
		_manager.quests_changed.disconnect(_schedule_actions)
	if is_instance_valid(_manager) and _manager.has_signal("actions_changed") and _manager.actions_changed.is_connected(_schedule_actions):
		_manager.actions_changed.disconnect(_schedule_actions)
	_manager = manager
	_inventory = inventory
	_progress = progress
	if _manager != null:
		_manager.quests_changed.connect(_schedule_actions)
		if _manager.has_signal("actions_changed"):
			_manager.actions_changed.connect(_schedule_actions)
		if _manager.has_method("set_flow"):
			_manager.set_flow(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _manager == null:
		set_dependencies(get_node("/root/QuestSystem"), get_node("/root/PlayerInventory"), get_node("/root/GameProgress"))
	_dialogic = get_node("/root/Dialogic")
	_dialogic.timeline_started.connect(_on_timeline_started)
	_dialogic.timeline_ended.connect(_on_timeline_ended)
	_dialogic.signal_event.connect(_on_dialogic_signal)
	get_tree().scene_changed.connect(_on_scene_changed)
	_connect_save_system.call_deferred()


func _connect_save_system() -> void:
	var save := get_node_or_null("/root/SaveSystem")
	if save != null and not save.restore_started.is_connected(begin_restore):
		save.restore_started.connect(begin_restore)
		save.restore_finished.connect(end_restore)


func get_story(story_id: StringName) -> QuestStoryData:
	if _manager == null:
		return null
	var catalog: Resource = _manager.get("catalog")
	if catalog == null:
		return null
	for story: QuestStoryData in catalog.stories:
		if story != null and story.story_id == story_id:
			return story
	return null


func get_active_story_id() -> StringName:
	return _active_story_id


func is_story_playing(story_id: StringName = &"") -> bool:
	return _active_story_id != &"" and (story_id == &"" or story_id == _active_story_id)


func is_story_completed(story_id: StringName) -> bool:
	return _stories.get(story_id, {}).get("status", "") == "completed"


func get_story_state(story_id: StringName) -> Dictionary:
	return _stories.get(story_id, {}).duplicate(true)


func set_story_override(story_id: StringName, options: Dictionary) -> void:
	_overrides[story_id] = options.duplicate()


func _story_options(story: QuestStoryData, options: Dictionary = {}) -> Dictionary:
	var result := {"timeline_path": story.timeline_path, "return_scene_path": story.return_scene_path, "allowed_scene_path": story.allowed_scene_path}
	result.merge(_overrides.get(story.story_id, {}), true)
	result.merge(options, true)
	return result


func start_story(story_id: StringName, options: Dictionary = {}) -> Dictionary:
	if _blocked():
		return _error("正在恢复进度，暂不能播放剧情。")
	if _finishing:
		return _error("当前剧情正在结束，请稍后继续。")
	var story := get_story(story_id)
	if story == null:
		return _error("找不到剧情配置：%s" % story_id)
	if is_story_completed(story_id):
		return {"ok": true, "error": "", "already_completed": true}
	if _active_story_id != &"":
		return _error("当前剧情正在播放。")
	if _dialogic == null or _dialogic.current_timeline != null:
		return _error("当前剧情尚未结束，请稍后继续。")
	var settings := _story_options(story, options)
	var scene := get_tree().current_scene
	if not str(settings.allowed_scene_path).is_empty() and (scene == null or scene.scene_file_path != settings.allowed_scene_path):
		return _error("请前往指定地点继续剧情。")
	var path: String = settings.timeline_path
	if path.is_empty() or not ResourceLoader.exists(path):
		return _error("无法播放后续剧情：timeline 不存在。\n%s" % path)
	var timeline := load(path) as DialogicTimeline
	if timeline == null or story.completion_signal == &"":
		return _error("剧情配置缺少有效 timeline 或完成信号。")
	var run_id := "%s/%d" % [story_id, _next_run_id]
	_interrupted.erase(story_id)
	_next_run_id += 1
	_stories[story_id] = {"status": "playing", "run_id": run_id, "timeline_path": timeline.resource_path,
		"return_scene_path": str(settings.return_scene_path), "action_key": str(options.get("action_key", "")),
		"owner_scene_path": scene.scene_file_path if scene != null else ""}
	_active_story_id = story_id
	_active_timeline = timeline
	_finishing = false
	_dialogic.start(timeline)
	flow_changed.emit()
	return {"ok": true, "error": "", "run_id": run_id}


func _on_timeline_started() -> void:
	if _blocked() or _active_story_id == &"" or _dialogic.current_timeline != _active_timeline:
		return
	var story := get_story(_active_story_id)
	_set_legacy_flag(story.legacy_started_flag, true)
	story_started.emit(_active_story_id)


func _on_timeline_ended() -> void:
	if _blocked() or _finishing or _active_story_id == &"":
		return
	_interrupt_active_story()


func _interrupt_active_story() -> void:
	var id := _active_story_id
	if id == &"":
		return
	var record: Dictionary = _stories[id]
	record.status = "pending"
	_interrupted[id] = true
	var story := get_story(id)
	if story != null:
		_set_legacy_flag(story.legacy_started_flag, false)
	_release_action(str(record.get("action_key", "")))
	_active_story_id = &""
	_active_timeline = null
	_finishing = false
	story_finished.emit(id, false)
	flow_changed.emit()


func _on_dialogic_signal(argument: String) -> void:
	if _blocked() or _finishing or _active_story_id == &"" or _dialogic.current_timeline != _active_timeline:
		return
	var story := get_story(_active_story_id)
	if story == null or StringName(argument) != story.completion_signal:
		return
	var id := _active_story_id
	var record: Dictionary = _stories[id]
	var generation := _generation
	var run_id: String = record.run_id
	_finishing = true
	record.status = "completed"
	_active_story_id = &""
	_active_timeline = null
	_set_legacy_flag(story.legacy_completed_flag, true)
	_finish_action(str(record.get("action_key", "")))
	# Both facts identify this exact run. An unrelated signal or canceled run
	# can never be substituted for the authored completion.
	if story.actor_id != &"":
		_manager.report_event(&"talk", {"actor_id": story.actor_id, "topic_id": story.topic_id, "story_id": id, "run_id": run_id}, "story:%s:talk" % run_id)
	_manager.report_event(&"story_completed", {"story_id": id, "run_id": run_id}, "story:%s:complete" % run_id)
	await _dialogic.end_timeline(true)
	if not is_inside_tree() or _blocked() or generation != _generation:
		return
	_finishing = false
	story_finished.emit(id, true)
	flow_changed.emit()
	var return_path: String = record.get("return_scene_path", "")
	var current_scene := get_tree().current_scene
	var owner_path: String = record.get("owner_scene_path", "")
	var current_path: String = current_scene.scene_file_path if current_scene != null else ""
	if not return_path.is_empty() and current_path != return_path and (owner_path.is_empty() or current_path == owner_path):
		var error := get_tree().change_scene_to_file(return_path)
		if error != OK:
			playback_failed.emit("剧情已结束，但无法返回指定场景：%s" % return_path)
	_schedule_actions()


func _on_scene_changed() -> void:
	if _blocked():
		return
	var generation := _generation
	var interrupted_here := false
	if _active_story_id != &"" and not _finishing:
		var scene := get_tree().current_scene
		var owner: String = _stories[_active_story_id].get("owner_scene_path", "")
		if scene == null or (not owner.is_empty() and scene.scene_file_path != owner):
			interrupted_here = true
			await cancel_story()
	if generation != _generation or _blocked():
		return
	if not interrupted_here:
		_interrupted.clear()
	_schedule_actions()


func cancel_story() -> void:
	if _blocked() or _active_story_id == &"":
		return
	var timeline := _active_timeline
	_interrupt_active_story()
	if timeline != null and _dialogic.current_timeline == timeline:
		await _dialogic.end_timeline(true)


func _schedule_actions() -> void:
	if _scheduled or _blocked() or _suppress_schedule:
		return
	_scheduled = true
	_execute_scheduled.call_deferred()


func _execute_scheduled() -> void:
	_scheduled = false
	execute_pending_actions(false)


func execute_pending_actions(allow_retry: bool = true) -> void:
	if _blocked() or _executing or _manager == null or not _manager.has_method("get_pending_actions"):
		return
	_executing = true
	_manager.begin_transaction()
	for entry: Dictionary in _manager.get_pending_actions():
		var action: QuestActionData = entry.action
		var key: String = entry.key
		if action != null and action.kind == &"request_story" and not allow_retry and _interrupted.has(action.target_id):
			continue
		var result := _execute_action(action, key)
		if result.ok and not result.get("running", false):
			_finish_action(key)
		if result.ok:
			_action_errors.erase(key)
		if not result.ok and (str(result.error).contains("timeline") or str(result.error).contains("找不到")) and _action_errors.get(key, "") != result.error:
			_action_errors[key] = result.error
			playback_failed.emit(result.error)
	_manager.end_transaction()
	_executing = false


func is_action_transaction_active() -> bool:
	return _executing


func _execute_action(action: QuestActionData, key: String) -> Dictionary:
	if action == null:
		return _error("任务动作无效。")
	match action.kind:
		&"request_story":
			var result := start_story(action.target_id, {"action_key": key})
			if result.ok and not result.get("already_completed", false) and get_story_state(action.target_id).get("status", "") == "playing":
				_manager.mark_action_started(key)
				result["running"] = true
			elif result.ok and not is_story_completed(action.target_id):
				return _error("剧情播放被中断。")
			return result
		&"accept_quest":
			if not _manager.get_quest_state(action.target_id).is_empty():
				return {"ok": true, "error": ""}
			return {"ok": _manager.accept_quest(action.target_id), "error": "无法接取后续任务。"}
		&"grant_item":
			return _inventory.add_item(action.target_id, action.amount)
	return _error("不支持的任务动作：%s" % action.kind)


func _finish_action(key: String) -> void:
	if not key.is_empty() and _manager != null:
		_manager.complete_action(key)


func _release_action(key: String) -> void:
	if not key.is_empty() and _manager != null:
		_manager.reset_action(key)


func begin_restore() -> void:
	is_restoring = true
	_generation += 1
	_scheduled = false
	_finishing = false
	_active_timeline = null


func end_restore() -> void:
	is_restoring = false
	_suppress_schedule = true
	# Bind a restored checkpoint; never start a timeline from the beginning here.
	if _active_story_id != &"" and _stories.has(_active_story_id):
		var record: Dictionary = _stories[_active_story_id]
		var timeline := load(record.timeline_path) as DialogicTimeline if ResourceLoader.exists(record.timeline_path) else null
		if timeline != null and _dialogic.current_timeline == timeline:
			_active_timeline = timeline
			story_started.emit(_active_story_id)
		else:
			_interrupt_active_story()
	for id in _stories:
		var story := get_story(id)
		if story != null:
			_set_legacy_flag(story.legacy_started_flag, _stories[id].status != "pending")
			_set_legacy_flag(story.legacy_completed_flag, _stories[id].status == "completed")
	_suppress_schedule = false
	flow_changed.emit()


func get_save_state() -> Dictionary:
	return {"stories": _stories.duplicate(true), "active_story_id": _active_story_id, "next_run_id": _next_run_id}


func validate_save_state(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {"ok": true, "error": ""}
	if not state.get("stories") is Dictionary or not (state.get("active_story_id") is String or state.get("active_story_id") is StringName) or not state.get("next_run_id") is int or state.next_run_id < 1:
		return _error("存档中的剧情流程结构无效。")
	var playing := 0
	var run_ids: Dictionary = {}
	for id in state.stories:
		if not (id is String or id is StringName) or get_story(StringName(id)) == null or not state.stories[id] is Dictionary:
			return _error("存档包含未知剧情。")
		var record: Dictionary = state.stories[id]
		if record.get("status") not in ["pending", "playing", "completed"]:
			return _error("存档中的剧情流程状态无效。")
		for field: String in ["run_id", "timeline_path", "return_scene_path", "action_key", "owner_scene_path"]:
			if not record.get(field) is String:
				return _error("存档中的剧情播放记录无效。")
		var serial_text: String = str(record.run_id).get_slice("/", str(record.run_id).get_slice_count("/") - 1)
		if not str(record.run_id).begins_with(str(id) + "/") or not serial_text.is_valid_int() or int(serial_text) < 1 or int(serial_text) >= state.next_run_id or run_ids.has(record.run_id):
			return _error("存档中的剧情播放编号无效。")
		run_ids[record.run_id] = true
		if record.status == "playing":
			playing += 1
			if StringName(state.active_story_id) != StringName(id) or record.run_id.is_empty() or not ResourceLoader.exists(record.timeline_path):
				return _error("存档中的活跃剧情不匹配。")
	if playing > 1 or (playing == 0 and not str(state.active_story_id).is_empty()):
		return _error("存档中的活跃剧情数量无效。")
	return {"ok": true, "error": ""}


func restore_save_state(state: Dictionary, notify: bool = true) -> void:
	_generation += 1
	_stories.clear()
	for id in state.get("stories", {}):
		_stories[StringName(id)] = state.stories[id].duplicate(true)
	_active_story_id = StringName(state.get("active_story_id", ""))
	_active_timeline = null
	_next_run_id = int(state.get("next_run_id", 1))
	_finishing = false
	_scheduled = false
	_interrupted.clear()
	_action_errors.clear()
	if notify:
		flow_changed.emit()


## Scene checkpoint compatibility. This binds identity only; it never plays.
func restore_playback(story_id: StringName, playing: bool) -> void:
	if not playing:
		if _active_story_id == story_id:
			if not is_story_completed(story_id):
				_stories[story_id].status = "pending"
			_active_story_id = &""
			_active_timeline = null
		return
	var story := get_story(story_id)
	if story == null:
		return
	if not _stories.has(story_id) or _stories[story_id].status != "playing":
		var options := _story_options(story)
		var scene := get_tree().current_scene
		_stories[story_id] = {"status": "playing", "run_id": "%s/%d" % [story_id, _next_run_id],
			"timeline_path": str(options.timeline_path), "return_scene_path": str(options.return_scene_path),
			"action_key": "", "owner_scene_path": scene.scene_file_path if scene != null else ""}
		_next_run_id += 1
	_active_story_id = story_id
	var path: String = _stories[story_id].timeline_path
	_active_timeline = load(path) as DialogicTimeline if ResourceLoader.exists(path) else null


func reset_for_new_game() -> void:
	restore_save_state({})
	_overrides.clear()


func migrate_legacy_state(progress: Dictionary, scene_path: String = "", scene_state: Dictionary = {}, timeline_path: String = "") -> Dictionary:
	var result := {"stories": {}, "active_story_id": &"", "next_run_id": 1}
	if _manager == null or _manager.get("catalog") == null:
		return result
	for story: QuestStoryData in _manager.catalog.stories:
		var completed: bool = story.legacy_completed_flag != &"" and progress.get(story.legacy_completed_flag, false)
		var started: bool = story.legacy_started_flag != &"" and progress.get(story.legacy_started_flag, false)
		if not completed and not started:
			continue
		var playing: bool = not completed and scene_state.get("story_playing", false) and not timeline_path.is_empty() and load(timeline_path) == load(story.timeline_path)
		var run_id := "%s/%d" % [story.story_id, result.next_run_id]
		result.next_run_id += 1
		result.stories[story.story_id] = {"status": "completed" if completed else ("playing" if playing else "pending"),
			"run_id": run_id, "timeline_path": story.timeline_path, "return_scene_path": story.return_scene_path,
			"action_key": "", "owner_scene_path": scene_path}
		if playing:
			result.active_story_id = story.story_id
	return result


func _set_legacy_flag(flag: StringName, value: bool) -> void:
	if _progress == null or flag == &"":
		return
	for property: Dictionary in _progress.get_property_list():
		if StringName(property.name) == flag and int(property.type) == TYPE_BOOL:
			if _progress.get(flag) != value:
				_progress.set(flag, value)
				if _progress.has_signal("room_story_changed"):
					_progress.emit_signal("room_story_changed")
			return


func _blocked() -> bool:
	if is_restoring or not is_inside_tree():
		return true
	if _manager != null and _manager.get("is_restoring") == true:
		return true
	var save := get_node_or_null("/root/SaveSystem")
	return save != null and save.is_restoring


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

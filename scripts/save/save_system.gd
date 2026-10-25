extends Node

signal slots_changed
signal restore_started
signal restore_finished

const SLOT_COUNT := 120
const PAGE_SIZE := 12
const FORMAT_VERSION := 1
const WORLD_SCENE := "res://scenes/world.tscn"

var storage_directory := "user://game_saves"
var chapter: int = 1
var play_seconds: float = 0.0
var is_restoring := false
var _last_tick: int
var _chapter_pattern := RegEx.new()

@onready var _dialogic: Node = get_node("/root/Dialogic")
@onready var _inventory: InventorySystem = get_node("/root/PlayerInventory")
@onready var _progress: Node = get_node("/root/GameProgress")
@onready var _quests: QuestManager = get_node("/root/QuestSystem")
@onready var _quest_flow: QuestFlowRunner = get_node("/root/QuestFlow")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_tick = Time.get_ticks_msec()
	_chapter_pattern.compile("^CP_?(\\d+)")
	_dialogic.timeline_started.connect(_on_timeline_started)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not is_restoring and not get_tree().paused and not _dialogic.paused and is_gameplay_context():
		play_seconds += float(now - _last_tick) / 1000.0
	_last_tick = now


func is_gameplay_context() -> bool:
	var scene := get_tree().current_scene
	if scene != null and scene.is_in_group("quest_sandbox"):
		return false
	return _dialogic.current_timeline != null or (scene != null and scene.is_in_group("settings_context"))


func can_save() -> Dictionary:
	var scene := get_tree().current_scene
	if _quests.is_transaction_active() or _quest_flow.is_action_transaction_active():
		return _error("正在提交物品或任务动作，请稍后保存。")
	if is_restoring or scene == null or not is_gameplay_context() or scene.scene_file_path.is_empty():
		return _error("当前没有可以保存的游戏进度。")
	if _dialogic.current_timeline != null:
		var index: int = _dialogic.current_event_idx
		if _dialogic.current_timeline.resource_path.is_empty():
			return _error("当前 timeline 尚未保存为文件，无法存档。")
		if index < 0 or index >= _dialogic.current_timeline_events.size():
			return _error("请等待剧情进入文字或选择节点后再保存。")
		var event = _dialogic.current_timeline_events[index]
		if not (event is DialogicTextEvent or event is DialogicChoiceEvent):
			return _error("请等待剧情进入文字或选择节点后再保存。")
	return {"ok": true, "error": ""}


func set_chapter(number: int) -> void:
	chapter = clampi(number, 1, 999)


func _on_timeline_started() -> void:
	if is_restoring or _dialogic.current_timeline == null:
		return
	var name: String = _dialogic.current_timeline.resource_path.get_file().get_basename()
	var match_result := _chapter_pattern.search(name)
	if match_result != null:
		set_chapter(int(match_result.get_string(1)))


static func format_play_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func capture_thumbnail() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var picture := get_viewport().get_texture().get_image()
	if picture != null and not picture.is_empty():
		picture.resize(480, 270, Image.INTERPOLATE_LANCZOS)
	return picture


func _slot_path(index: int) -> String:
	return storage_directory.path_join("slot_%03d.res" % index)


func get_slot_record(index: int) -> Dictionary:
	if index < 1 or index > SLOT_COUNT:
		return {"state": "corrupt", "error": "存档编号无效。"}
	var path := _slot_path(index)
	if not FileAccess.file_exists(path):
		path = path + ".backup.res"
	if not FileAccess.file_exists(path):
		return {"state": "empty"}
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameSaveData
	if data == null or data.format_version != FORMAT_VERSION or data.saved_at.is_empty() or data.chapter < 1 or not is_finite(data.play_seconds) or data.play_seconds < 0:
		return {"state": "corrupt", "error": "存档损坏或版本不兼容。"}
	var texture: ImageTexture
	if not data.thumbnail_png.is_empty():
		var picture := Image.new()
		if picture.load_png_from_buffer(data.thumbnail_png) == OK:
			texture = ImageTexture.create_from_image(picture)
	return {"state": "saved", "chapter": "第%d章" % data.chapter,
		"saved_at": data.saved_at, "play_time": format_play_time(data.play_seconds), "texture": texture}


func save_slot(index: int, thumbnail: Image = null) -> Dictionary:
	if index < 1 or index > SLOT_COUNT:
		return _error("存档编号无效。")
	var check := can_save()
	if not check.ok:
		return check
	var data := GameSaveData.new()
	var scene := get_tree().current_scene
	data.scene_path = scene.scene_file_path
	data.chapter = chapter
	data.saved_at = Time.get_datetime_string_from_system(false, true).replace("-", "/")
	data.play_seconds = play_seconds
	data.inventory = _inventory.get_save_state()
	data.progress = _progress.get_save_state()
	data.quests = _quests.get_save_state()
	data.quest_flow = _quest_flow.get_save_state()
	data.scene_state = scene.get_save_state() if scene.has_method("get_save_state") else {}
	data.dialogic_state = _dialogic.get_full_state()
	if data.dialogic_state.timeline.is_empty():
		# Detached portrait/textbox state has no layout outside dialogue.
		var variables: Dictionary = data.dialogic_state.subsystems.get("VAR", {})
		data.dialogic_state.subsystems.clear()
		data.dialogic_state.subsystems["VAR"] = variables
	if thumbnail != null and not thumbnail.is_empty():
		data.thumbnail_png = thumbnail.save_png_to_buffer()
	check = _validate(data)
	if not check.ok:
		return check
	var error := DirAccess.make_dir_recursive_absolute(storage_directory)
	if error != OK:
		return _error("无法创建存档目录：%s" % error_string(error))
	var path := _slot_path(index)
	var pending := path + ".pending.res"
	var backup := path + ".backup.res"
	error = ResourceSaver.save(data, pending)
	if error != OK:
		return _error("保存失败，原存档未更改：%s" % error_string(error))
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup):
			error = DirAccess.remove_absolute(backup)
			if error != OK:
				return _error("无法更新存档备份，原存档未更改。")
		error = DirAccess.rename_absolute(path, backup)
		if error != OK:
			return _error("无法替换原存档：%s" % error_string(error))
	error = DirAccess.rename_absolute(pending, path)
	if error != OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(backup, path)
		return _error("存档写入失败，已保留原存档：%s" % error_string(error))
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	_dialogic.History.save_visited_history()
	slots_changed.emit()
	return {"ok": true, "error": ""}


func _read_slot(index: int) -> Dictionary:
	if index < 1 or index > SLOT_COUNT:
		return _error("存档编号无效。")
	var path := _slot_path(index)
	if not FileAccess.file_exists(path):
		path += ".backup.res"
	if not FileAccess.file_exists(path):
		return _error("该存档为空。")
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameSaveData
	var check := _validate(data)
	if check.ok:
		check["data"] = data
	return check


func _validate(data: GameSaveData) -> Dictionary:
	if data == null or data.format_version != FORMAT_VERSION:
		return _error("存档损坏或版本不兼容。")
	if data.saved_at.is_empty():
		return _error("存档缺少保存日期。")
	if data.chapter < 1 or data.chapter > 999 or not is_finite(data.play_seconds) or data.play_seconds < 0:
		return _error("存档中的章节或游玩时长无效。")
	if not data.scene_path.begins_with("res://") or not ResourceLoader.exists(data.scene_path):
		return _error("存档对应的游戏场景不存在。")
	var check := _inventory.validate_save_state(data.inventory)
	if not check.ok:
		return check
	check = _progress.validate_save_state(data.progress)
	if not check.ok:
		return check
	check = _quests.validate_save_state(data.quests)
	if not check.ok:
		return check
	check = _quest_flow.validate_save_state(data.quest_flow)
	if not check.ok:
		return check
	if data.dialogic_state == null:
		return _error("存档缺少剧情状态。")
	var active_story: StringName = data.quest_flow.get("active_story_id", &"")
	if active_story != &"":
		var story_record: Dictionary = data.quest_flow.stories[active_story]
		if data.dialogic_state.timeline.is_empty() or load(story_record.timeline_path) != load(data.dialogic_state.timeline):
			return _error("存档中的任务剧情与对话播放位置不一致。")
	if data.dialogic_state.timeline.is_empty() and (data.scene_state.get("playing", false) == true or data.scene_state.get("story_playing", false) == true):
		return _error("存档中的后续剧情缺少 timeline。")
	if not data.dialogic_state.timeline.is_empty():
		if not data.dialogic_state.timeline.begins_with("res://") or not ResourceLoader.exists(data.dialogic_state.timeline):
			return _error("存档对应的 timeline 不存在。")
		var timeline := load(data.dialogic_state.timeline) as DialogicTimeline
		if timeline == null:
			return _error("存档中的 timeline 无效。")
		timeline.process()
		var index := data.dialogic_state.event_index
		if index < 0 or index >= timeline.events.size() or not (timeline.events[index] is DialogicTextEvent or timeline.events[index] is DialogicChoiceEvent):
			return _error("存档的剧情节点无效，不能安全恢复。")
	var packed := load(data.scene_path) as PackedScene
	if packed == null:
		return _error("无法读取存档场景。")
	if not data.scene_state.is_empty():
		var preview := packed.instantiate()
		if preview.has_method("validate_save_state"):
			var inventory_preview := InventorySystem.new()
			inventory_preview.catalog = _inventory.catalog
			inventory_preview.restore_save_state(data.inventory)
			check = preview.validate_save_state(data.scene_state, inventory_preview, data.progress)
			inventory_preview.free()
		else:
			check = _error("存档中的场景状态不受支持。")
		preview.free()
		if not check.ok:
			return check
	return {"ok": true, "error": "", "scene": packed}


func load_slot(index: int) -> Dictionary:
	if is_restoring:
		return _error("正在读取存档，请稍候。")
	# Validate every subsystem before changing any of the current game state.
	var check := _read_slot(index)
	if not check.ok:
		return check
	var data: GameSaveData = check.data
	is_restoring = true
	restore_started.emit()
	_close_overlays()
	get_tree().paused = false
	# Freeze text reveal during Dialogic's one-frame event cleanup.
	_dialogic.paused = true
	_dialogic.Inputs.auto_skip.enabled = false
	_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	# Finish pending textbox animations while the old timeline is still valid.
	_dialogic._cleanup_previous_event()
	_dialogic.Animations.stop_animation()
	await _dialogic.end_timeline(true)
	_dialogic.paused = false
	var error := get_tree().change_scene_to_packed(check.scene)
	if error != OK:
		is_restoring = false
		restore_finished.emit()
		return _error("无法进入存档场景：%s" % error_string(error))
	# The old scene is detached but not freed yet. Notify after the new one is ready.
	_inventory.restore_save_state(data.inventory, false)
	_progress.restore_save_state(data.progress, false)
	var quest_state := data.quests if not data.quests.is_empty() else _quests.migrate_legacy_state(data.progress, data.scene_path)
	_quests.restore_save_state(quest_state, false)
	var flow_state := data.quest_flow if not data.quest_flow.is_empty() else _quest_flow.migrate_legacy_state(data.progress, data.scene_path, data.scene_state, data.dialogic_state.timeline)
	_quest_flow.restore_save_state(flow_state, false)
	chapter = data.chapter
	play_seconds = data.play_seconds
	await get_tree().scene_changed
	_inventory.inventory_changed.emit()
	_progress.notify_save_state_restored()
	_quests.notify_save_state_restored()
	var scene := get_tree().current_scene
	if scene.has_method("restore_save_state"):
		scene.restore_save_state(data.scene_state)
	await _dialogic.load_full_state(data.dialogic_state)
	if data.dialogic_state.timeline.is_empty():
		# Finish Dialogic's deferred empty-state cleanup before accepting new play.
		await get_tree().process_frame
		await get_tree().process_frame
	get_node("/root/GameSettings").apply_all()
	_dialogic.Inputs.block_input(0.2)
	is_restoring = false
	_last_tick = Time.get_ticks_msec()
	restore_finished.emit()
	return {"ok": true, "error": ""}


func start_new_game() -> Dictionary:
	if is_restoring:
		return _error("正在切换游戏进度，请稍候。")
	is_restoring = true
	restore_started.emit()
	_close_overlays()
	get_tree().paused = false
	_dialogic.paused = true
	_dialogic.Inputs.auto_skip.enabled = false
	_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	_dialogic._cleanup_previous_event()
	_dialogic.Animations.stop_animation()
	await _dialogic.end_timeline(true)
	_dialogic.paused = false
	await _dialogic.clear()
	_inventory.reset_for_new_game()
	_progress.reset_for_new_game()
	_quests.reset_for_new_game()
	_quest_flow.reset_for_new_game()
	chapter = 1
	play_seconds = 0.0
	var error := get_tree().change_scene_to_file(WORLD_SCENE)
	if error == OK:
		await get_tree().scene_changed
	# World skips automatic playback during restoration; start its opening now.
	is_restoring = false
	_last_tick = Time.get_ticks_msec()
	if error == OK:
		_dialogic.start("CP01_EP01_SI01")
	restore_finished.emit()
	return {"ok": error == OK, "error": "无法开始新游戏。" if error != OK else ""}


func _close_overlays() -> void:
	get_node("/root/DemoFlow").close_message()
	for entry in [["SettingsUI", "close_settings"], ["InventoryUI", "close_inventory"], ["SaveUI", "close_window"], ["QuestUI", "close_quests"]]:
		var overlay := get_node_or_null("/root/" + entry[0])
		if overlay != null:
			overlay.call(entry[1])


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

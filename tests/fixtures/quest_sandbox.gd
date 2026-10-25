extends Control

## Standalone F6 test content. Nothing here is registered in the production catalog.
const SNAPSHOT_PATH := "user://quest_sandbox/checkpoint.res"
const MAIN_QUEST := &"sandbox_student"
const STUDENT := &"sandbox_student_a"

@export var quest_catalog: Resource

var inventory: InventorySystem
var progress: GameProgressState
var manager: Node
var flow: Node
var delivery: RefCounted
var _selected: StringName = MAIN_QUEST
var _busy := false
var _global_ui: Array[Dictionary] = []
var _buttons: Array[Button] = []

@onready var _dialogic: Node = get_node("/root/Dialogic")
@onready var _status: Label = %Status
@onready var _tasks: ItemList = %Tasks
@onready var _details: Label = %Details
@onready var _stock: Label = %Stock


func _ready() -> void:
	for ui_name in ["QuestUI", "InventoryUI", "SettingsUI", "SaveUI"]:
		var ui := get_node_or_null("/root/" + ui_name) as CanvasLayer
		if ui != null:
			_global_ui.append({"node": ui, "visible": ui.visible, "mode": ui.process_mode})
			ui.hide()
			ui.process_mode = Node.PROCESS_MODE_DISABLED
	inventory = InventorySystem.new()
	inventory.name = "SandboxInventory"
	add_child(inventory)
	inventory.restore_save_state({"capacity": 200, "items": {}})
	progress = GameProgressState.new()
	progress.name = "SandboxProgress"
	add_child(progress)
	manager = load("res://scripts/quest/quest_system.gd").new()
	manager.name = "SandboxQuestSystem"
	manager.catalog = quest_catalog
	manager.set_dependencies(inventory, progress)
	flow = load("res://scripts/quest/quest_flow.gd").new()
	flow.name = "SandboxFlow"
	flow.set_dependencies(manager, inventory, progress)
	manager.set_flow(flow)
	add_child(manager)
	add_child(flow)
	delivery = load("res://scripts/quest/quest_delivery_service.gd").new()
	delivery.set_dependencies(manager, inventory)
	manager.quests_changed.connect(_refresh)
	inventory.inventory_changed.connect(_refresh)
	flow.flow_changed.connect(_refresh)
	flow.story_finished.connect(_on_story_finished)
	flow.playback_failed.connect(_show_error)
	_tasks.item_selected.connect(_on_task_selected)
	%Accept.pressed.connect(accept_commission)
	%Talk.pressed.connect(talk_to_student)
	%Supplies.pressed.connect(add_supplies)
	%Deliver.pressed.connect(func(): _show_result(deliver_to_student(), "交付成功，真实素材已扣除。"))
	%WrongRecipient.pressed.connect(func(): _show_result(deliver_to_student(&"sandbox_wrong_student"), "交付成功。"))
	%Ending.pressed.connect(play_ending)
	%NextLine.pressed.connect(advance_dialogue)
	%Save.pressed.connect(func(): _show_result(save_checkpoint(), "测试检查点已保存到独立目录。"))
	%Load.pressed.connect(_on_load_pressed)
	%Reset.pressed.connect(_on_reset_pressed)
	for child in %Accept.get_parent().get_children():
		if child is Button:
			_buttons.append(child)
	_refresh()


func _exit_tree() -> void:
	for state in _global_ui:
		if is_instance_valid(state.node):
			state.node.visible = state.visible
			state.node.process_mode = state.mode


func _input(event: InputEvent) -> void:
	# These controls must not advance the dialogue behind the test interface.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for button in _buttons:
			if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				button.pressed.emit()
				return


func accept_commission() -> void:
	var accepted: bool = manager.accept_quest(MAIN_QUEST)
	_status.text = "委托已接取。先与测试学生完整交谈。" if accepted else "该委托已接取，或当前前置条件未满足。"
	_refresh()


func talk_to_student() -> void:
	_show_result(flow.start_story(&"sandbox_briefing"), "交谈中：按空格或“继续剧情”阅读到结尾。")


func add_supplies() -> void:
	var herb := inventory.add_item(&"Herb", 2)
	var water := inventory.add_item(&"Water", 2)
	_show_result(water if herb.ok else herb, "测试背包获得：药草×2、清水×2。")


func deliver_to_student(recipient: StringName = STUDENT) -> Dictionary:
	return delivery.deliver(MAIN_QUEST, &"handover", recipient)


func play_ending() -> void:
	if manager.is_completed(MAIN_QUEST):
		_status.text = "委托已完成，奖励和后续剧情不会重复处理。"
		return
	var state: Dictionary = manager.get_quest_state(MAIN_QUEST)
	if state.is_empty() or str(state.get("stage_id", "")) != "report":
		_status.text = "请先完成交谈、准备和交付目标。"
		return
	_show_result(flow.start_story(&"sandbox_ending"), "后续剧情中：可以保存检查点，恢复后继续当前行。")


func advance_dialogue() -> void:
	if _dialogic.current_timeline == null:
		return
	if _dialogic.current_state == DialogicGameHandler.States.REVEALING_TEXT:
		_dialogic.Text.skip_text_reveal()
	elif _dialogic.current_state == DialogicGameHandler.States.IDLE:
		_dialogic.handle_next_event()


func save_checkpoint(path: String = SNAPSHOT_PATH) -> Dictionary:
	if _busy:
		return {"ok": false, "error": "正在恢复测试检查点。"}
	if manager.is_transaction_active() or flow.is_action_transaction_active():
		return {"ok": false, "error": "正在提交交付或完成动作，请稍后保存。"}
	if _dialogic.current_timeline != null:
		var index: int = _dialogic.current_event_idx
		if index < 0 or index >= _dialogic.current_timeline_events.size() or not (_dialogic.current_timeline_events[index] is DialogicTextEvent or _dialogic.current_timeline_events[index] is DialogicChoiceEvent):
			return {"ok": false, "error": "请等待剧情进入文字行后保存。"}
	var data := QuestSandboxSave.new()
	data.inventory = inventory.get_save_state()
	data.progress = progress.get_save_state()
	data.quests = manager.get_save_state()
	data.flow = flow.get_save_state()
	data.dialogue = _dialogic.get_full_state()
	if data.dialogue.timeline.is_empty():
		var variables: Dictionary = data.dialogue.subsystems.get("VAR", {})
		data.dialogue.subsystems.clear()
		data.dialogue.subsystems["VAR"] = variables
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = ResourceSaver.save(data, path)
	return {"ok": error == OK, "error": error_string(error) if error != OK else ""}


func load_checkpoint(path: String = SNAPSHOT_PATH) -> Dictionary:
	if _busy or not FileAccess.file_exists(path):
		return {"ok": false, "error": "尚无测试检查点，或正在恢复。"}
	var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as QuestSandboxSave
	if data == null or data.dialogue == null:
		return {"ok": false, "error": "测试检查点无效。"}
	for check in [inventory.validate_save_state(data.inventory), progress.validate_save_state(data.progress), manager.validate_save_state(data.quests), flow.validate_save_state(data.flow)]:
		if not check.ok:
			return check
	_set_busy(true)
	manager.begin_restore()
	flow.begin_restore()
	_dialogic.paused = true
	_dialogic.Inputs.auto_skip.enabled = false
	_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	_dialogic._cleanup_previous_event()
	_dialogic.Animations.stop_animation()
	await _dialogic.end_timeline(true)
	_dialogic.paused = false
	inventory.restore_save_state(data.inventory, false)
	progress.restore_save_state(data.progress, false)
	manager.restore_save_state(data.quests, false)
	flow.restore_save_state(data.flow, false)
	await _dialogic.load_full_state(data.dialogue)
	if data.dialogue.timeline.is_empty():
		# Dialogic ends an empty checkpoint through a deferred one-frame cleanup.
		await get_tree().process_frame
		await get_tree().process_frame
	manager.end_restore()
	flow.end_restore()
	_dialogic.Inputs.block_input(0.2)
	_set_busy(false)
	_refresh()
	return {"ok": true, "error": ""}


func reset_sandbox() -> void:
	_set_busy(true)
	manager.begin_restore()
	flow.begin_restore()
	if _dialogic.current_timeline != null:
		_dialogic.paused = true
		_dialogic._cleanup_previous_event()
		_dialogic.Animations.stop_animation()
		await _dialogic.end_timeline(true)
		_dialogic.paused = false
	inventory.restore_save_state({"capacity": 200, "items": {}}, false)
	progress.reset_for_new_game()
	flow.reset_for_new_game()
	manager.reset_for_new_game()
	manager.end_restore()
	flow.end_restore()
	_set_busy(false)
	_status.text = "独立测试已重置，正式背包和任务进度未更改。"
	_refresh()


func _on_load_pressed() -> void:
	_show_result(await load_checkpoint(), "测试进度已恢复。")


func _on_reset_pressed() -> void:
	await reset_sandbox()


func _show_result(result: Dictionary, success: String) -> void:
	_status.text = success if result.get("ok", false) else str(result.get("error", "操作未完成。"))
	_refresh()


func _show_error(message: String) -> void:
	_status.text = message

func _on_story_finished(story_id: StringName, completed: bool) -> void:
	if not completed:
		_status.text = "交谈已中断，目标尚未完成，可以重新开始。"
	elif story_id == &"sandbox_briefing":
		_status.text = "交谈已完成，请备齐材料后交付给测试学生。"
	elif story_id == &"sandbox_ending":
		_status.text = "委托已完成。测试奖励和后续委托仅在本场景中记录。"


func _set_busy(value: bool) -> void:
	_busy = value
	for button in _buttons:
		button.disabled = value


func _on_task_selected(index: int) -> void:
	_selected = _tasks.get_item_metadata(index)
	_refresh_details()


func _refresh() -> void:
	if not is_node_ready() or manager == null:
		return
	_tasks.clear()
	for id: StringName in manager.get_accepted_quests():
		var quest: Resource = manager.get_quest(id)
		var state: Dictionary = manager.get_quest_state(id)
		_tasks.add_item("%s · %s" % [quest.display_name, "已完成" if state.status == "completed" else "进行中"])
		_tasks.set_item_metadata(_tasks.item_count - 1, id)
		if id == _selected:
			_tasks.select(_tasks.item_count - 1)
	_refresh_details()
	_stock.text = "测试背包：药草×%d　清水×%d　回复药×%d" % [inventory.get_amount(&"Herb"), inventory.get_amount(&"Water"), inventory.get_amount(&"Potion")]


func _refresh_details() -> void:
	var state: Dictionary = manager.get_quest_state(_selected)
	if state.is_empty():
		_details.text = "请先接受学生委托。可以提前收集材料，交谈后系统会识别已有库存。"
		return
	var quest: Resource = manager.get_quest(_selected)
	var lines := PackedStringArray([quest.display_name, quest.description, ""])
	for row: Dictionary in manager.get_objectives(_selected):
		var text := "%s %s" % ["✓" if row.get("completed", false) else "○", row.text]
		if row.get("has_count", true):
			text += "　%d / %d" % [row.get("current", 0), row.get("required", 1)]
		lines.append(text)
	_details.text = "\n".join(lines)

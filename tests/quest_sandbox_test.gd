extends SceneTree

const MAIN := &"sandbox_student"
const SNAPSHOT := "user://quest_sandbox_test/progress.res"
const STORY_SNAPSHOT := "user://quest_sandbox_test/story.res"
const DONE_SNAPSHOT := "user://quest_sandbox_test/completed.res"

var _failures := 0
var _dialogic: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 10:
		await process_frame


func _wait_for_text() -> bool:
	for frame in 360:
		if _dialogic.current_timeline != null and _dialogic.current_state in [DialogicGameHandler.States.IDLE, DialogicGameHandler.States.REVEALING_TEXT]:
			return true
		await process_frame
	_expect(false, "A real Dialogic text event starts within the bounded wait")
	return false


func _finish_dialogue(sandbox: Control) -> void:
	for frame in 720:
		if _dialogic.current_timeline == null and sandbox.flow.get_active_story_id() == &"":
			await _settle()
			return
		sandbox.advance_dialogue()
		await process_frame
	_expect(false, "The authored story ending is reached without manually faking a completion event")


func _run() -> void:
	_dialogic = root.get_node("Dialogic")
	var global_inventory: InventorySystem = root.get_node("PlayerInventory")
	var global_progress: Node = root.get_node("GameProgress")
	var global_quests: Node = root.get_node("QuestSystem")
	var global_flow: Node = root.get_node("QuestFlow")
	var original_inventory := global_inventory.get_save_state()
	var original_progress: Dictionary = global_progress.get_save_state()
	var original_quests: Dictionary = global_quests.get_save_state()
	var original_flow: Dictionary = global_flow.get_save_state()
	_expect(global_quests.get_quest(MAIN) == null, "Production quest catalog contains no sandbox student commission")
	change_scene_to_file("res://tests/fixtures/quest_sandbox.tscn")
	await _settle()
	var sandbox: Control = current_scene
	var manager: Node = sandbox.manager
	var inventory: InventorySystem = sandbox.inventory
	var completions: Array[StringName] = []
	manager.quest_completed.connect(func(id: StringName): completions.append(id))
	_expect(manager.get_accepted_quests().is_empty() and inventory.get_items().is_empty(), "The F6 fixture starts with isolated empty progress and stock")
	_expect(not manager.accept_quest(&"sandbox_followup"), "A student's later commission respects its configured predecessor")
	inventory.add_item(&"Herb", 2)
	inventory.add_item(&"Water", 1)
	sandbox.accept_commission()
	_expect(manager.get_quest_state(MAIN).stage_id == &"briefing", "Early stock does not bypass the configured conversation")
	manager.report_event(&"talk", {"actor_id": &"someone_else", "topic_id": &"briefing"}, "wrong_actor")
	_expect(manager.get_quest_state(MAIN).stage_id == &"briefing", "A different character cannot complete the conversation objective")
	sandbox.talk_to_student()
	if not await _wait_for_text():
		quit(1)
		return
	_expect(manager.get_quest_state(MAIN).stage_id == &"briefing", "Starting the conversation does not complete it")
	await _finish_dialogue(sandbox)
	_expect(manager.get_quest_state(MAIN).stage_id == &"prepare", "Finishing the real configured conversation activates its next stage")
	inventory.remove_item(&"Herb", 2)
	inventory.add_item(&"Water", 1)
	_expect(manager.get_quest_state(MAIN).stage_id == &"prepare", "Parallel stock requirements must be met simultaneously, not at separate historical moments")
	inventory.add_item(&"Herb", 2)
	_expect(manager.get_quest_state(MAIN).stage_id == &"handover", "Reaching all configured requirements advances without a hardcoded stage name")
	var before_delivery := inventory.get_items()
	var result: Dictionary = sandbox.deliver_to_student(&"wrong_recipient")
	_expect(not result.ok and inventory.get_items() == before_delivery, "Wrong recipients cannot deduct inventory or advance objectives")
	manager.accept_quest(&"sandbox_other_delivery")
	result = sandbox.deliver_to_student()
	_expect(result.ok and inventory.get_amount(&"Herb") == 0 and inventory.get_amount(&"Water") == 0, "Delivery really consumes both configured item costs")
	_expect(manager.get_quest_state(MAIN).stage_id == &"report" and not manager.is_completed(&"sandbox_other_delivery"), "A delivery is scoped to its chosen task and objective")
	result = sandbox.deliver_to_student()
	_expect(not result.ok and inventory.get_items().is_empty(), "Repeated delivery does not deduct or count the same stock twice")
	_expect(manager.get_quest_state(MAIN).completed_stages.has(&"prepare"), "Already completed preparation remains complete after handing in stock")
	_expect(sandbox.save_checkpoint(SNAPSHOT).ok, "Sandbox progress saves to its own checkpoint file")
	inventory.add_item(&"Herb", 7)
	result = await sandbox.load_checkpoint(SNAPSHOT)
	_expect(result.ok and inventory.get_items().is_empty() and manager.get_quest_state(MAIN).stage_id == &"report", "Loading restores the independent inventory and quest stage rather than merging them")
	sandbox.play_ending()
	if not await _wait_for_text():
		quit(1)
		return
	var timeline_path: String = _dialogic.current_timeline.resource_path
	var saved_index: int = _dialogic.current_event_idx
	_expect(sandbox.save_checkpoint(STORY_SNAPSHOT).ok, "A real active story and its quest progress can be checkpointed together")
	_dialogic.paused = true
	_dialogic._cleanup_previous_event()
	_dialogic.Animations.stop_animation()
	await _dialogic.end_timeline(true)
	_dialogic.paused = false
	await _settle()
	_expect(not manager.is_completed(MAIN) and not sandbox.flow.is_story_completed(&"sandbox_ending"), "Canceling a real dialogue never counts as normal story completion")
	result = await sandbox.load_checkpoint(STORY_SNAPSHOT)
	_expect(result.ok and _dialogic.current_timeline != null and _dialogic.current_timeline.resource_path == timeline_path and _dialogic.current_event_idx == saved_index, "Restoration resumes the saved story position with its playback identity")
	_expect(not manager.is_completed(MAIN), "Loading a mid-story checkpoint cannot prematurely complete the quest")
	await _finish_dialogue(sandbox)
	_expect(manager.is_completed(MAIN) and completions.count(MAIN) == 1, "The configured story's real ending completes the student commission once")
	_expect(inventory.get_amount(&"Potion") == 1 and not manager.get_quest_state(&"sandbox_followup").is_empty(), "Persisted completion actions grant one reward and accept the configured followup")
	_expect(sandbox.save_checkpoint(DONE_SNAPSHOT).ok, "Completed task and action receipts save together")
	result = await sandbox.load_checkpoint(DONE_SNAPSHOT)
	await _settle()
	_expect(result.ok and inventory.get_amount(&"Potion") == 1 and completions.count(MAIN) == 1, "Reloading completed progress does not repeat rewards or completion events")
	result = sandbox.flow.start_story(&"sandbox_ending")
	_expect(result.get("already_completed", false) and _dialogic.current_timeline == null, "An already completed story cannot replay accidentally")
	_expect(global_inventory.get_save_state() == original_inventory and global_progress.get_save_state() == original_progress, "The isolated fixture never mutates the real inventory or GameProgress")
	_expect(global_quests.get_save_state() == original_quests and global_flow.get_save_state() == original_flow, "The fixture does not accept student content or record test story progress in the demo")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/quest_sandbox_preview.png")
	for path in [SNAPSHOT, STORY_SNAPSHOT, DONE_SNAPSHOT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("Isolated generic student commission: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

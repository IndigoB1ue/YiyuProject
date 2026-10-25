extends SceneTree

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 6:
		await process_frame

func _delivery_quest(id: StringName) -> QuestData:
	var quest := QuestData.new()
	quest.quest_id = id
	quest.display_name = str(id)
	var stage := QuestStageData.new()
	stage.stage_id = &"hand_in"
	stage.title = "交付测试素材"
	var objective := QuestObjectiveData.new()
	objective.objective_id = &"deliver_herb"
	objective.kind = &"delivery"
	objective.text = "向测试学生交付药草"
	objective.actor_id = &"test_student"
	objective.items = {&"Herb": 1}
	objective.include_history = true
	stage.objectives.append(objective)
	quest.stages.append(stage)
	return quest

func _run() -> void:
	var fixture_path := "res://.godot/quest_flow_fixture.dtl"
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string("用于通用任务流程测试。\n[signal arg=\"flow_test_finished\"]\n")
	file.close()
	var inventory := InventorySystem.new()
	root.add_child(inventory)
	var progress := GameProgressState.new()
	root.add_child(progress)
	var catalog := QuestCatalog.new()
	var first := _delivery_quest(&"test_delivery_a")
	var second := _delivery_quest(&"test_delivery_b")
	var reward := QuestActionData.new()
	reward.action_id = &"reward"
	reward.kind = &"grant_item"
	reward.target_id = &"Water"
	reward.amount = 1
	first.completion_actions.append(reward)
	var request := QuestActionData.new()
	request.action_id = &"after_delivery"
	request.kind = &"request_story"
	request.target_id = &"test_story"
	first.completion_actions.append(request)
	catalog.quests.append(first)
	catalog.quests.append(second)
	var blocked_reward_quest := _delivery_quest(&"test_blocked_reward")
	var blocked_reward := QuestActionData.new()
	blocked_reward.action_id = &"blocked_reward"
	blocked_reward.kind = &"grant_item"
	blocked_reward.target_id = &"Potion"
	blocked_reward.amount = 1
	blocked_reward_quest.completion_actions.append(blocked_reward)
	var other_story_action := QuestActionData.new()
	other_story_action.action_id = &"independent_story"
	other_story_action.kind = &"request_story"
	other_story_action.target_id = &"test_reward_story"
	blocked_reward_quest.completion_actions.append(other_story_action)
	var accept_next := QuestActionData.new()
	accept_next.action_id = &"accept_next"
	accept_next.kind = &"accept_quest"
	accept_next.target_id = &"test_followup"
	blocked_reward_quest.completion_actions.append(accept_next)
	catalog.quests.append(blocked_reward_quest)
	catalog.quests.append(_delivery_quest(&"test_followup"))
	var story := QuestStoryData.new()
	story.story_id = &"test_story"
	story.timeline_path = fixture_path
	story.completion_signal = &"flow_test_finished"
	story.actor_id = &"test_student"
	story.topic_id = &"delivery_thanks"
	catalog.stories.append(story)
	var second_story := QuestStoryData.new()
	second_story.story_id = &"test_reward_story"
	second_story.timeline_path = fixture_path
	second_story.completion_signal = &"flow_test_finished"
	catalog.stories.append(second_story)
	var manager := QuestManager.new()
	manager.catalog = catalog
	manager.set_dependencies(inventory, progress)
	root.add_child(manager)
	var flow := QuestFlowRunner.new()
	flow.set_dependencies(manager, inventory, progress)
	root.add_child(flow)
	var service := QuestDeliveryService.new(manager, inventory)
	manager.accept_quest(first.quest_id)
	manager.accept_quest(second.quest_id)
	var before := inventory.get_items()
	_expect(not service.deliver(first.quest_id, &"deliver_herb", &"someone_else").ok and inventory.get_items() == before, "Wrong recipient cannot consume items")
	manager.begin_restore()
	_expect(not service.deliver(first.quest_id, &"deliver_herb", &"test_student").ok and inventory.get_items() == before, "Restoration cannot consume or deliver items")
	manager.end_restore()
	var transaction_observations: Array[bool] = []
	inventory.inventory_changed.connect(func() -> void: transaction_observations.append(manager.is_transaction_active()))
	_expect(service.deliver(first.quest_id, &"deliver_herb", &"test_student").ok, "Configured delivery succeeds atomically")
	_expect(manager.is_completed(first.quest_id) and not manager.is_completed(second.quest_id), "One batch credits only the selected quest and objective")
	_expect(inventory.get_amount(&"Herb") == int(before.get(&"Herb", 0)) - 1, "Delivery consumes exactly the configured cost")
	_expect(not service.deliver(first.quest_id, &"deliver_herb", &"test_student").ok, "A completed objective cannot consume another batch")
	flow.execute_pending_actions()
	await _settle()
	var dialogic: Node = root.get_node("Dialogic")
	if dialogic.current_state == DialogicGameHandler.States.ANIMATING:
		await dialogic.Text.text_started
	_expect(inventory.get_amount(&"Water") == 1 and flow.is_story_playing(story.story_id), "Completion actions grant once and start the configured story")
	flow.execute_pending_actions()
	_expect(inventory.get_amount(&"Water") == 1, "Retrying actions cannot duplicate a granted reward")
	_expect(not transaction_observations.has(false), "Inventory-change callbacks observe a protected action or delivery transaction")
	dialogic.signal_event.emit("unrelated_signal")
	_expect(not flow.is_story_completed(story.story_id), "An unrelated signal cannot complete the active story")
	var flow_checkpoint := flow.get_save_state()
	var manager_checkpoint := manager.get_save_state()
	var dialogic_checkpoint: DialogicSaveState = dialogic.get_full_state()
	_expect(flow.validate_save_state(flow_checkpoint).ok, "Active story state is valid for a checkpoint")
	manager.begin_restore()
	flow.begin_restore()
	dialogic.paused = true
	await dialogic.end_timeline(true)
	manager.restore_save_state(manager_checkpoint, false)
	flow.restore_save_state(flow_checkpoint, false)
	dialogic.paused = false
	await dialogic.load_full_state(dialogic_checkpoint)
	manager.end_restore()
	flow.end_restore()
	_expect(flow.is_story_playing(story.story_id) and not flow.is_story_completed(story.story_id), "A saved run binds to its restored Dialogic checkpoint without replay")
	dialogic.signal_event.emit("flow_test_finished")
	await _settle()
	_expect(flow.is_story_completed(story.story_id) and dialogic.current_timeline == null, "Only the matching restored run's authored ending completes the story")
	flow.execute_pending_actions()
	_expect(inventory.get_amount(&"Water") == 1 and dialogic.current_timeline == null, "Completed story and reward remain idempotent")
	manager.accept_quest(blocked_reward_quest.quest_id)
	inventory.capacity = 1
	var starts: Array[StringName] = []
	flow.story_started.connect(func(id: StringName) -> void: starts.append(id))
	_expect(service.deliver(blocked_reward_quest.quest_id, &"deliver_herb", &"test_student").ok, "A second independent test delivery succeeds")
	flow.execute_pending_actions()
	await _settle()
	if dialogic.current_state == DialogicGameHandler.States.ANIMATING:
		await dialogic.Text.text_started
	_expect(inventory.get_amount(&"Potion") == 0 and flow.is_story_playing(second_story.story_id) and not manager.get_quest_state(&"test_followup").is_empty(), "A full backpack leaves its reward pending while independent story and acceptance effects succeed")
	flow.execute_pending_actions()
	_expect(starts.size() == 1 and inventory.get_amount(&"Potion") == 0, "A failed reward retry cannot restart another action's running story")
	dialogic.signal_event.emit("flow_test_finished")
	await _settle()
	inventory.capacity = 2
	flow.execute_pending_actions()
	flow.execute_pending_actions()
	_expect(inventory.get_amount(&"Potion") == 1 and starts.size() == 1 and dialogic.current_timeline == null, "Making room retries only the failed reward without duplicating the story or next quest")
	flow.queue_free()
	manager.queue_free()
	progress.queue_free()
	inventory.queue_free()
	await _settle()
	print("Generic quest flow / delivery: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)

func _goal(id: StringName, kind: StringName, target: StringName = &"", amount: int = 1) -> QuestObjectiveData:
	var goal := QuestObjectiveData.new()
	goal.objective_id = id
	goal.kind = kind
	goal.target_id = target
	goal.amount = amount
	return goal

func _quest(id: StringName, goals: Array[QuestObjectiveData], mode: StringName = &"all") -> QuestData:
	var quest := QuestData.new()
	quest.quest_id = id
	quest.display_name = str(id)
	var stage := QuestStageData.new()
	stage.stage_id = &"first"
	stage.match_mode = mode
	stage.objectives = goals
	quest.stages.append(stage)
	return quest

func _talk(id: StringName, history: bool = false) -> QuestObjectiveData:
	var goal := _goal(id, &"talk")
	goal.actor_id = &"test_actor"
	goal.topic_id = &"test_topic"
	goal.include_history = history
	return goal

func _run() -> void:
	var inventory := InventorySystem.new()
	root.add_child(inventory)
	inventory.restore_save_state({"capacity": 200, "items": {}})
	var progress := GameProgressState.new()
	root.add_child(progress)
	var catalog := QuestCatalog.new()
	var alternative := _quest(&"alternatives", [_goal(&"many_herbs", &"have_item", &"Herb", 10), _goal(&"two_waters", &"have_item", &"Water", 2)], &"any")
	catalog.quests.append(alternative)
	var historical := _quest(&"history", [_talk(&"talk", true)])
	var new_only := _quest(&"new_only", [_talk(&"talk")])
	catalog.quests.append(historical)
	catalog.quests.append(new_only)
	var sequential := _quest(&"two_conversations", [_talk(&"talk_once")])
	var next_stage := QuestStageData.new()
	next_stage.stage_id = &"second"
	next_stage.objectives.append(_talk(&"talk_again"))
	sequential.stages.append(next_stage)
	catalog.quests.append(sequential)
	var custom := _quest(&"custom_goal", [_goal(&"score", &"test_score", &"test_score", 2)])
	catalog.quests.append(custom)
	var later_talk := _talk(&"unmatched")
	later_talk.actor_id = &"another_actor"
	var later_quest := _quest(&"later_quest", [later_talk])
	catalog.quests.append(later_quest)
	var handover := _goal(&"handover", &"delivery")
	handover.actor_id = &"test_student"
	handover.items = {&"Herb": 1}
	handover.include_history = true
	var delivery_chain := _quest(&"delivery_chain", [handover])
	var second_handover := QuestStageData.new()
	second_handover.stage_id = &"second"
	second_handover.objectives.append(handover.duplicate(true))
	delivery_chain.stages.append(second_handover)
	catalog.quests.append(delivery_chain)
	var delivery_peer := _quest(&"delivery_peer", [handover.duplicate(true)])
	catalog.quests.append(delivery_peer)
	var manager := QuestManager.new()
	manager.catalog = catalog
	manager.set_dependencies(inventory, progress)
	manager.register_objective_handler(&"test_score", func(context: QuestManager, _quest_data: QuestData, goal: QuestObjectiveData, _event_count: int) -> Dictionary:
		var amount := context.get_fact(goal.target_id)
		return {"current": amount, "required": goal.amount, "completed": amount >= goal.amount, "has_count": true})
	root.add_child(manager)
	_expect(manager.validate_catalog().ok, "Registered objective adapters make an additional goal kind valid without changing the manager")
	manager.accept_quest(alternative.quest_id)
	inventory.add_item(&"Water", 2)
	_expect(manager.is_completed(alternative.quest_id) and inventory.get_amount(&"Herb") == 0, "ANY stage completes through one configured alternative")
	var alternative_rows := manager.get_objectives(alternative.quest_id)
	_expect(alternative_rows[0].get("skipped", false) and not alternative_rows[0].completed and alternative_rows[1].completed, "An ANY stage does not falsely mark unused alternatives as achieved")
	inventory.remove_item(&"Water", 2)
	_expect(manager.get_objectives(alternative.quest_id)[1].completed, "The achieved ANY alternative remains latched after its stock is consumed")
	var unmatched_event := {"actor_id": &"another_actor", "topic_id": &"test_topic"}
	manager.report_event(&"talk", unmatched_event, "unmatched_before_accept")
	manager.accept_quest(later_quest.quest_id)
	manager.report_event(&"talk", unmatched_event, "unmatched_before_accept")
	_expect(not manager.is_completed(later_quest.quest_id), "A previously unmatched event receipt cannot gain credit after acceptance")
	manager.report_event(&"talk", unmatched_event, "new_actor_conversation")
	_expect(manager.is_completed(later_quest.quest_id), "A fresh event credits the later accepted quest")
	var event := {"actor_id": &"test_actor", "topic_id": &"test_topic"}
	manager.report_event(&"talk", event, "before_accept")
	manager.accept_quest(historical.quest_id)
	manager.accept_quest(new_only.quest_id)
	_expect(manager.is_completed(historical.quest_id) and not manager.is_completed(new_only.quest_id), "Historical event inclusion is an explicit per-objective choice")
	manager.report_event(&"talk", event, "before_accept")
	_expect(not manager.is_completed(new_only.quest_id), "A repeated historic event receipt cannot be repurposed as a new action")
	manager.report_event(&"talk", event, "new_conversation")
	_expect(manager.is_completed(new_only.quest_id), "A new matching conversation completes the nonhistorical goal")
	manager.accept_quest(sequential.quest_id)
	manager.report_event(&"talk", event, "first_conversation")
	_expect(manager.get_quest_state(sequential.quest_id).stage_id == &"second" and not manager.is_completed(sequential.quest_id), "A single incoming event cannot complete a newly activated next stage")
	manager.report_event(&"talk", event, "first_conversation")
	_expect(not manager.is_completed(sequential.quest_id), "Replaying the same event never completes the second stage")
	manager.report_event(&"talk", event, "second_conversation")
	_expect(manager.is_completed(sequential.quest_id), "A distinct action completes the second matching stage")
	manager.accept_quest(custom.quest_id)
	manager.set_fact(&"test_score", 2)
	_expect(manager.is_completed(custom.quest_id), "A registered evaluator participates in normal progression")
	manager.accept_quest(delivery_chain.quest_id)
	manager.accept_quest(delivery_peer.quest_id)
	inventory.add_item(&"Herb", 3)
	var deliveries := QuestDeliveryService.new(manager, inventory)
	_expect(deliveries.deliver(delivery_chain.quest_id, &"handover", &"test_student").ok, "First scoped hand-in succeeds")
	_expect(manager.get_quest_state(delivery_chain.quest_id).stage_id == &"second" and not manager.is_completed(delivery_chain.quest_id) and not manager.is_completed(delivery_peer.quest_id), "Historical delivery credit cannot leak across quests or a later stage reusing an objective ID")
	_expect(deliveries.deliver(delivery_chain.quest_id, &"handover", &"test_student").ok and manager.is_completed(delivery_chain.quest_id), "A second real hand-in completes the next delivery stage")
	_expect(not manager.is_completed(delivery_peer.quest_id) and inventory.get_amount(&"Herb") == 1, "An independent delivery still requires its own remaining item batch")
	_expect(custom.stages[0].objectives[0].amount == 2 and custom.stages[0].stage_id == &"first", "Runtime progress never overwrites shared definition data")
	var snapshot := manager.get_save_state()
	_expect(manager.validate_save_state(snapshot).ok, "Event history, objective counters, and receipts produce a valid snapshot")
	manager.restore_save_state(snapshot)
	_expect(manager.get_objectives(alternative.quest_id)[0].get("skipped", false) and manager.get_objectives(alternative.quest_id)[1].completed, "Saved ANY achievement records preserve the selected alternative")
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged.accepted[&"two_conversations"].objective_counts[&"second"][&"talk_again"] = 99
	_expect(not manager.validate_save_state(damaged).ok and manager.get_save_state() == snapshot, "An invalid counter is rejected without mutating live quest progress")
	var bad: QuestCatalog = catalog.duplicate(true)
	bad.quests[0].stages[0].match_mode = &"unknown"
	_expect(not manager.validate_catalog(bad).ok, "Invalid stage combination rules cannot enter runtime")
	manager.queue_free()
	progress.queue_free()
	inventory.queue_free()
	await process_frame
	print("Generic quest adapters / history / stages: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

class_name GameProgressState
extends Node

signal recipes_changed
signal rovin_tutorial_changed
signal room_story_changed
signal guidance_changed(guidance_id: StringName)

var rovin_tutorial_completed: bool = false
var rovin_tutorial_skipped: bool = false
var cleanser_timeline_started: bool = false
var cleanser_timeline_completed: bool = false
var stairs_timeline_started: bool = false

var _unlocked_recipes: Dictionary = {}
var _claimed_interactions: Dictionary = {}
var _generic_guidance: Dictionary = {}

const SAVE_FLAGS := ["rovin_tutorial_completed", "rovin_tutorial_skipped", "cleanser_timeline_started", "cleanser_timeline_completed", "stairs_timeline_started"]

func get_save_state() -> Dictionary:
	var state := {"unlocked_recipes": _unlocked_recipes.duplicate(), "claimed_interactions": _claimed_interactions.duplicate(), "generic_guidance": _generic_guidance.duplicate()}
	for flag: String in SAVE_FLAGS:
		state[flag] = get(flag)
	return state

func validate_save_state(state: Dictionary) -> Dictionary:
	for flag: String in SAVE_FLAGS:
		if not state.get(flag) is bool:
			return {"ok": false, "error": "存档中的剧情标记无效：%s" % flag}
	for key: String in ["unlocked_recipes", "claimed_interactions"]:
		if not state.get(key) is Dictionary:
			return {"ok": false, "error": "存档中的剧情进度无效。"}
		for id in state[key]:
			if not (id is String or id is StringName) or str(id).is_empty() or state[key][id] != true:
				return {"ok": false, "error": "存档中的配方或收集记录无效。"}
	if not state.get("generic_guidance", {}) is Dictionary:
		return {"ok": false, "error": "存档中的教学提示记录无效。"}
	for id in state.get("generic_guidance", {}):
		if not (id is String or id is StringName) or str(id).is_empty() or state.generic_guidance[id] not in ["completed", "skipped"]:
			return {"ok": false, "error": "存档中的教学提示记录无效。"}
	return {"ok": true, "error": ""}

func restore_save_state(state: Dictionary, notify: bool = true) -> void:
	for flag: String in SAVE_FLAGS:
		set(flag, state[flag])
	_unlocked_recipes.clear()
	_claimed_interactions.clear()
	_generic_guidance.clear()
	for id in state.unlocked_recipes:
		_unlocked_recipes[StringName(id)] = true
	for id in state.claimed_interactions:
		_claimed_interactions[StringName(id)] = true
	for id in state.get("generic_guidance", {}):
		_generic_guidance[StringName(id)] = state.generic_guidance[id]
	if notify:
		notify_save_state_restored()

func notify_save_state_restored() -> void:
	recipes_changed.emit()
	rovin_tutorial_changed.emit()
	room_story_changed.emit()
	guidance_changed.emit(&"")

func reset_for_new_game() -> void:
	var initial := {"unlocked_recipes": {}, "claimed_interactions": {}}
	for flag: String in SAVE_FLAGS:
		initial[flag] = false
	restore_save_state(initial)

func is_recipe_unlocked(recipe_id: StringName) -> bool:
	return _unlocked_recipes.has(recipe_id)

func unlock_recipe(recipe_id: StringName) -> bool:
	if recipe_id == &"" or is_recipe_unlocked(recipe_id):
		return false
	_unlocked_recipes[recipe_id] = true
	recipes_changed.emit()
	return true

func is_interaction_claimed(interaction_id: StringName) -> bool:
	return _claimed_interactions.has(interaction_id)

func claim_interaction(interaction_id: StringName) -> bool:
	if is_interaction_claimed(interaction_id):
		return false
	_claimed_interactions[interaction_id] = true
	return true

## Failed rewards must remain available for another attempt.
func release_interaction(interaction_id: StringName) -> void:
	_claimed_interactions.erase(interaction_id)

func should_show_rovin_tutorial() -> bool:
	return not rovin_tutorial_completed and not rovin_tutorial_skipped

func complete_rovin_tutorial() -> void:
	if not should_show_rovin_tutorial():
		return
	rovin_tutorial_completed = true
	rovin_tutorial_changed.emit()
	guidance_changed.emit(&"rovin_tutorial")

func skip_rovin_tutorial() -> void:
	if not should_show_rovin_tutorial():
		return
	rovin_tutorial_skipped = true
	rovin_tutorial_changed.emit()
	guidance_changed.emit(&"rovin_tutorial")

func should_show_guidance(guidance_id: StringName) -> bool:
	if guidance_id == &"":
		return false
	if guidance_id == &"rovin_tutorial":
		return should_show_rovin_tutorial()
	return not _generic_guidance.has(guidance_id)

func skip_guidance(guidance_id: StringName) -> void:
	if not should_show_guidance(guidance_id):
		return
	if guidance_id == &"rovin_tutorial":
		skip_rovin_tutorial()
		return
	_generic_guidance[guidance_id] = "skipped"
	guidance_changed.emit(guidance_id)

func complete_guidance(guidance_id: StringName) -> void:
	if not should_show_guidance(guidance_id):
		return
	if guidance_id == &"rovin_tutorial":
		complete_rovin_tutorial()
		return
	_generic_guidance[guidance_id] = "completed"
	guidance_changed.emit(guidance_id)

func complete_cleanser_timeline() -> void:
	if cleanser_timeline_completed:
		return
	cleanser_timeline_completed = true
	room_story_changed.emit()

func mark_stairs_timeline_started() -> void:
	if stairs_timeline_started:
		return
	stairs_timeline_started = true
	room_story_changed.emit()

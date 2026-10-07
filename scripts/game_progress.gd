class_name GameProgressState
extends Node

signal recipes_changed

var _unlocked_recipes: Dictionary = {}
var _claimed_interactions: Dictionary = {}

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

extends Node

## Each modal owns a lease. Only the last close restores the original state.
var _owners: Dictionary = {}
var _tree_was_paused := false
var _dialogue_was_paused := false
var _timeline: Resource

@onready var _dialogic: Node = get_node("/root/Dialogic")

func acquire(owner: Node) -> void:
	var id := owner.get_instance_id()
	if _owners.has(id):
		return
	if _owners.is_empty():
		_tree_was_paused = get_tree().paused
		_dialogue_was_paused = _dialogic.paused
		_timeline = _dialogic.current_timeline
	_owners[id] = weakref(owner)
	if _dialogic.current_timeline != null:
		_dialogic.paused = true
		_dialogic.Inputs.block_input(0.15)
	get_tree().paused = true

func release(owner: Node) -> void:
	if not _owners.has(owner.get_instance_id()):
		return
	_owners.erase(owner.get_instance_id())
	if not _owners.is_empty():
		return
	get_tree().paused = _tree_was_paused
	if _dialogic.current_timeline == _timeline or _dialogic.current_timeline == null:
		_dialogic.paused = _dialogue_was_paused
		if not _dialogic.paused and _dialogic.Inputs.auto_skip.enabled:
			_dialogic.Inputs.set_process(true)
	if _dialogic.current_timeline != null:
		_dialogic.Inputs.block_input(0.15)
	_timeline = null

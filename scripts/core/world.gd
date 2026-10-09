extends Node2D

const ROVINROOMSCENE = "res://scenes/RovinRoom.tscn"

func _ready() -> void:
	Dialogic.signal_event.connect(_on_dialogic_signal)
	# 开始故事
	Dialogic.start("CP01_EP01_SI01")
	

func _on_dialogic_signal(argument:String):
	if argument == "OpenRovinRoom":
		Dialogic.end_timeline(true)
		get_tree().change_scene_to_file(ROVINROOMSCENE)

extends Node2D

const ROVINROOMSCENE = "res://scenes/RovinRoom.tscn"

func _ready() -> void:
	Dialogic.timeline_ended.connect(_on_timeline_ended, CONNECT_ONE_SHOT)
	Dialogic.signal_event.connect(_on_dialogic_signal)
	Dialogic.signal_event.connect(_dialogic_event)
	Dialogic.start("CP01_EP01_SI01")
	



func _dialogic_event(name: String) -> void:
	print(name)


func _on_timeline_ended() -> void:
	get_tree().quit()


func _on_dialogic_signal(argument:String):
	if argument == "Open Rovin's Room":
		get_tree().change_scene_to_file(ROVINROOMSCENE)

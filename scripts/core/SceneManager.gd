extends Node

const ROVINROOMSCENE = "res://scenes/RovinRoom.tscn"

func change_scene(scene_path: String) -> void:
	Dialogic.end_timeline(true)
	
	if scene_path == "RovinRoom":
		get_tree().change_scene_to_file(ROVINROOMSCENE)

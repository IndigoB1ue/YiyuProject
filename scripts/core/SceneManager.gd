extends Node

const ROVINROOMSCENE = "res://scenes/RovinRoom.tscn"
const ACADEMY_MAP_SCENE = "res://scenes/AcademyMap.tscn"

func open_map() -> bool:
	if Dialogic.current_timeline != null or get_tree().paused:
		return false
	return get_tree().change_scene_to_file(ACADEMY_MAP_SCENE) == OK

func change_scene(scene_path: String) -> void:
	Dialogic.end_timeline(true)
	
	if scene_path == "RovinRoom":
		get_tree().change_scene_to_file(ROVINROOMSCENE)

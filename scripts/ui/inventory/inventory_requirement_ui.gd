extends VBoxContainer


func display(icon: Texture2D, label: String) -> void:
	$Icon.texture = icon if icon != null else preload("res://asserts/image/icon/question_mark.svg")
	$Label.text = label

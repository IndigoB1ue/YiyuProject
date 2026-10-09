extends VBoxContainer


func display(icon: Texture2D, label: String) -> void:
	$Icon.texture = icon if icon != null else preload("res://data/items/question_mark.svg")
	$Label.text = label

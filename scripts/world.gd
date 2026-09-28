extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Dialogic.start("talk_2")
	Dialogic.signal_event.connect(_dialogic_event)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _dialogic_event(name:String):
	print(name)

extends SceneTree

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)

func _settle() -> void:
	for frame in 8:
		await process_frame

func _run() -> void:
	var dialogic: Node = root.get_node("Dialogic")
	var flow: Node = root.get_node("DemoFlow")
	change_scene_to_file("res://scenes/AcademyMap.tscn")
	await _settle()
	var timeline := DialogicTimeline.new()
	timeline.from_text("do DemoFlow.show_message(\"本次Demo游玩结束，感谢您的游玩！\")\n[wait time=\"60.0\" hide_text=\"false\"]")
	dialogic.start(timeline)
	await _settle()
	_expect(flow._message.visible and flow._message.dialog_text.contains("游玩结束"), "The existing demo ending opens through the content-flow autoload")
	flow._message.get_ok_button().pressed.emit()
	await _settle()
	_expect(current_scene.scene_file_path == "res://scenes/main_menu.tscn" and dialogic.current_timeline == null, "Confirming the demo ending cleans up dialogue and returns to the menu")
	_expect(not paused and not dialogic.paused, "The ending leaves no modal pause behind")
	print("Demo ending flow: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

extends SceneTree

var _failures := 0
var _settings: Node
var _dialogic: Node


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _settle() -> void:
	for frame in 8:
		await process_frame


func _click(position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await _settle()


func _start(timeline: DialogicTimeline) -> void:
	_dialogic.start(timeline)
	# The textbox entrance animation must finish before forcibly ending a test timeline.
	await _dialogic.Text.text_started
	await _settle()


func _run() -> void:
	_settings = root.get_node("GameSettings")
	_dialogic = root.get_node("Dialogic")
	if OS.get_cmdline_user_args().has("--verify-persisted"):
		_expect(_settings.get_value("text", "speed") == 6 and _settings.get_value("audio", "music") == 2,
			"A new process loads the previously saved preferences")
		_expect(is_equal_approx(float(_dialogic.Settings.text_speed), 10.0 / 6.0), "Loaded text settings are applied at startup")
		_expect(Engine.max_fps == 120, "Loaded graphics settings are applied at startup")
		var read_probe := DialogicTimeline.new()
		read_probe.take_over_path("res://.godot/settings_read_policy_test.dtl")
		_expect(_dialogic.History.has_event_been_visited(0, read_probe), "Previously read text history loads in a new process")
		_finish()
		return
	for section: String in _settings.DEFAULTS:
		_settings.reset_section(section)
	_dialogic.History.reset_visited_history()
	_expect(_settings.set_value("text", "speed", 4) == OK, "Text preference saves successfully")
	_expect(is_equal_approx(_dialogic.Settings.text_speed, 2.5), "Reading speed applies a real Dialogic delay multiplier")
	_settings.set_value("text", "auto_delay", 3)
	_expect(is_equal_approx(_dialogic.Inputs.auto_advance._calculate_autoadvance_delay("很多文字"), 3.0), "Automatic playback interval is fixed seconds after reveal")
	_settings.set_value("text", "skip_unread", true)
	_expect(not _dialogic.Inputs.auto_skip.disable_on_unread_text, "Skip-all policy allows unread lines")
	_settings.set_value("text", "skip_unread", false)
	_expect(_dialogic.Inputs.auto_skip.disable_on_unread_text, "Read-only policy protects unread lines")
	_settings.set_value("graphics", "max_fps", 120)
	_expect(Engine.max_fps == 120, "Frame limit affects the engine")
	_settings.set_value("audio", "master", 0)
	_expect(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Zero master volume mutes the entire mix")
	_settings.set_value("audio", "music", 2)
	_expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.2), "Music volume affects only the Music bus")
	_settings.set_value("audio", "master", 10)
	_expect(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Raising volume clears mute")
	_settings.reload_settings()
	_expect(_settings.get_value("text", "speed") == 4 and _settings.get_value("audio", "music") == 2, "Preferences survive a disk reload")
	_settings.reset_section("audio")
	_expect(_settings.get_value("text", "speed") == 4 and _settings.is_default_section("audio"), "Restoring one page leaves the other pages intact")
	_settings.set_value("text", "speed", 1000)
	_expect(_settings.get_value("text", "speed") == 10, "Invalid numeric settings are clamped")
	_settings.set_value("graphics", "max_fps", -20)
	_expect(_settings.get_value("graphics", "max_fps") == 60, "Invalid frame limits fall back safely")
	_settings.set_value("text", "language", "unsupported")
	_expect(_settings.get_value("text", "language") == "zh_CN", "Language list cannot activate an unavailable translation")
	change_scene_to_file("res://scenes/RovinRoom.tscn")
	await _settle()
	var sound := AudioStreamWAV.new()
	sound.mix_rate = 8000
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	var silence := PackedByteArray()
	silence.resize(16000)
	sound.data = silence
	var sound_path := "res://.godot/settings_silent_test.tres"
	ResourceSaver.save(sound, sound_path)
	_dialogic.Audio.update_audio("music", sound_path)
	_dialogic.Audio.update_audio("", sound_path, {"loop": false})
	await _settle()
	_expect(_dialogic.Audio.current_audio_channels.music.bus == &"Music", "Dialogic background music routes to Music")
	_expect(_dialogic.Audio.one_shot_audio_node.get_child(0).bus == &"SFX", "Dialogic one-shot sounds route to SFX")
	_dialogic.Voice.set_file(sound_path)
	_dialogic.Voice.set_bus("Master")
	_dialogic.Voice.play_voice()
	_expect(_dialogic.Voice.voice_player.bus == &"Voice", "Voice events route to the independent voice bus")
	_dialogic.Voice.stop_audio()
	var timeline := DialogicTimeline.new()
	timeline.from_text("这是一行文字。\n第二行文字。\n第三行文字。")
	await _start(timeline)
	_dialogic.Text.skip_text_reveal()
	await _settle()
	_settings.set_value("text", "speed", 2)
	_expect(is_equal_approx(get_nodes_in_group("dialogic_dialog_text")[0].active_speed, 0.05),
		"Changing reading speed updates the actual active text node without a one-step delay")
	_settings.set_value("text", "speed", 10)
	_settings.set_value("text", "auto_delay", 1)
	var auto_button: Button = _dialogic.Styles.get_layout_node().find_child("AutoButton", true, false)
	_expect(auto_button != null, "Dialogue layout provides an automatic playback button")
	auto_button.pressed.emit()
	_expect(_dialogic.Inputs.auto_advance.enabled_until_user_input and auto_button.button_pressed, "Automatic playback button enables the configured interval")
	await create_timer(1.2).timeout
	_expect(_dialogic.current_event_idx >= 1, "Automatic playback advances an actual timeline")
	_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	_settings.set_value("text", "skip_unread", false)
	var fast_button: Button = _dialogic.Styles.get_layout_node().find_child("FastForwardButton", true, false)
	fast_button.pressed.emit()
	_expect(_dialogic.Inputs.auto_skip.disable_on_unread_text, "Existing fast-forward button does not override read-only preference")
	_dialogic.Inputs.auto_skip.enabled = false
	await _dialogic.end_timeline(true)
	await _settle()
	var read_timeline := DialogicTimeline.new()
	read_timeline.from_text("未读第一行。\n未读第二行。")
	read_timeline.take_over_path("res://.godot/settings_read_policy_test.dtl")
	await _start(read_timeline)
	_settings.set_value("text", "skip_unread", false)
	_settings.toggle_fast_forward()
	_expect(not _dialogic.Inputs.auto_skip.enabled, "Read-only mode does not skip the first viewing of a line")
	await _dialogic.end_timeline(true)
	await _settle()
	await _start(read_timeline)
	_settings.toggle_fast_forward()
	_expect(_dialogic.Inputs.auto_skip.enabled, "Read-only mode can fast-forward a previously viewed line")
	await create_timer(0.4).timeout
	_expect(_dialogic.current_event_idx == 1 and not _dialogic.Inputs.auto_skip.enabled, "Read-only fast-forward stops at the next unread line")
	await _dialogic.end_timeline(true)
	await _settle()
	var skip_timeline := DialogicTimeline.new()
	skip_timeline.from_text("未读也允许快进。\n继续快进。\n最后一行。")
	skip_timeline.take_over_path("res://.godot/settings_skip_all_test.dtl")
	await _start(skip_timeline)
	_settings.set_value("text", "skip_unread", true)
	_settings.toggle_fast_forward()
	await create_timer(0.45).timeout
	_expect(_dialogic.current_timeline != skip_timeline or _dialogic.current_event_idx > 0, "Skip-all mode advances previously unread dialogue")
	_dialogic.Inputs.auto_skip.enabled = false
	if _dialogic.current_timeline != null:
		await _dialogic.end_timeline(true)
	await _settle()
	_settings.set_value("text", "skip_unread", false)
	var choice_timeline := DialogicTimeline.new()
	choice_timeline.from_text("重要选择。\n- 接受 | [important=\"true\"]\n\t接受了。\n- 拒绝\n\t拒绝了。")
	await _start(choice_timeline)
	_dialogic.Text.skip_text_reveal()
	await _settle()
	var hint: PanelContainer = _settings.get_node("ImportantChoiceHint/Panel")
	_expect(hint.visible, "Marked important choices display a nonblocking hint")
	_settings.set_value("text", "important_hints", false)
	_expect(not hint.visible, "Turning off important-choice hints takes effect immediately")
	_settings.set_value("text", "important_hints", true)
	_expect(hint.visible, "Turning hints back on restores the active question hint")
	await create_timer(0.25).timeout
	await _click(_dialogic.Choices.get_choice_button(1).get_global_rect().get_center())
	await _settle()
	_expect(not hint.visible, "Making a choice hides its hint")
	await _dialogic.end_timeline(true)
	await _settle()
	_settings.set_value("text", "speed", 6)
	_settings.set_value("audio", "music", 2)
	_settings.set_value("graphics", "max_fps", 120)
	_finish()


func _finish() -> void:
	print("Settings behavior and persistence: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(0 if _failures == 0 else 1)

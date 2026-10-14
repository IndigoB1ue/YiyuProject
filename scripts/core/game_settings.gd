extends Node

signal settings_changed(section: String)

const DEFAULTS := {
	"text": {"speed": 10, "auto_delay": 7, "skip_unread": false, "important_hints": true, "language": "zh_CN"},
	"graphics": {"fullscreen": false, "resolution": Vector2i(1280, 720), "max_fps": 60},
	"audio": {"master": 10, "music": 3, "sfx": 6, "voice": 8},
}
const RESOLUTIONS := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const FRAME_LIMITS := [30, 60, 120, 144, 240, 0]
const AUDIO_BUSES := {"master": "Master", "music": "Music", "sfx": "SFX", "voice": "Voice"}

var storage_path := "user://settings.cfg"
var last_save_error: Error = OK
var _values: Dictionary = DEFAULTS.duplicate(true)
var _dialogic: Node


func _ready() -> void:
	_dialogic = get_node("/root/Dialogic")
	_dialogic.History.load_visited_history()
	reload_settings()
	_dialogic.timeline_started.connect(apply_text_settings)
	_dialogic.timeline_ended.connect(_dialogic.History.save_visited_history)
	_dialogic.Audio.audio_started.connect(_on_audio_started)
	_dialogic.Voice.voiceline_started.connect(_on_voice_started)
	apply_all()
	apply_text_settings.call_deferred()
	var hint := preload("res://scenes/ui/settings/important_choice_hint.tscn").instantiate()
	add_child(hint)


func _exit_tree() -> void:
	if is_instance_valid(_dialogic):
		_dialogic.History.save_visited_history()


func get_value(section: String, key: String) -> Variant:
	return _values.get(section, {}).get(key)


func is_default_section(section: String) -> bool:
	return _values.get(section, {}) == DEFAULTS.get(section, {})


func get_languages() -> PackedStringArray:
	var locales := PackedStringArray(["zh_CN"])
	for locale in TranslationServer.get_loaded_locales():
		if not locales.has(locale):
			locales.append(locale)
	return locales


func get_windowed_resolutions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var available := Vector2i(3840, 2160)
	if DisplayServer.get_name() != "headless":
		available = DisplayServer.screen_get_usable_rect().size
	for size: Vector2i in RESOLUTIONS:
		if size.x <= available.x and size.y <= available.y:
			result.append(size)
	if result.is_empty():
		result.append(available)
	return result


func set_value(section: String, key: String, value: Variant) -> Error:
	if not DEFAULTS.has(section) or not DEFAULTS[section].has(key):
		return ERR_INVALID_PARAMETER
	_values[section][key] = _validated_value(section, key, value)
	_apply_section(section)
	last_save_error = save_settings()
	settings_changed.emit(section)
	return last_save_error


func reset_section(section: String) -> Error:
	if not DEFAULTS.has(section):
		return ERR_INVALID_PARAMETER
	_values[section] = DEFAULTS[section].duplicate(true)
	if section == "graphics":
		_values[section]["resolution"] = _validated_value(section, "resolution", _values[section]["resolution"])
	_apply_section(section)
	last_save_error = save_settings()
	settings_changed.emit(section)
	return last_save_error


func reload_settings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(storage_path)
	_values = DEFAULTS.duplicate(true)
	for section: String in DEFAULTS:
		for key: String in DEFAULTS[section]:
			var value: Variant = config.get_value(section, key, DEFAULTS[section][key]) if error == OK else DEFAULTS[section][key]
			_values[section][key] = _validated_value(section, key, value)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_warning("设置文件无法读取，已使用默认值。")
	return error


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	for section: String in _values:
		for key: String in _values[section]:
			config.set_value(section, key, _values[section][key])
	return config.save(storage_path)


func _validated_value(section: String, key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[section][key]
	if key == "language":
		return value if value is String and get_languages().has(value) else fallback
	if key == "resolution":
		var resolutions := get_windowed_resolutions()
		return value if value is Vector2i and resolutions.has(value) else (fallback if resolutions.has(fallback) else resolutions[0])
	if key == "max_fps":
		return value if value is int and FRAME_LIMITS.has(value) else fallback
	if fallback is bool:
		return value if value is bool else fallback
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return clampi(roundi(float(value)), 0 if section == "audio" else 1, 10)


func apply_all() -> void:
	for section: String in DEFAULTS:
		_apply_section(section)


func _apply_section(section: String) -> void:
	match section:
		"text": apply_text_settings()
		"graphics": _apply_graphics()
		"audio": _apply_audio()


func apply_text_settings() -> void:
	TranslationServer.set_locale(_values.text.language)
	if not is_instance_valid(_dialogic) or _dialogic.Inputs.auto_advance == null:
		return
	# Dialogic's user speed multiplies the delay between characters.
	_dialogic.Settings.text_speed = 10.0 / float(_values.text.speed)
	# Settings' callback fires before its stored value changes in Alpha 20.
	_dialogic.Text.update_text_speed()
	var advance = _dialogic.Inputs.auto_advance
	var delay_changed: bool = advance.fixed_delay != float(_values.text.auto_delay)
	advance.fixed_delay = float(_values.text.auto_delay)
	advance.per_word_delay = 0.0
	advance.per_character_delay = 0.0
	advance.await_playing_voice = true
	# A timer already waiting on the current line must use the new interval too.
	if delay_changed and advance.is_advancing():
		advance.start()
	_dialogic.Inputs.auto_skip.disable_on_unread_text = not _values.text.skip_unread
	if not _values.text.skip_unread and _dialogic.Inputs.auto_skip.enabled and not _dialogic.History.has_last_event_been_visited():
		_dialogic.Inputs.auto_skip.enabled = false
	_dialogic.Inputs.auto_skip.time_per_event = 0.1


func toggle_fast_forward() -> void:
	apply_text_settings()
	var skip = _dialogic.Inputs.auto_skip
	var enable: bool = not skip.enabled
	if enable and not _values.text.skip_unread and not _dialogic.History.has_last_event_been_visited():
		return
	if enable:
		_dialogic.Inputs.auto_advance.enabled_until_user_input = false
	skip.enabled = enable


func toggle_auto_advance() -> void:
	apply_text_settings()
	_dialogic.Inputs.auto_skip.enabled = false
	var advance = _dialogic.Inputs.auto_advance
	advance.enabled_until_user_input = not advance.enabled_until_user_input


func _apply_graphics() -> void:
	Engine.max_fps = int(_values.graphics.max_fps)
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.content_scale_size = Vector2i(1280, 720)
	var target_mode := Window.MODE_FULLSCREEN if _values.graphics.fullscreen else Window.MODE_WINDOWED
	if window.mode != target_mode:
		window.mode = target_mode
	# Fullscreen follows the desktop mode; resolution changes affect windowed mode.
	if not _values.graphics.fullscreen and window.size != _values.graphics.resolution:
		window.size = _values.graphics.resolution


func _apply_audio() -> void:
	for key: String in AUDIO_BUSES:
		var bus_name: String = AUDIO_BUSES[key]
		var index := AudioServer.get_bus_index(bus_name)
		if index == -1:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var volume := float(_values.audio[key]) / 10.0
		AudioServer.set_bus_volume_db(index, linear_to_db(volume) if volume > 0 else -80.0)
		AudioServer.set_bus_mute(index, volume == 0)
	_route_dialogic_audio()
	_on_voice_started({})


func _on_audio_started(_info: Dictionary) -> void:
	# Dialogic emits audio_started before creating its player.
	_route_dialogic_audio.call_deferred()


func _route_dialogic_audio() -> void:
	if not is_instance_valid(_dialogic):
		return
	for channel: String in _dialogic.Audio.current_audio_channels:
		var player = _dialogic.Audio.current_audio_channels[channel]
		if is_instance_valid(player) and player.bus in [&"Master", &""]:
			player.bus = &"Music" if channel.to_lower() in ["music", "bgm", "background_music"] else &"SFX"
	for player: AudioStreamPlayer in _dialogic.Audio.one_shot_audio_node.get_children():
		if player.bus in [&"Master", &""]:
			player.bus = &"SFX"


func _on_voice_started(_info: Dictionary) -> void:
	if is_instance_valid(_dialogic) and _dialogic.Voice.voice_player.bus in [&"Master", &""]:
		_dialogic.Voice.voice_player.bus = &"Voice"

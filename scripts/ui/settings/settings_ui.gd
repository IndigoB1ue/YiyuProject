class_name SettingsPanel
extends Control

signal closed

const SECTIONS := ["text", "graphics", "audio"]
const TITLES := ["文字设置", "图形设置", "声音设置"]

var _section_index := 0
var _resolutions: Array[Vector2i] = []
var _languages: PackedStringArray
var _preview_elapsed := 0.0
@onready var _settings: Node = get_node("/root/GameSettings")
@onready var _pages: Array[Control] = [%TextPage, %GraphicsPage, %AudioPage]
@onready var _tabs: Array[Button] = [%TextTab, %GraphicsTab, %AudioTab]
@onready var _heading: Label = %PageHeading
@onready var _status: Label = %Status
@onready var _text_speed: Node = %TextSpeed
@onready var _auto_delay: Node = %AutoDelay
@onready var _language: OptionButton = %Language
@onready var _resolution: OptionButton = %Resolution
@onready var _fps: OptionButton = %FrameLimit
@onready var _preview: Label = %TextPreview


func _ready() -> void:
	hide()
	_text_speed.value_changed.connect(_on_value_changed.bind("text", "speed"))
	_auto_delay.value_changed.connect(_on_value_changed.bind("text", "auto_delay"))
	%MasterVolume.value_changed.connect(_on_value_changed.bind("audio", "master"))
	%MusicVolume.value_changed.connect(_on_value_changed.bind("audio", "music"))
	%SfxVolume.value_changed.connect(_on_value_changed.bind("audio", "sfx"))
	%VoiceVolume.value_changed.connect(_on_value_changed.bind("audio", "voice"))
	_settings.settings_changed.connect(_on_settings_changed)
	for limit in _settings.FRAME_LIMITS:
		_fps.add_item("不限帧率" if limit == 0 else "%d fps" % limit, limit)
	_languages = _settings.get_languages()
	for locale in _languages:
		_language.add_item("简体中文" if locale == "zh_CN" else TranslationServer.get_locale_name(locale))
	_language.disabled = _languages.size() == 1
	_language.tooltip_text = "当前可用语言：简体中文" if _language.disabled else "选择游戏语言"
	_refresh()


func open_settings() -> void:
	_section_index = 0
	_status.text = "设置即时生效并自动保存。"
	_refresh()
	show()
	_restart_preview()
	_tabs[0].grab_focus()


func close_settings() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible:
		if event.is_action_pressed("ui_cancel"):
			close_settings()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or _section_index != 0 or _preview.visible_characters < 0:
		return
	_preview_elapsed += delta
	var interval := 0.1 / float(_settings.get_value("text", "speed"))
	if _preview_elapsed >= interval:
		var count := int(_preview_elapsed / interval)
		_preview_elapsed -= count * interval
		_preview.visible_characters = mini(_preview.text.length(), _preview.visible_characters + count)


func _restart_preview() -> void:
	_preview_elapsed = 0.0
	_preview.visible_characters = 0


func _on_tab_pressed(index: int) -> void:
	_section_index = index
	_refresh()
	if index == 0:
		_restart_preview()


func _refresh() -> void:
	for index in _pages.size():
		_pages[index].visible = index == _section_index
		_tabs[index].set_pressed_no_signal(index == _section_index)
	var section: String = SECTIONS[_section_index]
	_heading.text = TITLES[_section_index] + ("（默认）" if _settings.is_default_section(section) else "（自定义）")
	_text_speed.set_value(_settings.get_value("text", "speed"))
	_auto_delay.set_value(_settings.get_value("text", "auto_delay"))
	%SkipAll.set_pressed_no_signal(_settings.get_value("text", "skip_unread"))
	%SkipRead.set_pressed_no_signal(not _settings.get_value("text", "skip_unread"))
	%HintsOn.set_pressed_no_signal(_settings.get_value("text", "important_hints"))
	%HintsOff.set_pressed_no_signal(not _settings.get_value("text", "important_hints"))
	_language.select(_languages.find(_settings.get_value("text", "language")))
	var fullscreen: bool = _settings.get_value("graphics", "fullscreen")
	%Fullscreen.set_pressed_no_signal(fullscreen)
	%Windowed.set_pressed_no_signal(not fullscreen)
	_resolutions = _settings.get_windowed_resolutions()
	var selected: Vector2i = _settings.get_value("graphics", "resolution")
	if fullscreen and DisplayServer.get_name() != "headless":
		selected = DisplayServer.screen_get_size()
		if not _resolutions.has(selected):
			_resolutions.append(selected)
	_resolution.clear()
	for size in _resolutions:
		_resolution.add_item("%d × %d" % [size.x, size.y])
	_resolution.select(_resolutions.find(selected))
	_resolution.disabled = fullscreen
	_fps.select(_fps.get_item_index(_settings.get_value("graphics", "max_fps")))
	%MasterVolume.set_value(_settings.get_value("audio", "master"))
	%MusicVolume.set_value(_settings.get_value("audio", "music"))
	%SfxVolume.set_value(_settings.get_value("audio", "sfx"))
	%VoiceVolume.set_value(_settings.get_value("audio", "voice"))


func _on_settings_changed(_section: String) -> void:
	_refresh()
	_status.text = "设置已保存。" if _settings.last_save_error == OK else "设置已生效，但保存失败，请检查用户目录权限。"


func _on_value_changed(value: float, section: String, key: String) -> void:
	_settings.set_value(section, key, value)
	if section == "text" and key == "speed":
		_restart_preview()


func _on_option_pressed(section: String, key: String, value: bool) -> void:
	_settings.set_value(section, key, value)


func _on_language_selected(index: int) -> void:
	_settings.set_value("text", "language", _languages[index])


func _on_resolution_selected(index: int) -> void:
	_settings.set_value("graphics", "resolution", _resolutions[index])


func _on_fps_selected(index: int) -> void:
	_settings.set_value("graphics", "max_fps", _fps.get_item_id(index))


func _on_restore_pressed() -> void:
	_settings.reset_section(SECTIONS[_section_index])
	_restart_preview()

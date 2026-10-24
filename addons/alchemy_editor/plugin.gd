@tool
extends EditorPlugin

const PANEL = preload("res://addons/alchemy_editor/main_panel.tscn")
var _panel: Control
var _smoke_runner: RefCounted

func _enter_tree() -> void:
	_panel = PANEL.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_panel.resources_saved.connect(func(): EditorInterface.get_resource_filesystem().scan())
	_make_visible(false)
	if OS.get_cmdline_user_args().has("--alchemy-editor-smoke"):
		_smoke_runner = load("res://tests/alchemy_editor_plugin_smoke.gd").new()
		_smoke_runner.call_deferred("run", self)

func _exit_tree() -> void:
	if is_instance_valid(_panel):
		_panel.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if is_instance_valid(_panel):
		_panel.visible = visible

func _get_plugin_name() -> String:
	return "炼金配置"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")

func _get_unsaved_status(_for_scene: String) -> String:
	return "炼金配置中还有未保存的更改。" if is_instance_valid(_panel) and _panel.has_unsaved_changes() else ""

func _save_external_data() -> void:
	if is_instance_valid(_panel) and _panel.has_unsaved_changes():
		_panel._save_current()

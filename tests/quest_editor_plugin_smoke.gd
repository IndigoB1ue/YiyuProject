@tool
extends RefCounted

## Runs through the real EditorPlugin lifecycle; it never saves project data.
func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	for frame in 15: await tree.process_frame
	EditorInterface.set_main_screen_editor("任务配置")
	for frame in 6: await tree.process_frame
	var panel = plugin._panel
	var ok: bool = panel.is_visible_in_tree() and panel._store != null and panel._list.item_count == panel._store.entries(0).size()
	ok = ok and panel._form.get_field("quest_id") is LineEdit and not panel.has_unsaved_changes()
	panel._check_all()
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://.godot/quest_editor_plugin.png")
	print("Quest editor plugin smoke: ", "PASS" if ok else "FAIL")
	tree.quit(0 if ok else 1)

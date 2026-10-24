@tool
extends RefCounted

## Runs only inside a real editor with -- --alchemy-editor-smoke; does not save content.
func run(plugin: EditorPlugin) -> void:
	var tree := plugin.get_tree()
	for frame in 15:
		await tree.process_frame
	EditorInterface.set_main_screen_editor("炼金配置")
	for frame in 5:
		await tree.process_frame
	var panel = plugin._panel
	var ok: bool = panel.is_visible_in_tree() and panel._store != null and panel._list.item_count == panel._store.recipes.recipes.size()
	var expected := panel._store.recipes.find_recipe(&"ExperimentThree") as AlchemyRecipe
	panel._open(expected, false)
	await tree.process_frame
	ok = ok and panel._preview.get_public_preview().slots.size() == 4 and not panel.has_unsaved_changes()
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var output := "res://.godot/alchemy_editor_plugin.png"
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output)
	print("Alchemy editor plugin smoke: ", "PASS" if ok else "FAIL")
	tree.quit(0 if ok else 1)

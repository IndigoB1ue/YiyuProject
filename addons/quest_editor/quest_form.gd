@tool
extends VBoxContainer

signal changed

var _store
var _draft: Resource
var _is_new := false
var _page := 0
var _stage_index := 0
var _objective_index := 0
var _fields: Dictionary = {}
var _locked_ids: Dictionary = {}

const LABELS := {
	"quest_id": "任务 ID", "display_name": "显示名称", "description": "说明", "category": "任务分类",
	"stage_id": "阶段 ID", "objective_id": "目标 ID", "title": "公开标题", "text": "公开目标文本",
	"kind": "类型", "amount": "所需数量", "item_id": "物品", "recipe_id": "配方", "recipe": "配方",
	"story_id": "剧情", "actor_id": "交谈对象 ID", "topic_id": "交谈主题 ID", "fact_id": "事实 ID",
	"target_id": "目标 ID", "target_tags": "公开定位标签（逗号分隔）", "latch": "达成后保留完成记录",
	"visible": "向玩家显示", "hidden": "隐藏此目标", "optional": "可选目标", "has_count": "显示数量",
	"match_mode": "达成规则", "match_policy": "达成规则", "completion_mode": "达成规则",
	"timeline_path": "Dialogic 剧情文件", "completion_signal": "正常结束信号",
	"return_scene_path": "完成后返回场景", "allowed_scene_path": "允许播放的场景",
	"legacy_started_flag": "旧档开始标记（兼容用）", "legacy_completed_flag": "旧档完成标记（兼容用）",
	"ref_id": "引用 ID", "value": "期望值", "expected": "期望值", "retrospective": "认可接取前的记录",
	"event_policy": "历史事件策略", "visibility": "玩家可见性", "key": "记录键", "consume": "交付时消耗物品",
	"student_id": "关联学生 ID（可留空）", "auto_accept": "条件满足时自动接取", "include_history": "认可目标开启前的事件记录", "action_id": "动作 ID",
	"guidance_id": "教学辅助 ID（可留空）",
}

func bind_data(store) -> void:
	_store = store
	if is_node_ready():
		_rebuild()

func edit_resource(resource: Resource, is_new: bool, page: int = 0, reset_selection: bool = true) -> void:
	_draft = resource.duplicate(true) if resource != null else null
	_is_new = is_new
	_page = page
	if reset_selection:
		_stage_index = 0
		_objective_index = 0
		_locked_ids.clear()
		if resource != null and not is_new:
			_capture_ids(resource)
	if is_node_ready():
		_rebuild()

func _ready() -> void:
	_rebuild()

func get_resource() -> Resource:
	return _draft

func get_field(path: String) -> Control:
	return _fields.get(path)

func _capture_ids(resource: Resource, stage_id: String = "") -> void:
	if resource is QuestStageData:
		stage_id = str(resource.stage_id)
	for property in resource.get_property_list():
		var name: String = property.name
		if name in ["quest_id", "story_id", "stage_id", "objective_id", "action_id"]:
			_locked_ids[_identity_key(name, resource.get(name), stage_id)] = true
		var value: Variant = resource.get(name)
		if value is Array:
			for child in value:
				if child is Resource:
					_capture_ids(child, stage_id)

func _identity_key(field: String, value: Variant, stage_id: String = "") -> String:
	return "%s::%s::%s" % [field, stage_id if field == "objective_id" else "", value]

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_fields.clear()
	if _draft == null or _store == null:
		return
	if _page == 1:
		_heading(self, "剧情衔接")
		_render_parameters(self, _draft, "")
		return
	_heading(self, "任务基本信息")
	for field in ["quest_id", "display_name", "description", "category", "student_id", "guidance_id", "auto_accept"]:
		_add_field(self, _draft, field, field)
	for field in ["accept_conditions", "acceptance_conditions", "conditions"]:
		if _has(_draft, field):
			_resource_array(self, "接取条件 · 全部满足后允许接取", _draft, field, "quest_condition_data.gd", field)
	_stages_section()
	for field in ["completion_actions", "on_complete", "complete_actions"]:
		if _has(_draft, field):
			_resource_array(self, "任务完成动作 · 独立执行，失败可重试", _draft, field, "quest_action_data.gd", field)

func _stages_section() -> void:
	_heading(self, "顺序阶段")
	var stages: Array = _draft.get("stages")
	var list := ItemList.new()
	list.custom_minimum_size.y = 112
	add_child(list)
	for index in stages.size():
		var stage: Resource = stages[index]
		list.add_item("%d. %s [%s]" % [index + 1, _title(stage), stage.get("stage_id")])
	_stage_index = clampi(_stage_index, 0, maxi(0, stages.size() - 1))
	if not stages.is_empty():
		list.select(_stage_index)
	list.item_selected.connect(func(index): _stage_index = index; _objective_index = 0; _rebuild())
	var actions := HBoxContainer.new()
	add_child(actions)
	_button(actions, "新增阶段", _add_stage)
	_button(actions, "删除", _remove_stage, stages.is_empty())
	_button(actions, "↑ 上移", _move_stage.bind(-1), _stage_index <= 0)
	_button(actions, "↓ 下移", _move_stage.bind(1), _stage_index >= stages.size() - 1)
	if stages.is_empty():
		return
	var stage: Resource = stages[_stage_index]
	var prefix := "stages.%d" % _stage_index
	var card := _card(self)
	_heading(card, "阶段设置")
	_render_parameters(card, stage, prefix, ["objectives", "completion_actions", "on_complete", "complete_actions"])
	_objectives_section(card, stage, prefix)
	for field in ["completion_actions", "on_complete", "complete_actions"]:
		if _has(stage, field):
			_resource_array(card, "阶段完成动作", stage, field, "quest_action_data.gd", prefix + "." + field)

func _objectives_section(parent: VBoxContainer, stage: Resource, prefix: String) -> void:
	_heading(parent, "阶段内并行目标")
	var objectives: Array = stage.get("objectives")
	var list := ItemList.new()
	list.custom_minimum_size.y = 92
	parent.add_child(list)
	for index in objectives.size():
		var goal: Resource = objectives[index]
		list.add_item("%s [%s]" % [_title(goal), goal.get("kind")])
	_objective_index = clampi(_objective_index, 0, maxi(0, objectives.size() - 1))
	if not objectives.is_empty():
		list.select(_objective_index)
	list.item_selected.connect(func(index): _objective_index = index; _rebuild())
	var actions := HBoxContainer.new()
	parent.add_child(actions)
	_button(actions, "新增目标", _add_objective)
	_button(actions, "删除目标", _remove_objective, objectives.is_empty())
	if objectives.is_empty():
		return
	var goal: Resource = objectives[_objective_index]
	_render_parameters(parent, goal, "%s.objectives.%d" % [prefix, _objective_index])

func _resource_array(parent: VBoxContainer, title: String, owner_resource: Resource, field: String, script_file: String, prefix: String) -> void:
	_heading(parent, title)
	var entries: Array = owner_resource.get(field)
	for index in entries.size():
		var card := _card(parent)
		var entry: Resource = entries[index]
		_render_parameters(card, entry, "%s.%d" % [prefix, index])
		_button(card, "移除此项", func(): entries.remove_at(index); changed.emit(); _rebuild())
	_button(parent, "＋ 添加", func():
		var entry: Resource = load("res://scripts/quest/" + script_file).new()
		if _has(entry, "action_id"): entry.set("action_id", _next_id(entries, "action_id", "action"))
		entries.append(entry)
		changed.emit()
		_rebuild())

func _render_parameters(parent: VBoxContainer, resource: Resource, prefix: String, excluded: Array = []) -> void:
	for property in resource.get_property_list():
		var field: String = property.name
		if not (property.usage & PROPERTY_USAGE_EDITOR) or field in excluded or field in ["script", "resource_name", "resource_local_to_scene", "resource_path"]:
			continue
		if property.type in [TYPE_ARRAY, TYPE_OBJECT] and field != "recipe":
			continue
		if not _relevant(resource, field):
			continue
		if field == "items":
			_delivery_items(parent, resource, prefix + ".items")
			continue
		_add_field(parent, resource, field, field if prefix.is_empty() else prefix + "." + field)

func _relevant(resource: Resource, field: String) -> bool:
	if not _has(resource, "kind"): return true
	var kind := str(resource.get("kind"))
	if field == "recipe": return kind in ["recipe_materials", "craft_confirmed"]
	if field == "items": return kind == "delivery"
	if field == "actor_id": return kind in ["talk", "delivery"]
	if field == "topic_id": return kind == "talk"
	if field == "target_id": return kind not in ["recipe_materials", "delivery"]
	if field == "amount": return kind in ["have_item", "craft_confirmed", "grant_item", "fact"]
	if field == "include_history": return kind in ["craft_confirmed", "talk", "delivery", "story_completed"]
	return true

func _delivery_items(parent: VBoxContainer, resource: Resource, prefix: String) -> void:
	_heading(parent, "交付物品 · 按此清单检查并扣除")
	var costs: Dictionary = resource.get("items")
	for id in costs:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var picker := OptionButton.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.fit_to_longest_item = false
		row.add_child(picker)
		for item: ItemData in _store.items.items:
			if item == null: continue
			var index := picker.item_count
			picker.add_item("%s [%s]" % [item.display_name, item.item_id])
			picker.set_item_metadata(index, item.item_id)
			picker.set_item_disabled(index, costs.has(item.item_id) and item.item_id != StringName(id))
			if item.item_id == StringName(id): picker.select(index)
		picker.item_selected.connect(func(index):
			var next_id: StringName = picker.get_item_metadata(index)
			if next_id != StringName(id):
				var amount: int = costs[id]
				costs.erase(id)
				costs[next_id] = amount
				changed.emit()
				_rebuild.call_deferred())
		var amount := SpinBox.new()
		amount.min_value = 1
		amount.max_value = 999999
		amount.value = costs[id]
		row.add_child(amount)
		_fields[prefix + "." + str(id)] = amount
		amount.value_changed.connect(func(value): costs[id] = int(value); changed.emit())
		_button(row, "移除", func(): costs.erase(id); changed.emit(); _rebuild())
	_button(parent, "＋ 添加交付物品", func():
		for item: ItemData in _store.items.items:
			if item != null and not costs.has(item.item_id):
				costs[item.item_id] = 1
				changed.emit()
				_rebuild()
				break)

func _add_field(parent: VBoxContainer, resource: Resource, field: String, path: String) -> void:
	if not _has(resource, field):
		return
	var value: Variant = resource.get(field)
	var label := Label.new()
	label.text = LABELS.get(field, field)
	if field == "target_id" and _has(resource, "kind"):
		label.text = {"have_item": "所需物品", "recipe_known": "需要解锁的配方", "craft_confirmed": "目标产物", "talk": "关联剧情（可留空）", "story_completed": "需要完成的剧情", "fact": "事实记录 ID", "request_story": "请求播放的剧情", "accept_quest": "后续任务", "grant_item": "奖励物品", "quest_completed": "前置任务"}.get(str(resource.get("kind")), "目标 ID")
	parent.add_child(label)
	if field == "target_id" and _has(resource, "kind") and resource.get("kind") == &"scene":
		label.text = "目标场景"
	if field == "actor_id" and _has(resource, "kind") and resource.get("kind") == &"delivery":
		label.text = "交付对象 ID"
	var control: Control
	var choices: Array = _store.field_choices(resource, field)
	if not choices.is_empty():
		var option := OptionButton.new()
		control = option
		option.fit_to_longest_item = false
		var selected := -1
		for choice: Dictionary in choices:
			var index := option.item_count
			option.add_item(choice.label)
			option.set_item_metadata(index, choice.value)
			if choice.value == value or (field == "recipe" and choice.value is AlchemyRecipe and value is AlchemyRecipe and choice.value.recipe_id == value.recipe_id):
				selected = index
		if selected < 0:
			selected = option.item_count
			option.add_item("未找到引用：" + str(value))
			option.set_item_metadata(selected, value)
		option.select(selected)
		option.item_selected.connect(func(index):
			resource.set(field, option.get_item_metadata(index))
			if field == "kind" and _has(resource, "amount") and resource.get("kind") not in [&"have_item", &"craft_confirmed", &"grant_item", &"fact"]:
				resource.set("amount", 1)
			changed.emit()
			if field == "kind": _rebuild.call_deferred())
	elif value is bool:
		var check := CheckBox.new()
		control = check
		check.text = "启用"
		check.button_pressed = value
		check.toggled.connect(func(enabled): resource.set(field, enabled); changed.emit())
	elif value is int:
		var spin := SpinBox.new()
		control = spin
		spin.min_value = 0
		spin.max_value = 999999
		spin.value = value
		spin.value_changed.connect(func(number): resource.set(field, int(number)); changed.emit())
	elif field in ["description", "text", "public_text", "designer_notes"]:
		var edit := TextEdit.new()
		control = edit
		edit.custom_minimum_size.y = 76
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text = str(value)
		edit.text_changed.connect(func(): resource.set(field, edit.text); changed.emit())
	else:
		var edit := LineEdit.new()
		control = edit
		edit.text = ", ".join(value) if value is PackedStringArray else str(value)
		var is_identity := field in ["quest_id", "story_id", "stage_id", "objective_id", "action_id"] and (_page == 1 or field != "story_id")
		var stage_id := str(_draft.get("stages")[int(path.get_slice(".", 1))].stage_id) if field == "objective_id" and path.begins_with("stages.") else ""
		edit.editable = not (is_identity and _locked_ids.has(_identity_key(field, value, stage_id)))
		if not edit.editable:
			edit.tooltip_text = "已有 ID 保持稳定；修改文案不会改变存档引用。复制配置可使用新 ID。"
		edit.text_changed.connect(func(text):
			if value is StringName: resource.set(field, StringName(text))
			elif value is PackedStringArray:
				var tags := PackedStringArray()
				for tag: String in text.split(",", false): tags.append(tag.strip_edges())
				resource.set(field, tags)
			else: resource.set(field, text)
			changed.emit())
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(control)
	_fields[path] = control
	if (field.ends_with("_path") and (field.contains("scene") or field.contains("timeline"))) or (field == "target_id" and _has(resource, "kind") and resource.get("kind") == &"scene"):
		_button(parent, "从项目选择文件…", _pick_file.bind(resource, field, path))

func _pick_file(resource: Resource, field: String, _path: String) -> void:
	var dialog := FileDialog.new()
	add_child(dialog)
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.dtl ; Dialogic 剧情文件"] if field.contains("timeline") else ["*.tscn ; Godot 场景"])
	dialog.file_selected.connect(func(path): resource.set(field, path); changed.emit(); _rebuild.call_deferred())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(780, 560))

func _add_stage() -> void:
	var stages: Array = _draft.get("stages")
	var stage: Resource = load("res://scripts/quest/quest_stage_data.gd").new()
	stage.set("stage_id", _next_id(stages, "stage_id", "stage"))
	stages.append(stage)
	_stage_index = stages.size() - 1
	_objective_index = 0
	changed.emit()
	_rebuild()

func _remove_stage() -> void:
	var stages: Array = _draft.get("stages")
	if _stage_index < stages.size():
		stages.remove_at(_stage_index)
		changed.emit()
		_rebuild()

func _move_stage(offset: int) -> void:
	var stages: Array = _draft.get("stages")
	var next := _stage_index + offset
	if next >= 0 and next < stages.size():
		var stage: Resource = stages[_stage_index]
		stages.remove_at(_stage_index)
		stages.insert(next, stage)
		_stage_index = next
		changed.emit()
		_rebuild()

func _add_objective() -> void:
	var stages: Array = _draft.get("stages")
	if stages.is_empty(): return
	var goals: Array = stages[_stage_index].get("objectives")
	var goal: Resource = load("res://scripts/quest/quest_objective_data.gd").new()
	goal.set("objective_id", _next_id(goals, "objective_id", "goal"))
	goals.append(goal)
	_objective_index = goals.size() - 1
	changed.emit()
	_rebuild()

func _remove_objective() -> void:
	var stages: Array = _draft.get("stages")
	if stages.is_empty(): return
	var goals: Array = stages[_stage_index].get("objectives")
	if _objective_index < goals.size():
		goals.remove_at(_objective_index)
		changed.emit()
		_rebuild()

func _next_id(resources: Array, field: String, prefix: String) -> StringName:
	var used: Array = []
	for resource: Resource in resources: used.append(resource.get(field))
	var index := 1
	while used.has(StringName("%s_%d" % [prefix, index])): index += 1
	return StringName("%s_%d" % [prefix, index])

func focus_field(path: String) -> void:
	var parts := path.split(".")
	if parts.size() >= 2 and parts[0] == "stages":
		_stage_index = int(parts[1])
		if parts.size() >= 4 and parts[2] == "objectives": _objective_index = int(parts[3])
		_rebuild()
	var field: Control = _fields.get(path)
	if field != null:
		field.grab_focus()
		_scroll_to_field.call_deferred(field)

func _scroll_to_field(field: Control) -> void:
	var scroll := get_parent() as ScrollContainer
	if is_instance_valid(field) and scroll != null and scroll.is_ancestor_of(field):
		scroll.ensure_control_visible(field)

func _has(resource: Resource, field: String) -> bool:
	for property in resource.get_property_list():
		if property.name == field: return true
	return false

func _title(resource: Resource) -> String:
	for field in ["display_name", "title", "text"]:
		if _has(resource, field) and not str(resource.get(field)).is_empty(): return str(resource.get(field))
	return "未命名"

func _heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)

func _card(parent: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"EditorCard"
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	return box

func _button(parent: Node, text: String, action: Callable, disabled: bool = false) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.pressed.connect(action)
	parent.add_child(button)

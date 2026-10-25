# 保存与读取

主菜单点击LoadGame打开读取模式。游戏中点击右上角“存档 [F5]”打开保存模式，也可以按F5打开保存、F9打开读取。
窗口提供120个手动存档位置，每页3行4列，共10页。右上角×或Esc关闭，关闭后恢复原来的暂停状态和焦点。
当前没有自动存档或Auto页面。

每个记录中央显示打开存档窗口之前的游戏截图；左上角显示章节；下方显示保存日期、时分秒和累计游玩时长，游玩时长格式为HH:MM:SS。
空槽显示NO DATA；截图缺失的有效记录显示“暂无截图”，仍可读取。无图形的测试运行不会生成截图。

读取模式：点击非空记录先确认，确认后恢复；空槽显示“该存档为空”。保存模式：点击空槽直接保存，点击已有记录需要确认覆盖，取消不改变旧存档。
主菜单没有活动游戏，因此保存模式禁用。设置、背包及确认弹窗打开时，不叠加存档窗口。

## 保存内容

- 当前场景、章节和累计游玩时长。
- PlayerInventory的容量和实际ItemID/数量。
- GameProgress的配方解锁、房间领取地点、教程完成／跳过和后续剧情标记。
- QuestSystem 的已接任务、阶段与目标完成记录、目标计数、业务事实、事件收据、完成动作及其执行状态、追踪任务和面板收起状态。任务子结构版本为 2，旧结构或缺少任务字段时按既有剧情证据迁移，详见 [通用任务系统](generic_quest_system.md)。
- QuestFlow 的剧情完成记录、当前剧情播放身份，以及其与任务完成动作的关联。读取时绑定已保存的 Dialogic 位置，不从头重播；已发放奖励和已完成动作不重复执行。
- 炼金界面选中的配方、各槽已选素材、当前素材槽及后续剧情播放状态。
- 学院地图中的礼堂剧情播放状态。
- Dialogic原生完整状态：timeline路径、当前文字／选择节点、变量、背景、立绘、声音等。

仅在可恢复的文字或选择节点保存timeline，避免读取时重做领取、场景切换等有副作用的事件。读取时从保存的文本节点继续，当前行会重新显示。
读档清理旧剧情时抑制旧场景的结束跳转，并避免World自动播放开场。剧情结束后，炼金后续和礼堂剧情仍按原流程返回房间／地图。

点击NewGame会重置背包到ItemCatalog.initial_inventory，清空配方、领取与剧情标记，重置章节和游玩时长，然后播放开场。已保存的文件、选项设置和已读记录不被清除。

## 章节与时长

默认第1章。timeline文件名以CP01、CP02、CP_02等形式开头时自动更新；其他名字保持当前章节。
需要手动更新时调用 `SaveSystem.set_chapter(2)`，也可在Dialogic Call事件中调用。
游玩时长只累计活动游戏时间，主菜单、存档窗口、设置窗口、背包及剧情暂停期间不累计。读档后继续该存档的时长。

## 文件与编辑

存档保存在 `user://game_saves/slot_001.res` 到 `slot_120.res`。每个文件同时包含状态和PNG缩略图，GameSaveData格式版本为1。
覆盖时先写临时文件，再用备份替换，写入失败保留旧记录。读取前检查版本、场景、timeline节点、ItemID、物品数量、剧情数据与炼金素材选择；验证失败不改变当前游戏状态。
物品交付和任务完成动作正在提交时暂不允许保存，避免把已扣物品但尚未记录目标的中间状态写入文件。独立学生委托场景使用 `user://quest_sandbox/` 检查点，不读写正式存档槽。

- `scripts/save/game_save_data.gd`：存档资源结构。
- `scripts/save/save_system.gd`：SaveSystem Autoload，保存、校验、恢复、截图及章节／时长。
- `scenes/ui/save/save_ui.tscn`：SaveUI Autoload，窗口、模式切换、分页、入口和确认弹窗，可在编辑器修改。
- `scenes/ui/save/save_slot_ui.tscn`：单个记录的截图、章节与时间布局。
- `themes/save_theme.tres`：槽位和章节标签样式；窗口沿用settings_theme。

代码入口：`SaveUI.open_load()`、`SaveUI.open_save()`。不需要参数，可用于Dialogic Call事件。
直接保存可调用 `SaveSystem.save_slot(1, SaveSystem.capture_thumbnail())`；直接读取用 `await SaveSystem.load_slot(1)`。返回字典包含ok和error。

未来地图根节点加入settings_context分组即可显示存档入口。需要保存额外场景数据时提供get_save_state、validate_save_state和restore_save_state接口，参考AcademyMap与AlchemyUI。
测试见 `tests/save_system_test.gd` 和 `tests/save_ui_test.gd`；覆盖跨进程读取、覆盖确认、最后一页、场景恢复、损坏记录、写入失败及实际截图。

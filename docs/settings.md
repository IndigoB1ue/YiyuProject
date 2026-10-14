# 游戏选项设置

主菜单点击“设置”打开三类选项，右侧切换文字、图形和声音，右上角×或Esc关闭。
关闭后键盘焦点回到主菜单“设置”按钮。设置即时生效，自动保存在 `user://settings.cfg`，再次运行游戏自动加载。
“恢复默认设置”只恢复当前页面，不修改其他类别。

学院一级地图、RovinRoom二级地图、炼金界面和正在播放的任意timeline，都可以点击右上角“设置 [Esc]”或按Esc打开同一个窗口。
打开设置时暂停场景交互、文字显示、自动播放及快进；关闭后恢复原来的暂停状态，保留炼金素材选择和剧情进度。
文字速度、音量、窗口模式及帧率修改立即应用；正在等待的自动播放计时也会更新为新间隔。
背包或确认弹窗打开时保留其原有关闭操作，不叠加设置窗口。设置打开期间，I不会打开背包。

全局入口为Autoload `SettingsUI`，可在代码或Dialogic Call事件中调用 `SettingsUI.open_settings()`，无需参数。
以后新增一级或二级地图时，将场景根节点加入 `settings_context` 分组，即可自动显示入口并支持Esc。

## 文字

- 文本显示速度：1～10，数值越大越快，默认10。使用Dialogic实际文字延迟倍率，并提供界面预览。
- 自动播放间隔：文字完整显示后等待1～10秒，默认7秒；有语音时至少等待语音结束。
- 文本跳过模式：全部或仅已读，默认仅已读。现有“快进”按钮遵守该设置；已读记录在剧情结束和退出游戏时保存，下次启动继续使用。
- 重要分支提示：默认开启，仅对标记为重要的选择显示提示，不拦截玩家操作。
- 语言：只列出项目实际加载的语言。当前只接入简体中文，因此该项显示简体中文并禁用切换；添加Translation资源后其他语言会进入列表。

新增语言时需要提供界面和剧情翻译资源；Dialogic剧情翻译还需启用其Translation配置并设置正确的原文语言。

对话布局增加“自动”按钮，用来启用或停止玩家主动开启的自动播放。
在Dialogic选择的Extra Data中添加 `important = true`，即可标记重要分支。文本写法：

```text
这是一个重要选择。
- 接受 | [important="true"]
	选择后的剧情。
- 拒绝
	另一段剧情。
```

## 图形

- 显示模式：窗口或全屏，默认窗口。
- 分辨率：窗口模式调整实际窗口尺寸，只列出当前屏幕可容纳的预设尺寸，默认1280×720。
- 全屏使用当前桌面分辨率，分辨率项显示实际值并禁用选择。
- 最大帧数：30、60、120、144、240或不限，默认60。实际帧数仍取决于设备及垂直同步。

## 声音

四项范围均为0～10，0为静音。默认主音量10、音乐3、效果音6、角色语音8。
使用 `default_bus_layout.tres` 的Master、Music、SFX、Voice通道，三个分类通道均发送到Master。
Dialogic的music通道默认发送到Music，一次性音效发送到SFX，角色语音的默认Master输出在播放时转到Voice。
对话打字音发送到SFX。其他AudioStreamPlayer请在检查器中选择对应Bus；自定义音频通道可以自行指定输出总线。

## 编辑与扩展

- `scripts/core/game_settings.gd`：默认值、校验、读写及应用逻辑，Autoload名称GameSettings。
- `scenes/ui/settings/settings_ui.tscn`：完整三页界面，可在编辑器修改布局和选项。
- `scenes/ui/settings/settings_overlay.tscn`：全局窗口层和游戏内入口按钮，可在编辑器调整入口位置。
- `scripts/ui/settings/settings_overlay.gd`：入口、暂停恢复、焦点恢复及场景切换清理。
- `scenes/ui/settings/settings_slider_row.tscn`：滑条、名称与数值组件。
- `themes/settings_theme.tres`：字体、红黑半透明面板、按钮和滑条样式。
- `scenes/ui/settings/important_choice_hint.tscn`：重要分支的提示外观。

代码修改示例：`GameSettings.set_value("audio", "music", 5)`。
测试：`tests/settings_test.gd`验证应用、音频分类、分支提示和持久化；`tests/settings_ui_test.gd`验证实际鼠标、快捷键、恢复默认和窗口尺寸；`tests/settings_context_test.gd`验证地图、炼金及timeline中的设置入口、即时应用和暂停恢复。

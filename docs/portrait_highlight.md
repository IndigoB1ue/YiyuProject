# 立绘说话高亮

所有 Scene 为空的 Dialogic 立绘使用项目默认场景：
`res://scenes/dialogue/speaking_portrait.tscn`。
当前六个角色的九张立绘均已自动接入，原有图片、缩放、偏移和镜像配置照常生效。
以后添加图片立绘时，继续保留 Scene 为空即可；自定义立绘也可以显式选择这个场景。

行为：
- 角色入场时默认变暗。
- 台词指定的说话角色恢复原色，并排在其他角色立绘前面。
- 切换说话角色时，上一位变暗并恢复 timeline 中设置的原有层级。
- 无说话角色的旁白让所有角色变暗。
- 同一角色更换表情时保留说话状态。
- 新角色入场时，当前说话角色仍然排在立绘最前面。

在场景根节点 Inspector 中调整：
- `Inactive Color`：未说话颜色。默认 RGB 0.35、Alpha 1；RGB 越小越暗，Alpha 保持 1。
- `Speaking Z Order`：说话层级的最低值，默认 100。实际值会高于当前其他角色的层级。

项目设置对应 `dialogic/portraits/default_portrait`，也可从 Dialogic 的 Portraits 设置中更换默认场景。
脚本位于 `res://scripts/dialogue/speaking_portrait.gd`；无需修改插件或给每句台词添加事件。

# 学院地图

入口：房间引导完成或跳过后，点击“学院地图 [M]”或按 M。完成清洗剂剧情后，楼梯也会进入同一张地图。地图是独立场景 `scenes/AcademyMap.tscn`；罗维宿舍直接进入现有 `scenes/RovinRoom.tscn`，作为完整的二级房间地图。

四栋建筑：教学楼、学生礼堂、学生宿舍、罗维宿舍。教学楼和学生宿舍暂未开放。学生礼堂需要 `GameProgress.cleanser_timeline_completed`，开放后直接播放 `CP01_EP02_SI03`，不打开二级平面图。

地图根节点检查器可配置 `Hall Timeline Path` 和 `Room Scene Path`。背景图片及建筑按钮在 `MapArea/MapCanvas` 下，参考尺寸 1680 × 945，使用 `room_canvas_fit.gd` 一起等比缩放。可在编辑器直接调整建筑按钮区域；按钮正常、悬停和禁用样式保存在场景中。

礼堂剧情继续使用旧字段 `stairs_timeline_started` 记录单次播放状态，以兼容现有进度结构。离开楼梯不再标记剧情已播放，返回房间保留背包、领取、教程和剧情状态。目前进度仅保留在本次运行中，与原有系统一致。

验证：Godot 4.7.2 下运行 `tests/rovin_stairs_story_test.gd`、`tests/alchemy_story_test.gd`、`tests/rovin_room_ui_test.gd`。覆盖实际鼠标点击、礼堂前置条件、完整炼金剧情衔接、两种窗口尺寸、重复播放防护、错误配置重试和房间往返状态。

## 地图图片

图片：`asserts/image/map/academy_map.png`。使用内置 imagegen 工具生成，建筑名称由游戏 UI 绘制。生成提示词如下：

```text
Use case: stylized-concept. Asset type: game campus navigation map background, landscape 16:9. Create a charming cartoon illustrated royal magic academy campus, overhead slightly isometric view, soft clean painted shapes, pastel green lawns, cream stone walls and blue slate roofs, warm daylight, clear winding paths connecting EXACTLY FOUR distinct buildings with generous spacing for clickable UI overlays. Layout needed for game hotspots: large teaching building in upper left quadrant centered at (27%,30%); elegant student assembly hall in upper right quadrant centered at (73%,30%); long multi-room student dormitory in lower left quadrant centered at (27%,70%); small cozy detached teacher Rovin dormitory in lower right quadrant centered at (73%,70%). Teaching building has classroom windows and small clock tower, hall broad arched entrance and large roof, student dormitory repeated windows, Rovin dormitory modest two-storey cottage. Surrounding trees, gardens, central small fountain and pathways, no additional buildings. No people, no text, no lettering, no labels, no UI, no border. Entire four buildings fully visible within image. Cartoon storybook game art, not realistic.
```

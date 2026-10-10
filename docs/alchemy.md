# 简化炼金系统

## 运行

在 Godot 编辑器打开 `scenes/RovinRoom.tscn`，按 F6 体验探索到炼金的完整流程，也可从现有剧情进入房间。

1. 点击书柜，获得“清洗剂配方”物品 ×1，同时解锁清洗剂配方。
2. 点击床头柜，获得清洗剂粉末 ×1。
3. 点击鞋柜、书桌、测算长桌，每处各获得清水 ×1。
4. 点击右上角炼金区域，界面只显示已经获取的配方。
5. 依次在粉末和三个清水需求槽中各选入一个素材，点击“开始炼金”。
6. 获得清洗剂 ×1，粉末和清水全部扣除，原有药草不变。

直接运行 `AlchemyRoom.tscn` 时，新的游戏会显示“尚未获取配方”，点击“返回房间”即可探索。房间各地点只能领取一次。点击房间炼金区域时，满足以下任意条件即可进入：背包有清洗剂配方 ×1（`clear_potion_recipe`）和清水 ×3；或者背包有清洁剂成品 ×1（沿用当前清洗剂物品 `clear_potion`）。否则留在房间，并提示缺少配方或清水的数量。

入口读取实际背包数量，不使用搜过的地点数或已解锁标记代替物品数量。成品条件优先检查，即使没有配方和素材也可以进入，入口不消耗成品、配方或清水。粉末不属于此次入口条件，实际炼金仍需要粉末 ×1、清水 ×3，并在点击“开始炼金”时再次验证及扣除。配方物品不消耗。

奖励数据配置在 `RovinRoom` 根节点的 `found_recipe`、`recipe_item_id` 和 `material_rewards` 中。初始背包仍由 `data/items/catalog.tres` 的 `initial_inventory` 配置，目前保留药草 ×2，配方、清水和粉末通过房间领取。

界面采用上中下三层：上层配方选择，中层横向需求图标，下层匹配素材网格。需求图标数量根据配方数据生成，不固定为四个。

每个素材单位占一格，不显示堆叠数量。点击一格选入 1 个后，该单位从可选网格移除；实际背包在炼金成功前保持不变。选满的槽会禁用剩余可选格。右键需求图标、点击“清空当前槽”或按 Backspace 可清空选择，素材重新出现在可选网格中。切换配方清空本次选择。大背包可以滚动，网格列数随窗口宽度调整。

所有槽选满后开始按钮才启用；库存发生变化时自动重新验证。失败消息显示在界面或结果窗口中，库存保持不变。此次仅调整展示和键鼠操作，背包继续用 ItemID/数量结构保存，没有引入独立物品实例、品质或特性。

`PlayerInventory` 为唯一玩家背包 Autoload，跨场景保留；启动游戏时从目录资源初始化一次。当前没有存档和新游戏重置功能。

`GameProgress` Autoload 记录已获取配方 ID 和已领取的房间地点，切换场景后仍保留，退出并重新运行游戏后重置；当前没有存档持久化。

## 文件职责

- `ItemData`：物品 ID、名称、描述、图标以及可选分类。
- `ItemCatalog`：物品目录和演示初始背包，配置在 `data/items/catalog.tres`。
- `InventorySystem`：提供 `get_item`、`get_items`、`get_amount`、`add_item`、`remove_item` 和原子 `exchange`；库存变化发送 `inventory_changed`。`get_items` 返回副本。
- `IngredientRequirement`：素材需求和数量；有 ItemID 时精确匹配，否则按单个 category 字段匹配。
- `AlchemyRecipe`：配方数据，示例为 `data/recipes/potion.tres`。
- `AlchemySystem`：配方检查、素材候选、选择记录、跨槽预留统计、最终校验及调用背包提交。选择为每个素材槽一个 `{ItemID: 数量}` 字典。
- `AlchemyUI`：组合界面，转交操作并刷新显示。
- `GameProgressState`：记录已获取配方和已领取地点，供房间与炼金 UI 共享。
- `RovinTutorialController`：按背包和领取状态判断引导阶段，指定当前目标。
- `RovinTutorialUI`：显示提示卡、进度和目标描边，接收跳过操作。
- `AlchemyStoryTrigger`：播放清洗剂后续剧情，结束后返回房间并开放楼梯。
- `RovinStairsTrigger`：完成清洗剂剧情后开放楼梯，点击返回学院地图。
- `RecipeListUI`、`IngredientSlotUI`、`IngredientSelectUI`、`AlchemyResultUI`：各自负责配方列表、素材槽、素材选择和结果显示。

## 增加配方

1. 在物品目录中添加新的 `ItemData`，确保物品 ID 唯一。
2. 创建 `AlchemyRecipe` Resource，填写唯一 RecipeID、名称、描述、成品 ID/数量、图标和 `IngredientRequirement` 列表。
3. 将资源加入 `AlchemyRoom` 根节点的 `recipes` 数组。此数组是配方目录，UI 会筛选玩家已获取的配方。
4. 配置获取入口，例如将 `RovinRoom` 根节点的 `found_recipe` 指向该资源；其他事件可调用 `GameProgress.unlock_recipe(recipe_id)`。

配方和初始库存均在资源中配置，不需要修改 UI。新增物品请确保也加入目录；不存在的素材或成品 ID 会返回清晰错误。

其他系统应通过 `PlayerInventory.add_item/remove_item` 修改库存；炼金的消耗和产出通过 `exchange` 一次完成，成功只发出一次变化通知。当前流程同步执行，无随机成功率、品质或动画。

## 首次进入房间的教程

第一次进入 RovinRoom 时会显示左下角提示卡和目标描边，依次引导玩家获取配方、收集素材、点击炼金区域。素材进度从当前配方的 ItemID 需求和实际背包数量计算；搜过或已经满足需求的地点不再高亮。玩家可自由选择搜集顺序，也可以提前搜集素材，提示会根据已拥有的物品继续下一阶段。

“跳过引导”按钮会立即关闭提示卡及教程描边，不发放物品、不解锁配方、不影响领取与炼金入口检查。成功从房间进入炼金场景后，教程记录为完成；场景没有实际切换时不会记录完成。未完成的教程返回房间时按现有进度继续，已完成或已跳过的教程不再出现。已经拥有清洗剂成品的玩家也会自动结束引导。

完成和跳过状态保存在 `GameProgress` 中，本次运行内跨场景保留；重新启动游戏后重置，目前没有写入存档。

在编辑器中打开 `scenes/ui/rovin_tutorial_ui.tscn` 可调整提示卡位置、大小及跳过按钮。`scenes/ui/rovin_tutorial_target.tscn` 是目标描边模板；颜色和边框在 `themes/alchemy_theme.tres` 的 `RovinTutorialCard`、`RovinTutorialHighlight`、`RovinTutorialTargetLabel` 类型变体中配置。高亮区域跟随实际房间按钮的缩放和位置，并允许鼠标点击穿透。

## 获得清洗剂后的 timeline

`AlchemyRoom` 中的 `StoryTrigger` 节点负责后续 Dialogic 剧情，现已配置为 `CP01_EP02_SI02`。编辑器保存的 `uid://` 引用和 `res://` 文件路径都支持。路径留空时炼金仍正常进行，不播放剧情，也不记录为已经播放。

创建好新的 Dialogic timeline 后，打开 `scenes/AlchemyRoom.tscn`，选中 `StoryTrigger`，在检查器的 `Timeline Path` 选择 `.dtl` 文件并保存场景。`Target Item Id` 默认是清洗剂成品 `clear_potion`。

流程为：成功炼金并加入背包 → 显示获得清洗剂的结果 → 玩家确认或关闭结果窗口 → 下一帧开始 timeline。失败炼金、其他成品不会触发。剧情播放时隐藏炼金操作区，保留场景背景；剧情结束后自动进入 `RovinRoom`，并记录清洗剂剧情已完成。

剧情每次游戏运行只触发一次，状态保存在 `GameProgress.cleanser_timeline_started`，跨场景保留；重复获得清洗剂不会再次播放。配置路径不存在时显示错误，已经获得的物品不会丢失，也不会标记为已播放。当前没有存档持久化。

## 剧情结束后的楼梯

只有在清洗剂后续 timeline 结束、`GameProgress.cleanser_timeline_completed` 为 true 后，房间底部标注“楼梯”的区域才会出现与素材收集相同的交互高亮。仅拥有清洗剂或仅开始播放剧情不会提前开放楼梯。

点击楼梯进入 `scenes/AcademyMap.tscn`，不播放剧情。地图中的罗维宿舍返回完整 `RovinRoom`；学生礼堂在清洗剂剧情完成后开放，点击播放 `CP01_EP02_SI03`。目标在学院地图根节点的 `Hall Timeline Path` 中配置。教学楼和学生宿舍目前显示但不可进入。

礼堂剧情播放时隐藏地图操作，连续点击不会重复启动。实际开始播放礼堂剧情时记录兼容旧字段 `GameProgress.stairs_timeline_started`，离开楼梯不记录该状态。剧情结束后恢复地图并禁止重复播放礼堂剧情。无效路径在地图底部显示错误并保留重试机会。楼梯始终可以返回地图；领取和剧情状态在本次运行内跨场景保留。礼堂原有 Demo 结束提示保持不变。

房间引导完成或跳过后显示“学院地图 [M]”按钮。对话播放、背包打开或物品提示窗口显示时不能从此入口切换地图。首次流程仍可直接通过剧情解锁的楼梯离开。

## 在编辑器中调整 UI

### 房间 UI

`RovinRoom.tscn` 已包含全部房间 UI：`RoomCanvas/Hotspots` 下的书柜、床头柜、鞋柜、书桌、测算长桌、炼金区域和楼梯按钮，根节点下的 `Status` 状态文字及 `Message` 提示窗口。按钮的点击信号也保存在场景中。

选中相应热点按钮，即可在 2D 编辑器中拖动或调整尺寸。所有热点和背景共用 1070 ×787 的 `RoomCanvas` 参考画布，`room_canvas_fit.gd` 在编辑器和运行时将整个画布等比缩放、居中，不会覆盖单个按钮的布局。教程描边会自动跟随真实按钮位置。

高亮的颜色、透明度、边框及状态文字样式位于 `themes/rovin_room_theme.tres`：`RovinHotspot` 管理 normal/hover/pressed/disabled 样式，`RovinStatusLabel` 管理字号和阴影。状态文字保留字号 25、阴影偏移 5；位置可以直接拖动 `Status`，提示窗口可编辑 `Message`。

楼梯默认隐藏且不可用，运行时由剧情进度控制。编辑其区域时可以选中 `StairsHotspot` 查看边框，或临时显示以调整布局。请保留这些节点的唯一名称和点击信号连接，它们是脚本的交互入口。

### 炼金 UI

固定布局已移入场景，打开 `scenes/AlchemyRoom.tscn` 后可直接在 2D 编辑器中查看和调整三层界面。`Margin/Columns` 的两侧 Spacer 和中间 ContentScroll 负责界面宽度，Page 下依次为标题、配方选择、配方说明、需求图标区、素材网格及底部操作区。

| 编辑内容 | 文件 |
| --- | --- |
| 主界面布局、返回/清空/炼金按钮 | `scenes/AlchemyRoom.tscn` |
| 配方箭头和下拉框 | `scenes/ui/alchemy/recipe_list_ui.tscn` |
| 单个素材需求图标、名称、进度 | `scenes/ui/alchemy/ingredient_slot_ui.tscn` |
| 素材标题、提示、滚动网格 | `scenes/ui/alchemy/ingredient_select_ui.tscn` |
| 单个可选素材格的尺寸和显示 | `scenes/ui/alchemy/material_cell_ui.tscn` |
| 空素材格 | `scenes/ui/alchemy/empty_material_cell.tscn` |
| 结果窗口尺寸及确认按钮 | `scenes/ui/alchemy/alchemy_result_ui.tscn` |
| 全局颜色、字号、边框、按钮状态及容器间距 | `themes/alchemy_theme.tres` |

双击组件场景可以独立设计。Theme 包含 `AlchemyTitle`、`AlchemySectionTitle`、`AlchemyIngredientSlot`、`AlchemyMaterialCell`、`AlchemyBackground` 类型变体，可分别调整标题、需求槽、素材格和背景。素材格的图标最大宽度位于 `AlchemyMaterialCell` 的 constants/icon_max_width。

主场景和网格中的 Preview 节点只用于编辑器布局预览，不代表真实库存。运行时先移除预览，再按配方与库存实例化需求槽和素材格；修改组件模板会影响运行时全部实例。模板默认图标、名称和数量会由实际物品数据覆盖。

脚本只负责数据刷新、事件处理和动态实例化，网格列数根据素材格的实际尺寸及 Theme 间距自适应。自定义信号仍由脚本连接，静态按钮及组件内部信号已保存在场景中。调整布局时请保留标记为唯一名称的节点名称（例如 RecipeList、IngredientSlots、StartAlchemy），它们是脚本引用入口。

## 验证

使用 Godot 4 编辑器可执行文件运行：

```text
godot --headless --path . --script res://tests/alchemy_test.gd
godot --headless --path . --script res://tests/alchemy_ui_test.gd
godot --headless --path . --script res://tests/alchemy_config_test.gd
godot --headless --path . --script res://tests/rovin_alchemy_test.gd
godot --headless --path . --script res://tests/rovin_entry_test.gd
godot --headless --path . --script res://tests/rovin_tutorial_test.gd
godot --headless --path . --script res://tests/rovin_tutorial_skip_test.gd
godot --headless --path . --script res://tests/alchemy_story_test.gd
godot --headless --path . --script res://tests/rovin_stairs_story_test.gd
godot --headless --path . --script res://tests/rovin_room_ui_test.gd
godot --headless --path . res://scenes/AlchemyRoom.tscn --quit-after 3
```

首次使用命令行时先执行 `godot --headless --editor --path . --import`，以生成脚本类缓存和图标导入文件。

核心及通用 UI 测试使用独立测试配方和背包，配置测试验证编辑器中的实际配方，房间测试从真实初始状态验证获取、往返场景、重复领取防护及清洗剂制作。

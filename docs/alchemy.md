# 简化炼金系统

## 运行

在 Godot 编辑器打开 `scenes/RovinRoom.tscn`，按 F6 体验探索到炼金的完整流程，也可从现有剧情进入房间。

1. 点击书柜，获得“清洗剂”配方。
2. 点击床头柜，获得清洗剂粉末 ×1。
3. 点击鞋柜、书桌、测算长桌，每处各获得清水 ×1。
4. 点击右上角炼金区域，界面只显示已经获取的配方。
5. 依次在粉末和三个清水需求槽中各选入一个素材，点击“开始炼金”。
6. 获得清洗剂 ×1，粉末和清水全部扣除，原有药草不变。

直接运行 `AlchemyRoom.tscn` 时，新的游戏会显示“尚未获取配方”，点击“返回房间”即可探索。房间各地点只能领取一次。点击房间炼金区域时，必须已经获取清洗剂配方，且实际背包具备粉末 ×1、清水 ×3；否则留在房间并提示未获得的配方或缺少的素材数量。

入口检查依据当前配方数据合并重复素材需求，并读取实际背包库存，不使用已领取地点数代替库存。已经搜过的素材若被其他系统消耗，仍会阻止进入；入口检查不会扣除物品，真正点击“开始炼金”时仍会再次验证和扣除素材。

奖励数据配置在 `RovinRoom` 根节点的 `found_recipe` 和 `material_rewards` 中。初始背包仍由 `data/items/catalog.tres` 的 `initial_inventory` 配置，目前保留药草 ×2，清水和粉末通过房间领取。

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
- `RecipeListUI`、`IngredientSlotUI`、`IngredientSelectUI`、`AlchemyResultUI`：各自负责配方列表、素材槽、素材选择和结果显示。

## 增加配方

1. 在物品目录中添加新的 `ItemData`，确保物品 ID 唯一。
2. 创建 `AlchemyRecipe` Resource，填写唯一 RecipeID、名称、描述、成品 ID/数量、图标和 `IngredientRequirement` 列表。
3. 将资源加入 `AlchemyRoom` 根节点的 `recipes` 数组。此数组是配方目录，UI 会筛选玩家已获取的配方。
4. 配置获取入口，例如将 `RovinRoom` 根节点的 `found_recipe` 指向该资源；其他事件可调用 `GameProgress.unlock_recipe(recipe_id)`。

配方和初始库存均在资源中配置，不需要修改 UI。新增物品请确保也加入目录；不存在的素材或成品 ID 会返回清晰错误。

其他系统应通过 `PlayerInventory.add_item/remove_item` 修改库存；炼金的消耗和产出通过 `exchange` 一次完成，成功只发出一次变化通知。当前流程同步执行，无随机成功率、品质或动画。

## 在编辑器中调整 UI

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
godot --headless --path . res://scenes/AlchemyRoom.tscn --quit-after 3
```

首次使用命令行时先执行 `godot --headless --editor --path . --import`，以生成脚本类缓存和图标导入文件。

核心及通用 UI 测试使用独立测试配方和背包，配置测试验证编辑器中的实际配方，房间测试从真实初始状态验证获取、往返场景、重复领取防护及清洗剂制作。

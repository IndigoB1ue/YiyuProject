# 背包窗口

在 RovinRoom 或播放 Dialogic timeline 时，点击右上角“背包 [I]”或按 I 打开。
再次按 I、Esc 或点击关闭按钮关闭。主菜单和普通炼金操作界面不显示入口。
窗口由 Autoload `InventoryUI` 共用，不会因切换场景创建第二份背包数据。

打开时只有左侧物品栏，选中物品后显示右侧图标和详情。
配方格子为灰色，其他物品格子为蓝色，配方排在前面。
同一 ItemID 叠放在一格并显示数量；配方和素材共用 200 格，五列排列，可以滚动到底部。
右侧配方详情从 AlchemyRecipe 读取所需素材，并合并重复的 ItemID，例如清水的三个槽显示为清水 ×3。
查看背包不会使用、丢弃或消耗物品。

## 在编辑器中修改

- `scenes/ui/inventory/inventory_ui.tscn`：左右面板、尺寸、详情框、入口和关闭按钮。
- `scenes/ui/inventory/inventory_slot_ui.tscn`：单个物品格子，图标和数量位置。
- `scenes/ui/inventory/inventory_requirement_ui.tscn`：配方详情中的素材图标和数量。
- `themes/alchemy_theme.tres`：`InventoryRecipeCell`、`InventoryMaterialCell`、`InventoryEmptyCell` 等样式。

## 添加物品与配方

物品仍在 `data/items/catalog.tres` 的 Items 中配置，初始数量在 Initial Inventory 中配置。
普通物品填写 ItemID、Display Name、Icon、Description 即可。
配方物品另外将 Alchemy Recipe 指向对应的配方资源，例如 `data/recipes/clear_potion.tres`。
它会自动使用灰色格子并显示配方所需素材，UI 不包含配方名称或素材列表的硬编码。
获得配方和解锁炼金配方仍由现有剧情/房间逻辑处理。

背包数据由 PlayerInventory 管理。Capacity 默认 200，同类物品增加数量不额外占格。
满格时拒绝新增物品类型；炼金会先计算扣除素材和增加成品后的最终格数，再一次性提交，失败不会扣素材。
当前数据在本次运行内保留，尚未接入存档。

## 在代码或 timeline 中打开

```gdscript
InventoryUI.open_inventory()
InventoryUI.close_inventory()
InventoryUI.toggle_inventory()
```

Dialogic Call 事件选择 Autoload `InventoryUI` 的 `open_inventory` 方法，无需参数。
在 timeline 文本模式中也可以写 `do InventoryUI.open_inventory()`。
打开时暂停游戏和 Dialogic，阻止底层点击、自动推进和快进；关闭时恢复打开前的暂停状态。
切换场景或 timeline 开始/结束时会自动关闭，避免暂停状态残留。

验证脚本：`tests/inventory_capacity_test.gd`、`tests/inventory_ui_test.gd`。

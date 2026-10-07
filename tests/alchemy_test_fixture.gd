extends RefCounted

## Test data is independent of editable gameplay recipes and starting inventory.
static func potion_recipe() -> AlchemyRecipe:
	var recipe := AlchemyRecipe.new()
	recipe.recipe_id = &"TestPotionRecipe"
	recipe.display_name = "回复药"
	recipe.result_item_id = &"Potion"
	recipe.result_amount = 1
	var herb := IngredientRequirement.new()
	herb.item_id = &"Herb"
	herb.amount = 2
	var water := IngredientRequirement.new()
	water.item_id = &"Water"
	water.amount = 1
	recipe.ingredients = [herb, water]
	return recipe

static func prepare_inventory(inventory: InventorySystem) -> void:
	for id in inventory.get_items():
		inventory.remove_item(id, inventory.get_amount(id))
	inventory.add_item(&"Herb", 5)
	inventory.add_item(&"Water", 3)

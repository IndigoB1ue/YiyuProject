@tool
class_name AlchemyCatalog
extends Resource

## Project recipes; player unlocks remain the responsibility of GameProgress.
@export var recipes: Array[AlchemyRecipe] = []

func find_recipe(recipe_id: StringName) -> AlchemyRecipe:
	for recipe in recipes:
		if recipe != null and recipe.recipe_id == recipe_id:
			return recipe
	return null

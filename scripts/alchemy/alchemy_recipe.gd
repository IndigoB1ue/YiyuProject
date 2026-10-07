class_name AlchemyRecipe
extends Resource

@export var recipe_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var result_item_id: StringName
@export_range(1, 999) var result_amount: int = 1
@export var ingredients: Array[IngredientRequirement] = []

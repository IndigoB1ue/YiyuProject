class_name RecipeListUI
extends HBoxContainer

signal recipe_selected(recipe: AlchemyRecipe)

var _recipes: Array[AlchemyRecipe] = []
@onready var _previous: Button = $Previous
@onready var _next: Button = $Next
@onready var _dropdown: OptionButton = $Dropdown

func _on_previous_pressed() -> void:
	cycle(-1)

func _on_next_pressed() -> void:
	cycle(1)

func display(recipes: Array[AlchemyRecipe]) -> void:
	_recipes.clear()
	_dropdown.clear()
	for recipe in recipes:
		if recipe == null:
			continue
		_recipes.append(recipe)
		_dropdown.add_item(recipe.display_name)
	_previous.disabled = _recipes.size() < 2
	_next.disabled = _recipes.size() < 2
	_dropdown.disabled = _recipes.is_empty()
	if _recipes.is_empty():
		_dropdown.add_item("暂无可用配方")
	else:
		select_recipe(0)

func select_recipe(index: int) -> void:
	if index < 0 or index >= _recipes.size():
		return
	_dropdown.select(index)
	recipe_selected.emit(_recipes[index])

func cycle(direction: int) -> void:
	if _recipes.size() > 1:
		select_recipe(posmod(_dropdown.selected + direction, _recipes.size()))

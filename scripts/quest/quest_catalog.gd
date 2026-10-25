@tool
class_name QuestCatalog
extends Resource

@export var quests: Array[QuestData] = []
@export var stories: Array[QuestStoryData] = []

func find_quest(id: StringName) -> QuestData:
	for quest in quests:
		if quest != null and quest.quest_id == id:
			return quest
	return null

func find_story(id: StringName) -> QuestStoryData:
	for story in stories:
		if story != null and story.story_id == id:
			return story
	return null

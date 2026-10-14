extends Button

signal slot_chosen(index: int)

var slot_index: int

@onready var _picture: TextureRect = $Margin/Content/Picture/Thumbnail
@onready var _empty: Label = $Margin/Content/Picture/Empty
@onready var _chapter: PanelContainer = $Margin/Content/Picture/Chapter
@onready var _chapter_label: Label = $Margin/Content/Picture/Chapter/Label
@onready var _caption: Label = $Margin/Content/Caption


func display(index: int, record: Dictionary) -> void:
	slot_index = index
	var saved: bool = record.state == "saved"
	_picture.texture = record.get("texture")
	_chapter.visible = saved
	_chapter_label.text = record.get("chapter", "")
	_empty.visible = _picture.texture == null
	_empty.text = "暂无截图" if saved else ("存档损坏" if record.state == "corrupt" else "NO DATA")
	_caption.text = "[%03d] %s\n游玩时长 %s" % [index, record.saved_at, record.play_time] if saved else "[%03d] %s" % [index, "存档损坏" if record.state == "corrupt" else "空存档"]
	tooltip_text = _caption.text
	set_pressed_no_signal(false)


func _on_pressed() -> void:
	slot_chosen.emit(slot_index)

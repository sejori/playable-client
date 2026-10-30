class_name FloatingRewardText
extends Node3D
## FloatingRewardText.gd
## 3D Floating dopamine feedback reward label (+500 Coins!).

@export var text: String = "+100 Coins!"
@export var float_speed: float = 2.0
@export var lifetime: float = 1.0

var _timer: float = 0.0
var _label: Label3D = null

func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = 48
	_label.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)

func _process(delta: float) -> void:
	global_position.y += float_speed * delta
	_timer += delta
	if _timer >= lifetime:
		queue_free()

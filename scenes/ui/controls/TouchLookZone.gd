extends Control
## TouchLookZone.gd
## Touch gesture zone capturing camera look drag gestures on mobile and handheld displays.

signal camera_look_dragged(relative: Vector2)

@export var sensitivity: float = 1.0

var touch_id: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			accept_event()
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_id:
		var delta_vec: Vector2 = event.relative * sensitivity
		camera_look_dragged.emit(delta_vec)
		accept_event()

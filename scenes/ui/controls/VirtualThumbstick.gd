extends Control
## VirtualThumbstick.gd
## On-screen virtual analog thumbstick supporting floating and fixed modes.
## Maps touch displacement to move_left, move_right, move_forward, move_back actions.

signal stick_moved(vector: Vector2)

@export var radius: float = 65.0
@export var deadzone: float = 0.15
@export var stick_mode: String = "floating" # "floating" or "fixed"

var touch_id: int = -1
var is_pressed: bool = false
var base_position: Vector2 = Vector2.ZERO
var knob_position: Vector2 = Vector2.ZERO
var current_vector: Vector2 = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(radius * 2.5, radius * 2.5)
	base_position = size * 0.5

func _draw() -> void:
	var draw_center: Vector2 = base_position if (is_pressed and stick_mode == "floating") else size * 0.5
	# Outer boundary ring
	draw_circle(draw_center, radius, Color(0.08, 0.12, 0.18, 0.45))
	draw_arc(draw_center, radius, 0.0, TAU, 36, Color(0.22, 0.74, 0.97, 0.6), 2.0)
	
	# Deadzone ring
	draw_arc(draw_center, radius * deadzone, 0.0, TAU, 24, Color(0.22, 0.74, 0.97, 0.25), 1.0)
	
	# Thumb knob
	var knob_center := draw_center + knob_position
	var knob_radius := radius * 0.42
	draw_circle(knob_center, knob_radius, Color(0.22, 0.74, 0.97, 0.75 if is_pressed else 0.5))
	draw_arc(knob_center, knob_radius, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, 0.9), 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			_start_touch(event.index, event.position)
			accept_event()
		elif not event.pressed and event.index == touch_id:
			_stop_touch()
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_id:
		_drag_touch(event.position)
		accept_event()

func _start_touch(idx: int, pos: Vector2) -> void:
	touch_id = idx
	is_pressed = true
	if stick_mode == "floating":
		base_position = pos
	else:
		base_position = size * 0.5
	_drag_touch(pos)
	queue_redraw()

func _drag_touch(pos: Vector2) -> void:
	var offset := pos - base_position
	var dist := offset.length()
	if dist > radius:
		offset = offset.normalized() * radius
	knob_position = offset
	
	var norm := knob_position / radius
	if norm.length() < deadzone:
		current_vector = Vector2.ZERO
		_release_actions()
	else:
		current_vector = norm
		_dispatch_actions(norm)
	
	stick_moved.emit(current_vector)
	queue_redraw()

func _stop_touch() -> void:
	touch_id = -1
	is_pressed = false
	knob_position = Vector2.ZERO
	current_vector = Vector2.ZERO
	_release_actions()
	stick_moved.emit(Vector2.ZERO)
	queue_redraw()

func _dispatch_actions(norm: Vector2) -> void:
	# X-axis (left/right)
	if norm.x < -deadzone:
		var strength := clampf((-norm.x - deadzone) / (1.0 - deadzone), 0.0, 1.0)
		Input.action_press("move_left", strength)
		Input.action_release("move_right")
	elif norm.x > deadzone:
		var strength := clampf((norm.x - deadzone) / (1.0 - deadzone), 0.0, 1.0)
		Input.action_press("move_right", strength)
		Input.action_release("move_left")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")

	# Y-axis (forward/back) - Note in screen coordinates: negative Y is UP / FORWARD
	if norm.y < -deadzone:
		var strength := clampf((-norm.y - deadzone) / (1.0 - deadzone), 0.0, 1.0)
		Input.action_press("move_forward", strength)
		Input.action_release("move_back")
	elif norm.y > deadzone:
		var strength := clampf((norm.y - deadzone) / (1.0 - deadzone), 0.0, 1.0)
		Input.action_press("move_back", strength)
		Input.action_release("move_forward")
	else:
		Input.action_release("move_forward")
		Input.action_release("move_back")

func _release_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_forward")
	Input.action_release("move_back")

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if stick_mode != "floating" or not is_pressed:
			base_position = size * 0.5
		queue_redraw()

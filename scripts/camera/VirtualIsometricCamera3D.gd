class_name VirtualIsometricCamera3D
extends VirtualCameraBase3D
## VirtualIsometricCamera3D.gd
## Fixed-tilt isometric camera with smooth player tracking and wheel zoom.
## Primary camera for Cartridge 2: Tick-Based Sandbox.

@export var tilt_degrees: float = 55.0
@export var yaw_degrees: float = 45.0
@export var distance: float = 18.0
@export var min_distance: float = 8.0
@export var max_distance: float = 32.0
@export var zoom_speed: float = 2.0
@export var rotate_speed: float = 0.05
@export var follow_offset: Vector3 = Vector3(0.0, 1.2, 0.0)

var _current_distance: float = 18.0
var _current_yaw: float = 45.0
var _is_middle_dragging: bool = false

func _ready() -> void:
	super._ready()
	_current_distance = distance
	_current_yaw = yaw_degrees

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_distance = clampf(_current_distance - zoom_speed, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_distance = clampf(_current_distance + zoom_speed, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_middle_dragging = event.pressed
	elif event is InputEventMouseMotion and _is_middle_dragging:
		_current_yaw += event.relative.x * rotate_speed

func get_desired_global_transform() -> Transform3D:
	var pivot: Vector3 = global_position + follow_offset
	if target != null and is_instance_valid(target):
		pivot = target.global_position + follow_offset

	var rot := Basis(Vector3.UP, deg_to_rad(_current_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-tilt_degrees))
	var cam_pos := pivot + (rot * (Vector3.BACK * _current_distance))
	return Transform3D(rot, cam_pos)

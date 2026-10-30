class_name VirtualTabletopCamera3D
extends VirtualCameraBase3D
## VirtualTabletopCamera3D.gd
## High-angle tactical camera with WASD/edge panning and smooth elevation zoom.
## Primary camera for Cartridge 4: 4X Strategy & Tabletop.

@export var tilt_degrees: float = 65.0
@export var pan_speed: float = 24.0
@export var elevation: float = 20.0
@export var min_elevation: float = 6.0
@export var max_elevation: float = 40.0
@export var zoom_speed: float = 3.0
@export var edge_pan_margin_px: float = 25.0
@export var edge_pan_enabled: bool = false

var pan_offset: Vector3 = Vector3.ZERO
var _current_elevation: float = 20.0

func _ready() -> void:
	super._ready()
	_current_elevation = elevation

func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_elevation = clampf(_current_elevation - zoom_speed, min_elevation, max_elevation)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_elevation = clampf(_current_elevation + zoom_speed, min_elevation, max_elevation)

func update_virtual_camera(delta: float) -> void:
	if not is_active:
		return
	var pan_input := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		pan_input.x -= 1.0
	if Input.is_action_pressed("move_right"):
		pan_input.x += 1.0
	if Input.is_action_pressed("move_forward"):
		pan_input.y -= 1.0
	if Input.is_action_pressed("move_back"):
		pan_input.y += 1.0

	if edge_pan_enabled:
		var vp := get_viewport()
		if vp != null:
			var m_pos := vp.get_mouse_position()
			var v_size := vp.get_visible_rect().size
			if m_pos.x <= edge_pan_margin_px:
				pan_input.x -= 1.0
			elif m_pos.x >= v_size.x - edge_pan_margin_px:
				pan_input.x += 1.0
			if m_pos.y <= edge_pan_margin_px:
				pan_input.y -= 1.0
			elif m_pos.y >= v_size.y - edge_pan_margin_px:
				pan_input.y += 1.0

	pan_input = pan_input.normalized()
	pan_offset.x += pan_input.x * pan_speed * delta
	pan_offset.z += pan_input.y * pan_speed * delta

func get_desired_global_transform() -> Transform3D:
	var base_pos: Vector3 = global_position + pan_offset
	if target != null and is_instance_valid(target):
		base_pos = target.global_position + pan_offset

	var rot := Basis(Vector3.RIGHT, deg_to_rad(-tilt_degrees))
	var cam_pos := base_pos + Vector3(0.0, _current_elevation, _current_elevation * 0.46)
	return Transform3D(rot, cam_pos)

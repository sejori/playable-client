class_name VirtualTurntableCamera3D
extends VirtualCameraBase3D
## VirtualTurntableCamera3D.gd
## Continuous 360° orbiting turntable showcase camera for vehicles, items, and arena vistas.

@export var orbit_speed_deg: float = 24.0
@export var radius: float = 12.0
@export var height: float = 4.5
@export var center_offset: Vector3 = Vector3(0.0, 1.0, 0.0)

var _angle: float = 0.0

func update_virtual_camera(delta: float) -> void:
	_angle += deg_to_rad(orbit_speed_deg * delta)
	if _angle > TAU:
		_angle -= TAU

func get_desired_global_transform() -> Transform3D:
	var center := global_position + center_offset
	if target != null and is_instance_valid(target):
		center = target.global_position + center_offset

	var cam_pos := center + Vector3(cos(_angle) * radius, height, sin(_angle) * radius)
	var forward := (center - cam_pos).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var basis := Basis(right, up, -forward)
	return Transform3D(basis, cam_pos)

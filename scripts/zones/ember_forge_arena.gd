class_name EmberForgeArena
extends Node3D

## EmberForgeArena controller with cinematic showcase orbit
var _camera: Camera3D = null
var _orbit_angle: float = 0.0

func _ready() -> void:
	_camera = get_node_or_null("MainCamera") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "MainCamera"
		_camera.current = true
		_camera.fov = 55.0
		add_child(_camera)
	_update_camera(0.0)

func _process(delta: float) -> void:
	_orbit_angle += delta * 0.22
	_update_camera(_orbit_angle)

func _update_camera(angle: float) -> void:
	if _camera == null:
		return
	var radius: float = 28.0
	var height: float = 12.0
	_camera.position = Vector3(sin(angle) * radius, height, cos(angle) * radius)
	_camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)

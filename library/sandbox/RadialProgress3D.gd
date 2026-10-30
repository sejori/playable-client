class_name RadialProgress3D
extends Node3D
## RadialProgress3D.gd
## 3D Billboard radial harvesting progress indicator displayed above resource nodes.

signal progress_completed()

@export var max_ticks: int = 4
@export var current_progress_ticks: int = 0
@export var billboard_offset: Vector3 = Vector3(0.0, 2.5, 0.0)

var _mesh: MeshInstance3D = null

func _ready() -> void:
	_create_indicator()
	update_progress(0)

func _create_indicator() -> void:
	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.4, 1.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	torus.material = mat
	_mesh.mesh = torus
	_mesh.position = billboard_offset
	add_child(_mesh)

func advance_tick() -> void:
	update_progress(current_progress_ticks + 1)

func update_progress(ticks: int) -> void:
	current_progress_ticks = ticks
	var ratio := clampf(float(current_progress_ticks) / float(max_ticks), 0.0, 1.0)
	visible = (current_progress_ticks > 0 and current_progress_ticks < max_ticks)

	if _mesh != null:
		var scale_val := 0.5 + ratio * 0.5
		_mesh.scale = Vector3(scale_val, scale_val, scale_val)

	if current_progress_ticks >= max_ticks:
		progress_completed.emit()
		current_progress_ticks = 0
		visible = false

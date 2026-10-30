class_name FPSLaserTracer
extends Node3D
## FPSLaserTracer.gd
## High-speed laser beam tracer effect for hitscan weapons.

@export var lifetime: float = 0.08
@export var beam_color: Color = Color(0.2, 0.9, 1.0, 1.0)
@export var beam_radius: float = 0.03

static func spawn_tracer(parent: Node, from: Vector3, to: Vector3, color: Color = Color(0.2, 0.9, 1.0, 1.0)) -> void:
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	var dist := from.distance_to(to)
	cyl.height = maxf(0.1, dist)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	cyl.material = mat

	mesh_inst.mesh = cyl
	var mid_point := (from + to) * 0.5
	mesh_inst.position = mid_point

	# Orient cylinder along line from -> to
	var dir := (to - from).normalized()
	if absf(dir.y) < 0.999:
		mesh_inst.look_at(to, Vector3.UP)
		mesh_inst.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		mesh_inst.rotate_x(PI * 0.5)

	parent.add_child(mesh_inst)

	# Auto-destroy after 80ms using scene tree timer
	parent.get_tree().create_timer(0.08).timeout.connect(func():
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
	)

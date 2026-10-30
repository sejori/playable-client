class_name ProximityMagnet
extends Area3D
## ProximityMagnet.gd
## Vacuum magnet trigger that attracts nearby collectible tokens toward the player.

@export var magnet_radius: float = 6.0
@export var pull_force: float = 18.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 4 # Layer 4: Interactable_Resource
	_setup_collider()

func _setup_collider() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		col = CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var sph := SphereShape3D.new()
		sph.radius = magnet_radius
		col.shape = sph
		add_child(col)

func _physics_process(delta: float) -> void:
	var parent_body := get_parent() as Node3D
	if parent_body == null:
		return
	var center := parent_body.global_position

	for body in get_overlapping_bodies():
		if body.is_in_group("collectible"):
			var dir := (center - body.global_position).normalized()
			body.global_position += dir * pull_force * delta

	for area in get_overlapping_areas():
		if area.is_in_group("collectible"):
			var dir := (center - area.global_position).normalized()
			area.global_position += dir * pull_force * delta

class_name ModularCharacter3D
extends CharacterBody3D
## ModularCharacter3D.gd
## Universal Avatar Controller (Layer 2) supporting swappable MoverComponentBase implementations.
## Supports ActionMover3D, ClickToMoveMover3D, VoxelMover3D, FPSMover3D, and VelocityRider3D.

@export var mover_path: NodePath
var active_mover: MoverComponentBase = null

func _ready() -> void:
	collision_layer = 2 # Layer 2: Player_Character
	collision_mask = 1 | 3 | 4 # Static Environment, Enemy Hitbox, Interactable
	_setup_default_collider()
	_resolve_mover()
	var puppet := get_node_or_null("/root/PuppetServer")
	if puppet != null and puppet.has_method("register_puppet_character"):
		puppet.call("register_puppet_character", self)

func _setup_default_collider() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.8
		col.shape = cap
		col.position = Vector3(0.0, 0.9, 0.0)
		add_child(col)

func _resolve_mover() -> void:
	if not mover_path.is_empty():
		active_mover = get_node_or_null(mover_path) as MoverComponentBase
	if active_mover == null:
		for child in get_children():
			if child is MoverComponentBase:
				active_mover = child
				break
	if active_mover == null:
		# Fallback to ActionMover3D
		active_mover = ActionMover3D.new()
		active_mover.name = "ActionMover3D"
		add_child(active_mover)

func set_mover(mover: MoverComponentBase) -> void:
	active_mover = mover

func _unhandled_input(event: InputEvent) -> void:
	if active_mover != null:
		active_mover.handle_input(event, self)

func _physics_process(delta: float) -> void:
	if active_mover != null:
		velocity = active_mover.compute_velocity(delta, velocity, self)
		active_mover.on_physics_step(delta, self)

	move_and_slide()

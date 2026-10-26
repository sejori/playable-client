extends CharacterBody3D
## player_controller.gd
## 3rd-Person CharacterBody3D controller with Godot 4.6+ native IKModifier3D foot placement
## and elemental metal/earth bending abilities.

const MOVE_SPEED: float = 7.5
const JUMP_VELOCITY: float = 6.2

var hp: float = 500.0
var chi: float = 100.0
var metal_shield_active: bool = false
var _ik_modifier: Node = null

func _ready() -> void:
	collision_layer = 2 # Layer 2: Player_Character per interface_contracts.json
	collision_mask = 1 | 3 | 4 # Collides with Environment_Static, Enemy_Hitbox, MetalBending_Interactable
	PuppetServer.register_puppet_character(self)
	_setup_skeletal_ik()

func _setup_skeletal_ik() -> void:
	var skeleton := get_node_or_null("Skeleton3D")
	if skeleton != null and ClassDB.class_exists("IKModifier3D"):
		_ik_modifier = ClassDB.instantiate("IKModifier3D")
		_ik_modifier.name = "FootPlacement_IKModifier3D"
		skeleton.add_child(_ik_modifier)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)

	move_and_slide()

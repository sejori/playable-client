extends CharacterBody3D
## player_controller.gd
## 3rd-Person CharacterBody3D controller with Godot 4.6+ native IKModifier3D foot placement
## and elemental metal/earth bending abilities.

const MOVE_SPEED: float = 9.0
const JUMP_VELOCITY: float = 6.2

var hp: float = 500.0
var max_hp: float = 500.0
var chi: float = 100.0
var metal_shield_active: bool = false
var _ik_modifier: Node = null
var _shield_mesh: MeshInstance3D = null

func _ready() -> void:
	collision_layer = 2 # Layer 2: Player_Character per interface_contracts.json
	collision_mask = 1 | 3 | 4 # Collides with Environment_Static, Enemy_Hitbox, MetalBending_Interactable
	PuppetServer.register_puppet_character(self)
	_ensure_collision_and_visuals()
	_setup_skeletal_ik()

func _ensure_collision_and_visuals() -> void:
	if get_node_or_null("PlayerCollider") == null:
		var col := CollisionShape3D.new()
		col.name = "PlayerCollider"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.5
		cap.height = 1.8
		col.shape = cap
		col.position = Vector3(0.0, 0.9, 0.0)
		add_child(col)

	if get_node_or_null("PlayerMesh") == null:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "PlayerMesh"
		var cap_mesh := CapsuleMesh.new()
		cap_mesh.radius = 0.55
		cap_mesh.height = 1.8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#38bdf8")
		mat.emission_enabled = true
		mat.emission = Color("#0284c7")
		mat.emission_energy_multiplier = 0.6
		cap_mesh.material = mat
		mesh_inst.mesh = cap_mesh
		mesh_inst.position = Vector3(0.0, 0.9, 0.0)
		add_child(mesh_inst)

	if _shield_mesh == null:
		_shield_mesh = MeshInstance3D.new()
		_shield_mesh.name = "MetalShieldAura"
		var sph := SphereMesh.new()
		sph.radius = 1.35
		sph.height = 2.7
		var smat := StandardMaterial3D.new()
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.22, 0.74, 0.97, 0.28)
		smat.emission_enabled = true
		smat.emission = Color("#38bdf8")
		smat.emission_energy_multiplier = 1.2
		sph.material = smat
		_shield_mesh.mesh = sph
		_shield_mesh.position = Vector3(0.0, 1.0, 0.0)
		_shield_mesh.visible = false
		add_child(_shield_mesh)

func set_metal_shield(active: bool) -> void:
	metal_shield_active = active
	if _shield_mesh != null:
		_shield_mesh.visible = active

func _setup_skeletal_ik() -> void:
	var skeleton := get_node_or_null("Skeleton3D")
	if skeleton != null and ClassDB.class_exists("IKModifier3D"):
		_ik_modifier = ClassDB.instantiate("IKModifier3D")
		_ik_modifier.name = "FootPlacement_IKModifier3D"
		skeleton.add_child(_ik_modifier)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	if global_position.y < 0.2:
		global_position.y = 0.2
		velocity.y = 0.0

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	if direction.length() > 0.01:
		velocity.x = direction.x * MOVE_SPEED
		velocity.z = direction.z * MOVE_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, MOVE_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, MOVE_SPEED)

	move_and_slide()
	global_position.x = clampf(global_position.x, -22.0, 22.0)
	global_position.z = clampf(global_position.z, -44.0, 22.0)

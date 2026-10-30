class_name FPSBotAI
extends CharacterBody3D
## FPSBotAI.gd
## Line-of-sight combat AI with tactical strafing, cover peeking, and hitscan engagement.

signal bot_eliminated()

@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var shoot_interval: float = 0.8
@export var detection_range: float = 35.0
@export var move_speed: float = 6.0

var target_enemy: Node3D = null
var _shoot_timer: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_timer: float = 1.2

func _ready() -> void:
	collision_layer = 3 # Layer 3: Enemy_Hitbox
	collision_mask = 1 | 2 # Environment & Player
	add_to_group("enemy_bot")
	current_health = max_health

func take_damage(amount: float, _hit_pos: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
	current_health -= amount
	if current_health <= 0.0:
		bot_eliminated.emit()
		queue_free()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 18.0 * delta

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.8, 1.8)
		_strafe_dir *= -1.0

	if target_enemy == null or not is_instance_valid(target_enemy):
		_find_target()

	if target_enemy != null and is_instance_valid(target_enemy):
		var to_target := target_enemy.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()

		if dist < detection_range:
			look_at(Vector3(target_enemy.global_position.x, global_position.y, target_enemy.global_position.z), Vector3.UP)
			var right := global_transform.basis.x
			velocity.x = right.x * move_speed * _strafe_dir * 0.7
			velocity.z = right.z * move_speed * _strafe_dir * 0.7

			_shoot_timer += delta
			if _shoot_timer >= shoot_interval:
				_shoot_timer = 0.0
				_fire_at_target()

	move_and_slide()

func _find_target() -> void:
	var players := get_tree().get_nodes_in_group("player_character")
	if not players.is_empty():
		target_enemy = players[0] as Node3D

func _fire_at_target() -> void:
	if target_enemy == null:
		return
	var eye_pos := global_position + Vector3(0.0, 1.5, 0.0)
	var target_pos := target_enemy.global_position + Vector3(0.0, 1.2, 0.0)
	FPSLaserTracer.spawn_tracer(get_parent(), eye_pos, target_pos, Color(1.0, 0.2, 0.2, 1.0))
	if target_enemy.has_method("take_damage"):
		target_enemy.call("take_damage", 15.0, target_pos, Vector3.UP)

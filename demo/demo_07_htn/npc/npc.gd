extends CharacterBody3D

signal player_nearby_changed(is_nearby: bool)
signal scared
signal tired
signal coin_cooldown_changed(is_active: bool)

const Player = preload("res://demo_07_htn/objects/player.gd")

const SCARE_DISTANCE := 3.0
const SCARES_BEFORE_TIRED := 3
const FALL_LIMIT := -10.0
const STOP_DISTANCE := 0.1

@export var movement_speed: float = 4.0
@export var jump_strength: float = 7.0
@export var coin_cooldown_min: float = 3.0
@export var coin_cooldown_max: float = 10.0

var player_in_sight: Player

var _movement_velocity := Vector3.ZERO
var _rotation_direction: float
var _gravity: float = 0.0
var _previously_floored: bool = false
var _scares: int = 0
var _spawn_position: Vector3

@onready var particles_trail: CPUParticles3D = $ParticlesTrail
@onready var rest_particles: CPUParticles3D = $RestParticle
@onready var sound_footsteps: AudioStreamPlayer3D = $SoundFootsteps
@onready var sound_land: AudioStreamPlayer3D = $SoundLand
@onready var sound_coin: AudioStreamPlayer3D = $SoundCoin
@onready var model: Node3D = $Character
@onready var animation: AnimationPlayer = $Character/AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent


func _ready() -> void:
	_spawn_position = position
	_rotation_direction = rotation.y


func _physics_process(delta: float) -> void:
	_gravity += 25 * delta
	if _gravity > 0 and is_on_floor():
		_gravity = 0
	_handle_effects()

	var applied_velocity: Vector3 = velocity.lerp(_movement_velocity, delta * 10)
	applied_velocity.y = -_gravity
	velocity = applied_velocity
	move_and_slide()

	if Vector2(velocity.z, velocity.x).length() > 0.1:
		_rotation_direction = Vector2(velocity.z, velocity.x).angle()
	rotation.y = lerp_angle(rotation.y, _rotation_direction, delta * 10)

	if position.y < FALL_LIMIT:
		position = _spawn_position
		_gravity = 0

	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)
	if is_on_floor() and _gravity > 2 and not _previously_floored:
		model.scale = Vector3(1.25, 0.75, 1.25)
		sound_land.play()
	_previously_floored = is_on_floor()


func _handle_effects() -> void:
	var is_walking: bool = is_on_floor() and (abs(velocity.x) > 1 or abs(velocity.z) > 1)
	particles_trail.emitting = is_walking
	if is_walking and not sound_footsteps.playing:
		sound_footsteps.play()
	elif not is_walking:
		sound_footsteps.stop()

	if not is_on_floor():
		animation.play("jump", 0.5)
	elif is_walking:
		animation.play("walk", 0.5)
	else:
		animation.play("idle", 0.5)


func walk_towards(destination: Vector3) -> void:
	if not navigation_agent.target_position.is_equal_approx(destination):
		navigation_agent.target_position = destination
	var direction := navigation_agent.get_next_path_position() - global_position
	direction.y = 0
	# The path ends short of an off-mesh destination; stand still there instead of jittering.
	if direction.length() < STOP_DISTANCE:
		stop()
		return
	_movement_velocity = direction.normalized() * movement_speed


func closest_reachable_point(destination: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if not has_navigation_at(map, destination):
		return destination
	return NavigationServer3D.map_get_closest_point(map, destination)


static func has_navigation_at(map: RID, point: Vector3) -> bool:
	# Querying a map before its first sync is an engine error, and an empty map answers the origin.
	return NavigationServer3D.map_get_iteration_id(map) != 0 and NavigationServer3D.map_get_closest_point_owner(map, point).is_valid()


func stop() -> void:
	_movement_velocity = Vector3.ZERO


func face(point: Vector3) -> void:
	var direction := point - position
	_rotation_direction = Vector2(direction.z, direction.x).angle()


func jump() -> void:
	_gravity = -jump_strength
	model.scale = Vector3(0.5, 1.5, 0.5)


func relax() -> void:
	if _scares >= SCARES_BEFORE_TIRED:
		_scares = 0
		tired.emit()


func set_resting(is_resting: bool) -> void:
	rest_particles.emitting = is_resting


func collect_coin() -> void:
	sound_coin.play()
	coin_cooldown_changed.emit(true)
	await get_tree().create_timer(randf_range(coin_cooldown_min, coin_cooldown_max)).timeout
	coin_cooldown_changed.emit(false)


func _on_player_jumped() -> void:
	if position.distance_to(player_in_sight.position) < SCARE_DISTANCE:
		_scares += 1
		scared.emit()


func _on_player_detection_sensor_body_entered(body: Node3D) -> void:
	player_in_sight = body as Player
	player_in_sight.jumped.connect(_on_player_jumped)


func _on_player_detection_sensor_body_exited(_body: Node3D) -> void:
	player_in_sight.jumped.disconnect(_on_player_jumped)
	player_in_sight = null


func _on_close_range_sensor_body_entered(_body: Node3D) -> void:
	player_nearby_changed.emit(true)


func _on_close_range_sensor_body_exited(_body: Node3D) -> void:
	player_nearby_changed.emit(false)

extends CharacterBody3D

signal jumped

@export_subgroup("Components")
@export var view: Node3D

@export_subgroup("Properties")
@export var movement_speed: float = 250.0
@export var jump_strength: float = 7.0

var movement_velocity: Vector3
var rotation_direction: float
var gravity: float = 0.0

var previously_floored: bool = false

var jump_single: bool = true
var jump_double: bool = true

@onready var particles_trail: CPUParticles3D = $ParticlesTrail
@onready var sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var sound_jump: AudioStreamPlayer = $SoundJump
@onready var sound_land: AudioStreamPlayer = $SoundLand
@onready var sound_coin: AudioStreamPlayer = $SoundCoin
@onready var model: Node3D = $Character
@onready var animation: AnimationPlayer = $Character/AnimationPlayer


func _physics_process(delta: float) -> void:
	handle_controls(delta)
	handle_gravity(delta)
	handle_effects()

	var applied_velocity: Vector3 = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity

	velocity = applied_velocity
	move_and_slide()

	if Vector2(velocity.z, velocity.x).length() > 0:
		rotation_direction = Vector2(velocity.z, velocity.x).angle()

	rotation.y = lerp_angle(rotation.y, rotation_direction, delta * 10)

	if position.y < -10:
		get_tree().reload_current_scene()

	model.scale = model.scale.lerp(Vector3(1, 1, 1), delta * 10)

	if is_on_floor() and gravity > 2 and not previously_floored:
		model.scale = Vector3(1.25, 0.75, 1.25)
		sound_land.play()

	previously_floored = is_on_floor()


func handle_effects() -> void:
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


func handle_controls(delta: float) -> void:
	var input := Vector3.ZERO

	input.x = Input.get_axis("move_left", "move_right")
	input.z = Input.get_axis("move_forward", "move_back")

	input = input.rotated(Vector3.UP, view.rotation.y).normalized()

	movement_velocity = input * movement_speed * delta

	if Input.is_action_just_pressed("jump"):
		if jump_single or jump_double:
			sound_jump.play()

		if jump_double:
			gravity = -jump_strength
			jump_double = false
			model.scale = Vector3(0.5, 1.5, 0.5)

		if jump_single:
			jump()


func handle_gravity(delta: float) -> void:
	gravity += 25 * delta

	if gravity > 0 and is_on_floor():
		jump_single = true
		gravity = 0


func jump() -> void:
	gravity = -jump_strength

	model.scale = Vector3(0.5, 1.5, 0.5)

	jump_single = false
	jump_double = true

	jumped.emit()


func collect_coin() -> void:
	sound_coin.play()

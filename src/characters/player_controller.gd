class_name PlayerController
extends CharacterBody3D
## Third person. The player is the woman, and the camera is on a spring arm so
## her drawn figure is on screen the whole time — which is what justifies the
## customization feature existing at all (plan §11.2).
##
## No run. An old woman in her husband's memory does not sprint down a gallery,
## and a sprint key would undercut every other pacing decision in the game.

const WALK_SPEED := 1.70
const SLOW_SPEED := 0.75
const ACCELERATION := 7.0
const FRICTION := 9.0
const TURN_RATE := 9.0

const ARM_LENGTH := 3.6
const ARM_HEIGHT := 1.35
const CAMERA_PITCH := -8.0
const MOUSE_SENSITIVITY := 0.0022

## While examining a photograph the camera eases to a framing position rather
## than cutting, and movement is locked out.
const EXAMINE_BLEND := 4.0

var figure: PixelFigure = null
var camera: Camera3D = null

var _arm: SpringArm3D = null
var _yaw_pivot: Node3D = null
var _yaw := 0.0
var _examining := false
var _examine_target := Transform3D.IDENTITY
var _walk_phase := 0.0


func _ready() -> void:
	_build_body()
	_build_camera()
	_build_figure()


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.55
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.775, 0)
	add_child(col)


func _build_camera() -> void:
	_yaw_pivot = Node3D.new()
	_yaw_pivot.name = "YawPivot"
	_yaw_pivot.position = Vector3(0, ARM_HEIGHT, 0)
	add_child(_yaw_pivot)

	_arm = SpringArm3D.new()
	_arm.name = "SpringArm"
	_arm.spring_length = ARM_LENGTH
	_arm.margin = 0.3
	# Collision-aware: the arm shortens rather than clipping through a wall,
	# which matters even in a nine-metre hall when she walks close to a wall.
	_arm.collision_mask = 1
	_arm.rotation_degrees = Vector3(CAMERA_PITCH, 0, 0)
	_yaw_pivot.add_child(_arm)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 62.0
	_arm.add_child(camera)


func _build_figure() -> void:
	figure = PixelFigure.new()
	figure.name = "Figure"
	add_child(figure)
	figure.build()


func _unhandled_input(event: InputEvent) -> void:
	if _examining:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY


func _physics_process(delta: float) -> void:
	if _examining:
		_blend_to_examine(delta)
		_animate_walk(delta)
		return

	var input := Input.get_vector(&"move_left", &"move_right",
		&"move_forward", &"move_back")
	var speed := SLOW_SPEED if Input.is_action_pressed(&"walk_slow") else WALK_SPEED

	# Movement is camera-relative, which is the only thing that feels right in
	# third person.
	var basis := Basis(Vector3.UP, _yaw)
	var wish := (basis * Vector3(input.x, 0.0, input.y)).normalized()

	if wish.length_squared() > 0.01:
		velocity.x = move_toward(velocity.x, wish.x * speed, ACCELERATION * delta)
		velocity.z = move_toward(velocity.z, wish.z * speed, ACCELERATION * delta)
		# Face the direction of travel.
		var target_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, TURN_RATE * delta)
		_walk_phase += delta * speed * 5.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)
		_walk_phase = lerp(_walk_phase, 0.0, delta * 4.0)

	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	_yaw_pivot.rotation.y = _yaw - rotation.y
	_animate_walk(delta)
	move_and_slide()


## A drawn figure has no joints, so the gait is a bob and a lean rather than
## swinging limbs — and the sprite has to be turned toward the camera each
## frame or she reads as a card seen edge-on.
func _animate_walk(delta: float) -> void:
	if figure == null:
		return
	figure.animate_walk(delta, Vector2(velocity.x, velocity.z).length())
	if camera != null:
		figure.update_view_for_camera(camera.global_position)


# --- examine mode ---

## Ease the camera to a framing position in front of a photograph. Called by
## the round controller when she engages a frame.
func begin_examine(frame_transform: Transform3D) -> void:
	_examining = true
	var forward := frame_transform.basis.z.normalized()
	_examine_target = Transform3D(
		Basis.looking_at(-forward, Vector3.UP),
		frame_transform.origin + forward * 2.6 + Vector3(0, -0.25, 0))


func end_examine() -> void:
	_examining = false


func is_examining() -> bool:
	return _examining


func _blend_to_examine(delta: float) -> void:
	velocity = Vector3.ZERO
	var current := camera.global_transform
	camera.global_transform = current.interpolate_with(
		_examine_target, clampf(EXAMINE_BLEND * delta, 0.0, 1.0))

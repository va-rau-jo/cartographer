extends RefCounted
## The camera, and the one rule about it: SpringArm3D rewrites its children's
## transforms every physics frame from its own raycast, so ANYTHING that wants
## to aim the camera has to take it off the arm first.
##
## The ending learned that the hard way and documented it. Examine mode did
## not, so engaging a photograph only ever changed where the camera LOOKED —
## she stood five metres away and the view swung round to stare at the wall.
## These assertions are structural, so they need no physics frames: the camera
## is either a child of the arm or it is not.

var _holder: Node = null


func run() -> TestFramework:
	var t := TestFramework.new("camera")

	_holder = Node.new()
	_holder.name = "CameraTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	_test_examine(t)
	_test_cutscene(t)
	_test_examine_then_cutscene(t)

	_holder.get_parent().remove_child(_holder)
	_holder.free()
	_holder = null
	return t


func _player() -> PlayerController:
	var player := PlayerController.new()
	_holder.add_child(player)
	player.global_position = Vector3.ZERO
	return player


## Somewhere on the right-hand wall, facing into the hall.
func _frame_at(x: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(x, 1.9, z))


func _test_examine(t: TestFramework) -> void:
	var player := _player()
	var arm: SpringArm3D = player._arm
	t.ok(player.camera.get_parent() == arm,
		"the camera walks the hall on the arm")

	player.begin_examine(_frame_at(4.5, -3.4))
	t.ok(player.is_examining(), "she is examining")
	t.ok(player.camera.get_parent() != arm,
		"and the camera has come OFF the arm, or the blend below is undone"
			+ " every physics frame")
	t.ok(player.camera.get_parent() == player.get_parent(),
		"onto whatever the player hangs from")

	# The blend now moves the camera in space as well as in rotation. Run it
	# to convergence by hand: _physics_process needs physics frames, this does
	# not.
	for _i in 60:
		player._blend_to_examine(0.05)
	var target: Transform3D = player._examine_target
	t.lt(player.camera.global_position.distance_to(target.origin), 0.05,
		"the camera reaches the framing position (%.2f m away)"
			% player.camera.global_position.distance_to(target.origin))
	t.gt(float(player.camera.global_basis.z.dot(target.basis.z)), 0.99,
		"and is pointing the same way")

	# It really is in front of the photograph rather than behind her.
	t.lt(absf(player.camera.global_position.x - 4.5) - 2.6, 0.2,
		"which is about two and a half metres out from the wall")

	# Coming back: it eases to the arm's own pose and then the arm takes it.
	player.end_examine()
	t.ok(not player.is_examining(), "she stops examining")
	t.ok(player._returning, "and the camera is on its way back")
	t.ok(player.camera.get_parent() != arm,
		"not handed over while it is still two metres out")

	var ticks := 0
	while player._returning and ticks < 400:
		player._blend_back(0.05)
		ticks += 1
	t.lt(float(ticks) * 0.05, 6.0,
		"it gets back in a couple of seconds (%.1f s)" % (float(ticks) * 0.05))
	t.ok(player.camera.get_parent() == arm, "and the arm has it again")
	t.ok(player.camera.transform.origin.is_equal_approx(
		Vector3(0.0, 0.0, arm.get_hit_length()))
		or player.camera.transform == Transform3D.IDENTITY,
		"at the length the arm expects")
	t.ok(not player._returning, "and nothing is still blending")

	# A second end_examine is harmless.
	player.end_examine()
	t.ok(player.camera.get_parent() == arm, "ending it twice changes nothing")

	player.get_parent().remove_child(player)
	player.free()


func _test_cutscene(t: TestFramework) -> void:
	var player := _player()
	var arm: SpringArm3D = player._arm

	player.begin_cutscene()
	t.ok(player.is_in_cutscene(), "the ending has her")
	t.ok(player.camera.get_parent() != arm, "and the camera is off the arm")

	# The ending writes the camera directly; nothing may undo it.
	var framed := Transform3D(Basis(Vector3.UP, 0.6), Vector3(2.0, 1.3, -4.0))
	player.camera.global_transform = framed
	player._physics_process(0.05)
	t.ok(player.camera.global_transform.origin.is_equal_approx(framed.origin),
		"a frame of physics does not move it")

	player.end_cutscene()
	t.ok(not player.is_in_cutscene(), "control comes back")
	t.ok(player.camera.get_parent() == arm, "and so does the arm's camera")

	player.get_parent().remove_child(player)
	player.free()


## The ending can start while she is stood at a photograph, and it must win.
func _test_examine_then_cutscene(t: TestFramework) -> void:
	var player := _player()
	var arm: SpringArm3D = player._arm

	player.begin_examine(_frame_at(4.5, -3.4))
	player.begin_cutscene()
	t.ok(not player.is_examining(), "the cutscene ends the examine")
	t.ok(not player._returning, "and cancels the return blend")
	t.ok(player.camera.get_parent() != arm, "the camera stays off the arm")

	# end_examine during a cutscene must not hand the camera back mid-shot.
	player._examining = true
	player.end_examine()
	t.ok(not player._returning,
		"ending an examine inside a cutscene starts no blend")
	t.ok(player.camera.get_parent() != arm,
		"and does not give the camera back to the arm")

	player.get_parent().remove_child(player)
	player.free()

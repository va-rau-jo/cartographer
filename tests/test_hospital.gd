extends RefCounted
## The opening scene: the room, the man in the bed, and the transition.
##
## Two of these assertions exist because of bugs a render caught and no number
## would have:
##
##   * the head on the pillow drew nothing at all, because the pixel-plotting
##     lambdas wrote to a copy of the canvas (see resting_head.gd);
##   * it was then twice life size, and square instead of longer than wide.
##
## So the head is checked for geometry, for scale in metres, and for sitting on
## the pillow rather than floating above it or sinking into the mattress.

var _holder: Node3D = null
var _scene: Node3D = null


func run() -> TestFramework:
	var t := TestFramework.new("hospital")

	_holder = Node3D.new()
	_holder.name = "HospitalTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	_test_resting_head(t)
	_test_room(t)
	_test_timeline(t)

	_teardown()
	return t


func _teardown() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null


# ------------------------------------------------------------------- head

func _test_resting_head(t: TestFramework) -> void:
	var head := RestingHead.new()
	_holder.add_child(head)
	head.build(PixelFigure.Palette.for_trousers())

	# The lambda bug: a head that draws nothing leaves an empty bed.
	t.gt(float(head.filled_pixels()), 100.0,
		"the head is actually drawn (%d px)" % head.filled_pixels())
	t.gt(float(head.total_triangles()), 0.0, "and produces geometry")

	var size := head.size_metres()
	t.close(size.x, 0.23, 0.05, "a head's width across the bed")
	t.close(size.y, 0.29, 0.06, "and its length along it")
	t.gt(size.y, size.x, "seen from above, a head is longer than it is wide")

	var mesh: MeshInstance3D = head.get_node_or_null("Drawing")
	t.ok(mesh != null, "the head has a mesh")
	if mesh != null:
		# Laid flat: the drawing's own height must end up along Z, not Y.
		var aabb := mesh.mesh.get_aabb()
		t.gt(aabb.size.y, aabb.size.x, "the drawing itself stands up…")
		t.close(absf(mesh.rotation_degrees.x), 90.0, 0.1,
			"…and is then laid down on the pillow")

	head.get_parent().remove_child(head)
	head.free()


# ------------------------------------------------------------------- room

func _test_room(t: TestFramework) -> void:
	_scene = load("res://src/hospital/hospital_scene.gd").new()
	_scene.name = "Hospital"
	_holder.add_child(_scene)

	t.eq(GameState.phase, GameState.Phase.HOSPITAL,
		"entering the scene sets the phase")

	var meshes := _scene.find_children("*", "MeshInstance3D", true, false)
	t.gt(float(meshes.size()), 20.0,
		"the room is furnished (%d meshes)" % meshes.size())

	var lights := _scene.find_children("*", "Light3D", true, false)
	t.gt(float(lights.size()), 2.0,
		"and lit from more than one place (%d lights)" % lights.size())
	# The clerestory acne lesson: every shadow-casting light in the project
	# needs a bias above the engine default.
	for light in lights:
		var l: Light3D = light
		if l.shadow_enabled:
			t.gt(l.shadow_bias, 0.031,
				"%s carries a raised shadow bias" % l.name)

	t.ok(_scene.get_node_or_null("RestingHead") != null,
		"there is someone in the bed")
	t.ok(_scene.get_node_or_null("Her") != null, "and she is at his side")
	t.ok(_scene.get_node_or_null("Camera") != null, "the scene has its camera")

	# She stands beside the bed, not in it.
	var her: Node3D = _scene.get_node("Her")
	var head: Node3D = _scene.get_node("RestingHead")
	t.gt(her.global_position.x, head.global_position.x,
		"she is on the near side of the bed")
	t.gt(her.global_position.distance_to(head.global_position), 0.5,
		"at arm's length, not on top of him")

	# The head rests on the pillow: a few centimetres above the mattress top,
	# and below the side rail.
	t.gt(head.global_position.y, 0.60, "his head is up on the pillow")
	t.lt(head.global_position.y, 0.90, "and not hovering over the bed")


# --------------------------------------------------------------- timeline

func _test_timeline(t: TestFramework) -> void:
	if _scene == null:
		return

	t.eq(_scene._stage, _scene.Stage.DARK, "it opens in the dark")

	var exposure_at_start: float = _scene._env.tonemap_exposure

	# Up out of black, into the hold.
	for _i in 80:
		_scene._process(0.05)
	t.eq(_scene._stage, _scene.Stage.HOLD, "it fades up to the hold")
	t.ok(not _scene._prompt.text.is_empty(),
		"and asks her to take his hand")

	# Taking his hand starts the light rising.
	_scene._begin_rise()
	t.eq(_scene._stage, _scene.Stage.RISE, "taking his hand starts the rise")

	for _i in 40:
		_scene._process(0.05)
	t.gt(_scene._env.tonemap_exposure, exposure_at_start * 1.4,
		"the room is brighter than it was")
	t.ok(_scene._prompt.text.is_empty(), "the prompt is gone")

	# Deliberately not driven to the end: the last step changes scene, and a
	# test that swaps the running scene out from under the suite is a bad idea.
	t.lt(float(_scene._clock), _scene.RISE_TIME + 1.0,
		"the rise is a handful of seconds, not a minute")

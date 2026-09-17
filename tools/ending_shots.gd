extends Node
## The body of tools/render_ending.gd, as a Node.
##
## It lives in its own file for one reason: a script passed to `--script` is
## compiled BEFORE the project's autoloads are registered as GDScript globals,
## so it cannot name GameState or EventBus. A Node added to the root can.
## Same reason tests/test_host.gd exists.
##
## Separate from render_shots.gd because this one has to drive time: the ending
## is a stage machine, so the interesting frames are at particular moments
## inside it rather than at particular camera positions. It fakes a finished
## session, starts the ending, and photographs it as it plays.
##
## This is the only way to check the drawn embrace. Every previous character
## bug — hips below the leg length, a jagged ring around the head, sprites
## overlapping into one slab — was invisible in the numbers and obvious in a
## picture.

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(960, 540)
const WARMUP_FRAMES := 10

## Seconds into the ending at which to take each frame.
const MOMENTS := [
	{"at": 0.6, "name": "10_ending_walk",
	 "note": "She starts down the last stretch; the camera swings to the side."},
	{"at": 3.4, "name": "11_ending_settle",
	 "note": "She has arrived and turned to him, still two separate figures."},
	{"at": 6.2, "name": "12_ending_embrace",
	 "note": "THE DRAWN PAIR: one sprite, both palettes, lit by the hall."},
	{"at": 8.4, "name": "13_ending_fade",
	 "note": "The light rising through the embrace."},
	{"at": 13.5, "name": "14_results",
	 "note": "The results screen: ten lines, a total, and a way back."},
]


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var root_window := get_window()
	root_window.size = SHOT_SIZE

	var script := load("res://src/mansion/gallery.gd") as GDScript
	if script == null or not script.can_instantiate():
		print("gallery.gd did not compile")
		get_tree().quit(3)
		return
	var gallery: Node3D = script.new()
	gallery.name = "Gallery"
	root_window.add_child(gallery)

	for _i in WARMUP_FRAMES:
		await get_tree().process_frame

	_fake_a_finished_session(gallery)

	# Straight to the ending, the way RoundController._finish_round would.
	GameState.phase = GameState.Phase.ENDING
	EventBus.session_completed.emit(GameState.total_score())
	EventBus.ending_started.emit()

	var written: PackedStringArray = PackedStringArray()
	var elapsed := 0.0
	var moment := 0

	# Real frames, real deltas: the sequence runs on _process like it does in
	# the game, so what is photographed is what a player would see.
	while moment < MOMENTS.size() and elapsed < 40.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if elapsed < float(MOMENTS[moment]["at"]):
			continue

		var img := root_window.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, MOMENTS[moment]["name"]]
		if img.save_png(path) == OK:
			written.append(path)
			print("  %-20s  t=%5.1fs  %s"
				% [MOMENTS[moment]["name"], elapsed, MOMENTS[moment]["note"]])
		moment += 1

	# One close shot of the drawing itself, from a camera of our own so the
	# ending's framing is not the thing being judged. Taken after the fade, so
	# the fade rectangle is lifted first.
	var close := await _close_up(gallery, root_window)
	if not close.is_empty():
		written.append(close)
		print("  %-20s  %s" % ["15_embrace_close",
			"Close on the drawn pair: does the pose read as an embrace?"])

	print("")
	print("ending stage   %d (4 = fade, 5 = done)" % gallery.ending.stage())
	var embrace: EmbraceFigure = gallery.get_node_or_null("Embrace")
	if embrace != null:
		print("embrace tris   %d, drawn pixels %d, canvas %dx%d"
			% [embrace.total_triangles(), embrace.filled_pixels(),
			   EmbraceFigure.CANVAS_WIDTH, EmbraceFigure.CANVAS_HEIGHT])
		var mesh: MeshInstance3D = embrace.get_node_or_null("Body/Drawing")
		if mesh != null:
			var aabb := mesh.mesh.get_aabb()
			print("embrace size   %.2f x %.2f x %.2f m"
				% [aabb.size.x, aabb.size.y, aabb.size.z])
	else:
		print("embrace        NOT PRESENT — the hug never staged")
	print("total score    %.0f over %d rounds"
		% [GameState.total_score(), GameState.photos_played()])
	print("")
	print("wrote %d shots to %s"
		% [written.size(), ProjectSettings.globalize_path(OUT_DIR)])

	get_tree().quit(0 if written.size() >= MOMENTS.size() else 1)


## Close on the pair, with the ending's fade and the results screen hidden so
## the drawing is all that is being looked at.
func _close_up(gallery: Node3D, window: Window) -> String:
	var embrace: EmbraceFigure = gallery.get_node_or_null("Embrace")
	if embrace == null:
		return ""

	for layer in gallery.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false

	var cam := Camera3D.new()
	cam.name = "CloseCamera"
	window.add_child(cam)
	cam.fov = 40.0
	var at := embrace.global_position
	# Just off the axis they are standing on, at chest height, two metres out.
	cam.position = at + Vector3(1.75, 1.15, 1.25)
	cam.look_at(at + Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	for _i in 4:
		await get_tree().process_frame
		embrace.face_camera(cam.global_position)

	var path := "%s/15_embrace_close.png" % OUT_DIR
	var img := window.get_texture().get_image()
	return path if img.save_png(path) == OK else ""


## Ten plausible rounds, so the results screen has something to show and the
## ending fires for the right reason.
func _fake_a_finished_session(gallery: Node3D) -> void:
	# Stand her where play would actually leave her. The tenth photograph hangs
	# in the last bay, so when the ending fires she is a few metres from him —
	# not twenty-four, which is what the far end of an untouched hall gives and
	# which made the walk read as a hike.
	gallery.player.global_position = gallery.companion.global_position \
		+ Vector3(1.4, 0.0, 4.2)

	var count: int = gallery.frames.size()
	GameState.reset_for_album(count)
	for i in count:
		var hit := i % 3 == 0
		GameState.results[i] = {
			"total_score": 6400.0 if hit else 1250.0 + float(i) * 90.0,
			"distance_km": 0.3 if hit else 120.0 + float(i) * 210.0,
			"year_error": 0 if hit else 1 + i % 5,
			"guess_label": "Somewhere %d" % (i + 1),
			"guess_date_label": "%d" % (1958 + i * 5),
			"hints_used": 0 if hit else i % 4,
			"unblur_tier": 0 if hit else i % 3,
		}
		GameState.unblur_tiers[i] = int(GameState.results[i]["unblur_tier"])

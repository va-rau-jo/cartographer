extends RefCounted
## The ending, the results screen, and the two new pieces they lean on: the
## drawn embrace and the reusable scene fade.
##
## All four are time-driven rather than input-driven, which makes them testable
## headlessly: nothing here waits for a frame or a keypress, it just calls
## _process() with a known delta. That is the reason the sequence was written
## as an explicit stage machine instead of a chain of awaits.

const PLACES := [
	[43.7696, 11.2558, "Florence, Italy"],
	[54.4858, -0.6206, "Whitby, England"],
	[64.1466, -21.9426, "Reykjavik, Iceland"],
	[35.0116, 135.7681, "Kyoto, Japan"],
	[38.7223, -9.1393, "Lisbon, Portugal"],
]

var _holder: Node3D = null


func run() -> TestFramework:
	var t := TestFramework.new("ending")

	_holder = Node3D.new()
	_holder.name = "EndingTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	_test_embrace(t)
	_test_scene_fade(t)
	_test_sequence(t)
	_test_sequence_without_figures(t)
	_test_results(t)
	_test_closing_line_roundtrip(t)

	_teardown()
	return t


func _teardown() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null


# ------------------------------------------------------------- the drawing

func _test_embrace(t: TestFramework) -> void:
	var e := EmbraceFigure.new()
	_holder.add_child(e)
	e.build(PixelFigure.Palette.new(), PixelFigure.Palette.for_trousers())

	t.gt(float(e.total_triangles()), 0.0, "the embrace produces geometry")
	# A pair of figures fills far more of the canvas than one would, but must
	# not fill it solid — the silhouette is what makes it read as two people.
	var filled := e.filled_pixels()
	t.gt(float(filled), 700.0, "the drawing is substantial (%d px)" % filled)
	t.lt(float(filled), float(EmbraceFigure.CANVAS_WIDTH
		* EmbraceFigure.CANVAS_HEIGHT) * 0.72,
		"the drawing is not a solid block (%d px)" % filled)

	var mesh: MeshInstance3D = e.get_node("Body/Drawing")
	t.ok(mesh != null, "the drawing has a mesh")

	var aabb := mesh.mesh.get_aabb()
	# Feet on the floor: the canvas's y = 0 row must sit at the node's origin,
	# or the pair floats or sinks the moment it is placed in the hall.
	t.close(aabb.position.y, 0.0, 0.001, "the pair stands on the floor")
	t.gt(aabb.size.y, 1.4, "the pair is person-height (%.2f m)" % aabb.size.y)
	t.lt(aabb.size.y, 1.8, "the pair is not a giant (%.2f m)" % aabb.size.y)
	# Two people side by side are wider than one.
	# One figure is about 0.55 m across; the pair has to be clearly wider or
	# the two of them have merged into a single lump.
	t.gt(aabb.size.x, 0.9, "the pair is wider than one figure (%.2f m)"
		% aabb.size.x)
	t.lt(aabb.size.x, 1.4, "and not spread into two separate people (%.2f m)"
		% aabb.size.x)
	t.lt(aabb.size.z, 0.2, "the drawing keeps its shallow thickness")

	# Both palettes have to be present, or one of them is invisible: her tones
	# live at 1..11 and his at 12..22 in the same colour table.
	var saw_hers := false
	var saw_his := false
	for v in _embrace_canvas(e):
		if v == 0:
			continue
		if v >= EmbraceFigure.LEFT_BASE and v < EmbraceFigure.RIGHT_BASE:
			saw_hers = true
		elif v >= EmbraceFigure.RIGHT_BASE and v < EmbraceFigure.EDGE:
			saw_his = true
	t.ok(saw_hers, "she is in the drawing")
	t.ok(saw_his, "he is in the drawing")

	# Turning to camera: the body must yaw, or the pair foreshortens to a plank.
	var body: Node3D = e.get_node("Body")
	e.face_camera(e.global_position + Vector3(4.0, 1.0, 0.0))
	var yaw_east := body.global_rotation.y
	e.face_camera(e.global_position + Vector3(0.0, 1.0, 4.0))
	var yaw_north := body.global_rotation.y
	t.gt(absf(angle_difference(yaw_east, yaw_north)), 1.0,
		"the drawing turns to face the camera")

	# The breath is a breath, not a bounce.
	var highest := 0.0
	for i in 200:
		e.breathe(float(i) * 0.05)
		highest = maxf(highest, absf(body.position.y))
	t.lt(highest, 0.02, "the breath stays under two centimetres")

	e.get_parent().remove_child(e)
	e.free()


## The canvas is private; reach it through the pixel count's sibling accessor
## by rebuilding it the same way the figure does. Kept in the test rather than
## exposed on the class, because nothing in the game needs it.
func _embrace_canvas(e: EmbraceFigure) -> PackedByteArray:
	return e._draw()


# ------------------------------------------------------------------- fade

func _test_scene_fade(t: TestFramework) -> void:
	var fade := SceneFade.new()
	_holder.add_child(fade)

	var rect: ColorRect = fade.get_child(0)
	fade.fade_in(Color.BLACK, 2.0)
	t.close(rect.color.a, 1.0, 0.001, "a fade-in starts opaque")

	var finished := [false]
	fade.finished.connect(func() -> void: finished[0] = true)

	for _i in 10:
		fade._process(0.1)
	t.lt(rect.color.a, 1.0, "the fade-in has begun to clear")
	t.ok(not finished[0], "it has not finished halfway through")

	for _i in 12:
		fade._process(0.1)
	t.close(rect.color.a, 0.0, 0.001, "a fade-in ends clear")
	t.ok(finished[0], "it reports when it is done")
	t.ok(not fade.is_running(), "and stops running")

	fade.fade_out(Color(1, 1, 1), 1.0)
	t.close(rect.color.a, 0.0, 0.001, "a fade-out starts clear")
	for _i in 12:
		fade._process(0.1)
	t.close(rect.color.a, 1.0, 0.001, "a fade-out ends covered")

	fade.hold(Color(1, 1, 1), 1.0)
	t.close(rect.color.a, 1.0, 0.001, "hold sets an alpha without animating")
	t.ok(not fade.is_running(), "hold is not an animation")

	fade.get_parent().remove_child(fade)
	fade.free()


# --------------------------------------------------------------- the ending

func _test_sequence(t: TestFramework) -> void:
	var album := _album()
	album.closing_line = "There you are."

	var player := PlayerController.new()
	_holder.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	var companion := PixelFigure.new()
	_holder.add_child(companion)
	companion.build(PixelFigure.Palette.for_trousers())
	# Six metres down the hall, which is roughly where he waits.
	companion.global_position = Vector3(0, 0, -6.0)

	var seq := EndingSequence.new()
	seq.setup(player, companion, album)
	_holder.add_child(seq)

	var lines: Array = []
	EventBus.curator_line_requested.connect(
		func(text: String, _mood: StringName) -> void: lines.append(text))
	var finished := [0]
	EventBus.ending_finished.connect(func() -> void: finished[0] += 1)

	t.eq(seq.stage(), EndingSequence.Stage.IDLE, "the ending waits its turn")
	t.ok(not seq.is_running(), "and is not running before it starts")

	seq.start()
	t.eq(seq.stage(), EndingSequence.Stage.WALK, "it starts by walking")
	t.ok(player.is_in_cutscene(), "she hands over control")
	t.ok(seq.is_running(), "it is running")

	# She has about five metres to walk, so this must not take forever.
	var ticks := 0
	while seq.stage() == EndingSequence.Stage.WALK and ticks < 600:
		seq._process(0.05)
		ticks += 1
	t.lt(float(ticks) * 0.05, 7.0, "they reach each other in a few seconds")
	t.eq(seq.stage(), EndingSequence.Stage.SETTLE, "then she settles")

	var gap := player.global_position.distance_to(companion.global_position)
	t.close(gap, EndingSequence.MEET_GAP, 0.25, "they stop an arm's length apart")
	# Each on their own side, not through each other.
	t.gt(player.global_position.z, companion.global_position.z,
		"they stop short rather than walking through each other")
	# And they met in the middle: she covered about as much ground as he did.
	var she_walked := absf(player.global_position.z - 0.0)
	var he_walked := absf(companion.global_position.z - (-6.0))
	t.close(she_walked, he_walked, 0.3, "they each walked about half the gap")

	while seq.stage() == EndingSequence.Stage.SETTLE and ticks < 900:
		seq._process(0.05)
		ticks += 1
	t.eq(seq.stage(), EndingSequence.Stage.EMBRACE, "then they hold each other")
	t.ok(lines.has("There you are."),
		"his closing line is said, once, before the hug")
	t.eq(lines.size(), 1, "and nothing else is said")

	var embrace: Node = seq.get_node_or_null("../Embrace")
	t.ok(embrace != null, "the drawn pair is in the scene")
	t.ok(not companion.visible, "he is swapped out for the drawing")
	t.ok(not player.figure.visible, "and so is she")

	var mid := (player.global_position + companion.global_position) * 0.5
	if embrace != null:
		var e: EmbraceFigure = embrace
		t.lt(e.global_position.distance_to(mid), 0.05,
			"the drawing stands between the two of them")

	while seq.stage() == EndingSequence.Stage.EMBRACE and ticks < 1400:
		seq._process(0.05)
		ticks += 1
	t.eq(seq.stage(), EndingSequence.Stage.FADE, "then the light rises")

	while seq.stage() == EndingSequence.Stage.FADE and ticks < 2000:
		seq._process(0.05)
		ticks += 1
	t.eq(seq.stage(), EndingSequence.Stage.DONE, "and it is over")
	t.eq(finished[0], 1, "the results are cued exactly once")

	# The whole ending is about fifteen seconds; long enough to land, short
	# enough that nobody reaches for Escape.
	t.lt(float(ticks) * 0.05, 22.0, "the ending is not interminable")
	t.gt(float(ticks) * 0.05, 8.0, "and it is not a blink")

	# A second finish must not fire the results again.
	seq._finish()
	t.eq(finished[0], 1, "finishing twice cues the results once")

	seq.free()
	companion.get_parent().remove_child(companion)
	companion.free()
	player.get_parent().remove_child(player)
	player.free()


## Nothing to stage — the gallery was entered with no album and no figures.
## It must still reach the results rather than stranding her.
func _test_sequence_without_figures(t: TestFramework) -> void:
	var seq := EndingSequence.new()
	seq.setup(null, null, null)
	_holder.add_child(seq)

	var finished := [0]
	EventBus.ending_finished.connect(func() -> void: finished[0] += 1)

	seq.start()
	t.eq(seq.stage(), EndingSequence.Stage.DONE,
		"with no figures it goes straight to the results")
	t.eq(finished[0], 1, "and still cues them")

	seq.free()


# ---------------------------------------------------------------- results

func _test_results(t: TestFramework) -> void:
	var album := _album()
	var screen: Node = load("res://src/ui/results_screen.gd").new()
	_holder.add_child(screen)
	screen.setup(album)

	GameState.reset_for_album(album.photos.size())

	# Three played, two not: a session she walked away from must still read.
	GameState.results[0] = {
		"total_score": 6800.0, "distance_km": 0.4, "year_error": 0,
		"guess_label": "Florence, Italy", "guess_date_label": "June 1961",
		"hints_used": 0, "unblur_tier": 0,
	}
	GameState.results[1] = {
		"total_score": 2100.0, "distance_km": 412.0, "year_error": 3,
		"guess_label": "Whitby, England", "guess_date_label": "1970",
		"hints_used": 2, "unblur_tier": 1,
	}
	GameState.results[2] = {
		"total_score": 40.0, "distance_km": 9100.0, "year_error": 22,
		"guess_label": "Kyoto, Japan", "guess_date_label": "1999",
		"hints_used": 3, "unblur_tier": 3,
	}

	screen.show_results()

	var rows: VBoxContainer = screen._rows
	t.eq(rows.get_child_count(), album.photos.size(),
		"every photograph gets a line, played or not")

	# The total is the sum, and the verdict is a sentence rather than a grade.
	t.ok(screen._total.text.contains("8940"),
		"the total is the sum of the rounds (got %s)" % screen._total.text)
	t.ok(not screen._total.text.to_lower().contains("score"),
		"the total is not labelled 'score'")

	# What she said, phrased for a person.
	var exact: String = screen._said_line(GameState.results[0])
	t.ok(exact.contains("exactly"), "a hit is called exact (got: %s)" % exact)
	t.ok(exact.contains("right year"), "and the year is credited")

	var near: String = screen._said_line(GameState.results[1])
	t.ok(near.contains("412 km"), "a miss is reported in km (got: %s)" % near)
	t.ok(near.contains("3 years out"), "and the years are reported")

	var one_year: String = screen._said_line({
		"guess_label": "Lisbon, Portugal", "guess_date_label": "1962",
		"distance_km": 12.0, "year_error": 1,
	})
	t.ok(one_year.contains("a year out"), "one year is 'a year', not '1 years'")

	# Help taken, in words rather than percentages.
	t.eq(screen._help_line(GameState.results[0]), "no help",
		"an unaided round says so")
	t.ok(screen._help_line(GameState.results[1]).contains("2 questions"),
		"questions asked are counted")
	t.ok(screen._help_line(GameState.results[2]).contains("cleared 3 times"),
		"unblurs are counted")

	# An unplayed round must not throw or invent a number.
	var unplayed_row: Control = rows.get_child(4)
	t.ok(unplayed_row != null, "an unplayed photograph still has a row")

	# The verdict bands.
	var ceiling := album.scoring.max_round_score()
	GameState.results[0]["total_score"] = ceiling * 0.95
	GameState.results[1]["total_score"] = ceiling * 0.95
	GameState.results[2]["total_score"] = ceiling * 0.95
	t.ok(screen._verdict().contains("nearly all"),
		"a strong session is recognised (got: %s)" % screen._verdict())

	GameState.results[0]["total_score"] = ceiling * 0.02
	GameState.results[1]["total_score"] = ceiling * 0.02
	GameState.results[2]["total_score"] = ceiling * 0.02
	t.ok(screen._verdict().contains("He remembered"),
		"and a hard one is met kindly (got: %s)" % screen._verdict())

	# The author's private notes must never reach this screen.
	var rendered := _all_text(rows)
	t.ok(not rendered.contains("PRIVATE"),
		"private notes stay out of the results")
	t.ok(rendered.contains("Florence, Italy"), "the truth is shown")

	screen.get_parent().remove_child(screen)
	screen.free()
	GameState.reset_for_album(0)


func _all_text(node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		out.append(_all_text(child))
	return " ".join(out)


## The closing line is new in the manifest, so it has to survive a round trip
## like every other field (schema rule: never drop one).
func _test_closing_line_roundtrip(t: TestFramework) -> void:
	var a := AlbumSchema.Album.create_empty("Closing")
	a.closing_line = "Stay a minute."
	var back := AlbumSchema.Album.from_dict(a.to_dict())
	t.eq(back.closing_line, "Stay a minute.",
		"the closing line survives a save and load")

	var bare := AlbumSchema.Album.from_dict({"schemaVersion": 1})
	t.eq(bare.closing_line, "",
		"a manifest without one defaults to silence")


# -------------------------------------------------------------- fixtures

func _album() -> AlbumSchema.Album:
	var a := AlbumSchema.Album.create_empty("Ending Test")
	a.curator_voice_name = "Tom"
	var order: PackedStringArray = PackedStringArray()
	for i in PLACES.size():
		var p := AlbumSchema.Photo.new()
		p.id = "e_%03d" % (i + 1)
		p.aspect = 1.5
		p.truth.lat = PLACES[i][0]
		p.truth.lon = PLACES[i][1]
		p.truth.place_label = PLACES[i][2]
		p.truth.date.year = 1961 + i * 6
		p.truth.date.month = 6
		p.truth.date_precision = AlbumSchema.DatePrecision.MONTH
		p.content.private_note = "PRIVATE: do not show this anywhere."
		a.photos.append(p)
		order.append(p.id)
	a.hang_order = order
	return a

extends RefCounted
## The round state machine, driven through ten complete rounds.
##
## This suite builds real PhotoFrames and a real PlayerController in the tree
## rather than stubbing them, because the bugs worth catching here live in the
## wiring: a phase that does not advance, a cost that is charged twice, a
## reveal that never fires. It does not need the gallery's geometry or
## lighting, so it stays fast.

const PLACES := [
	[43.7696, 11.2558, "Florence, Italy"],
	[54.4858, -0.6206, "Whitby, England"],
	[64.1466, -21.9426, "Reykjavik, Iceland"],
	[35.0116, 135.7681, "Kyoto, Japan"],
	[38.7223, -9.1393, "Lisbon, Portugal"],
	[51.1784, -115.5708, "Banff, Canada"],
	[31.6295, -7.9811, "Marrakesh, Morocco"],
	[55.9533, -3.1883, "Edinburgh, Scotland"],
	[36.3932, 25.4615, "Santorini, Greece"],
	[54.4300, -2.9615, "Ambleside, England"],
]

var _holder: Node3D = null


func run() -> TestFramework:
	var t := TestFramework.new("round")

	var album := _album()
	var ctx := _build(album)
	var rc: RoundController = ctx["controller"]

	_test_initial_state(t, rc)
	_test_single_round(t, rc, album)
	_test_costs(t, rc, album)
	_test_full_session(t, rc, album)
	_test_cancel(t, rc, album)
	_test_hint_count_from_album(t, rc, album)
	_test_no_album(t, rc)
	_test_setup_twice(t, rc, album)

	_teardown()
	return t


# -------------------------------------------------------------- fixtures

func _album() -> AlbumSchema.Album:
	var a := AlbumSchema.Album.create_empty("Round Test")
	a.curator_voice_name = "Tom"
	a.curator_player_name = "Maggie"
	var order: PackedStringArray = PackedStringArray()

	for i in PLACES.size():
		var p := AlbumSchema.Photo.new()
		p.id = "p_%03d" % (i + 1)
		p.aspect = 1.5
		var paths := AlbumSchema.Photo.default_paths(p.id)
		p.full_path = paths["full"]
		p.blur_paths = PackedStringArray(paths["blurTiers"])
		p.thumb_path = paths["thumb"]
		p.truth.lat = PLACES[i][0]
		p.truth.lon = PLACES[i][1]
		p.truth.place_label = PLACES[i][2]
		p.truth.location_precision_km = 8.0
		p.truth.date.year = 1961 + i * 6
		p.truth.date.month = 6
		p.truth.date_precision = AlbumSchema.DatePrecision.MONTH
		p.content.description = "Something the author wrote."
		p.curator.hints = PackedStringArray([
			"Warm stone, and you complained all week.",
			"Somewhere in Europe that summer.",
			"It was %s, love." % PLACES[i][2],
		])
		p.curator.reveal_monologue = "That summer. You wore the green dress."
		p.curator.approved_by_author = true
		a.photos.append(p)
		order.append(p.id)

	a.hang_order = order
	return a


func _build(album: AlbumSchema.Album) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	_holder = Node3D.new()
	_holder.name = "RoundTestHolder"
	tree.root.add_child(_holder)

	var hallway := HallwayBuilder.build()

	var frames: Array[PhotoFrame] = []
	var hung := album.hung_photos()
	for i in hung.size():
		var frame := PhotoFrame.new()
		_holder.add_child(frame)
		frame.transform = hallway.frame_anchors[i]
		frame.setup(hung[i], null)
		frames.append(frame)

	var player := PlayerController.new()
	_holder.add_child(player)
	player.transform = hallway.player_start

	var rc := RoundController.new()
	_holder.add_child(rc)
	rc.setup(album, frames, player)

	GameState.reset_for_album(frames.size())
	return {"controller": rc, "frames": frames, "player": player}


func _teardown() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null


# ----------------------------------------------------------------- tests

func _test_initial_state(t: TestFramework, rc: RoundController) -> void:
	t.eq(rc.frames.size(), AlbumSchema.PHOTOS_PER_ALBUM,
		"controller holds ten frames")
	t.eq(GameState.phase, GameState.Phase.GALLERY_IDLE,
		"a fresh gallery is idle")
	t.eq(rc.active_index(), -1, "nothing is active yet")
	t.eq(GameState.photos_played(), 0, "nothing has been played")
	t.close(GameState.total_score(), 0.0, 0.001, "the score starts at zero")

	# Every frame must have an interaction volume, or she can never engage it.
	for i in rc.frames.size():
		t.ok(rc.frames[i].interaction_area != null,
			"frame %d has an interaction volume" % i)


func _test_single_round(t: TestFramework, rc: RoundController,
		album: AlbumSchema.Album) -> void:
	_reset(rc)

	rc._nearby = 0
	GameState.phase = GameState.Phase.APPROACH
	rc._begin_examine(0)

	t.eq(GameState.phase, GameState.Phase.GUESSING,
		"examining a photograph opens the guess")
	t.eq(rc.active_index(), 0, "the first photograph is active")
	t.eq(GameState.current_photo_index, 0, "state tracks the active index")
	t.ok(rc.active_photo() != null, "the active photograph resolves")

	# An exact, unassisted answer must score the full round.
	var photo: AlbumSchema.Photo = album.photos[0]
	var date := AlbumSchema.PhotoDate.new()
	date.year = photo.truth.date.year
	date.month = photo.truth.date.month
	rc.submit_guess(photo.truth.lat, photo.truth.lon, date)

	t.eq(GameState.phase, GameState.Phase.REVEALED,
		"a submitted guess reveals the photograph")
	t.ok(rc.frames[0].revealed, "the frame itself is marked revealed")

	var result: Variant = GameState.results[0]
	t.ok(result != null, "the round recorded a result")
	if result != null:
		var r: Dictionary = result
		t.close(float(r["distance_km"]), 0.0, 0.001, "an exact pin is zero km out")
		t.close(float(r["total_score"]), album.scoring.max_round_score(), 0.5,
			"an exact unassisted answer scores the whole round")
		t.eq(r["error_band"], &"exact", "an exact pin reports as exact")

	# The dwell must end the round and return her to the hall.
	rc._reveal_timer = 0.0
	rc._process(0.1)
	t.eq(GameState.phase, GameState.Phase.GALLERY_IDLE,
		"the round hands back to the hall")
	t.eq(rc.active_index(), -1, "nothing is active after the round")
	t.eq(GameState.photos_played(), 1, "one photograph is played")

	# A played photograph must not re-open.
	t.ok(GameState.is_played(0), "the first photograph is marked played")
	rc._on_body_entered(rc.player, 0)
	t.eq(GameState.phase, GameState.Phase.GALLERY_IDLE,
		"walking back to a played photograph does not re-open it")


func _test_costs(t: TestFramework, rc: RoundController,
		album: AlbumSchema.Album) -> void:
	_reset(rc)
	var cfg := album.scoring

	rc._nearby = 1
	GameState.phase = GameState.Phase.APPROACH
	rc._begin_examine(1)

	t.close(rc.spent_fraction(), 0.0, 0.001, "nothing is spent at the start")
	t.ok(rc.can_unblur(), "a fresh photograph can be unblurred")
	t.ok(rc.can_hint(), "a fresh photograph has hints left")

	# --- unblurring walks the tier ladder and stops at the top ---
	var tiers_bought := 0
	while rc.can_unblur():
		t.ok(rc.purchase_unblur(), "unblur %d succeeds" % tiers_bought)
		tiers_bought += 1
		if tiers_bought > 10:
			break
	t.eq(tiers_bought, AlbumSchema.BLUR_TIER_COUNT - 1,
		"there are exactly three steps from the opening tier to the clearest")
	t.ok(not rc.purchase_unblur(), "unblurring past the top fails cleanly")
	t.eq(GameState.unblur_tiers[1], AlbumSchema.BLUR_TIER_COUNT - 1,
		"the tier is recorded on the round")

	# --- the hint ladder is three deep, monotonic, and then exhausted ---
	var lines: PackedStringArray = PackedStringArray()
	while rc.can_hint():
		var line := rc.purchase_hint()
		t.ok(not line.is_empty(), "hint %d returns a line" % lines.size())
		lines.append(line)
		if lines.size() > 5:
			break
	t.eq(lines.size(), 3, "there are exactly three hints")
	t.eq(rc.purchase_hint(), "", "asking a fourth time returns nothing")

	# Tier 3 names the place; tier 1 must not.
	var photo: AlbumSchema.Photo = album.photos[1]
	var city := photo.truth.place_label.split(",")[0].strip_edges()
	t.ok(lines[2].to_lower().contains(city.to_lower()),
		"the last hint names the place")
	t.ok(not lines[0].to_lower().contains(city.to_lower()),
		"the first hint does not name the place")

	# --- spend is capped, and a fully assisted correct answer still scores ---
	var spent := rc.spent_fraction()
	t.close(spent, cfg.max_spent_fraction, 0.001,
		"total reliance is capped at maxSpentFraction")

	var date := AlbumSchema.PhotoDate.new()
	date.year = photo.truth.date.year
	date.month = photo.truth.date.month
	rc.submit_guess(photo.truth.lat, photo.truth.lon, date)

	var r: Dictionary = GameState.results[1]
	t.gt(float(r["total_score"]), 0.0,
		"a fully assisted correct answer still scores something")
	t.close(float(r["total_score"]),
		cfg.max_round_score() * (1.0 - cfg.max_spent_fraction), 0.5,
		"and scores exactly the uncapped remainder")
	t.lt(float(r["total_score"]), cfg.max_round_score(),
		"but less than an unassisted one")

	rc._reveal_timer = 0.0
	rc._process(0.1)

	# Spending outside a round must be refused rather than silently charged.
	t.ok(not rc.purchase_unblur(), "unblurring outside a round is refused")
	t.eq(rc.purchase_hint(), "", "asking outside a round is refused")


func _test_full_session(t: TestFramework, rc: RoundController,
		album: AlbumSchema.Album) -> void:
	_reset(rc)

	var hints_before := GameState.total_hints_taken
	for i in rc.frames.size():
		rc._nearby = i
		GameState.phase = GameState.Phase.APPROACH
		rc._begin_examine(i)
		t.eq(GameState.phase, GameState.Phase.GUESSING,
			"round %d opens" % i)

		# Lean on him for the second half, so reliance actually moves.
		if i >= 5:
			rc.purchase_hint()

		var photo: AlbumSchema.Photo = album.photos[i]
		var date := AlbumSchema.PhotoDate.new()
		date.year = photo.truth.date.year
		date.month = photo.truth.date.month
		rc.submit_guess(photo.truth.lat, photo.truth.lon, date)
		rc._reveal_timer = 0.0
		rc._process(0.1)

	t.eq(GameState.photos_played(), AlbumSchema.PHOTOS_PER_ALBUM,
		"every photograph is played")
	t.eq(GameState.phase, GameState.Phase.ENDING,
		"the tenth photograph ends the session rather than returning to the hall")
	t.eq(GameState.total_hints_taken - hints_before, 5,
		"exactly the hints taken were counted")
	t.gt(GameState.reliance(), 0.0, "reliance rose because she asked for help")
	t.lt(GameState.reliance(), 1.0, "but she did not ask for everything")

	# The total must equal the sum of the parts.
	var summed := 0.0
	for r in GameState.results:
		summed += float((r as Dictionary)["total_score"])
	t.close(GameState.total_score(), summed, 0.5,
		"the session total is the sum of its rounds")
	t.gt(GameState.total_score(), 0.0, "the session scored something")


func _test_cancel(t: TestFramework, rc: RoundController,
		_album: AlbumSchema.Album) -> void:
	_reset(rc)

	rc._nearby = 3
	GameState.phase = GameState.Phase.APPROACH
	rc._begin_examine(3)
	t.eq(GameState.phase, GameState.Phase.GUESSING, "the round opened")

	# Stepping back must not strand the phase machine, and must not score.
	#
	# It goes back to APPROACH rather than to GALLERY_IDLE, because she is
	# still standing in front of the photograph — backing out of the guess
	# panel does not move her. This assertion used to read GALLERY_IDLE, and
	# then quietly put `_nearby` and the phase back by hand before re-opening,
	# which is what hid the bug: in the game, Area3D's body_entered is an edge
	# event and does not fire again while she is inside the volume, so E was
	# dead and the prompt gone until she walked out and back in again.
	var approached: Array = []
	var connection := func(index: int) -> void: approached.append(index)
	EventBus.photo_approached.connect(connection)

	rc.cancel_guessing()
	t.eq(GameState.phase, GameState.Phase.APPROACH,
		"cancelling puts her back in front of the photograph")
	t.eq(rc.nearby_index(), 3, "which is still the one she is standing at")
	t.eq(approached, [3], "and the prompt is put back up")
	t.eq(rc.active_index(), -1, "cancelling clears the active photograph")
	t.ok(GameState.results[3] == null, "cancelling does not record a score")
	t.ok(not GameState.is_played(3), "a cancelled photograph is still unplayed")

	# So E works again with no further help: nothing is touched here.
	rc._begin_examine(3)
	t.eq(GameState.phase, GameState.Phase.GUESSING,
		"a cancelled photograph can be re-opened on the spot")
	rc.cancel_guessing()

	# Walking away and cancelling from nowhere leaves the hall, not an
	# approach to a frame she is not at.
	rc._nearby = -1
	GameState.phase = GameState.Phase.APPROACH
	rc._begin_examine(3)
	rc.cancel_guessing()
	t.eq(GameState.phase, GameState.Phase.GALLERY_IDLE,
		"cancelling with no frame nearby returns to the hall")

	EventBus.photo_approached.disconnect(connection)


## The gallery can be entered with no album at all, to walk the space. Nothing
## sized the per-round state in that case, so the HUD's first frame indexed off
## the end of it. setup() now sizes the arrays itself; this pins that.
func _test_no_album(t: TestFramework, rc: RoundController) -> void:
	# clear() rather than assigning [], because these are typed arrays and an
	# untyped literal will not assign to them.
	GameState.results.clear()
	GameState.unblur_tiers.clear()
	GameState.hints_taken.clear()

	rc.setup(null, rc.frames, rc.player)

	t.eq(GameState.unblur_tiers.size(), rc.frames.size(),
		"setup sizes the unblur state to the frames")
	t.eq(GameState.hints_taken.size(), rc.frames.size(),
		"setup sizes the hint state to the frames")
	t.eq(GameState.results.size(), rc.frames.size(),
		"setup sizes the results to the frames")

	# The accessors the HUD polls every frame must be safe with nothing active.
	t.ok(not rc.can_unblur(), "nothing to unblur with no active round")
	t.ok(not rc.can_hint(), "nothing to ask with no active round")
	t.close(rc.spent_fraction(), 0.0, 0.001, "nothing spent with no active round")
	t.close(rc.next_hint_cost(), 0.0, 0.001, "no hint cost with no active round")
	t.ok(rc.active_photo() == null, "no active photograph with no album")

	# And with a round open but no album behind it, they must still not throw.
	rc.debug_open(0)
	t.ok(not rc.can_unblur() or rc.can_unblur(), "can_unblur is answerable")
	t.ok(not rc.can_hint() or rc.can_hint(), "can_hint is answerable")
	t.eq(rc.purchase_hint(), "",
		"asking with no album returns nothing rather than throwing")
	rc.cancel_guessing()


func _reset(rc: RoundController) -> void:
	GameState.reset_for_album(rc.frames.size())
	GameState.phase = GameState.Phase.GALLERY_IDLE
	for frame in rc.frames:
		frame.revealed = false
	rc._active = -1
	rc._nearby = -1


## How many hints there are is the ALBUM's decision, by how many costs it
## lists. It used to be a hardcoded 3 in the controller, while
## ScoringConfig.hint_cost returns 0.0 past the end of the list — so an album
## carrying two costs still granted a third hint, and the third hint is the one
## that names the answer outright. It was free, and the HUD advertised it as
## costing nothing.
func _test_hint_count_from_album(t: TestFramework, rc: RoundController,
		album: AlbumSchema.Album) -> void:
	var keep := album.scoring.hint_costs

	# Two costs: two hints, and neither of them free.
	album.scoring.hint_costs = PackedFloat32Array([0.10, 0.20])
	_reset(rc)
	t.eq(rc.hint_tier_count(), 2, "two listed costs mean two hints")

	rc._nearby = 0
	GameState.phase = GameState.Phase.APPROACH
	rc._begin_examine(0)

	var granted := 0
	var free_hints := 0
	while rc.can_hint() and granted < 6:
		var cost := rc.next_hint_cost()
		if rc.purchase_hint().is_empty():
			break
		granted += 1
		if cost <= 0.0:
			free_hints += 1
	t.eq(granted, 2, "and only two are ever granted")
	t.eq(free_hints, 0, "neither of them free")
	t.ok(rc.purchase_hint().is_empty(), "asking again gives nothing")
	t.close(rc.spent_fraction(), 0.30, 0.001, "and the spend is the two costs")
	rc.cancel_guessing()

	# More costs than there are lines to say: still three.
	album.scoring.hint_costs = PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5])
	t.eq(rc.hint_tier_count(), 3,
		"more costs than lines still means three hints")

	# And the album's own three, which is the normal case.
	album.scoring.hint_costs = keep
	t.eq(rc.hint_tier_count(), 3, "three costs mean three hints")
	_reset(rc)


## setup() used to connect every frame's area without disconnecting what an
## earlier setup() had connected. A second call therefore asked Godot for a
## duplicate connection, once per frame, and the engine printed an error and
## refused it — and had the frames changed in between, the handlers bound to
## the old indices would still have been live on areas that were still around.
func _test_setup_twice(t: TestFramework, rc: RoundController, album: AlbumSchema.Album) -> void:
	rc.setup(album, rc.frames, rc.player)
	rc.setup(album, rc.frames, rc.player)

	var doubled := 0
	for frame in rc.frames:
		var area := frame.interaction_area
		if area == null:
			continue
		if area.body_entered.get_connections().size() != 1:
			doubled += 1
		if area.body_exited.get_connections().size() != 1:
			doubled += 1
	t.eq(doubled, 0, "setting up twice leaves one connection per frame signal")

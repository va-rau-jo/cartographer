class_name RoundController
extends Node
## The round state machine: the thing that turns a walkable hallway into a game.
##
## Owns every transition of GameState.phase. Nothing else writes it — that rule
## is what stops the state machine leaking into the HUD and the companion AI
## (plan §2.2).
##
##   GALLERY_IDLE → APPROACH → EXAMINE → GUESSING
##                → (unblur | hint)*  → SUBMITTED → SCORED → REVEALED
##                → REFLECT → GALLERY_IDLE
##                                     ↓ after the tenth
##                                   ENDING
##
## Facts about the world go out through EventBus; requests come in as direct
## calls from the HUD and the guess panel.

## How long the reveal holds before she can walk away.
const REVEAL_DWELL := 1.2

var album: AlbumSchema.Album = null
var frames: Array[PhotoFrame] = []
var player: PlayerController = null

## Index into the hung order, or -1 when she is not at a photograph.
var _nearby := -1
var _active := -1
var _reveal_timer := 0.0
var _hung: Array[AlbumSchema.Photo] = []


func setup(a: AlbumSchema.Album, f: Array[PhotoFrame], p: PlayerController) -> void:
	album = a
	frames = f
	player = p
	# Not a ternary: the empty-literal branch is an untyped Array and will not
	# assign to Array[Photo]. Same trap as in gallery.gd.
	_hung = []
	if a != null:
		_hung = a.hung_photos()

	for i in frames.size():
		var frame := frames[i]
		var area := frame.interaction_area
		if area == null:
			continue
		# Bound so each frame reports its own index without a lookup.
		area.body_entered.connect(_on_body_entered.bind(i))
		area.body_exited.connect(_on_body_exited.bind(i))

	# Size the per-round state to the frames we actually have. AlbumService
	# does this when an album loads, but the gallery can also be entered with
	# no album at all (placeholder pictures, for walking the space), and then
	# nothing had sized these arrays — so the HUD indexed off the end of them
	# on its first frame.
	if GameState.unblur_tiers.size() != frames.size():
		GameState.reset_for_album(frames.size())

	GameState.phase = GameState.Phase.GALLERY_IDLE
	CCLog.info("round", "controller ready for %d photographs" % frames.size())


func _process(delta: float) -> void:
	match GameState.phase:
		GameState.Phase.REVEALED:
			_reveal_timer -= delta
			if _reveal_timer <= 0.0:
				_finish_round()
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"interact"):
		return

	match GameState.phase:
		GameState.Phase.APPROACH:
			_begin_examine(_nearby)
		GameState.Phase.REVEALED:
			# Let her skip the dwell.
			_reveal_timer = 0.0
		_:
			pass


# ------------------------------------------------------------- proximity

func _on_body_entered(body: Node3D, index: int) -> void:
	if body != player:
		return
	if GameState.is_played(index):
		# Already guessed: she can look, but there is nothing left to do.
		return
	if GameState.phase != GameState.Phase.GALLERY_IDLE:
		return

	_nearby = index
	GameState.phase = GameState.Phase.APPROACH
	EventBus.photo_approached.emit(index)


func _on_body_exited(body: Node3D, index: int) -> void:
	if body != player or _nearby != index:
		return
	_nearby = -1
	if GameState.phase == GameState.Phase.APPROACH:
		GameState.phase = GameState.Phase.GALLERY_IDLE


# ----------------------------------------------------------------- round

func _begin_examine(index: int) -> void:
	if index < 0 or index >= frames.size():
		return

	_active = index
	GameState.current_photo_index = index
	GameState.phase = GameState.Phase.EXAMINE

	player.begin_examine(frames[index].global_transform)
	EventBus.photo_examined.emit(index)

	# The full-resolution decode is the only slow step in the round, so start
	# it now rather than at the reveal. She is standing still looking at a
	# blurred photograph; there is no better moment to spend 40 ms.
	var photo := _photo_at(index)
	if photo != null:
		AlbumService.prewarm_full(photo.id)

	open_guessing()


func open_guessing() -> void:
	if _active < 0:
		return
	GameState.phase = GameState.Phase.GUESSING
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.round_started.emit(_active)


## Step the blur down one tier, at a cost. Returns false when there is nothing
## left to unblur.
func purchase_unblur() -> bool:
	if GameState.phase != GameState.Phase.GUESSING or _active < 0:
		return false

	if not _in_range(_active):
		return false

	var tier: int = GameState.unblur_tiers[_active]
	var max_tier := AlbumSchema.BLUR_TIER_COUNT - 1
	if tier >= max_tier:
		return false

	tier += 1
	GameState.unblur_tiers[_active] = tier

	var photo := _photo_at(_active)
	if photo != null:
		frames[_active].set_texture(AlbumService.tier_texture(photo.id, tier))
		frames[_active].set_tier(tier)

	var cost := _scoring().unblur_cost_fraction
	EventBus.unblur_purchased.emit(_active, tier, cost)
	CCLog.info("round", "photo %d unblurred to tier %d" % [_active, tier])
	return true


## Ask him. Returns the line, or "" when every tier has already been spent.
func purchase_hint() -> String:
	if GameState.phase != GameState.Phase.GUESSING or _active < 0:
		return ""

	if not _in_range(_active):
		return ""

	var taken: Array = GameState.hints_taken[_active]
	var next_tier := taken.size() + 1
	if next_tier > 3:
		return ""

	taken.append(next_tier)
	GameState.hints_taken[_active] = taken
	GameState.total_hints_taken += 1

	var photo := _photo_at(_active)
	var line := ""
	if photo != null:
		line = photo.curator.hint_for_tier(next_tier, photo.truth.place_label)

	var cost := _scoring().hint_cost(next_tier)
	EventBus.hint_purchased.emit(_active, next_tier, cost)
	EventBus.curator_line_requested.emit(line, _mood_for_hint(next_tier))
	CCLog.info("round", "photo %d hint tier %d taken" % [_active, next_tier])
	return line


## Commit a guess. `guess_date` may be a year-only PhotoDate. `guess_label` is
## only ever shown back to her on the results screen ("you said Lisbon"), so it
## is optional and never scored.
func submit_guess(guess_lat: float, guess_lon: float,
		guess_date: AlbumSchema.PhotoDate, guess_label: String = "") -> void:
	if GameState.phase != GameState.Phase.GUESSING or _active < 0:
		return

	if not _in_range(_active):
		return

	GameState.phase = GameState.Phase.SUBMITTED
	EventBus.guess_submitted.emit(_active)

	var photo := _photo_at(_active)
	if photo == null:
		_finish_round()
		return

	var spent := Scoring.spent_fraction(
		GameState.unblur_tiers[_active],
		GameState.hints_taken[_active],
		_scoring())

	var breakdown := Scoring.score_round(photo, guess_lat, guess_lon,
		guess_date, spent, _scoring())
	# What she actually said, for the results screen. Kept out of Scoring so
	# that stays a pure function of the numbers.
	breakdown["guess_label"] = guess_label
	breakdown["guess_date_label"] = guess_date.label()
	breakdown["guess_lat"] = guess_lat
	breakdown["guess_lon"] = guess_lon
	breakdown["photo_id"] = photo.id
	breakdown["hints_used"] = (GameState.hints_taken[_active] as Array).size()
	breakdown["unblur_tier"] = int(GameState.unblur_tiers[_active])
	GameState.results[_active] = breakdown

	GameState.phase = GameState.Phase.SCORED
	EventBus.round_scored.emit(_active, breakdown)

	_reveal(photo, breakdown)


func _reveal(photo: AlbumSchema.Photo, breakdown: Dictionary) -> void:
	GameState.phase = GameState.Phase.REVEALED
	_reveal_timer = REVEAL_DWELL
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	frames[_active].reveal(AlbumService.full_texture(photo.id))
	EventBus.photo_revealed.emit(_active)

	# What he says depends on how close she was. This is the moment the round
	# is actually for.
	var line := photo.curator.reveal_monologue
	var band: StringName = breakdown.get("error_band", &"far")
	if line.is_empty():
		line = photo.truth.place_label
	EventBus.curator_line_requested.emit(line, band)


func _finish_round() -> void:
	var finished := _active
	_active = -1
	_nearby = -1
	GameState.phase = GameState.Phase.REFLECT

	player.end_examine()
	EventBus.round_finished.emit(finished)

	if GameState.photos_played() >= frames.size():
		GameState.phase = GameState.Phase.ENDING
		EventBus.session_completed.emit(GameState.total_score())
		EventBus.ending_started.emit()
		CCLog.info("round", "all %d photographs played, total %.0f"
			% [frames.size(), GameState.total_score()])
		return

	GameState.phase = GameState.Phase.GALLERY_IDLE
	GameState.current_photo_index = -1


## Abandon the current round without scoring it, so Escape out of the guess
## panel does not strand the phase machine.
func cancel_guessing() -> void:
	if GameState.phase != GameState.Phase.GUESSING:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.end_examine()
	_active = -1
	GameState.current_photo_index = -1
	GameState.phase = GameState.Phase.GALLERY_IDLE


# ------------------------------------------------------------- accessors

func active_index() -> int:
	return _active


func nearby_index() -> int:
	return _nearby


func active_photo() -> AlbumSchema.Photo:
	return _photo_at(_active)


## Fraction of this round's score already spent on help.
func spent_fraction() -> float:
	if not _in_range(_active):
		return 0.0
	return Scoring.spent_fraction(
		GameState.unblur_tiers[_active],
		GameState.hints_taken[_active],
		_scoring())


func can_unblur() -> bool:
	if not _in_range(_active):
		return false
	return GameState.unblur_tiers[_active] < AlbumSchema.BLUR_TIER_COUNT - 1


func can_hint() -> bool:
	if not _in_range(_active):
		return false
	return (GameState.hints_taken[_active] as Array).size() < 3


func next_hint_cost() -> float:
	if not _in_range(_active):
		return 0.0
	return _scoring().hint_cost((GameState.hints_taken[_active] as Array).size() + 1)


func unblur_cost() -> float:
	return _scoring().unblur_cost_fraction


## Open a round directly, bypassing proximity. For the screenshot tool and
## for manual testing; the game itself always arrives here through APPROACH.
func debug_open(index: int) -> void:
	if index < 0 or index >= frames.size():
		return
	_nearby = index
	GameState.phase = GameState.Phase.APPROACH
	_begin_examine(index)


# --- internals ---

## True when `index` addresses both a frame and its round state. Everything the
## HUD polls goes through here, because the HUD runs every frame and must never
## be the thing that throws.
func _in_range(index: int) -> bool:
	return index >= 0 \
		and index < frames.size() \
		and index < GameState.unblur_tiers.size() \
		and index < GameState.hints_taken.size()


func _photo_at(index: int) -> AlbumSchema.Photo:
	if index < 0 or index >= _hung.size():
		return null
	return _hung[index]


func _scoring() -> AlbumSchema.ScoringConfig:
	if album != null:
		return album.scoring
	return AlbumSchema.ScoringConfig.new()


## Later hints cost him more to give, and the curator system dims the room to
## match (plan §8.2).
func _mood_for_hint(tier: int) -> StringName:
	match tier:
		1: return &"gentle"
		2: return &"tired"
		3: return &"failing"
	return &"gentle"

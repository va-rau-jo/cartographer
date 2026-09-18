class_name EndingSequence
extends Node
## The last minute of the game: she walks to him, they hold each other, and the
## hall goes to light.
##
## The brief was explicit — the game ends with the hug — so nothing interrupts
## it. No prompt, no score, no input beyond a skip. The numbers arrive
## afterwards, once this emits EventBus.ending_finished.
##
## Stages, all time-driven rather than input-driven:
##
##   WALK     she walks the last stretch of the hall toward him
##   SETTLE   she arrives; the camera swings round to see them both
##   EMBRACE  both figures are swapped for one drawn pose (EmbraceFigure)
##   FADE     the light rises until it is all there is
##
## Why swap figures rather than animate them: an extruded drawing has no
## joints, so an embrace has to be drawn. See EmbraceFigure's header.

enum Stage { IDLE, WALK, SETTLE, EMBRACE, FADE, DONE }

## How far apart they stop. Close enough that the drawn pair, which is centred
## between them, lands where they are both standing.
const MEET_GAP := 1.15
## They walk toward each other and meet in the middle, so neither of them has
## to cross the whole hall — she may well have finished at the near end, and
## twenty-three metres at an old woman's pace is a minute of nothing.
const WALK_SPEED_MIN := 0.95
const WALK_SPEED_MAX := 1.50
## The walk is aimed at roughly this many seconds, whatever the distance, by
## scaling the pace between the two bounds above. Short gaps stay unhurried;
## the length of the hall no longer costs a quarter of a minute.
const WALK_TARGET_SECONDS := 4.0
## Beyond this she is considered to have arrived, however slow the last inch.
const ARRIVE_EPSILON := 0.10

const SETTLE_TIME := 1.6
const EMBRACE_TIME := 5.2
const FADE_TIME := 4.0
## How long the drawn pair holds before the light starts to rise.
const FADE_HOLD := 2.2

## Camera framing for the embrace: off to the side, a little low, looking
## slightly up at them, because that is how this shot is always framed.
const CAM_SIDE := 2.35
const CAM_BACK := 1.60
const CAM_HEIGHT := 1.30
const CAM_EASE := 2.2

var player: PlayerController = null
var companion: PixelFigure = null
var album: AlbumSchema.Album = null
## Who the two of them are. The embrace is a drawn pose of a specific pair —
## her on the left, him on the right — so it asks the cast for the wife and the
## husband by name rather than for "the player" and "the companion". Whoever
## walked the hall, the hug looks the same.
var cast: CastProfile = null

var _stage: Stage = Stage.IDLE
var _clock := 0.0
var _her_target := Vector3.ZERO
var _his_target := Vector3.ZERO
var _walk_speed := WALK_SPEED_MIN
var _embrace: EmbraceFigure = null
var _fade: ColorRect = null
var _fade_layer: CanvasLayer = null
var _camera: Camera3D = null
var _said_closing := false


func setup(p: PlayerController, c: PixelFigure, a: AlbumSchema.Album,
		who: CastProfile = null) -> void:
	player = p
	companion = c
	album = a
	cast = who if who != null else CastProfile.load_saved()


func _ready() -> void:
	_build_fade()
	EventBus.ending_started.connect(start)


func start() -> void:
	if _stage != Stage.IDLE:
		return
	if player == null or companion == null:
		# Nothing to stage. Go straight to the results rather than stranding
		# the player in a finished gallery.
		CCLog.warn("ending", "no figures to stage; skipping to results")
		_finish()
		return

	_camera = player.camera
	player.begin_cutscene()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# They meet in the middle, each stopping half the gap short of it, so
	# neither walks through the other and neither crosses the whole hall.
	var from := player.global_position
	var to := companion.global_position
	var axis := from - to
	axis.y = 0.0
	if axis.length_squared() < 0.01:
		axis = Vector3.FORWARD
	var gap := axis.length()
	axis = axis.normalized()

	var middle := (from + to) * 0.5
	_her_target = middle + axis * (MEET_GAP * 0.5)
	_her_target.y = from.y
	_his_target = middle - axis * (MEET_GAP * 0.5)
	_his_target.y = to.y

	# Pace scaled to the distance, within an old couple's plausible range.
	var each := maxf(0.0, (gap - MEET_GAP) * 0.5)
	_walk_speed = clampf(each / WALK_TARGET_SECONDS,
		WALK_SPEED_MIN, WALK_SPEED_MAX)

	_stage = Stage.WALK
	_clock = 0.0
	CCLog.info("ending", "%.1f m apart; %.1f m each at %.2f m/s"
		% [gap, each, _walk_speed])


# ------------------------------------------------------------------ stages

func _process(delta: float) -> void:
	_clock += delta

	match _stage:
		Stage.WALK:
			_tick_walk(delta)
		Stage.SETTLE:
			_tick_settle(delta)
		Stage.EMBRACE:
			_tick_embrace(delta)
		Stage.FADE:
			_tick_fade(delta)
		_:
			pass


func _tick_walk(delta: float) -> void:
	var her_done := _step_toward(player, _her_target, delta)
	var his_done := _step_toward(companion, _his_target, delta)

	if player.figure != null:
		player.figure.animate_walk(delta, _walk_speed if not her_done else 0.0)
	companion.animate_walk(delta, _walk_speed if not his_done else 0.0)

	_drive_camera(delta, 0.55)
	_face_figures()

	if her_done and his_done:
		_enter_settle()


## Move one figure a step toward its mark. Returns true once it is there.
func _step_toward(who: Node3D, target: Vector3, delta: float) -> bool:
	var here := who.global_position
	var to_target := target - here
	to_target.y = 0.0
	var distance := to_target.length()
	if distance <= ARRIVE_EPSILON:
		return true

	var direction := to_target / distance
	who.global_position = here + direction * minf(_walk_speed * delta, distance)
	# A Node3D faces -Z, which is what the controller aims along travel.
	who.rotation.y = lerp_angle(who.rotation.y,
		atan2(-direction.x, -direction.z), 8.0 * delta)
	return false


func _enter_settle() -> void:
	_stage = Stage.SETTLE
	_clock = 0.0

	# They turn to each other.
	var between := companion.global_position - player.global_position
	between.y = 0.0
	if between.length_squared() > 0.001:
		between = between.normalized()
		player.rotation.y = atan2(-between.x, -between.z)
		companion.rotation.y = atan2(between.x, between.z)

	if player.figure != null:
		player.figure.animate_walk(0.016, 0.0)
	companion.animate_walk(0.016, 0.0)


func _tick_settle(delta: float) -> void:
	_drive_camera(delta, 1.0)
	_face_figures()
	if player.figure != null:
		player.figure.animate_walk(delta, 0.0)

	# His last line, if the author wrote one. If not, silence — which is the
	# better default for someone else's marriage.
	if not _said_closing and _clock > 0.35:
		_said_closing = true
		if album != null and not album.closing_line.strip_edges().is_empty():
			EventBus.curator_line_requested.emit(album.closing_line, &"gentle")

	if _clock >= SETTLE_TIME:
		_enter_embrace()


func _enter_embrace() -> void:
	_stage = Stage.EMBRACE
	_clock = 0.0

	# One drawing replaces two figures, standing midway between them.
	_embrace = EmbraceFigure.new()
	_embrace.name = "Embrace"
	companion.get_parent().add_child(_embrace)

	var mid := (player.global_position + companion.global_position) * 0.5
	mid.y = minf(player.global_position.y, companion.global_position.y)
	_embrace.global_position = mid

	# Her colours and his, from the cast — NOT from whichever figure the player
	# happens to be walking as. With the husband as the player those two are
	# swapped, and the drawn pose would have put her hair on his body.
	var her_palette := PixelFigure.Palette.new()
	var his_palette := PixelFigure.Palette.husband()
	if cast != null:
		her_palette = cast.wife.to_palette()
		his_palette = cast.husband.to_palette()
	elif player.figure != null:
		her_palette = player.figure.palette
		his_palette = companion.palette
	_embrace.build(her_palette, his_palette)

	if player.figure != null:
		player.figure.visible = false
	companion.visible = false

	CCLog.info("ending", "embrace: %d triangles, %d drawn pixels"
		% [_embrace.total_triangles(), _embrace.filled_pixels()])


func _tick_embrace(delta: float) -> void:
	_drive_camera(delta, 1.0)
	if _embrace != null:
		_embrace.breathe(_clock)
		if _camera != null:
			_embrace.face_camera(_camera.global_position)

	if _clock >= FADE_HOLD:
		_stage = Stage.FADE
		_clock = 0.0


func _tick_fade(delta: float) -> void:
	_drive_camera(delta, 1.0)
	if _embrace != null:
		_embrace.breathe(FADE_HOLD + _clock)
		if _camera != null:
			_embrace.face_camera(_camera.global_position)

	# Into light, not into black. He is not being switched off; she is being
	# let go of.
	_fade.color.a = smoothstep(0.0, 1.0, clampf(_clock / FADE_TIME, 0.0, 1.0))

	if _clock >= FADE_TIME:
		_finish()


func _finish() -> void:
	if _stage == Stage.DONE:
		return
	_stage = Stage.DONE
	if _fade != null:
		_fade.color.a = 1.0
	EventBus.ending_finished.emit()
	CCLog.info("ending", "finished")


# ------------------------------------------------------------------ camera

## Ease the camera to a framing that sees both of them, side on. `weight`
## scales the easing so the walk keeps a looser, more drifting camera than the
## embrace.
func _drive_camera(delta: float, weight: float) -> void:
	if _camera == null:
		return

	var her := player.global_position
	var him := companion.global_position
	var mid := (her + him) * 0.5

	var axis := him - her
	axis.y = 0.0
	if axis.length_squared() < 0.0001:
		axis = Vector3.FORWARD
	axis = axis.normalized()
	# Perpendicular in the floor plane: the shot is from beside them, not from
	# behind one of their heads.
	var side := Vector3(-axis.z, 0.0, axis.x)

	var eye := mid + side * CAM_SIDE - axis * CAM_BACK \
		+ Vector3(0.0, CAM_HEIGHT, 0.0)
	var look := mid + Vector3(0.0, 1.05, 0.0)

	var want := Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	_camera.global_transform = _camera.global_transform.interpolate_with(
		want, clampf(CAM_EASE * weight * delta, 0.0, 1.0))


## Both drawings have to keep turning to camera, or they flatten into planks.
func _face_figures() -> void:
	if _camera == null:
		return
	if player.figure != null:
		player.figure.update_view_for_camera(_camera.global_position)
	if companion != null:
		companion.update_view_for_camera(_camera.global_position)


# -------------------------------------------------------------------- fade

func _build_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "EndingFade"
	_fade_layer.layer = 18
	add_child(_fade_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.97, 0.95, 0.90, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade)


func stage() -> Stage:
	return _stage


func is_running() -> bool:
	return _stage != Stage.IDLE and _stage != Stage.DONE


## Skip to the end of the ending. Deliberately not bound to a key here — the
## gallery decides whether skipping is allowed; this only makes it possible.
func skip() -> void:
	if not is_running():
		return
	_finish()

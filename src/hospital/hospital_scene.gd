extends Node3D
## The opening: a room, a bed, and the last few seconds before she goes in.
##
## Thirty seconds at most, and it only has to do three things — establish that
## he is dying, establish that she is there, and hand the player over to the
## gallery without a cut. It plays once, at the start, and never returns (that
## was the brief: the game ends with the hug, not back here).
##
## Everything is built in code, like the gallery: the room is eleven boxes and
## two lights, which is cheaper to maintain than a scene file and keeps the
## whole project's art in one pipeline.
##
## The staging is deliberately not a close-up. The camera sits back by the door
## at roughly her eye height, the room is mostly dark, and the only bright thing
## is the window — so what the player reads is a shape in a bed and a woman
## beside it, which is as much as this scene should say.

## Stages. Time-driven; the only input is skip.
enum Stage { DARK, HOLD, RISE, LEAVE, DONE }

const FADE_IN_TIME := 3.2
const HOLD_TIME := 6.5
## The light rising as she goes in. Long, because it is the transition.
const RISE_TIME := 5.0
const LEAVE_TIME := 1.0

const ROOM_WIDTH := 4.2
const ROOM_DEPTH := 5.4
const ROOM_HEIGHT := 2.8

## Camera: back by the door, her side of the bed, looking along it toward the
## head. It pushes in a little and no more — the first framing sat almost on
## the mattress, which put the bed across the whole frame, his head out of
## shot and her cut off at the edge.
const CAM_START := Vector3(1.66, 2.06, 2.40)
const CAM_END := Vector3(1.30, 1.92, 1.35)
const CAM_LOOK := Vector3(-0.34, 0.76, -1.80)

var _stage: Stage = Stage.DARK
## Time in the current stage; reset at every stage change.
var _clock := 0.0
## Time since the scene began, which never goes backwards. The camera push
## needs this one.
var _elapsed := 0.0
var _camera: Camera3D = null
var _fade: SceneFade = null
var _window_light: OmniLight3D = null
var _window_pane: MeshInstance3D = null
var _her: PixelFigure = null
## Who is in the bed and who is standing beside it. The dying one is the SIDE
## character: the main character has come into their mind, so they cannot also
## be the one lying there.
var _cast: CastProfile = null
var _prompt: Label = null
var _prompt_layer: CanvasLayer = null
var _base_exposure := 0.62
var _env: Environment = null


func _ready() -> void:
	GameState.phase = GameState.Phase.HOSPITAL

	_cast = CastProfile.for_album(AlbumService.album())

	_build_environment()
	_build_room()
	_build_bed()
	_build_furniture()
	_build_figures()
	_build_camera()
	_build_overlay()

	_fade = SceneFade.new()
	_fade.name = "Fade"
	add_child(_fade)
	_fade.fade_in(Color(0.0, 0.0, 0.0), FADE_IN_TIME)

	CCLog.info("hospital", "opening scene ready")


# -------------------------------------------------------------- environment

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.022, 0.026)

	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Cold: it is early, and this is a room nobody chose to be in.
	_env.ambient_light_color = Color(0.33, 0.35, 0.40)
	_env.ambient_light_energy = 0.19

	_env.fog_enabled = true
	_env.fog_light_color = Color(0.22, 0.24, 0.28)
	_env.fog_light_energy = 0.4
	_env.fog_density = 0.02
	_env.fog_sky_affect = 0.0

	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = _base_exposure
	_env.tonemap_white = 9.0

	_env.glow_enabled = true
	_env.glow_intensity = 0.3
	_env.glow_bloom = 0.15
	_env.glow_hdr_threshold = 1.0
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.08
	_env.adjustment_saturation = 0.82

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)


# --------------------------------------------------------------------- room

func _build_room() -> void:
	var hw := ROOM_WIDTH * 0.5
	var hd := ROOM_DEPTH * 0.5

	_box("Floor", Vector3(ROOM_WIDTH, 0.1, ROOM_DEPTH),
		Vector3(0, -0.05, 0), Color(0.24, 0.23, 0.22), 0.7)
	_box("Ceiling", Vector3(ROOM_WIDTH, 0.1, ROOM_DEPTH),
		Vector3(0, ROOM_HEIGHT + 0.05, 0), Color(0.30, 0.30, 0.31), 0.9)

	var wall := Color(0.38, 0.40, 0.41)
	_box("WallFar", Vector3(ROOM_WIDTH, ROOM_HEIGHT, 0.12),
		Vector3(0, ROOM_HEIGHT * 0.5, -hd), wall, 0.92)
	_box("WallNear", Vector3(ROOM_WIDTH, ROOM_HEIGHT, 0.12),
		Vector3(0, ROOM_HEIGHT * 0.5, hd), wall, 0.92)
	_box("WallRight", Vector3(0.12, ROOM_HEIGHT, ROOM_DEPTH),
		Vector3(hw, ROOM_HEIGHT * 0.5, 0), wall, 0.92)

	# The left wall is the window wall, built in three pieces around the
	# opening so the light has somewhere to come from.
	_box("WallLeftLow", Vector3(0.12, 0.95, ROOM_DEPTH),
		Vector3(-hw, 0.475, 0), wall, 0.92)
	_box("WallLeftHigh", Vector3(0.12, ROOM_HEIGHT - 2.15, ROOM_DEPTH),
		Vector3(-hw, ROOM_HEIGHT - (ROOM_HEIGHT - 2.15) * 0.5, 0), wall, 0.92)
	_box("WallLeftFront", Vector3(0.12, 1.2, 1.5),
		Vector3(-hw, 1.55, hd - 0.75), wall, 0.92)
	_box("WallLeftBack", Vector3(0.12, 1.2, 1.5),
		Vector3(-hw, 1.55, -hd + 0.75), wall, 0.92)

	# Skirting, because a room with none reads as a box.
	_box("Skirting", Vector3(ROOM_WIDTH - 0.1, 0.12, 0.06),
		Vector3(0, 0.06, -hd + 0.09), Color(0.30, 0.29, 0.28), 0.8)

	_build_window()


func _build_window() -> void:
	var hw := ROOM_WIDTH * 0.5

	_window_pane = MeshInstance3D.new()
	_window_pane.name = "WindowPane"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.2)
	_window_pane.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.70, 0.74, 0.78)
	mat.emission_enabled = true
	# Blue-grey daylight, not sunshine. It turns warm as the scene ends.
	mat.emission = Color(0.72, 0.80, 0.92)
	mat.emission_energy_multiplier = 0.55
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_window_pane.material_override = mat
	_window_pane.position = Vector3(-hw + 0.07, 1.55, 0)
	_window_pane.rotation_degrees = Vector3(0, 90, 0)
	_window_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_window_pane)

	# A glazing bar, so the window is a window.
	_box("WindowBar", Vector3(0.05, 1.2, 0.05),
		Vector3(-hw + 0.1, 1.55, 0), Color(0.26, 0.26, 0.27), 0.7)

	var light := SpotLight3D.new()
	light.name = "WindowSpot"
	light.light_color = Color(0.80, 0.86, 0.98)
	light.light_energy = 3.4
	light.spot_range = 9.0
	light.spot_angle = 68.0
	light.spot_angle_attenuation = 0.7
	light.shadow_enabled = true
	# Same grazing-angle acne as the gallery; same fix (see gallery.gd).
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 4.0
	light.position = Vector3(-hw + 0.25, 1.75, 0)
	# A spot shines down its local -Z; rotate it to face across the room.
	light.rotation_degrees = Vector3(-18, -90, 0)
	add_child(light)

	# Spill from the corridor behind the camera. Without it everything on the
	# near side of the bed — her included — rendered as a black column.
	var door := OmniLight3D.new()
	door.name = "DoorSpill"
	door.light_color = Color(0.98, 0.92, 0.80)
	door.light_energy = 0.85
	door.omni_range = 5.0
	door.shadow_enabled = false
	door.position = Vector3(1.45, 2.10, 2.45)
	add_child(door)

	# A little light on her, from the open door. She is on the dark side of the
	# room by design, but at first she rendered as a solid black post.
	var on_her := OmniLight3D.new()
	on_her.name = "HerFill"
	on_her.light_color = Color(0.96, 0.90, 0.82)
	on_her.light_energy = 0.55
	on_her.omni_range = 3.2
	on_her.shadow_enabled = false
	on_her.position = Vector3(1.85, 1.55, 0.70)
	add_child(on_her)

	# The light over the bed, dimmed down for the night. Without it his head was
	# a dark patch on the pillow — the one thing in the scene that has to read.
	_box("BedLamp", Vector3(0.34, 0.07, 0.10),
		Vector3(-0.35, 2.05, -2.62), Color(0.74, 0.75, 0.76), 0.5)
	var over_bed := OmniLight3D.new()
	over_bed.name = "OverBed"
	over_bed.light_color = Color(0.94, 0.92, 0.88)
	over_bed.light_energy = 0.95
	over_bed.omni_range = 2.9
	# Shadowed, so his head sits on the pillow instead of floating above it.
	over_bed.shadow_enabled = true
	over_bed.shadow_bias = 0.04
	over_bed.shadow_normal_bias = 2.0
	over_bed.position = Vector3(-0.35, 1.92, -2.30)
	add_child(over_bed)

	_window_light = OmniLight3D.new()
	_window_light.name = "WindowBounce"
	_window_light.light_color = Color(0.84, 0.88, 0.96)
	_window_light.light_energy = 0.9
	_window_light.omni_range = 5.5
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(-hw + 0.9, 1.5, 0)
	add_child(_window_light)


# ---------------------------------------------------------------------- bed

func _build_bed() -> void:
	var sheet := Color(0.72, 0.73, 0.74)
	var blanket := Color(0.36, 0.40, 0.46)
	var frame := Color(0.52, 0.53, 0.55)

	# Bed along the far wall, head end toward -Z.
	var bed_centre := Vector3(-0.35, 0.0, -1.35)

	_box("BedBase", Vector3(1.05, 0.40, 2.10),
		bed_centre + Vector3(0, 0.20, 0), Color(0.28, 0.28, 0.30), 0.8)
	_box("Mattress", Vector3(1.02, 0.16, 2.06),
		bed_centre + Vector3(0, 0.48, 0), sheet, 0.85)
	# Greyer than a clean sheet: against a white pillow his white hair
	# disappeared entirely.
	_box("Pillow", Vector3(0.70, 0.13, 0.42),
		bed_centre + Vector3(0, 0.62, -0.80), Color(0.70, 0.71, 0.73), 0.9)

	# Him under the blanket, in three steps rather than one slab: chest,
	# then hips, then the long low run to the feet. One box read as a table.
	_box("BlanketChest", Vector3(1.04, 0.16, 0.66),
		bed_centre + Vector3(0, 0.62, -0.20), blanket, 0.95)
	_box("BlanketHips", Vector3(1.04, 0.13, 0.52),
		bed_centre + Vector3(0, 0.60, 0.34), blanket, 0.95)
	_box("BlanketLegs", Vector3(1.04, 0.09, 0.72),
		bed_centre + Vector3(0, 0.58, 0.92), blanket, 0.95)
	# His shoulders, a little proud of the blanket.
	_box("Shoulders", Vector3(0.62, 0.10, 0.20),
		bed_centre + Vector3(0, 0.70, -0.50), blanket, 0.95)
	# An arm out over the blanket on her side — the one she takes.
	_box("Arm", Vector3(0.14, 0.09, 0.52),
		bed_centre + Vector3(0.36, 0.70, -0.12), blanket, 0.95)
	_box("Hand", Vector3(0.13, 0.07, 0.15),
		bed_centre + Vector3(0.36, 0.71, 0.20),
		_dying().skin, 0.7)

	_box("Headboard", Vector3(1.10, 0.62, 0.07),
		bed_centre + Vector3(0, 0.62, -1.06), frame, 0.6)
	_box("Footboard", Vector3(1.10, 0.42, 0.07),
		bed_centre + Vector3(0, 0.52, 1.06), frame, 0.6)
	# A raised rail on her side, the way hospital beds have.
	_box("SideRail", Vector3(0.05, 0.05, 1.10),
		bed_centre + Vector3(0.55, 0.86, -0.1), frame, 0.5)
	_box("SideRailPost1", Vector3(0.04, 0.24, 0.04),
		bed_centre + Vector3(0.55, 0.74, -0.62), frame, 0.5)
	_box("SideRailPost2", Vector3(0.04, 0.24, 0.04),
		bed_centre + Vector3(0.55, 0.74, 0.42), frame, 0.5)

	# On the pillow, which tops out at 0.685.
	var head := RestingHead.new()
	head.name = "RestingHead"
	add_child(head)
	head.build(_dying().to_palette(), _dying().form)
	head.position = bed_centre + Vector3(0, 0.72, -0.78)


# ---------------------------------------------------------------- furniture

func _build_furniture() -> void:
	# Bedside table with a lamp that is switched off, and a framed photograph
	# lying flat — the one thing in the room that belongs to them rather than
	# to the hospital.
	_box("Table", Vector3(0.46, 0.06, 0.40), Vector3(0.45, 0.66, -2.05),
		Color(0.40, 0.34, 0.28), 0.7)
	_box("TableLeg1", Vector3(0.05, 0.63, 0.05), Vector3(0.26, 0.31, -1.90),
		Color(0.32, 0.27, 0.22), 0.7)
	_box("TableLeg2", Vector3(0.05, 0.63, 0.05), Vector3(0.63, 0.31, -1.90),
		Color(0.32, 0.27, 0.22), 0.7)
	_box("TableLeg3", Vector3(0.05, 0.63, 0.05), Vector3(0.26, 0.31, -2.20),
		Color(0.32, 0.27, 0.22), 0.7)
	_box("TableLeg4", Vector3(0.05, 0.63, 0.05), Vector3(0.63, 0.31, -2.20),
		Color(0.32, 0.27, 0.22), 0.7)

	_box("FramedPhoto", Vector3(0.16, 0.02, 0.12), Vector3(0.45, 0.70, -2.05),
		Color(0.68, 0.62, 0.52), 0.5)

	# A chair pushed back from the bed: she has been sitting a long time and has
	# just stood up.
	# Pushed back from the bed and away from the lens: at its first position it
	# sat directly under the camera and read as a black blob in the foreground.
	const CHAIR := Vector3(1.32, 0.0, -1.05)
	_box("ChairSeat", Vector3(0.42, 0.05, 0.42), CHAIR + Vector3(0, 0.45, 0),
		Color(0.34, 0.31, 0.28), 0.8)
	_box("ChairBack", Vector3(0.05, 0.48, 0.42), CHAIR + Vector3(0.21, 0.70, 0),
		Color(0.34, 0.31, 0.28), 0.8)
	for i in 4:
		var dx := 0.17 if i % 2 == 0 else -0.17
		var dz := 0.17 if i < 2 else -0.17
		_box("ChairLeg%d" % i, Vector3(0.04, 0.45, 0.04),
			CHAIR + Vector3(dx, 0.225, dz),
			Color(0.28, 0.26, 0.23), 0.8)

	# A drip stand, the one unmistakable sign of where this is.
	_box("StandPole", Vector3(0.035, 1.55, 0.035), Vector3(-0.95, 0.775, -2.05),
		Color(0.62, 0.63, 0.65), 0.35)
	_box("StandBase", Vector3(0.36, 0.03, 0.36), Vector3(-0.95, 0.015, -2.05),
		Color(0.55, 0.56, 0.58), 0.4)
	_box("DripBag", Vector3(0.10, 0.22, 0.05), Vector3(-0.88, 1.40, -2.05),
		Color(0.80, 0.84, 0.80), 0.3)


# ------------------------------------------------------------------ figures

## The one in the bed, and the one who is about to go in. Both fall back to the
## default cast, so this scene still builds with no saved profile at all.
func _dying() -> FigureProfile:
	if _cast == null:
		_cast = CastProfile.for_album(AlbumService.album())
	return _cast.side_figure()


func _standing() -> FigureProfile:
	if _cast == null:
		_cast = CastProfile.for_album(AlbumService.album())
	return _cast.main_figure()


func _build_figures() -> void:
	# She stands at the near side of the bed, turned toward him, so the camera
	# sees her back and her profile rather than her face. This is his scene.
	_her = PixelFigure.new()
	_her.name = "Her"
	add_child(_her)
	var standing := _standing()
	_her.build(standing.to_palette(), standing.form)
	# Same reason as the hall: a drawn figure has to turn to the lens or it is
	# a card seen edge-on, and this camera looks along the bed rather than at
	# her. She was rendering about seventy degrees off, as a sliver.
	_her.auto_face_camera = true
	_her.position = Vector3(0.62, 0.0, -1.05)
	_her.rotation_degrees = Vector3(0, 90, 0)


# ------------------------------------------------------------------- camera

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 52.0
	_camera.position = CAM_START
	_camera.look_at_from_position(CAM_START, CAM_LOOK, Vector3.UP)
	add_child(_camera)
	_camera.make_current()


func _build_overlay() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "Prompt"
	_prompt_layer.layer = 10
	add_child(_prompt_layer)

	_prompt = Label.new()
	_prompt.text = ""
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", Color(0.72, 0.70, 0.66))
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -86
	_prompt.offset_bottom = -52
	_prompt.modulate.a = 0.0
	_prompt_layer.add_child(_prompt)


# ----------------------------------------------------------------- timeline

func _process(delta: float) -> void:
	_clock += delta
	_elapsed += delta

	match _stage:
		Stage.DARK:
			_push_camera(delta)
			if _clock >= FADE_IN_TIME:
				_stage = Stage.HOLD
				_clock = 0.0
				_prompt.text = "Take his hand    ·    E"
		Stage.HOLD:
			_push_camera(delta)
			_prompt.modulate.a = clampf(_prompt.modulate.a + delta * 0.7, 0.0, 1.0)
			if _clock >= HOLD_TIME:
				_begin_rise()
		Stage.RISE:
			_push_camera(delta)
			_tick_rise()
		Stage.LEAVE:
			if _clock >= LEAVE_TIME:
				_enter_gallery()
		_:
			pass


func _unhandled_input(event: InputEvent) -> void:
	if _stage != Stage.HOLD and _stage != Stage.DARK:
		return
	if event.is_action_pressed(&"interact") or event.is_action_pressed(&"ui_accept"):
		_begin_rise()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_cancel_custom"):
		# Straight past the opening, for anyone replaying.
		_enter_gallery()
		get_viewport().set_input_as_handled()


## A very slow push toward the bed. Slow enough that it reads as attention
## rather than as a camera move.
func _push_camera(delta: float) -> void:
	if _camera == null:
		return
	# `_elapsed`, not `_clock`: the clock is reset to zero at every stage
	# change, so the push jumped backwards at DARK→HOLD and then spent the
	# whole five-second RISE — the move that is supposed to carry her into his
	# mind — easing AWAY from the bed.
	var t := clampf(_elapsed / (FADE_IN_TIME + HOLD_TIME), 0.0, 1.0)
	var eye := CAM_START.lerp(CAM_END, smoothstep(0.0, 1.0, t) * 0.85)
	_camera.position = _camera.position.lerp(eye, clampf(delta * 3.0, 0.0, 1.0))
	_camera.look_at(CAM_LOOK, Vector3.UP)


func _begin_rise() -> void:
	if _stage == Stage.RISE or _stage == Stage.LEAVE or _stage == Stage.DONE:
		return
	_stage = Stage.RISE
	_clock = 0.0
	_prompt.text = ""
	CCLog.info("hospital", "going in")


## She takes his hand, and the room gives way. The light does the work: the
## window warms and floods, the exposure climbs, and the whole thing ends
## white — which is what the gallery then fades in from, so there is no cut.
func _tick_rise() -> void:
	var t := clampf(_clock / RISE_TIME, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)

	_prompt.modulate.a = maxf(0.0, _prompt.modulate.a - 0.05)

	if _env != null:
		_env.tonemap_exposure = lerpf(_base_exposure, _base_exposure * 2.3, eased)
		_env.ambient_light_energy = lerpf(0.16, 0.85, eased)
		_env.ambient_light_color = Color(0.33, 0.35, 0.40).lerp(
			Color(0.98, 0.94, 0.86), eased)
		_env.fog_light_color = Color(0.22, 0.24, 0.28).lerp(
			Color(0.96, 0.93, 0.87), eased)
		_env.fog_density = lerpf(0.02, 0.10, eased)

	if _window_light != null:
		_window_light.light_energy = lerpf(0.9, 5.5, eased)
		_window_light.light_color = Color(0.84, 0.88, 0.96).lerp(
			Color(1.0, 0.95, 0.86), eased)

	if _window_pane != null:
		var mat: StandardMaterial3D = _window_pane.material_override
		mat.emission = Color(0.72, 0.80, 0.92).lerp(Color(1.0, 0.96, 0.88), eased)
		mat.emission_energy_multiplier = lerpf(0.55, 1.0, eased)

	# The last second and a half is a plain fade to white, so the transition
	# lands on a known colour whatever the renderer did with the exposure.
	if t > 0.68 and not _fade.is_running():
		_fade.fade_out(Color(0.97, 0.95, 0.90), RISE_TIME * 0.32)

	if t >= 1.0:
		_stage = Stage.LEAVE
		_clock = 0.0
		GameState.phase = GameState.Phase.TRANSITION


func _enter_gallery() -> void:
	if _stage == Stage.DONE:
		return
	_stage = Stage.DONE
	GameState.phase = GameState.Phase.TRANSITION
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var err := get_tree().change_scene_to_file("res://scenes/gallery/gallery.tscn")
	if err != OK:
		CCLog.error("hospital", "could not open the gallery: %d" % err)
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


# -------------------------------------------------------------------- build

func _box(node_name: String, size: Vector3, at: Vector3, albedo: Color,
		roughness: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi

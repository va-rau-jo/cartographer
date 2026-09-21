extends Node3D
## Assembles the gallery hallway: geometry, materials, lighting, the ten
## frames, the two figures, and the environment.
##
## Grey-box quality by intent. M1 exists to answer one question — does a
## realistic room with voxel people in it read well — and the answer has to be
## visible before any art budget is committed (plan §12, M1 go/no-go).
##
## Lighting follows plan §6.3: baked GI is not here yet, so this is the
## real-time stand-in — window light plus per-frame accents plus depth fog.
## No volumetric fog and no SSAO, because the Compatibility renderer has
## neither; the shafts are geometry (LightShaft) and contact shading will come
## from Blender-baked AO in the trim sheets.

const FOG_DENSITY := 0.009
const AMBIENT_ENERGY := 0.20

## Matches the white the hospital scene fades out to.
const ARRIVAL_COLOR := Color(0.97, 0.95, 0.90)
const ARRIVAL_FADE_TIME := 3.0

## Shadow bias for every shadow-casting light in the hall.
##
## Godot's defaults (0.03 / 1.0) give bad acne here, and it had been in every
## render for two milestones read as corrugated plaster: the clerestory light
## strikes the opposite wall at a grazing angle, which is the worst case for
## shadow-map self-shadowing. 0.08 / 4.0 removes the banding completely while
## keeping the pictures' cast shadows attached to their frames; higher values
## start to detach them (see tools/diag_shadows.gd, which is what settled it).
const SHADOW_BIAS := 0.08
const SHADOW_NORMAL_BIAS := 4.0

@export var show_debug_markers := false

## Fake volumetric shafts are OFF by default.
##
## They are built and wired up (LightShaft), but additive slab geometry does
## not survive this corridor: cull_disabled renders both faces of every box,
## the fades are evaluated at the surface rather than integrated through the
## volume, and looking down the hall stacks ten of them — which blew the whole
## upper frame to white at any energy high enough to see.
##
## Doing this properly needs either raymarched fog or a single camera-facing
## billboard per window, and it is cosmetic: the hall reads well without it.
## Revisit at M7 alongside the lightmap bake, when the lighting model changes
## anyway. Turn on to experiment.
@export var enable_light_shafts := false

var hallway: HallwayBuilder.Result = null
var frames: Array[PhotoFrame] = []
var player: PlayerController = null
var companion: PixelFigure = null
## The two characters, read once when the hall is built. The player controller
## builds its own figure from the same place.
var cast: CastProfile = null

var rounds: RoundController = null
var hud: Node = null
var guess_panel: Node = null
var ending: EndingSequence = null
var results: Node = null

var _shafts: Array[LightShaft] = []


func _ready() -> void:
	hallway = HallwayBuilder.build()

	_build_environment()
	_build_shell()
	_build_windows()
	_build_frames()
	_build_characters()
	_build_round_logic()
	_build_arrival()

	GameState.phase = GameState.Phase.GALLERY_IDLE
	CCLog.info("gallery", "built: %d frames, %d windows, %d shafts, hall %.1f m"
		% [frames.size(), hallway.window_anchors.size(), _shafts.size(),
		   hallway.hall_length])


# --------------------------------------------------------------- environment

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.031, 0.027)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.34, 0.38)
	env.ambient_light_energy = AMBIENT_ENERGY

	# Depth fog: the far end of the hall falls into darkness, which is where he
	# waits and is also how the renderer's limits get hidden (plan §1.5).
	env.fog_enabled = true
	env.fog_light_color = Color(0.26, 0.23, 0.21)
	env.fog_light_energy = 0.55
	env.fog_density = FOG_DENSITY
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.70
	env.tonemap_white = 9.0

	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.glow_bloom = 0.10
	env.glow_hdr_threshold = 1.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.94

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)


# --------------------------------------------------------------------- shell

func _build_shell() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Shell"
	mi.mesh = hallway.mesh

	# One material per surface. Flat colours at grey-box; these become the
	# trim sheets with Blender-baked AO at M7.
	var mats := [
		_matte(Color(0.20, 0.16, 0.13), 0.55, 0.22),   # floor: dark parquet
		_matte(Color(0.52, 0.49, 0.44), 0.88, 0.10),   # walls: warm plaster
		_matte(Color(0.44, 0.41, 0.37), 0.72, 0.14),   # trim
		_matte(Color(0.40, 0.38, 0.35), 0.92, 0.06),   # ceiling
	]
	for i in mini(mats.size(), hallway.mesh.get_surface_count()):
		mi.set_surface_override_material(i, mats[i])

	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "ShellCollision"
	for box in hallway.colliders:
		var shape := BoxShape3D.new()
		shape.size = box["size"]
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = box["origin"]
		body.add_child(cs)
	add_child(body)


func _matte(albedo: Color, roughness: float, specular: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = specular
	return m


# ------------------------------------------------------------------- windows

func _build_windows() -> void:
	var win_size := Vector2(HallwayBuilder.CLERESTORY_WIDTH,
		HallwayBuilder.CLERESTORY_HEAD - HallwayBuilder.CLERESTORY_SILL)

	for i in hallway.window_anchors.size():
		var anchor: Transform3D = hallway.window_anchors[i]

		var holder := Node3D.new()
		holder.name = "Window_%d" % i
		holder.transform = anchor
		add_child(holder)

		# The pane itself: bright, unshaded, so it reads as daylight outside.
		var pane := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = win_size
		pane.mesh = quad
		var pane_mat := StandardMaterial3D.new()
		pane_mat.albedo_color = Color(0.74, 0.74, 0.70)
		pane_mat.emission_enabled = true
		pane_mat.emission = Color(1.0, 0.95, 0.84)
		# Bright, but nowhere near 2.6: with ACES plus glow that clipped to a
		# featureless white slab and read as a light box rather than daylight.
		pane_mat.emission_energy_multiplier = 0.34
		pane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pane.material_override = pane_mat
		# No extra rotation: the window anchor's basis already faces local +Z
		# into the hall, and a QuadMesh faces +Z. Rotating it again laid the
		# panes flat along the hall so they overlapped into one glowing wall.
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(pane)

		# The actual light doing the work on the opposite wall.
		var light := SpotLight3D.new()
		light.light_color = Color(1.0, 0.94, 0.82)
		light.light_energy = 4.4
		light.spot_range = 16.0
		light.spot_angle = 62.0
		light.spot_angle_attenuation = 0.6
		light.shadow_enabled = true
		light.shadow_bias = SHADOW_BIAS
		light.shadow_normal_bias = SHADOW_NORMAL_BIAS
		light.position = Vector3(0, 0.2, 0.3)
		# A spot shines along its local -Z. The anchor's local -Z points back
		# through the wall, so this turns it around to face into the hall and
		# tilts it down onto the opposite wall where the pictures hang. Getting
		# this backwards left the whole corridor unlit by anything but the
		# accent lights.
		# Steeper than before: the opening is now four metres up, and the
		# pictures it has to reach are on the far wall and low down.
		light.rotation_degrees = Vector3(-34, 180, 0)
		holder.add_child(light)

		var bounce := OmniLight3D.new()
		bounce.light_color = Color(0.92, 0.88, 0.80)
		bounce.light_energy = 0.42
		bounce.omni_range = 6.5
		bounce.shadow_enabled = false
		bounce.position = Vector3(0, -1.2, 2.4)
		holder.add_child(bounce)

		if not enable_light_shafts:
			continue

		var shaft := LightShaft.new()
		shaft.name = "Shaft"
		holder.add_child(shaft)
		# No node rotation: the slab extends along its own local +Z, which the
		# window anchor already points into the hall. Keep the energy low —
		# looking down the corridor you see through several shafts at once and
		# additive blending stacks them.
		shaft.setup(win_size, HallwayBuilder.HALL_WIDTH + 0.4, 0.085)
		_shafts.append(shaft)

	# The near end has no window of its own, so she would begin in the dark.
	# A dim spill from the doorway she arrives through.
	var entrance := OmniLight3D.new()
	entrance.name = "EntranceSpill"
	entrance.light_color = Color(0.96, 0.90, 0.80)
	entrance.light_energy = 1.7
	entrance.omni_range = 9.5
	entrance.shadow_enabled = true
	entrance.shadow_bias = SHADOW_BIAS
	entrance.shadow_normal_bias = SHADOW_NORMAL_BIAS
	entrance.position = Vector3(0, 2.6, 0.9)
	add_child(entrance)

	# Dust in the shafts. One emitter for the whole hall.
	_build_dust()


func _build_dust() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Dust"
	particles.amount = 620
	particles.lifetime = 14.0
	particles.preprocess = 7.0
	# In the emitter's OWN space, which is where Godot interprets it — and the
	# emitter is offset to the middle of the hall below. Written in hall
	# coordinates it declared a box that did not contain the particles, so
	# looking at the near half of the hall put the declared box outside the
	# frustum and the whole dust system was culled: the dust flickered out
	# depending on where she was standing.
	var half_len := hallway.hall_length * 0.5
	particles.visibility_aabb = AABB(
		Vector3(-HallwayBuilder.HALL_WIDTH, -HallwayBuilder.HALL_HEIGHT * 0.5 - 1.0,
			-half_len - 2.0),
		Vector3(HallwayBuilder.HALL_WIDTH * 2.0,
			HallwayBuilder.HALL_HEIGHT + 2.0, hallway.hall_length + 4.0))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(HallwayBuilder.HALL_WIDTH * 0.5,
		HallwayBuilder.HALL_HEIGHT * 0.5, hallway.hall_length * 0.5)
	mat.gravity = Vector3(0, -0.012, 0)
	mat.initial_velocity_min = 0.01
	mat.initial_velocity_max = 0.05
	mat.scale_min = 0.6
	mat.scale_max = 1.8
	mat.color = Color(1.0, 0.95, 0.86, 0.22)
	particles.process_material = mat

	var dot := QuadMesh.new()
	dot.size = Vector2(0.009, 0.009)
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dot_mat.albedo_color = Color(1.0, 0.96, 0.88, 0.30)
	dot_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dot_mat.vertex_color_use_as_albedo = true
	dot.material = dot_mat
	particles.draw_pass_1 = dot

	particles.position = Vector3(0, HallwayBuilder.HALL_HEIGHT * 0.5,
		-hallway.hall_length * 0.5)
	add_child(particles)


# -------------------------------------------------------------------- frames

func _build_frames() -> void:
	var album := AlbumService.album()
	# Not a ternary: the empty-literal branch would be an untyped Array and
	# will not assign to Array[Photo].
	var hung: Array[AlbumSchema.Photo] = []
	if album != null:
		hung = album.hung_photos()

	for i in hallway.frame_anchors.size():
		# An album with fewer than a full wall leaves the rest of the hall
		# bare. The alternative is a frame she can walk up to, prompt at, and
		# never examine — and because the ending waits for every frame to be
		# played, a hall with one unplayable frame in it never ends. Only a
		# gallery with no album at all falls through to the placeholders.
		if album != null and i >= hung.size():
			break

		var frame := PhotoFrame.new()
		add_child(frame)
		frame.transform = hallway.frame_anchors[i]

		if i < hung.size():
			var photo := hung[i]
			frame.setup(photo, AlbumService.tier_texture(photo.id, 0))
		else:
			# No album loaded: still hang something, so the space can be judged
			# on its own before the data layer is wired in.
			var placeholder := AlbumSchema.Photo.new()
			placeholder.id = "placeholder_%d" % i
			placeholder.aspect = [1.5, 0.667, 1.0, 1.33, 0.75][i % 5]
			frame.setup(placeholder, _placeholder_texture(i))

		frames.append(frame)


## Stand-in imagery so the mat system can be judged with mixed aspects before
## a real album exists.
func _placeholder_texture(index: int) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 700 + index * 53
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.02
	var img := noise.get_image(256, 256)
	img.convert(Image.FORMAT_RGBA8)
	var tint := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	tint.fill(Color.from_hsv(fmod(0.07 + float(index) * 0.06, 1.0), 0.45, 1.0, 0.45))
	img.blend_rect(tint, Rect2i(0, 0, 256, 256), Vector2i.ZERO)
	img.convert(Image.FORMAT_RGB8)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- characters

func _build_characters() -> void:
	player = PlayerController.new()
	player.name = "Player"
	add_child(player)
	player.transform = hallway.player_start

	# The side character waits at the far end, in the dark, facing back up the
	# hall.
	cast = CastProfile.for_album(AlbumService.album())
	var waiting := cast.side_figure()
	companion = PixelFigure.new()
	companion.name = "Companion"
	add_child(companion)
	companion.build(waiting.to_palette(), waiting.form)
	companion.transform = hallway.companion_end
	companion.rotation_degrees = Vector3(0, 180, 0)
	# Turn the drawing to whoever is looking, every frame. Standing still is
	# not an excuse: without this the figure is a flat card at a fixed angle,
	# and at 180° that card was showing its back.
	companion.auto_face_camera = true


## The round machine, the HUD, the guess panel, the ending and the results.
## Built last, because each needs the frames and the figures to already exist.
func _build_round_logic() -> void:
	var album := AlbumService.album()

	hud = load("res://src/ui/hud.gd").new()
	hud.name = "HUD"
	add_child(hud)

	guess_panel = load("res://src/ui/guess_panel.gd").new()
	guess_panel.name = "GuessPanel"
	add_child(guess_panel)

	rounds = RoundController.new()
	rounds.name = "RoundController"
	add_child(rounds)
	rounds.setup(album, frames, player)

	ending = EndingSequence.new()
	ending.name = "EndingSequence"
	ending.setup(player, companion, album, cast)
	add_child(ending)

	# Above the fade, so the numbers arrive on a white screen rather than under
	# it. The results screen shows itself on EventBus.ending_finished.
	results = load("res://src/ui/results_screen.gd").new()
	results.name = "ResultsScreen"
	add_child(results)
	results.setup(album)

	hud.setup(rounds)
	guess_panel.setup(rounds, album)


## She arrives out of the light the hospital scene ended on, so there is no
## cut between the two scenes — the white simply clears. Entered straight from
## the menu it is the same fade from a colour nobody was looking at, which
## costs nothing and still beats popping into a lit room.
func _build_arrival() -> void:
	var fade := SceneFade.new()
	fade.name = "ArrivalFade"
	add_child(fade)
	fade.fade_in(ARRIVAL_COLOR, ARRIVAL_FADE_TIME)


func camera() -> Camera3D:
	return player.camera if player != null else null


func _unhandled_input(event: InputEvent) -> void:
	# During the ending, Escape skips to the results rather than dropping her
	# back to the menu mid-hug.
	if GameState.phase == GameState.Phase.ENDING:
		if event.is_action_pressed(&"ui_cancel_custom") and ending != null \
				and ending.is_running():
			ending.skip()
			get_viewport().set_input_as_handled()
		return

	# Without this the captured mouse has no way out of a grey-box build.
	if event.is_action_pressed(&"ui_cancel_custom"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

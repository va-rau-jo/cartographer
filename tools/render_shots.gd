extends SceneTree
## Renders review screenshots of the gallery from fixed vantages.
##
##   xvfb-run -a godot --path . --script tools/render_shots.gd
##
## Exists because M1's exit criterion is a visual judgement (plan §12), and a
## judgement needs an image. Deterministic camera positions mean the shots are
## comparable between runs, so a lighting change can be judged as a diff rather
## than from memory.
##
## Writes to user://shots/. Also usable on a headless CI box, which is why it
## does not depend on the game's input or round logic at all.

const OUT_DIR := "user://shots"
const WARMUP_FRAMES := 10
## Software rasterisation (CI, or a container with no GPU) is slow enough that
## resolution has to be modest; the composition is what these shots are for.
const SHOT_SIZE := Vector2i(960, 540)

const SHOTS := [
	{"name": "01_down_the_hall",
	 "pos": Vector3(0.0, 1.62, 0.6), "look": Vector3(0.0, 1.9, -18.0), "fov": 66.0,
	 "pose_player": Vector3(2.1, 0.0, -11.6),
	 "note": "Her eye level at the near end. Nine metres wide, pictures on"
		+ " both walls, clerestory above."},

	{"name": "02_facing_pair",
	 "pos": Vector3(0.0, 2.0, -1.2), "look": Vector3(3.2, 2.1, -3.4), "fov": 58.0,
	 "pose_player": Vector3(2.1, 0.0, -11.6),
	 "note": "A bay's pair of pictures facing each other across the hall."},

	{"name": "03_frame_portrait",
	 "pos": Vector3(1.4, 2.10, -7.4), "look": Vector3(4.6, 2.05, -7.4), "fov": 52.0,
	 "note": "A portrait photo in the SAME landscape frame every other photo"
		+ " uses: the mount board absorbs the difference (plan §4.3)."},

	{"name": "04_raking_light",
	 "pos": Vector3(-3.0, 1.55, -1.4), "look": Vector3(3.6, 3.4, -10.0), "fov": 72.0,
	 "note": "Clerestory light down the pilasters and cornice — whether the"
		+ " mouldings read without SSAO."},

	{"name": "05_figure_in_room",
	 "pos": Vector3(-1.0, 1.55, -4.2), "look": Vector3(2.4, 1.15, -7.6), "fov": 52.0,
	 "pose_player": Vector3(2.0, 0.0, -7.4),
	 "note": "THE STYLE TEST: the drawn figure at a picture, in clerestory"
		+ " light, casting a real shadow."},

	{"name": "06_far_end",
	 "pos": Vector3(0.0, 1.70, -14.0), "look": Vector3(-1.1, 1.3, -26.0), "fov": 62.0,
	 "note": "The dark end where he waits, and how the fog carries it."},

	{"name": "07_third_person",
	 "pos": Vector3(0.4, 2.35, -1.6), "look": Vector3(0.0, 1.05, -8.0), "fov": 64.0,
	 "pose_player": Vector3(0.0, 0.0, -4.6),
	 "note": "Roughly the playing camera: her figure on screen, hall beyond."},

	{"name": "08_guessing",
	 "pos": Vector3(-2.4, 2.05, -1.0), "look": Vector3(3.4, 2.05, -3.4), "fov": 60.0,
	 "pose_player": Vector3(1.6, 0.0, -3.4),
	 "open_round": 0,
	 "note": "A round open: the HUD's spend panel, the guess panel, and a"
		+ " photograph still at tier 0."},

	{"name": "09_figure_close",
	 "pos": Vector3(0.1, 1.42, -5.9), "look": Vector3(1.75, 1.05, -7.4), "fov": 46.0,
	 "pose_player": Vector3(2.0, 0.0, -7.4),
	 "note": "Close on the figure: is the pixel resolution and shading"
		+ " readable at conversation distance?"},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var root_window := get_root()
	root_window.size = SHOT_SIZE

	var gallery: Node3D = load("res://src/mansion/gallery.gd").new()
	gallery.name = "Gallery"
	root_window.add_child(gallery)

	var cam := Camera3D.new()
	cam.name = "ShotCamera"
	root_window.add_child(cam)
	cam.make_current()

	# Lighting, shadow maps and the particle preroll all need a few frames to
	# settle; a single frame gives black shadows and no dust.
	for _i in WARMUP_FRAMES:
		await process_frame

	# Drop the arrival fade. The gallery opens by fading in from white over
	# three seconds, and at software-rendering frame rates that fade was still
	# half up when the shutter went — every shot came out looking hazy and
	# overexposed, which was read for a while as a lighting problem.
	var fade := gallery.get_node_or_null("ArrivalFade")
	if fade != null:
		fade.free()

	var written: PackedStringArray = PackedStringArray()

	for shot in SHOTS:
		if shot.has("open_round"):
			gallery.rounds.debug_open(int(shot["open_round"]))
		if shot.has("pose_player"):
			gallery.player.position = shot["pose_player"]
			# Face the wall she is standing at, so the drawn view the figure
			# picks is the one the shot is meant to show.
			var face_yaw: float = 90.0 if shot["pose_player"].x > 0.0 else -90.0
			gallery.player.rotation_degrees = Vector3(0, face_yaw, 0)
		cam.position = shot["pos"]
		cam.look_at(shot["look"], Vector3.UP)
		cam.fov = shot["fov"]

		for _i in 2:
			await process_frame

		var img := root_window.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, shot["name"]]
		var err := img.save_png(path)
		if err != OK:
			print("FAILED to write %s (%d)" % [path, err])
			continue
		written.append(path)
		print("  %-22s %s" % [shot["name"], shot["note"]])

	# A few facts worth having next to the pictures.
	print("")
	print("hall length    %.1f m" % gallery.hallway.hall_length)
	print("frames hung    %d" % gallery.frames.size())
	print("figure tris    %d (all three drawn views), sprite %dx%d"
		% [gallery.player.figure.total_triangles(),
		   PixelFigure.SPRITE_WIDTH, PixelFigure.SPRITE_HEIGHT])
	print("hall           %.1f m wide, %.1f m high"
		% [HallwayBuilder.HALL_WIDTH, HallwayBuilder.HALL_HEIGHT])
	print("picture        %.2f x %.2f m opening"
		% [PhotoFrame.OPENING_WIDTH, PhotoFrame.OPENING_HEIGHT])
	print("shell surfaces %d" % gallery.hallway.mesh.get_surface_count())
	var shell_tris := 0
	for s in gallery.hallway.mesh.get_surface_count():
		shell_tris += gallery.hallway.mesh.surface_get_array_len(s) / 3
	print("shell tris     %d" % shell_tris)
	print("")
	print("wrote %d shots to %s" % [written.size(), ProjectSettings.globalize_path(OUT_DIR)])

	quit(0 if written.size() == SHOTS.size() else 1)

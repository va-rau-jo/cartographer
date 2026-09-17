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
	 "pos": Vector3(0.6, 1.62, 0.2), "look": Vector3(-0.2, 1.5, -18.0), "fov": 62.0,
	 "note": "Her eye level, at the near end. The whole space in one read."},

	{"name": "02_frame_landscape",
	 "pos": Vector3(0.55, 1.72, -2.2), "look": Vector3(2.3, 1.72, -2.2), "fov": 48.0,
	 "note": "A landscape photo: shallow top and bottom mat."},

	{"name": "03_frame_portrait",
	 "pos": Vector3(0.55, 1.72, -4.6), "look": Vector3(2.3, 1.72, -4.6), "fov": 48.0,
	 "note": "A portrait photo in the SAME frame: wide side mat. This is the"
		+ " uniform-frame test (plan §4.3)."},

	{"name": "04_raking_light",
	 "pos": Vector3(-1.4, 1.30, -1.0), "look": Vector3(1.9, 2.1, -9.0), "fov": 70.0,
	 "note": "Window light across the pilasters and cornice — whether the"
		+ " mouldings read without SSAO."},

	{"name": "05_voxel_in_room",
	 "pos": Vector3(-1.5, 1.45, -2.6), "look": Vector3(0.9, 1.0, -4.4), "fov": 50.0,
	 "pose_player": Vector3(1.1, 0.0, -4.5),
	 "note": "THE STYLE TEST: a voxel figure in window light, in front of a"
		+ " lit frame. Does the clash read as intent?"},

	{"name": "06_far_end",
	 "pos": Vector3(0.0, 1.60, -17.0), "look": Vector3(-0.7, 1.2, -26.0), "fov": 60.0,
	 "note": "The dark end where he waits, and how the fog carries it."},

	{"name": "07_third_person",
	 "pos": Vector3(0.1, 2.10, -1.2), "look": Vector3(0.2, 1.05, -6.5), "fov": 62.0,
	 "pose_player": Vector3(0.2, 0.0, -3.6),
	 "note": "Roughly the playing camera: her figure on screen, hall beyond."},
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

	var written: PackedStringArray = PackedStringArray()

	for shot in SHOTS:
		if shot.has("pose_player"):
			gallery.player.position = shot["pose_player"]
			gallery.player.rotation_degrees = Vector3(0, 180, 0)
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
	print("figure tris    %d (player), %d (companion)"
		% [gallery.player.figure.total_triangles(), gallery.companion.total_triangles()])
	print("shell surfaces %d" % gallery.hallway.mesh.get_surface_count())
	var shell_tris := 0
	for s in gallery.hallway.mesh.get_surface_count():
		shell_tris += gallery.hallway.mesh.surface_get_array_len(s) / 3
	print("shell tris     %d" % shell_tris)
	print("")
	print("wrote %d shots to %s" % [written.size(), ProjectSettings.globalize_path(OUT_DIR)])

	quit(0 if written.size() == SHOTS.size() else 1)

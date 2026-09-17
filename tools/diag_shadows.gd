extends Node
## Diagnostic: is the banding across the walls shadow acne?
##
## The gallery's walls and ceiling carry regular horizontal stripes in every
## render. They look like corrugation but there is none in the geometry, so the
## suspect is shadow-map self-shadowing from the clerestory spots, which strike
## the opposite wall at a grazing angle — the classic case.
##
## This renders the same vantage four ways: shadows off, and three bias
## settings. Whichever kills the stripes without detaching the figures' shadows
## from their feet is the answer.
##
##   xvfb-run -a godot --path . --script tools/diag_shadows.gd
##
## Loaded as a Node rather than run with --script directly, for the autoload
## reason documented in tests/test_host.gd.

const OUT_DIR := "user://shots/diag"
const SHOT_SIZE := Vector2i(960, 540)

const VANTAGE_POS := Vector3(-3.0, 1.55, -1.4)
const VANTAGE_LOOK := Vector3(3.6, 3.4, -10.0)

const VARIANTS := [
	{"name": "a_shadows_off", "shadows": false, "bias": 0.0, "normal": 0.0},
	{"name": "b_default", "shadows": true, "bias": -1.0, "normal": -1.0},
	{"name": "c_bias_mid", "shadows": true, "bias": 0.08, "normal": 4.0},
	{"name": "d_bias_high", "shadows": true, "bias": 0.20, "normal": 8.0},
]


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var window := get_window()
	window.size = SHOT_SIZE

	var gallery: Node3D = load("res://src/mansion/gallery.gd").new()
	gallery.name = "Gallery"
	window.add_child(gallery)

	var cam := Camera3D.new()
	window.add_child(cam)
	cam.make_current()
	cam.fov = 72.0
	cam.position = VANTAGE_POS
	cam.look_at(VANTAGE_LOOK, Vector3.UP)

	for _i in 10:
		await get_tree().process_frame

	# Drop the gallery's fade-in from white (see tools/render_shots.gd).
	var fade := gallery.get_node_or_null("ArrivalFade")
	if fade != null:
		fade.free()

	var lights: Array[Light3D] = []
	for node in gallery.find_children("*", "Light3D", true, false):
		lights.append(node as Light3D)
	print("found %d lights" % lights.size())
	if not lights.is_empty():
		print("defaults: bias %.3f, normal_bias %.3f"
			% [lights[0].shadow_bias, lights[0].shadow_normal_bias])

	for variant in VARIANTS:
		for light in lights:
			light.shadow_enabled = bool(variant["shadows"])
			if float(variant["bias"]) >= 0.0:
				light.shadow_bias = float(variant["bias"])
				light.shadow_normal_bias = float(variant["normal"])

		for _i in 4:
			await get_tree().process_frame

		var img := window.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, variant["name"]]
		print("  %s -> %s" % [variant["name"], "ok" if img.save_png(path) == OK else "FAILED"])

	print("wrote to %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)

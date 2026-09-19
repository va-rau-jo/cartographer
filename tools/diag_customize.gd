extends Node
## Photographs the Characters screen — the two characters, their names and how
## they look.
##
##   xvfb-run -a godot --path . --script tools/run_diag_customize.gd
##
## The preview is a SubViewport with its own light rig, which is the sort of
## thing that comes out black or empty for reasons no assertion would notice.
## Both figures are photographed, because there are now two of them and the
## man's body is drawn from scratch.

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(1500, 900)


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var window := get_window()
	window.size = SHOT_SIZE

	var scene := load("res://scenes/menu/customize.tscn") as PackedScene
	if scene == null:
		print("scenes/menu/customize.tscn did not load")
		get_tree().quit(3)
		return

	var screen: Control = scene.instantiate()
	window.add_child(screen)
	for _i in 6:
		await get_tree().process_frame

	var editor: CastEditor = screen._editor

	# The main character, in colours that are nobody's default, so the swatches
	# visibly do something.
	editor._select(CastProfile.Role.MAIN)
	editor.cast.main.skin = FigureProfile.SKINS[3]
	editor.cast.main.hair = FigureProfile.HAIRS[0]
	editor._rebuild_figure()
	editor._mark_chosen()
	editor._turning = false
	editor._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "50_characters_main")
	var main_tris: int = editor._figure.total_triangles()

	# The side character, which is the other drawing.
	editor._select(CastProfile.Role.SIDE)
	editor._turning = false
	editor._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "51_characters_side")
	var side_tris: int = editor._figure.total_triangles()

	# Its profile and its back, because a drawn figure has three views and two
	# of them are easy to get wrong without noticing.
	editor._angle = PI * 0.5
	editor._figure.rotation.y = editor._angle
	for _i in 4:
		await get_tree().process_frame
	_save(window, "52_characters_side_profile")

	editor._angle = PI
	editor._figure.rotation.y = editor._angle
	for _i in 4:
		await get_tree().process_frame
	_save(window, "53_characters_side_back")

	# The one button that changes the game: swapping the two.
	editor._on_swap()
	editor._turning = false
	editor._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "54_characters_swapped")

	# And the main character on the skirt build, to prove the build is a look
	# and not a role.
	editor._select(CastProfile.Role.MAIN)
	editor._set_build(PixelFigure.Build.SKIRT)
	editor._turning = false
	editor._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "55_characters_main_skirt")

	print("")
	print("main tris      %d" % main_tris)
	print("side tris      %d" % side_tris)
	print("preview size   %dx%d"
		% [editor._viewport.size.x, editor._viewport.size.y])
	print("main           %s" % editor.cast.main_name())
	print("side           %s" % editor.cast.side_name())
	get_tree().quit(0)


func _save(window: Window, name: String) -> void:
	var img := window.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  %-16s %s" % [name, "ok" if img.save_png(path) == OK else "FAILED"])

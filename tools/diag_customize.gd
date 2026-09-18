extends Node
## Photographs the "choose how she looks" screen.
##
##   xvfb-run -a godot --path . --script tools/run_diag_customize.gd
##
## The preview is a SubViewport with its own light rig, which is the sort of
## thing that comes out black or empty for reasons no assertion would notice.

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

	# A figure that is nobody's default, so the swatches visibly do something.
	for _i in 6:
		await get_tree().process_frame
	screen.profile.skin = FigureProfile.SKINS[3]
	screen.profile.hair = FigureProfile.HAIRS[0]
	screen.profile.dress = FigureProfile.DRESSES[1]
	screen.profile.wrap = FigureProfile.WRAPS[5]
	screen._rebuild_figure()
	screen._mark_chosen()
	screen._turning = false
	screen._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "50_customize")

	print("")
	print("figure tris    %d" % screen._figure.total_triangles())
	print("preview size   %dx%d" % [screen._viewport.size.x, screen._viewport.size.y])
	print("chosen dress   %s" % screen.profile.dress.to_html(false))
	get_tree().quit(0)


func _save(window: Window, name: String) -> void:
	var img := window.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  %-16s %s" % [name, "ok" if img.save_png(path) == OK else "FAILED"])

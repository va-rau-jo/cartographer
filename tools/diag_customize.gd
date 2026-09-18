extends Node
## Photographs "the two of you" — the screen where you choose who walks the
## hall, what they are called, and how they look.
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

	# Her, in colours that are nobody's default, so the swatches visibly do
	# something.
	screen._set_editing(CastProfile.Role.WIFE)
	screen.cast.wife.skin = FigureProfile.SKINS[3]
	screen.cast.wife.hair = FigureProfile.HAIRS[0]
	screen.cast.wife.dress = FigureProfile.DRESSES[1]
	screen.cast.wife.wrap = FigureProfile.WRAPS[5]
	screen._rebuild_figure()
	screen._mark_chosen()
	screen._turning = false
	screen._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "50_customize_her")
	var her_tris: int = screen._figure.total_triangles()

	# Him, which is the new drawing: trousers, a short crop, no bun.
	screen._set_editing(CastProfile.Role.HUSBAND)
	screen._turning = false
	screen._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "51_customize_him")
	var his_tris: int = screen._figure.total_triangles()

	# His profile and his back, because a drawn figure has three views and two
	# of them are easy to get wrong without noticing.
	screen._angle = PI * 0.5
	screen._figure.rotation.y = screen._angle
	for _i in 4:
		await get_tree().process_frame
	_save(window, "52_customize_him_side")

	screen._angle = PI
	screen._figure.rotation.y = screen._angle
	for _i in 4:
		await get_tree().process_frame
	_save(window, "53_customize_him_back")

	# And the whole point of the screen: playing as him instead.
	screen._set_player(CastProfile.Role.HUSBAND)
	screen._turning = false
	screen._angle = 0.35
	for _i in 6:
		await get_tree().process_frame
	_save(window, "54_customize_playing_as_him")

	print("")
	print("her tris       %d" % her_tris)
	print("his tris       %d" % his_tris)
	print("preview size   %dx%d" % [screen._viewport.size.x, screen._viewport.size.y])
	print("playing as     %s" % screen.cast.player_name())
	print("waiting        %s" % screen.cast.companion_name())
	print("his trousers   %s" % screen.cast.husband.dress.to_html(false))
	get_tree().quit(0)


func _save(window: Window, name: String) -> void:
	var img := window.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  %-16s %s" % [name, "ok" if img.save_png(path) == OK else "FAILED"])

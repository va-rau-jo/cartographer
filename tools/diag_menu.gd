extends Node
## Photographs the main menu, which is the one screen everybody sees first.
##
##   xvfb-run -a godot --path . --script tools/run_diag_menu.gd

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(1280, 800)


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var window := get_window()
	window.size = SHOT_SIZE

	var scene := load("res://scenes/menu/main_menu.tscn") as PackedScene
	if scene == null:
		print("scenes/menu/main_menu.tscn did not load")
		get_tree().quit(3)
		return
	window.add_child(scene.instantiate())

	for _i in 4:
		await get_tree().process_frame

	var img := window.get_texture().get_image()
	var path := "%s/60_menu.png" % OUT_DIR
	print("  %-16s %s" % ["60_menu", "ok" if img.save_png(path) == OK else "FAILED"])
	get_tree().quit(0)

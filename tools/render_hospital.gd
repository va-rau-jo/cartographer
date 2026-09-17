extends SceneTree
## Renders the opening scene.
##
##   xvfb-run -a godot --path . --script tools/render_hospital.gd
##
## Thin, like tools/render_ending.gd: the work is in tools/hospital_shots.gd,
## because a `--script` script cannot name the autoloads.


func _initialize() -> void:
	var script := load("res://tools/hospital_shots.gd") as GDScript
	if script == null:
		push_error("could not load tools/hospital_shots.gd")
		quit(2)
		return
	var host: Node = script.new()
	host.name = "HospitalShots"
	root.add_child(host)

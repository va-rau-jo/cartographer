extends SceneTree
## Renders the ending and the results screen.
##
##   xvfb-run -a godot --path . --script tools/render_ending.gd
##
## Separate from render_shots.gd because this one has to drive time: the ending
## is a stage machine, so the interesting frames are at particular moments
## inside it rather than at particular camera positions. It fakes a finished
## session, starts the ending, and photographs it as it plays.
##
## This file is deliberately tiny. A `--script` script is compiled before the
## autoloads exist as globals, so the work is done by tools/ending_shots.gd,
## which is loaded into the tree and can name GameState and EventBus freely.


func _initialize() -> void:
	var script := load("res://tools/ending_shots.gd") as GDScript
	if script == null:
		push_error("could not load tools/ending_shots.gd")
		quit(2)
		return
	var host: Node = script.new()
	host.name = "EndingShots"
	root.add_child(host)

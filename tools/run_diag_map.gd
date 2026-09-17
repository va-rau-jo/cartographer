extends SceneTree
## Entry point for tools/diag_map.gd. See tests/test_host.gd for why the work
## happens in a Node rather than here.


func _initialize() -> void:
	var script := load("res://tools/diag_map.gd") as GDScript
	if script == null:
		push_error("could not load tools/diag_map.gd")
		quit(2)
		return
	var host: Node = script.new()
	host.name = "DiagMap"
	root.add_child(host)

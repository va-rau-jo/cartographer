extends SceneTree
## Entry point for tools/diag_shadows.gd. See tests/test_host.gd for why the
## work happens in a Node rather than here.


func _initialize() -> void:
	var script := load("res://tools/diag_shadows.gd") as GDScript
	if script == null:
		push_error("could not load tools/diag_shadows.gd")
		quit(2)
		return
	var host: Node = script.new()
	host.name = "DiagShadows"
	root.add_child(host)

extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script tests/run_tests.gd
##
## Exits non-zero on failure so CI can gate on it. The report is also written
## to user://test_report.txt, because stdout from a headless run is easy to
## lose to pipe buffering.
##
## This file does almost nothing on purpose. Two constraints shape it:
##
##   1. It is compiled BEFORE the project's autoloads are registered as
##      GDScript globals, so it must not name `Platform`, `GameState` and
##      friends. (The logger silences itself for test runs — see cc_log.gd.)
##   2. During `_initialize()` the root Window is not yet inside the tree, so
##      anything added to it has no working `_ready()` and no global
##      transforms. Tests that build real nodes need a live tree.
##
## So the suite list lives here and the work happens in tests/test_host.gd,
## which runs from its own `_ready()` — by which time the tree is live.

const SUITES := [
	"res://tests/test_geo.gd",
	"res://tests/test_scoring.gd",
	"res://tests/test_exif.gd",
	"res://tests/test_album.gd",
	"res://tests/test_geometry.gd",
	"res://tests/test_round.gd",
	"res://tests/test_ending.gd",
	"res://tests/test_hospital.gd",
]


func _initialize() -> void:
	var host_script := load("res://tests/test_host.gd") as GDScript
	if host_script == null:
		push_error("could not load tests/test_host.gd")
		quit(2)
		return

	var host: Node = host_script.new()
	host.name = "TestHost"
	host.suites = PackedStringArray(SUITES)
	root.add_child(host)

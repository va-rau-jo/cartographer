extends Node
## Runs the suites, from inside a live scene tree.
##
## This exists because of a sharp edge in `godot --script`: during a
## SceneTree's `_initialize()` the root Window is not yet inside the tree, so
## nothing added to it is either. `_ready()` never fires, `global_position`
## returns the identity and logs an error, and any test that builds real nodes
## is quietly testing nothing. (That is exactly what was happening: the round
## suite passed while the engine printed a wall of
## `Condition "!is_inside_tree()" is true`.)
##
## A Node added to root during `_initialize()` gets its `_ready()` when the
## tree starts iterating — by which time everything works normally. So the
## runner adds one of these and the real work happens here.
##
## Unlike run_tests.gd, this file is compiled after the project's autoloads are
## registered, so it may reference GameState, EventBus and friends.

signal run_finished(passed: int, failed: int)

const REPORT_PATH := "user://test_report.txt"

var suites: PackedStringArray = PackedStringArray()
## Set false by a caller that wants the report without the process exiting.
var quit_when_done := true

var passed := 0
var failed := 0
var report_text := ""


func _ready() -> void:
	# One frame of patience. Inside root's own _ready propagation the root is
	# "busy setting up children" and add_child() on it fails outright, so a
	# suite that hangs its fixtures off the root would still be building nodes
	# outside the tree. After process_frame everything behaves normally.
	await get_tree().process_frame
	run_suites()


func run_suites() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Chrono Cartographer — test run")
	lines.append("==============================")

	passed = 0
	failed = 0
	var started := Time.get_ticks_msec()

	for path in suites:
		lines.append(_run_one(path))

	lines.append("------------------------------")
	lines.append("%d passed, %d failed, %d ms total"
		% [passed, failed, Time.get_ticks_msec() - started])

	report_text = "\n".join(lines)
	print("\n" + report_text + "\n")

	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(report_text + "\n")
		f.close()

	run_finished.emit(passed, failed)

	if quit_when_done:
		get_tree().quit(0 if failed == 0 else 1)


func _run_one(path: String) -> String:
	var script := load(path) as GDScript
	if script == null:
		failed += 1
		return "[FAIL] could not load %s" % path

	# A suite that will not instantiate is almost always a parse error in that
	# file. Report it and carry on rather than letting the runner die mid-loop
	# and hang without ever reaching quit() — which cost an afternoon once.
	if not script.can_instantiate():
		failed += 1
		return "[FAIL] %s did not compile (see the errors above)" % path.get_file()

	var suite: Object = script.new()
	if suite == null or not suite.has_method("run"):
		failed += 1
		return "[FAIL] %s has no run()" % path.get_file()

	var t0 := Time.get_ticks_msec()
	var result: TestFramework = suite.run()
	if result == null:
		failed += 1
		return "[FAIL] %s returned no result" % path.get_file()

	passed += result.passed
	failed += result.failed
	return "%s  (%d ms)" % [result.report(), Time.get_ticks_msec() - t0]

extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script tests/run_tests.gd
##
## Exits non-zero on failure so CI can gate on it. The report is also written
## to user://test_report.txt, because stdout from a headless run is easy to
## lose to pipe buffering.
##
## Note: this script is compiled before the project's autoloads are registered
## as GDScript globals, so it must not reference `Log`, `Platform` and friends
## by name. Suites loaded below are compiled later and can use them freely.
## (The logger silences itself for test runs — see logger.gd.)

const SUITES := [
	"res://tests/test_geo.gd",
	"res://tests/test_scoring.gd",
	"res://tests/test_exif.gd",
	"res://tests/test_album.gd",
	"res://tests/test_geometry.gd",
]

const REPORT_PATH := "user://test_report.txt"


func _initialize() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Chrono Cartographer — test run")
	lines.append("==============================")

	var total_passed := 0
	var total_failed := 0
	var started := Time.get_ticks_msec()

	for path in SUITES:
		var script := load(path) as GDScript
		if script == null:
			lines.append("[FAIL] could not load %s" % path)
			total_failed += 1
			continue

		var suite: Object = script.new()
		var t0 := Time.get_ticks_msec()
		var result: TestFramework = suite.run()
		total_passed += result.passed
		total_failed += result.failed
		lines.append("%s  (%d ms)" % [result.report(), Time.get_ticks_msec() - t0])

	lines.append("------------------------------")
	lines.append("%d passed, %d failed, %d ms total"
		% [total_passed, total_failed, Time.get_ticks_msec() - started])

	var text := "\n".join(lines)
	print("\n" + text + "\n")

	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(text + "\n")
		f.close()

	quit(0 if total_failed == 0 else 1)

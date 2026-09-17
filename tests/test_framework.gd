class_name TestFramework
extends RefCounted
## A tiny assertion harness. Godot has no built-in unit test runner and GUT is
## a heavier dependency than this project needs for pure-function tests.

var suite_name: String = ""
var passed: int = 0
var failed: int = 0
var failures: PackedStringArray = PackedStringArray()


func _init(name: String) -> void:
	suite_name = name


func ok(condition: bool, what: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		failures.append("  FAIL  %s" % what)


func eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		failures.append("  FAIL  %s\n          expected: %s\n          actual:   %s"
			% [what, str(expected), str(actual)])


func close(actual: float, expected: float, tolerance: float, what: String) -> void:
	if is_nan(actual) and is_nan(expected):
		passed += 1
		return
	if not is_nan(actual) and absf(actual - expected) <= tolerance:
		passed += 1
	else:
		failed += 1
		failures.append("  FAIL  %s\n          expected: %f (+/- %f)\n          actual:   %f"
			% [what, expected, tolerance, actual])


func gt(actual: float, threshold: float, what: String) -> void:
	if actual > threshold:
		passed += 1
	else:
		failed += 1
		failures.append("  FAIL  %s\n          expected > %f, got %f"
			% [what, threshold, actual])


func lt(actual: float, threshold: float, what: String) -> void:
	if actual < threshold:
		passed += 1
	else:
		failed += 1
		failures.append("  FAIL  %s\n          expected < %f, got %f"
			% [what, threshold, actual])


func report() -> String:
	var status := "PASS" if failed == 0 else "FAIL"
	var head := "[%s] %-22s %d passed, %d failed" % [status, suite_name, passed, failed]
	if failed == 0:
		return head
	return head + "\n" + "\n".join(failures)

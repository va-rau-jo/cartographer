class_name CCLog
extends RefCounted
## Tagged logging with a ring buffer the debug overlay reads.
##
## Deliberately a static class rather than an autoload. Autoload names are not
## registered as GDScript globals until after the script passed to --script is
## compiled, so anything a headless tool or test runner depends on cannot
## reference an autoload — the whole data layer would become unusable from
## `godot --script`. A class_name with static members resolves at compile time
## everywhere: in the game, in tests, and in tools.
##
## Use CCLog.info("album", "loaded %d photos" % n) rather than print().

enum Level { DEBUG, INFO, WARN, ERROR }

const MAX_ENTRIES := 400

static var min_level: Level = Level.DEBUG

## When false, entries are still recorded but not printed or forwarded to
## push_warning/push_error. Tests turn this off: several suites deliberately
## exercise failure paths, and the engine's own error reporting would bury the
## actual results.
static var to_engine: bool = true

static var _entries: Array[Dictionary] = []
static var _configured: bool = false


static func debug(tag: String, msg: String) -> void:
	_write(Level.DEBUG, tag, msg)


static func info(tag: String, msg: String) -> void:
	_write(Level.INFO, tag, msg)


static func warn(tag: String, msg: String) -> void:
	_write(Level.WARN, tag, msg)


static func error(tag: String, msg: String) -> void:
	_write(Level.ERROR, tag, msg)


static func recent(count: int = 30) -> Array[Dictionary]:
	var start := maxi(0, _entries.size() - count)
	return _entries.slice(start)


static func clear() -> void:
	_entries.clear()


static func _write(level: Level, tag: String, msg: String) -> void:
	_configure_once()

	if level < min_level:
		return

	_entries.append({
		"level": level,
		"tag": tag,
		"msg": msg,
		"ms": Time.get_ticks_msec(),
	})
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)

	if not to_engine:
		return

	var line := "[%s] %s: %s" % [_level_name(level), tag, msg]
	print(line)
	if level == Level.WARN:
		push_warning(line)
	elif level == Level.ERROR:
		push_error(line)


## Silence engine forwarding automatically during a test run, so the runner
## does not have to reach in and set it.
static func _configure_once() -> void:
	if _configured:
		return
	_configured = true
	for arg in OS.get_cmdline_args():
		if arg.contains("run_tests.gd"):
			to_engine = false
			return


static func _level_name(level: Level) -> String:
	match level:
		Level.DEBUG: return "dbg"
		Level.INFO: return "inf"
		Level.WARN: return "WRN"
		Level.ERROR: return "ERR"
	return "?"

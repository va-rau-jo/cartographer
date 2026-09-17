#!/usr/bin/env bash
# Headless test run. Finds Godot on PATH, or set GODOT explicitly.
set -uo pipefail

if [ -z "${GODOT:-}" ]; then
  for candidate in godot godot4 Godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT="$candidate"
      break
    fi
  done
fi

if [ -z "${GODOT:-}" ]; then
  echo "Could not find Godot on PATH."
  echo "Set it explicitly:  GODOT=/path/to/godot tools/run_tests.sh"
  exit 9
fi

echo "Using Godot: $GODOT"
cd "$(dirname "$0")/.."

# Refresh the import cache before running anything. A --script run reads
# .godot/global_script_class_cache.cfg exactly as it finds it and never rescans
# the project, so any class_name added since the editor last ran is simply
# absent -- and every suite that names it fails to compile with "Could not find
# type ... in the current scope". --import rebuilds the cache.
if ! "$GODOT" --headless --path . --import >/dev/null 2>&1; then
  echo "WARNING: --import failed. If suites report \"did not compile\", the script"
  echo "class cache is stale - open the project in the Godot editor once, or point"
  echo "GODOT at an editor build rather than an export template."
  echo
fi

"$GODOT" --headless --path . --script tests/run_tests.gd
result=$?

report="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Chrono Cartographer/test_report.txt"
echo
[ -f "$report" ] && cat "$report" || echo "No report at: $report"

echo
if [ $result -ne 0 ]; then
  echo "TESTS FAILED (exit $result)"
else
  echo "All tests passed."
fi
exit $result

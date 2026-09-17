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

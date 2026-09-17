#!/usr/bin/env bash
# Headless test run. Set GODOT if the executable is not on PATH.
set -uo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

"$GODOT" --headless --path . --script tests/run_tests.gd
result=$?

if [ $result -ne 0 ]; then
  echo
  echo "TESTS FAILED"
else
  echo
  echo "All tests passed."
fi
exit $result

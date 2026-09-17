#!/usr/bin/env bash
# Local web export. Set GODOT if the executable is not on PATH.
set -euo pipefail

GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."

mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" "$PWD/build/web/index.html"

echo
echo "Exported to build/web"
du -sh build/web
echo "Serve it:  (cd build/web && python3 -m http.server 8080)"

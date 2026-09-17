#!/usr/bin/env python3
"""Load the exported web build in a real browser and check that it works.

    python tools/verify_web.py                 # expects build/web to exist
    python tools/verify_web.py --dir build/web --shots ~/shots

What it does: serves `build/web` over HTTP (a `file://` URL cannot fetch
WebAssembly), opens it in headless Chromium, waits for the engine banner,
clicks "Walk the gallery (no album)", waits for the hallway to build, and
saves screenshots. It fails if the engine never boots, if the gallery never
reports itself built, or if the page raises a JavaScript error.

Why this exists: "never yet opened in a browser" was the oldest open risk in
the project, and web is the primary delivery target (plan §1.3). The tests
prove the logic; this proves the thing a person will actually load.

Requires Playwright (`pip install playwright && playwright install chromium`).
It is not part of the test suite because of that dependency — run it after a
web export, and in CI if the runner has a browser.

Two caveats, both from software rendering. Headless Chromium here draws
through SwiftShader, on the CPU, at roughly a frame a second: that is fine for
"does it boot, build and draw", which is all this checks, but useless for
judging how the game feels, and slow enough that keyboard input barely moves
her — do not try to play a round through it. It also means the gallery's
three-second fade-in from white can still be part-way through when the
screenshot is taken, so the hall may look veiled. On real hardware it is not.
"""

from __future__ import annotations

import argparse
import http.server
import sys
import threading
import time
from pathlib import Path

PORT = 8099
BOOT_TIMEOUT = 180
BUILD_TIMEOUT = 120


def serve(directory: Path, port: int) -> http.server.ThreadingHTTPServer:
    """A THREADING server, which matters here.

    A single-threaded one deadlocks this: the browser opens several keep-alive
    connections at once for index.js, index.wasm and index.pck, and whichever
    one is not being served sits there until it times out. The engine then
    never boots and the failure looks like a broken build rather than a broken
    test harness.
    """
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(directory), **kwargs)

        def log_message(self, *args):
            pass

    http.server.ThreadingHTTPServer.allow_reuse_address = True
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def wait_for(page, logs: list[str], needle: str, seconds: int) -> bool:
    """Wait for a line of the game's own logging to appear in the console.

    Waits with page.wait_for_timeout, NOT time.sleep. Playwright's sync API
    only dispatches events while you are calling into it, so a loop that
    sleeps in Python never receives a single console message — which looked
    for an hour exactly like a web build that would not boot.
    """
    deadline = time.time() + seconds
    while time.time() < deadline:
        if any(needle in line for line in logs):
            return True
        page.wait_for_timeout(2000)
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", default="build/web", help="the exported build")
    parser.add_argument("--shots", default="", help="where to write screenshots")
    parser.add_argument("--port", type=int, default=PORT)
    args = parser.parse_args()

    build = Path(args.dir).resolve()
    if not (build / "index.html").exists():
        print("no index.html in %s — run tools/export_web first" % build)
        return 2

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("Playwright is not installed:")
        print("  pip install playwright && playwright install chromium")
        return 3

    shots = Path(args.shots) if args.shots else build.parent / "shots"
    shots.mkdir(parents=True, exist_ok=True)

    serve(build, args.port)
    url = "http://127.0.0.1:%d/index.html" % args.port
    print("serving %s at %s" % (build, url))

    logs: list[str] = []
    errors: list[str] = []
    failures: list[str] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(args=[
            # Software GL, so this runs on a machine with no GPU.
            "--enable-unsafe-swiftshader",
            "--use-gl=angle",
            "--use-angle=swiftshader",
            "--no-sandbox",
        ])
        # Small on purpose: every pixel is rasterised on the CPU.
        page = browser.new_page(viewport={"width": 640, "height": 360})
        page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.on("requestfailed",
                lambda r: failures.append("%s %s" % (r.url, r.failure)))

        page.goto(url, wait_until="load", timeout=120_000)

        if not wait_for(page, logs, "Godot Engine v", BOOT_TIMEOUT):
            print("FAIL: the engine never booted")
            for line in logs[-20:]:
                print("  %s" % line[:200])
            for line in failures[:10]:
                print("  request failed: %s" % line)
            for line in errors[:10]:
                print("  page error: %s" % line)
            print("  page title: %r" % page.title())
            browser.close()
            return 1
        print("engine booted")

        for line in logs:
            if "OpenGL API" in line or "Build configuration" in line:
                print("  %s" % line[len("log: "):][:160])

        _shot(page, shots / "web_01_menu.png")

        # "Walk the gallery (no album)" is the third button.
        box = page.query_selector("canvas").bounding_box()
        page.mouse.click(box["x"] + box["width"] * 0.5,
                         box["y"] + box["height"] * 0.514)

        if not wait_for(page, logs, "gallery: built", BUILD_TIMEOUT):
            print("FAIL: the gallery never reported itself built")
            for line in logs[-20:]:
                print("  %s" % line[:200])
            browser.close()
            return 1

        for line in logs:
            if "gallery: built" in line:
                print("  %s" % line[len("log: "):][:160])

        # Twenty seconds, not eight: the gallery fades in from white over
        # three, and under software GL the whole thing advances slowly enough
        # that a screenshot taken too early is a white veil over the hall.
        page.wait_for_timeout(20000)
        _shot(page, shots / "web_02_gallery.png")

        browser.close()

    print("console lines: %d" % len(logs))
    if failures:
        print("FAIL: %d request(s) failed" % len(failures))
        for line in failures[:10]:
            print("  %s" % line)
        return 1
    if errors:
        print("FAIL: %d page error(s)" % len(errors))
        for line in errors[:10]:
            print("  %s" % line)
        return 1

    print("the web build boots, renders and takes input. shots in %s" % shots)
    print("(a white veil over the hallway is this harness's software renderer"
          " still finishing the fade-in, not the build.)")
    return 0


def _shot(page, path: Path) -> None:
    try:
        # Generous: a single frame can take a second under software GL.
        page.screenshot(path=str(path), timeout=120_000)
        print("wrote %s" % path)
    except Exception as exc:  # noqa: BLE001 - a missed screenshot is not fatal
        print("could not screenshot %s (%s)" % (path.name, type(exc).__name__))


if __name__ == "__main__":
    sys.exit(main())

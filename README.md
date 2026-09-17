# Chrono Cartographer

An old woman steps into her dying husband's mind. It has taken the shape of a
gallery hallway hung with ten photographs of their life. She walks it with him.
Each photo starts as fog, and she has to say _where_ and _when_. He'll help if
she asks, but asking costs her. At the end of the hall they hug, and it fades
out.

Ten to fifteen minutes, start to finish.

The full design and milestone breakdown is in **[docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md)**.

---

## Status

**M0, M1 and the M2 data layer are done.** The gallery is walkable grey-box;
the round logic that turns it into a game is next.

| Area                                             | State                                  |
| ------------------------------------------------ | -------------------------------------- |
| Album format, ZIP IO, validation, migration hook | done, 134 tests                        |
| EXIF reader (date, GPS, orientation)             | done, 39 tests                         |
| Image pipeline (downscale, blur ladder, WebP)    | done                                   |
| Scoring (haversine distance, date, hint economy) | done, 42 tests                         |
| Map projection maths                             | done, 40 tests                         |
| Platform abstraction (web / desktop)             | done, untested in a real browser       |
| Main menu, debug overlay                         | minimal, functional                    |
| Gallery hallway, frames, characters              | grey-box, walkable                     |
| Web export + Pages deploy                        | working; never yet opened in a browser |
| Hospital scene, map widget, round logic, editor  | not started                            |

---

## Requirements

- **Godot 4.7** (standard build, _not_ .NET — see below)
- **Blender** only for the art pipeline later; nothing here needs it yet

### Why GDScript and not C#

C# has no production web export in Godot as of 2026: the draft implementation
is single-threaded only, globalization is invariant-mode, and browser API
bindings are stubbed. Web is this project's primary delivery target, so the
whole game is GDScript and `project.godot` carries no `[dotnet]` block. Do not
add one back.

### Why the Compatibility renderer

Web export runs WebGL 2 through the Compatibility renderer, so there is no
SDFGI, no VoxelGI, no volumetric fog, no SSAO/SSIL/SSR. The project targets
Compatibility on **both** platforms so the web build is the reference rather
than a degraded afterthought. Lighting comes from baked lightmaps plus
Blender-baked AO in the trim sheets.

---

## Running

### Play it

```
godot --path .
```

Menu → **Walk the gallery (no album)** to walk the grey-box.
**WASD** to walk, **F11** for the debug overlay, **Esc** to release the mouse
(press again to go back to the menu).

### Run the tests

The suite is headless and pure — no window, no GPU, about 16 seconds.

On Windows, point `GODOT` at your executable and run the batch file:

```bat
set GODOT=C:\Godot\Godot_v4.7-stable_win64_console.exe
tools\run_tests.bat
```

**Use the `_console.exe` build if you want to see the output.** The plain
`Godot_v4.7-stable_win64.exe` does not attach to a console on Windows, so a
`--headless` run finishes silently with nothing printed. This trips everyone up
once.

Either way the full report is also written to a file, so you can read it
whichever executable you used:

```
%APPDATA%\Godot\app_userdata\Chrono Cartographer\test_report.txt
```

Or invoke Godot directly, without the wrapper:

```bat
"C:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tests/run_tests.gd
```

On Linux or macOS: `GODOT=/path/to/godot tools/run_tests.sh`

A pass looks like this, and the process exits 0:

```
[PASS] geo        40 passed, 0 failed
[PASS] scoring    42 passed, 0 failed
[PASS] exif       39 passed, 0 failed
[PASS] album     134 passed, 0 failed
[PASS] geometry  176 passed, 0 failed
431 passed, 0 failed
```

A failure names the assertion, what was expected and what happened, and exits
non-zero. If instead you get `Identifier "X" not declared`, the script class
cache is stale — run `godot --headless --path . --import` once and try again.

### Generate a test album

```bat
tools\make_test_album.bat
```

Writes a valid ten-photo `.ccalbum` (ten real places, real coordinates) to
`%APPDATA%\Godot\app_userdata\Chrono Cartographer\test_album.ccalbum`.
Load it from the menu with **Load album…**.

### Export for the web

```bat
tools\export_web.bat
```

**The result will not open from `file://`** — browsers refuse to fetch
WebAssembly from a file URL. Serve it:

```bat
cd build\web
python -m http.server 8080
```

then open `http://localhost:8080`.

Current export size: **39 MB raw, about 10 MB gzipped.** The `.pck` is only
183 KB, because the hallway, the frames and the characters are all generated in
code rather than shipped as assets — which is the whole point of §1.4's budget.

#### If "Manage Export Templates" failed to download

The templates archive is **1.3 GB**, and the in-editor downloader gives up on
any interruption. The reliable route is to fetch it yourself:

1. Download
   `Godot_v4.7-stable_export_templates.tpz` from
   <https://github.com/godotengine/godot/releases/tag/4.7-stable>
   (a browser or `curl` resumes better than the editor does).
2. In Godot: **Editor → Manage Export Templates → Install from File**, and pick
   that `.tpz`.
3. It should then report `4.7.stable` installed.

To check by hand, the templates live in
`%APPDATA%\Godot\export_templates\4.7.stable\` and the web build needs
these four files present:

```
web_release.zip            web_debug.zip
web_nothreads_release.zip  web_nothreads_debug.zip
```

This project exports with **threads off**, so `web_nothreads_release.zip` is the
one that actually matters (see below).

You do not strictly need local templates at all: CI builds the web export for
you. They are only required for exporting from your own machine.

### Deploying

`.github/workflows/pages.yml` runs the tests, builds the web export and
publishes it to GitHub Pages on every push to `main`. To turn it on:

1. Push the repository to GitHub.
2. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
3. Push to `main`. The workflow caches Godot and the 1.3 GB template archive,
   so only the first run is slow.

Two constraints GitHub Pages imposes, both already handled:

- **No custom headers**, so no COOP/COEP, so no `SharedArrayBuffer` and no
  engine threads. The export preset sets `variant/thread_support=false` and the
  game is designed not to need threads — the blur ladder tops out at 512 px
  before the reveal, so nothing needs a worker. **Do not turn thread support
  on**; the build will load to a blank page.
- **100 MB per file** (a git limit, not a Pages one). `index.wasm` is 38 MB, so
  there is room, but it is the file to watch.

## Layout

```
src/
  core/      autoloads, event bus, logging, platform abstraction
  album/     schema, zip io, validation, exif, image pipeline
  map/       projection and distance maths
  gameplay/  scoring
  ui/        menus
  web/       JavaScriptBridge wrappers
tests/       headless test suites
tools/       headless utilities (test album generator, runners)
docs/        the implementation plan
```

### Two rules worth keeping

**1. The data layer never references an autoload.**

Autoload names are not registered as GDScript globals until _after_ the script
passed to `--script` is compiled. Anything a headless tool or the test runner
depends on therefore cannot reference `Platform`, `GameState` and friends, or
the whole data layer becomes unusable from `godot --script`. That is why
logging is `CCLog` (a `class_name` with static members) rather than a `Log`
autoload, and why `AlbumIO` does not call `Platform.sync_user_fs()`.

**2. Platform differences live in exactly one place.**

`src/core/platform.gd` and its two backends. No `OS.has_feature("web")`
checks anywhere else — that is what makes dual-target projects miserable.

---

## The album format

A `.ccalbum` is a ZIP holding exactly ten photos and a manifest, around 3–5 MB
for real photographs, so it attaches to an email. Your thousand-photo library
stays in your own folder; the editor picks ten out of it.

The blur ladder is built from **resolution, not a blur pass**. A 64 px image
stretched across a 1.5 m canvas is already fog, so each tier is a Lanczos
downscale — native, instant, and tiny. Measured on the generated test album:

| Tier | Long edge | Size                                              |
| ---- | --------- | ------------------------------------------------- |
| 0    | 64 px     | 1.6 KB                                            |
| 1    | 128 px    | 4.3 KB                                            |
| 2    | 256 px    | 11.4 KB                                           |
| 3    | 512 px    | 26.7 KB                                           |
| full | 2048 px   | ~110 KB (synthetic; ~300–400 KB for a real photo) |

The softening that turns bilinear upscale facets into convincing haze belongs
in the frame shader, with a per-tier radius. Blurring the _full-resolution_
image at runtime is the thing to avoid — it would keep the expensive texture
resident and defeat the entire design.

`schemaVersion` is checked on load and there is a migration hook in
`album_io.gd`. **Never remove a manifest field**; deprecate it and stop writing
it.

---

## Next

M1: grey-box hallway with ten frame anchors, third-person controller, one
code-generated voxel figure, lightmap bake, and a rough crossfade prototype of
the hospital-to-gallery transition. Then look at it in a browser and make the
art-direction call.

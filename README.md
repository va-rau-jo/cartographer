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

**The whole arc plays, and it plays in a browser.** Hospital room,
transition, ten rounds in the gallery, the hug, the fade, the results screen,
back to the menu — plus an editor that turns a folder of your own photographs
into a `.ccalbum`. It is grey-box throughout; the art pass has not happened.

| Area                                                |
| --------------------------------------------------- | ------------------------------------------ |
| Album format, ZIP IO, validation, migration hook    |
| EXIF reader (date, GPS, orientation)                | done, 39 tests                             |
| Image pipeline (downscale, blur ladder, WebP)       | done                                       |
| Scoring (haversine distance, date, hint economy)    | done, 42 tests                             |
| Round loop: approach, examine, spend, guess, reveal | done, 86 tests                             |
| HUD, text bubbles, hint ladder and costs            | done                                       |
| Guessing: map with a pin, or a place list           | done, 72 tests                             |
| Map coastline data                                  | **needs `tools/fetch_geo.py` run once**    |
| Hospital opening, the transition                    | done, 27 tests                             |
| The hug and the results screen                      | done, 67 tests                             |
| Gallery hallway, frames, characters                 | grey-box, walkable                         |
| Platform abstraction (web / desktop)                | done, untested in a real browser           |
| Web export + Pages deploy                           | working; **never yet opened in a browser** |
| Album editor                                        | done, 75 tests                             |
| Web build in a real browser                         | **verified** — `tools/verify_web.py`       |
| Art pass, music, customization, curator bake        | not started                                |

**758 tests, 0 failed.**

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

**Create settings** is the authoring screen: everything that goes into one
playable file, in three tabs.

1. **General** — the title, the note shown at the end, the two characters, the
   last line before the hug, and the calendar range.
2. **Photographs** — the source folder or zip, the wall in hang order, and
   everything about the selected photograph.
3. **Save** — what is still missing, and the button that writes the file.

**Load settings…** reads one back and lands on its own page, where you can
begin it or edit it. **Begin** plays the whole arc, starting in the hospital
room. **Walk the gallery (no album)** skips straight to the hall with
placeholder pictures.

### The two characters

There are two, and the words for them are **main** and **side**:

* the **main character** walks the hall with the map and is on screen the
  whole time — this is the one you play;
* the **side character** waits at the far end of it, lies in the bed at the
  start, and talks about the photographs.

Victor is the main character by default and Chelsea the side one. **Swap them**
exchanges the two, names and looks included, so whoever was waiting now walks.

Each has a name, a **build** and five colours — skin, hair, trousers or dress,
jumper or cardigan, shoes — with the real figure turning beside the swatches
under the hall's own light. The build is a look and not a role: either
character can be either. The two builds are drawn separately (a skirt and a
bun, or trousers and a short crop) and are the same height, because the hug at
the ending is one drawn pose.

The characters live **inside the settings file**, so the person a file was made
for meets the author's two characters and not whatever their own machine has
saved. **Characters** on the menu edits this machine's own default — what a new
file starts from, and who plays when a file names nobody. That is saved to
`user://cast.json`; a `user://profile.json` from a build that knew only one
figure is adopted once, as the main character.

|          |                                                                                 |
| -------- | ------------------------------------------------------------------------------- |
| **WASD** | walk                                                                            |
| **E**    | look at the photograph you are standing at (and, in the opening, take his hand) |
| **U**    | clear the photograph a little, at a cost                                        |
| **H**    | ask him, at a bigger cost                                                       |
| **Esc**  | release the mouse, step back out of a guess, or skip the ending                 |
| **F11**  | debug overlay                                                                   |

With no album loaded the pictures are placeholders and there is nothing behind
them to guess; the guess panel says so rather than showing an empty box.

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
[PASS] round      86 passed, 0 failed
[PASS] ending     67 passed, 0 failed
[PASS] hospital   27 passed, 0 failed
[PASS] map        72 passed, 0 failed
[PASS] editor     75 passed, 0 failed
758 passed, 0 failed
```

The album suite takes about fourteen seconds (it generates real images); the
rest are milliseconds.

A failure names the assertion, what was expected and what happened, and exits
non-zero. If instead you get `Identifier "X" not declared`, the script class
cache is stale — run `godot --headless --path . --import` once and try again.

### Where albums come from

A **`.ccalbum`** is a zip. Inside it: `album.json` — the manifest with the ten
photographs' places, dates, hints and hang order — and, per photograph, four
blur tiers, a full-resolution image and a thumbnail, all WebP. About 3–5 MB,
so it attaches to an email. The game plays a `.ccalbum` and nothing else,
because the blur ladder has to exist before she can be shown fog.

You never write that JSON by hand. **The editor does it.** Three ways in:

| | |
|---|---|
| **Open a .zip…** | A Google Photos album download, or a Google Takeout export. The editor reads Google's JSON sidecars, so dates, coordinates, captions and the people in each photograph fill themselves in. |
| **Choose a folder…** | Any folder of JPEGs or PNGs. Dates and GPS come from EXIF where the photographs carry it. |
| **Open an album…** | An existing `.ccalbum`, to change it and save it again. |

The fastest route for a Google Photos album: open the album in Google Photos,
select all, download — that gives you one zip — then **Create an album → Open a
.zip…**, pick your ten, write what you remember, and save. A Takeout export
works the same way and carries richer metadata.

Nothing is copied out of your library, and a zip is opened rather than
unpacked: a thousand photographs cost nothing until ten of them are chosen.

### Bake the map

The map needs the world's outline, which is not in this repository — no host
that serves Natural Earth is reachable from the environment the code was
written in. One command fixes it:

```bat
python tools\fetch_geo.py
python tools\fetch_geo.py --check
```

That writes `data/geo/coastlines.json` and the map picks it up next time the
game starts. It defaults to Natural Earth **50m** — about six times the detail
of 110m, which was too coarse to recognise anywhere from once you zoom in.
`--resolution 10m` gets every bay and headland; `--resolution 110m` is the old
coarse one.

If the download is blocked for you too, fetch `ne_50m_coastline.geojson` from
<https://github.com/nvkelso/natural-earth-vector/tree/master/geojson>
by hand and pass `--from <that file>`.

Until it exists the map draws its graticule and says so, and the guess panel
leads with a list of the album's places instead. That list is not a stopgap —
it stays as the easier mode for anyone who would rather not be tested on
coordinates.

**The map guesses in two stages.** Zoomed out, a click zooms in — to the
region it landed on, or to a window around it if that was open ocean. Zoomed
in, a click places the pin. "◀ the whole world", a double-click, or the wheel
gets you back out. A world map cannot pin a town and a zoomed map cannot find
a country, so it does both in turn.

### Generate a test album

```bat
tools\make_test_album.bat
```

Writes a valid ten-photo `.ccalbum` (ten real places, real coordinates) to
`%APPDATA%\Godot\app_userdata\Chrono Cartographer\test_album.ccalbum`.
Load it from the menu with **Load album…**.

### Look at it

Three tools render the game headlessly, which is how every character and
lighting bug in this project has actually been found:

```bash
xvfb-run -a godot --path . --script tools/render_shots.gd      # the gallery
xvfb-run -a godot --path . --script tools/render_hospital.gd   # the opening
xvfb-run -a godot --path . --script tools/render_ending.gd     # the hug
xvfb-run -a godot --path . --script tools/run_diag_map.gd      # the map
```

They write PNGs to `%APPDATA%\Godot\app_userdata\Chrono Cartographer\shots`.
On Windows, drop `xvfb-run -a` and the game opens a window instead.

**Change geometry, lighting or a drawn figure, then look at the result.** The
numbers cannot see a blindfold where a pair of closed eyes should be.

### Check the web build in a browser

```bash
pip install playwright && playwright install chromium
python tools/verify_web.py            # after exporting to build/web
```

It serves the build over HTTP (a `file://` URL cannot fetch WebAssembly),
opens it in headless Chromium, waits for the engine, clicks into the gallery
and fails on any JavaScript error. Verified 2026-09-17: boots on WebGL 2
through the Compatibility renderer, single-threaded, no errors, hallway built,
keyboard input reaching the game.

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
  core/        autoloads, event bus, logging, platform abstraction
  album/       schema, zip io, validation, exif, image pipeline
  map/         projection, distance, coastline data
  gameplay/    scoring, the round machine, the ending
  mansion/     the gallery hallway and its lighting
  hospital/    the opening scene
  photo/       the frames and the mat/blur shader
  characters/  the drawn figures and the greedy mesher
  ui/          menus, HUD, guess panel, map widget, results
  web/         JavaScriptBridge wrappers
tests/         headless test suites
tools/         headless utilities: test album, renders, diagnostics, geo bake
docs/          the implementation plan
data/geo/      the baked coastline (see "Bake the map")
```

### Three rules worth keeping

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

**3. Tests and headless tools run from a live scene tree.**

Same root cause as rule 1, one step further. During a `SceneTree`'s
`_initialize()` the root Window is not yet _inside_ the tree: `_ready` never
fires, every `global_transform` silently returns identity, and `add_child` on
the root fails outright. A suite that builds real nodes there is testing
nothing — 86 assertions were doing exactly that. So `tests/run_tests.gd` is a
stub that adds `tests/test_host.gd`, which waits one frame and then runs the
suites. Headless tools follow the same shape: a thin entry point plus a Node
that does the work (`tools/render_ending.gd` + `tools/ending_shots.gd`).

---

## The album format

See "Where albums come from" above for what a `.ccalbum` is and how to make
one. This section is about the part that decides how the game feels.

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

In order:

1. **Re-run `python tools\fetch_geo.py`** to replace the 110m coastline with
   the 50m default, now that the map zooms in far enough to notice.
2. **Deploy to Pages and open your own URL.**
3. **Build one real album in the editor**, from a Google Photos zip, and play
   it through. That is the first end-to-end use of the thing.
4. Bake that album's curator lines and read all thirty hint lines.
5. The art pass.

### Only you can do these

- **Open `https://<your-user>.github.io/<repo>/` and see whether it loads.**
  The build itself is verified in a browser (above); what is not verified is
  _your_ Pages deployment. Set _Settings → Pages → Source: GitHub Actions_
  first, then push to `main`.
- **Check the export templates installed**: Godot → _Editor → Manage Export
  Templates_ should say `4.7.stable`. See the section above if the download
  failed.
- **Run `tools\run_tests.bat`** and confirm 758 passing on your machine, not
  just in the container.

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

**M0 (foundation) and the M2 data layer are done.** The game is not yet
playable — there is no 3D yet by design, because the album format is the
keystone everything else binds to and it was built first.

| Area                                                            | State                            |
| --------------------------------------------------------------- | -------------------------------- |
| Album format, ZIP IO, validation, migration hook                | done, 134 tests                  |
| EXIF reader (date, GPS, orientation)                            | done, 39 tests                   |
| Image pipeline (downscale, blur ladder, WebP)                   | done                             |
| Scoring (haversine distance, date, hint economy)                | done, 42 tests                   |
| Map projection maths                                            | done, 40 tests                   |
| Platform abstraction (web / desktop)                            | done, untested in a real browser |
| Main menu, debug overlay                                        | minimal, functional              |
| Gallery hallway, hospital scene, characters, map widget, editor | not started                      |

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

```sh
# Play
godot --path .

# Tests (exits non-zero on failure; report also at user://test_report.txt)
godot --headless --path . --script tests/run_tests.gd

# Generate a playable ten-photo test album
godot --headless --path . --script tools/make_test_album.gd
```

On Windows, `tools/run_tests.bat` wraps the test command. Both wrappers take
the Godot executable path as `$GODOT` / `%GODOT%` if it is not on `PATH`.

Load the generated `.ccalbum` from the main menu with **Load album…**.
Press **F11** for the debug overlay, which shows the live score maths — those
constants can only be tuned by watching them move.

---

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

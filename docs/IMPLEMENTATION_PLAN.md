# Chrono Cartographer — Implementation Plan

**Status:** v5 · 2026-09-17 · supersedes v4. Same scope; the milestone table and §16 now record what was actually built, and where the implementation departed from this document.
**Repo:** `C:\Users\victor\src\cartographer`
**Engine:** Godot 4.7, GDScript, Compatibility renderer
**Targets:** Web (primary, GitHub Pages or self-hosted) + Windows
**Shape:** one album = 10 photos · one gallery hallway · 10–15 minute complete arc

---

## 0. The shape of the thing

A hospital room. An old woman at her husband's bedside. She takes his hand, and the room dissolves into his mind — a gallery hallway hung with ten photographs of their life. She walks it with him. Each photo starts as fog. She has a map and a calendar and sixty years of memory, and she has to say *where* and *when*. He'll help if she asks, but asking costs her. At the end of the hall they hug, the light goes, and it fades to the menu.

Ten to fifteen minutes, start to finish. That tight scope is the plan's biggest asset — every constraint that made v3 pessimistic has loosened.

### Confirmed decisions

| Question | Decision |
|---|---|
| Language | **GDScript.** C# has no production web export (§1.1). |
| Renderer | **Compatibility (WebGL 2)** on both platforms. |
| Scenes | **Two: hospital bedside → (transition) → gallery hallway.** |
| Session | 10 photos → hug → fade → main menu. Replay gives the same 10. |
| Album | **Exactly 10 photos, ~5 MB.** Emailable. The 1000-photo library stays in your source folder. |
| Editor | **In the shipped build, reachable from the menu** ("load game" page). |
| AI curator | Pre-baked at authoring time with **Claude**. Shipped game makes zero AI calls. |
| Husband's voice | **Text bubbles. No TTS.** |
| Guessing | Real-world map, haversine distance + date scoring. |
| Camera | Third person in the hallway. Player is the woman. |
| Hosting | **Static files only. No server side.** |
| Blender | **Available**, headless only (§6). |
| Google Photos | Phase 2, behind an interface (§11). |
| Licensing | Personal gift; not a constraint. |

### What this revision changes

Nothing about the design. v4 was written before the code existed; v5 is written
with six milestones' worth of it in the repository, so:

- the milestone table carries a **state** column and says what remains;
- §14 is rewritten as the actual next steps rather than the original ones;
- §15's open question is **answered** (the hospital only opens the game);
- a new **§16** records every place where the implementation had to depart from
  this plan, and why. That section is the one to read before changing anything:
  each entry cost a bug or a render to learn.

### What v3 got wrong, now corrected

Three subsystems are **deleted**, not deferred:

- **The byte-range ZIP reader.** A 5 MB album needs no such thing — plain `ZIPReader` is fine (§3.3). This was the right answer to a 480 MB album and is dead weight against a 5 MB one.
- **Room streaming, the layout solver, wings, per-room nav baking.** One hallway. Ten hand-placed frames, art-directed individually.
- **Batch authoring tooling as critical path.** Ten photos need ten descriptions. That's an evening, not a hundred sessions.

And one conclusion is **revised upward**: v3 said photorealism was out of reach. With the whole art budget going into one hallway and one small hospital room, that's no longer true (§1.4).

---

## 1. Platform constraints

### 1.1 GDScript, not C#

C# web export in Godot is still not production-ready in 2026: the draft PR is single-threaded only, globalization is invariant-mode, browser API bindings are stubbed, and the tracking issue is locked with no target version. **Remove the `[dotnet]` block from `project.godot` at M0**, before any script exists.

The only real cost is losing NuGet, so EXIF parsing is hand-written in GDScript (~250 lines: JPEG APP1 → TIFF IFD → `DateTimeOriginal` 0x9003 + GPS IFD tags 1–4). At ten photos per album this is a convenience rather than a necessity, but it's cheap and it saves typing dates.

### 1.2 Renderer: Compatibility / WebGL 2

Web export in 4.7 runs WebGL 2 through the Compatibility renderer; WebGPU did not land. Unavailable: SDFGI, VoxelGI, volumetric fog, SSAO, SSIL, SSR. `AreaLight3D` is very likely Forward+ only — **verify at M1 before designing lighting around it.**

Build for Compatibility on *both* platforms so the web build is the reference rather than a degraded afterthought.

### 1.3 Hosting — static files, confirmed

The whole game is static files. Author picks a source folder → builds a 10-photo album in the browser → `download_buffer()` hands over a ~5 MB `.ccalbum` → recipient opens the same URL and picks that file off their disk. Nothing uploads.

GitHub Pages specifics: 1 GB site, 100 GB/month bandwidth (both irrelevant here), and **100 MB per file** — a git limit, so Godot's `.pck` must stay under it. GitHub Pages also **can't send custom headers**, so no COOP/COEP and therefore no threads unless you add the `coi-serviceworker` shim.

**Plan single-threaded.** With ten photos and a blur ladder that tops out at 512 px pre-reveal (§4), threads buy nothing. This keeps hosting unconstrained.

### 1.4 Art budget — and why "realistic" is now achievable

The hard ceiling is the `.pck` under 100 MB. In v3 that had to cover ten room types; now it covers **one hallway and one hospital room**. Roughly a tenfold increase in bytes per square metre.

That changes the conclusion. v3 said three constraints stacked to put photorealism out of reach: no realtime GI, a tight budget, and no hand-modeling. Two of those have moved:

- **The budget is no longer binding.** 2K trim sheets, unique hero assets, dense prop dressing, and a high-resolution lightmap bake all fit comfortably in two small spaces.
- **Blender covers the missing GI and AO.** Bake ambient occlusion, curvature and detail normals into the textures, and bake full Cycles GI into the lightmap (§6.3). Static lighting in a static room is not a compromise — it's how architectural visualisation has always worked, and it looks excellent.

**A gallery hallway is also among the most achievable realistic interiors there is.** Repeated architectural rhythm (pilasters, cornices, sconces, a coffered ceiling), tightly controlled lighting, and a camera that's always in the middle of it looking down its length. You can art-direct every square foot because there are only a few hundred of them.

**Revised target: genuinely realistic and detailed.** Still not path-traced in real time, but the original brief's ask is now on the table. This is M1's go/no-go.

The creative direction still stands, because it serves the story: warm dusty light, strong value contrast, light shafts through tall windows, detail pooled around each photograph. It's a memory, so a little unreality is diegetic.

---

## 2. Structure

```
res://
  src/
    core/        # autoloads, event bus, logging, platform abstraction
    album/       # schema, zip io, validate, exif
    photo/       # texture loading, blur tiers, frame binding
    gameplay/    # round state machine, scoring, hint economy
    map/         # vector world map, projection, pin input
    calendar/    # date dial widget, precision handling
    curator/     # text bubbles, hint ladder, barks
    characters/  # controller, companion, customization, voxel builder
    ui/          # menu, HUD, results, ending
    editor/      # album editor (the "load game" page)
    web/         # JavaScriptBridge wrappers
  scenes/
    menu/  hospital/  gallery/  editor/
  art/ materials/ props/
  data/ geo/ places/
  tools/blender/    # headless scripts + runner
user://
  profile.json            # avatar customization, settings
  progress.json           # best scores per album id
  album-draft.json        # editor work in progress
```

**Autoloads — four:** `GameState`, `AlbumService`, `AudioDirector`, `EventBus`.

**Platform abstraction still matters.** File picking, album export, persistence sync and the Claude bake differ between web and Windows. One interface in `src/core/platform.gd`, two implementations, written at M0. Scattered `OS.has_feature("web")` checks are what make dual-target projects miserable.

### 2.1 Flow

```
Main menu ──► Load/Edit (editor) ──► pick or build album
    │                                      │
    └──────────────► Play ◄────────────────┘
                      │
      Hospital bedside ─(take his hand)─► transition ─► Gallery hallway
                                                            │
                                    10 × [Approach → Examine → Guessing
                                          → (Hint|Unblur)* → Scored → Revealed]
                                                            │
                                            End of hall ─► Hug ─► Fade ─► Menu
```

### 2.2 The round state machine

```
Idle → Approach → Examine → Guessing → (Hint | Unblur)* → Submitted → Scored → Revealed → Reflect → Idle
                                                                                            ↓ (10th)
                                                                                         Ending
```

Only `RoundController` changes `GameState.phase`. Each transition is one method.

---

## 3. The album format

Build this before any 3D work. Everything binds to it.

### 3.1 Container

A `*.ccalbum` ZIP holding exactly ten photos — roughly **5 MB**, so it attaches to an email and loads instantly.

```
album.json
photos/<photoId>/
  full.webp                  # 2048 px long edge
  blur_0.webp … blur_3.webp  # pre-baked tiers, descending resolution
  thumb.webp
cover.webp
```

Because the file is small, **use normal ZIP deflate and plain `ZIPReader`** — v3's STORE-only requirement and hand-rolled range reader exist to solve a problem that no longer exists. (WebP won't compress further, so the images are effectively stored anyway; there's just no need to enforce it.)

No `audio/` — text bubbles only. Leave the path reserved so adding voice later needs no schema bump.

### 3.2 Manifest schema (v1)

```jsonc
{
  "schemaVersion": 1,
  "albumId": "uuid",
  "title": "Margaret & Tom",
  "authorNote": "For Mum. — Ellie",
  "createdUtc": "2026-09-16T12:00:00Z",
  "coverPhotoId": "p_003",

  "curator": {
    "voiceName": "Tom",
    "playerName": "Maggie",
    "style": "warm, a little wry, drifts mid-sentence when tired"
  },
  "scoring": {
    "maxDistanceScore": 5000, "maxDateScore": 2000,
    "distanceHalfLifeKm": 250,
    "unblurCostFraction": 0.20, "hintCosts": [0.10, 0.20, 0.35],
    "maxSpentFraction": 0.85
  },

  "hangOrder": ["p_001", "p_002", "…"],   // exactly 10; wall order down the hall

  "photos": [
    {
      "id": "p_003",
      "files": {
        "full": "photos/p_003/full.webp",
        "blurTiers": ["photos/p_003/blur_0.webp", "…"],
        "thumb": "photos/p_003/thumb.webp"
      },
      "aspect": 1.5,
      "truth": {
        "lat": 43.7696, "lon": 11.2558,
        "placeLabel": "Florence, Italy",
        "admin": { "country": "IT", "region": "Tuscany" },
        "locationPrecisionKm": 5,
        "date": { "year": 1978, "month": 6, "day": null },
        "datePrecision": "month"
      },
      "content": {
        "title": "The bridge with the shops on it",
        "description": "Author's text. Source material for the Claude bake.",
        "people": ["Margaret", "Tom"],
        "tags": ["honeymoon", "europe", "summer"],
        "privateNote": "NEVER RENDERED IN GAME."
      },
      "curatorLines": {
        "idleBarks": ["You always liked this one."],
        "hints": [
          { "tier": 1, "text": "Warm stone. You complained about the heat for a week." },
          { "tier": 2, "text": "We were in Italy. You bought that awful straw hat." },
          { "tier": 3, "text": "Florence, love. The bridge with the little shops on it." }
        ],
        "wrongGuessFar": ["Not even the right sea, Maggie."],
        "wrongGuessNear": ["Close. Same country. Wrong city."],
        "revealMonologue": "June of '78. …",
        "bake": { "model": "claude-opus-5", "bakedUtc": "…", "approvedByAuthor": true }
      }
    }
  ]
}
```

Details that matter:

- **`hangOrder`** is the author's chosen sequence down the hallway. Order is dramatic: open with something easy and warm, close with the one that hurts.
- **`curator.playerName`** — he should use her name. Small field, large effect.
- **`schemaVersion`** checked on load, with a migration hook.
- **`datePrecision`** (`day`|`month`|`year`|`decade`) drives calendar granularity *and* scoring tolerance. Scanned photos often only have a decade; don't punish that.
- **`locationPrecisionKm`** lets a photo say "anywhere in this city counts," so a pin 3 km off a Florence centroid isn't docked.
- **`privateNote` is never rendered.** Put that in a comment on the field too.
- **`approvedByAuthor`** gates export; an album with unapproved AI text warns loudly.

### 3.3 Loading

```gdscript
# bytes from the JS file picker (§5) or FileAccess on Windows
var f := FileAccess.open("user://tmp.ccalbum", FileAccess.WRITE)
f.store_buffer(bytes); f.close()
var zip := ZIPReader.new()
zip.open("user://tmp.ccalbum")
# read album.json, then each photo's tiers on demand
```

`user://` on web is IndexedDB-backed and works through `FileAccess`; a 5 MB write is instant. Call `JavaScriptBridge.force_fs_sync()` after writes that must survive a refresh.

With only ten photos, **decode all four blur tiers for all ten up front** — that's about 600 KB of image data and well under a second. The full-res versions stay unloaded until each reveal. This removes the streaming system entirely: there is no eviction, no LRU, no budget.

Validation returns a **list** of problems rather than throwing on the first. Missing `truth.lat` is a hard error; a missing hint tier is a warning that falls back to the place label.

---

## 4. The blur ladder

### 4.1 Descending resolution

A blurred photo carries almost no information, so it doesn't need to be a big texture:

| Tier | Meaning | Long edge | Blur | ≈ size |
|---|---|---|---|---|
| 0 | Opening — fog with a shape in it | 64 px | heavy | 2 KB |
| 1 | First unblur | 128 px | strong | 5 KB |
| 2 | | 256 px | moderate | 15 KB |
| 3 | Nearly there | 512 px | light | 40 KB |
| full | Revealed | 2048 px | none | ~400 KB |

Upscaling a 64 px image onto a 1.5 m canvas with bilinear filtering **is** a blur, and a good-looking one. Bake the tiers at authoring time with a separable gaussian — never at runtime in a shader, which would keep the full-res texture resident and defeat the point.

### 4.2 Godot mechanics

- Decode from bytes: `Image.load_webp_from_buffer()` — exists, takes `PackedByteArray`. (`Image.load_from_file()` is static but wants a real path, so it's no use for archive contents.)
- `img.generate_mipmaps()`, then `img.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_SRGB)` on web / `COMPRESS_S3TC` on Windows, then `ImageTexture.create_from_image()`. Signature: `compress(mode, source = 0, profile = 0)`. `COMPRESS_SOURCE_SRGB` matters — the compressor weights colour channels differently. **Check the return and fall back to uncompressed** if a browser refuses.
- Frames use `StandardMaterial3D.albedo_texture`, swapped on tier change. Linear filter with mipmaps.
- The reveal decode (~40 ms for a 2048 px WebP) happens while the player stands still looking at the photo. Invisible. Decode it one frame after the guess is submitted so it's ready when the reveal animation plays.

### 4.3 Mixed aspect ratios in fixed frames

Ten hand-placed frames, but the author's photos will be a mix of portrait, landscape and square. Stretching is unacceptable and varying frame sizes wrecks the art direction.

**Solution, and it's what real galleries do: a uniform outer frame with a variable mat.** Every frame mesh is the same physical size; inside it, a passe-partout (mount board) whose window is cut to the photo's aspect. A portrait photo gets wide side margins, a landscape gets deep top and bottom. Implement as a shader on the mat quad that computes the window from the `aspect` field, or as a mesh whose inner border scales. Uniform, elegant, and it solves the problem completely.

Set a maximum window so a panorama doesn't become a letterbox slit — clamp extreme aspects and centre-crop slightly.

---

## 5. Loading photos from a folder

The editor points at your source folder — which may hold a thousand photos — and you pick ten.

### 5.1 The picker

```gdscript
# src/web/file_picker.gd
var _cb: JavaScriptObject   # MUST stay alive until the callback fires

func pick_folder() -> void:
    _cb = JavaScriptBridge.create_callback(_on_files_ready)
    JavaScriptBridge.eval("""
      (() => {
        const i = document.createElement('input');
        i.type = 'file';
        i.webkitdirectory = true;
        i.multiple = true;
        i.onchange = () => { window.__ccFiles = Array.from(i.files); window.__ccReady(); };
        i.click();
      })();
    """, true)
```

Confirmed APIs:

- `JavaScriptBridge.create_callback(callable)` — real callbacks, no polling. **Keep the returned object in a member variable** or it's garbage-collected before firing.
- `JavaScriptBridge.js_buffer_to_packed_byte_array(buf)` — JS `ArrayBuffer` → `PackedByteArray`. This is what makes binary loading work; `readAsText` corrupts image bytes, which is why the common blog-post approach is wrong.
- `JavaScriptBridge.download_buffer(bytes, name, mime)` — triggers a browser download; how the editor exports the `.ccalbum`.

### 5.2 A thousand-file folder is fine

`webkitdirectory` works in Chrome, Edge, Safari and Firefox, and its `File` objects are **lazy handles**: you get names, sizes and dates for a thousand files instantly and pay nothing until `.arrayBuffer()` is called. So the editor lists everything immediately, decodes thumbnails only for rows on screen (virtualised grid), and reads full bytes only for the ten being used.

**This is the one place worth a scale test** (folded into M5): a virtualised grid over 1,000–5,000 files, with lazy thumbnail decode and a cap on concurrent decodes.

The File System Access API (`window.showDirectoryPicker()`) gives persistent re-grantable handles so a returning author doesn't re-pick the folder — nice, Chrome/Edge only, strictly an enhancement.

**Windows:** native `FileDialog`, `access = ACCESS_FILESYSTEM`, directory mode. Same decode path behind the platform interface.

---

## 6. Art production

### 6.1 Two spaces

**The hospital room.** Small and intimate: a bed, a chair, a window with late light, an IV stand, a side table with a water glass. Mostly viewed from one or two angles. Minimal interaction — she walks to the bedside, one prompt ("take his hand"), and the transition begins. Cheap to build, enormous narrative return.

**The gallery hallway.** A long hall with ten frames. Tall windows down one side throwing light across the opposite wall where the photographs hang; pilasters and sconces setting a rhythm; a coffered ceiling; a runner on parquet; the far end in shadow where he waits. Ten frame anchors, hand-placed and individually lit.

A hallway is the right choice mechanically as well as artistically: it makes progression linear and legible, gives the walk between photographs a natural pace, and means the camera is nearly always looking down its length — so you can art-direct the exact composition the player sees.

### 6.2 What makes what

You're installing Blender but not using the UI, so **everything runs as `blender --background --python tools/blender/<script>.py`.** I write the scripts; you run a batch file.

| Asset class | How | Tool |
|---|---|---|
| Hallway shell — walls, floor, coffered ceiling, cornices, pilasters, wainscoting, window and door frames, picture frames, skirting | Hand-assembled from parameterised modules, art-directed in the Godot editor | GDScript generators + Godot editor |
| Trim-sheet textures with baked AO, curvature, detail normals | Baked from a high-poly source | **Blender headless** |
| Lightmap GI bake | Full Cycles GI baked to texture | **Blender headless** (or `LightmapGI`; §6.3) |
| Furniture, drapes, chandeliers, sconces, hospital bed, IV stand, rugs, books | Downloaded CC0 `.glb`, dressed by hand | Poly Haven, Quaternius, ambientCG |
| CC0 prop cleanup — decimation, LOD, atlas packing, glTF re-export | Batch processing | **Blender headless** |
| Voxel characters | A voxel model *is* a grid of coloured cubes — authored as data, greedy-meshed in code | GDScript |
| Animation (walk, idle, look, **the hug**) | Hand-keyed on a parts hierarchy | Godot `AnimationPlayer` |

Note the shift from v3: with **one** hallway rather than ten room types, hand-assembly beats procedural generation. Procedural earns its keep when you need a hundred variations cheaply; here you need one space to be beautiful, so art control wins. Keep the generators for repeated trim elements (running a cornice profile along a wall, spacing pilasters evenly) and place everything else by hand.

### 6.3 Lighting

- **Baked GI is the primary light source.** Try `LightmapGI` first — with a single static scene, v3's instancing worry evaporates entirely, so this is now the straightforward path. Blender/Cycles baking stays available if you want higher quality or more control.
- **Bake AO and detail normals into the trim sheets** (Blender). SSAO doesn't exist in Compatibility, so contact shading has to come from textures. Highest-value use of Blender here.
- **Fake the light shafts.** No volumetric fog on web: low-poly cones from each window with an additive, depth-faded, slightly animated shader. At these angles, barely distinguishable from the real thing — and a hallway with tall windows is exactly the setup where this reads best.
- **Dust motes** as `GPUParticles3D`. Survives Compatibility; enormous return per unit cost.
- **A dim accent light per photograph**, which also does gameplay work — it draws the eye to the next frame.
- **Post-process** on a fullscreen quad: ACES-ish tonemap, bloom, vignette, grain, gentle chromatic aberration. Restraint — a photograph, not a filter.
- Verify `AreaLight3D` in Compatibility at M1; window light is the obvious use if it works.

### 6.4 The transition

The dissolve from hospital room to gallery is the most important thirty seconds in the game, and it's a direction problem more than a technical one. Achievable entirely in Compatibility:

- Crossfade two loaded scenes through a fullscreen dissolve shader, masked by a noise texture so the hospital *peels* rather than fades flat.
- Carry motifs across: the window light in the hospital becomes the hallway's window light; the shape of the bed becomes the shape of the runner; the heart monitor's rhythm becomes her footsteps.
- Audio does half the work — monitor beep and ventilator hiss crossfading into room tone and echo.
- Hold it longer than feels comfortable. This beat is the premise.

---

## 7. Map, calendar, scoring

### 7.1 Bundled vector map, not tiles

Natural Earth: 1:110m countries and coastline for the wide view, 1:50m closer, populated places for labels. Public domain — "no permission is needed to use Natural Earth. Crediting the authors is unnecessary" — though `CREDITS.md` can carry their suggested "Made with Natural Earth" as a courtesy. Convert GeoJSON to compact binary at build time; draw with `Polygon2D`/`Line2D` or a custom `_draw()`.

A few MB, no network, and — the real reason — **it can be painted**. A parchment-and-ink map belongs in a dying man's memory palace in a way satellite tiles never would.

Use **equirectangular projection** underneath: lat/lon → x/y is one line and inverse-projecting a click is trivial. Paint distortion into the presentation if you like, but never let the pretty version and the math version diverge.

Online tiles are the wrong choice: internet dependency, attribution UI, OSM's tile ToS forbids app use, Mapbox costs per view, and it breaks the tone.

### 7.2 Scoring

```
effectiveKm    = max(0, distanceKm - locationPrecisionKm)      # haversine, r = 6371 km
distanceScore  = maxDistanceScore * exp(-effectiveKm / distanceHalfLifeKm)
dateScore      = maxDateScore * exp(-abs(guessYear - truthYear) / 4)   # + month bonus where precision allows
roundScore     = (distanceScore + dateScore) * (1 - clamp(totalSpent, 0, maxSpentFraction))
```

Exponential decay rewards real recognition steeply, still credits the right country, and tails to ~0 rather than going negative. A `decade`-precision photo scores full marks anywhere in the decade.

`totalSpent` sums unblur and hint costs. **Never let it reach zero** — a player who needed every hint still got it right, and this game should never punish that.

With only ten rounds, a final score out of ~70,000 is the session's whole result, and replaying the same ten photos for a better score is the only replay incentive. That's fine for a gift. Show a per-photo breakdown on the results screen; it's a keepsake in itself.

All constants live in the manifest with code defaults, plus **a debug overlay showing live score math** at M3 — these numbers are only tunable against a real album with a real player.

### 7.3 Calendar

A dial revealing decade → year → month → day, only as deep as `datePrecision` requires.

---

## 8. The curator

### 8.1 Text bubbles carry the whole performance

No TTS, so typography does the acting:

- Worldspace bubble above him — `Label3D`, or a billboarded `SubViewport` for proper rounded corners and a tail — with a screen-space fallback for long lines.
- **Character-by-character reveal with punctuation-aware pacing**: a comma pauses, a full stop pauses longer, an ellipsis pauses much longer. The single highest-value detail in the dialogue system; it's what makes text *feel* spoken.
- Dismiss on input, auto-advance after a generous dwell, never time-pressured.
- Large-text mode on by default (§10); bubbles auto-size.

### 8.2 Helping is grief

As a player takes more hints in a round, his bubbles degrade — slower reveal, a repeated word, a sentence trailing off — and the hallway dims a notch. Tier 3 should cost something that isn't points.

**At ten photos this matters more than it did at a thousand.** Over a long album the degradation would be a slow ambient texture; across ten rounds it's a visible arc, and if the player leans on him the hall is noticeably darker by the end than if she didn't. That's the game saying something. Worth getting right.

### 8.3 Baking with Claude

Runs in the editor. The Anthropic API supports direct browser calls via the `anthropic-dangerous-direct-browser-access: true` header. Your key is pasted into a field and stored in IndexedDB — **never in the shipped build, never committed.** Add a "clear key" button and a plain warning beside the field.

Ten photos per album, so **use `claude-opus-5` and don't think about cost** — a full bake is well under a dollar. v3's batching, resumability and Sonnet-for-bulk recommendations are unnecessary; one call per photo, done.

**The prompt's three hard constraints** — these *are* the quality bar, and with only ten rounds a single bad hint is 10% of the game:

1. **The ladder must be monotonic, generated in one call per photo.** Tier 1 gives sensory detail and emotion but no place name, country, language or landmark. Tier 2 narrows to region or country. Tier 3 names the place. Generating all three together keeps them consistent; never generate them independently.
2. **Voice, not narration.** He speaks *to her*, present tense, uses her name (`curator.playerName`), has opinions about the day. Not "This photograph depicts…"
3. **Never invent facts.** Only the author's description and metadata. **Hallucinated detail in a memorial gift is this project's worst failure mode** — worse than a crash. Request strict JSON, and show the source description beside every generated line so drift is visible at a glance.

**Graceful degradation:** with no key or a failed call, a local template generator produces serviceable lines from metadata alone (`"Somewhere warm. Somewhere near water."` → `"We were in {country}."` → `"{placeLabel}."`), flagged as needing a human pass. The game must never depend on the bake having happened.

---

## 9. The editor — the "load game" page

One build, reachable from the menu. Five screens, and at ten photos it's a modest piece of work rather than v3's two-milestone monster.

1. **Album** — load an existing `.ccalbum`, or start a new one. Shows the ten slots.
2. **Source** — pick your folder; virtualised thumbnail grid over up to a few thousand files with lazy decode; filter by name, date, subfolder. Drag a photo into a slot.
3. **Photo detail** — thumbnail, title, description, people, tags; map picker for lat/lon (reuses the gameplay map widget); calendar picker with precision selector. EXIF prefills date and GPS where present, and reverse-geocoding turns GPS into a readable place label.
4. **Curator** — generate lines with Claude, review and edit every field, regenerate one field, approve. Source description shown alongside.
5. **Hang & export** — order the ten down the hallway, then validate (with jump-to-problem) and export via `download_buffer`.

**Ingest per photo:** read bytes → parse EXIF → auto-rotate → downscale to 2048 → generate 4 blur tiers + thumb → encode WebP → prefill truth fields → queue for review.

Autosave `album-draft.json` to `user://` after every change (metadata only, never images) so closing the tab doesn't lose work, and offer "export draft" for an off-browser backup.

**Scanned photos have no EXIF**, which for sixty-year-old photographs is the common case, not the edge case. Manual entry must be the comfortable path and EXIF the pleasant surprise.

---

## 10. Characters, save, accessibility

### 10.1 Voxel pipeline

Characters are authored as data — a layer-stack of coloured grids per body part — and meshed in code with greedy meshing (a 16×32×16 figure drops from ~25k tris to a few hundred). Parts are separate `MeshInstance3D`s: head, torso, upper/lower arms, hands, upper/lower legs, feet. That hierarchy is both the rig and the customization slot system.

Voxel figures in a lit realistic hallway need help not to look pasted on: they must **receive** the baked light and **cast** real shadows, plus a contact-shadow blob at the feet. **Get one voxel figure into the lit grey-box hallway at M1** — if that shot doesn't read well, you want to know before building anything.

### 10.2 Customization

Slots: hair, head covering, glasses, dress/top, shawl, shoes, cane, jewellery. Colour via per-instance shader uniforms (skin, hair, two garment colours) — cheap, and multiplies the options. The customization scene sits off the main menu; saves to `user://profile.json`. Third-person camera means the avatar is always on screen, which is what justifies the feature.

### 10.3 The husband as companion

`NavigationAgent3D` on the hallway's nav mesh; follows with a lag and a personal-space radius, and **stops to look at photographs on his own** — that idle behaviour is most of the characterisation. Head aim at the player during dialogue, at the photo otherwise. Barks from `EventBus` with a cooldown. He should sometimes reach the next frame first and wait. Small thing; makes him a person. At the end he's waiting in the shadow at the far end of the hall.

### 10.4 Controller

`CharacterBody3D`, spring-arm camera with collision-aware arm length, walk and slow-walk (no run — wrong tone), ease to a framing position when examining rather than cutting. `Area3D` triggers on frames with a screen prompt.

### 10.5 Save and settings

Progress is only `progress.json` — best score and per-photo results per album id. No mid-session save: the session is ten to fifteen minutes and ends at the menu, so there's nothing to resume. Settings: mouse/gamepad, sensitivity, FOV, text size, audio buses, quality preset.

### 10.6 Accessibility is load-bearing

The plausible audience includes elderly players. Large text **on by default**, high-contrast UI option, no timers anywhere, no reflex requirements, adjustable walk speed, full keyboard-only and gamepad-only paths, and a **"just walk the gallery"** mode that skips the guessing and lets someone look at the photographs while he talks about them. That last one sounds like it undermines the game. It's the option that makes it a gift.

---

## 11. Google Photos — phase 2

The old path is gone: since 31 March 2025 the Library API no longer reads a user's existing library, and the broad read scopes were removed. The **Picker API** is the only route (single scope `photospicker.mediaitems.readonly`), and it's well-designed — the user selects inside Google's own UI.

The costs: **OAuth verification is required** (workable for a gift by staying in testing mode with your users added — capped at 100, shows an "unverified app" warning), and **token exchange needs a backend**, which breaks the static-hosting property you specifically wanted.

**Phase 2, behind a `PhotoSource` interface** with `LocalFolderSource` first, so `GooglePhotosSource` slots in without touching ingest or the album format. For sixty years of photographs, a folder of scans is the better source anyway.

---

## 12. Milestones

| # | Milestone | State | What remains |
|---|---|---|---|
| **M0** | Foundation | **done** | — |
| **M1** | Grey-box + style test | **done** | The go/no-go shot has now been taken *in a browser* (`tools/verify_web.py`), which was M1's actual exit criterion. |
| **M2** | Vertical slice | **done** | Album schema, ZIP load, blur tiers, uniform-frame/variable-mat, the round FSM, HUD, guess input and scoring all exist and are tested. Still not played end to end by a human with a real album. |
| **M3** | Map & calendar | **mostly** | Map widget, pin, zoom/pan, calendar dial, real scoring and the results screen are in. The Natural Earth bake is **not**: no host that serves it is reachable from this environment, so `tools/fetch_geo.py` has to be run once on a machine with network (§16.6). |
| **M4** | Curator | **part** | Text bubbles with punctuation pacing, the hint ladder, costs and fatigue are in. Idle barks, wrong-guess lines and hall dimming are not. Nothing is baked with Claude yet. |
| **M5** | Editor | **mostly** | Folder picking, ten slots, hang order, per-photo metadata, map pinning, EXIF prefill, validation, export and reopening all work, with 75 tests covering the pipeline from ten JPEGs to a loadable `.ccalbum`. Missing: a thumbnail grid (the source list is filenames), draft autosave, and the Claude bake. |
| **M6** | Characters | **part** | The figures exist, are drawn rather than voxelled (§16.2), walk, turn to camera and cast shadows. Customization slots, palette UI and profile save are not built. |
| **M7** | Art pass | **not started** | Both spaces are grey-box. Trim sheets, Blender AO/GI bakes, prop dressing. |
| **M8** | Narrative | **done** | Hospital opening, "take his hand", the transition, the hug, the fade and the return to the menu all play. No music or ambience. |
| **M9** | Polish | **not started** | Settings, accessibility pass, "just walk" mode, balance, playtest. |

**Ordering notes.** M3 before M4, because hints are only tunable once real scoring exists. M5 before M7, so the hallway is dressed against a real album rather than test data. **M7 is now a single art pass on two small spaces** rather than v3's ten room types — the largest single scope reduction in this revision.

**The ending (M8), as built:** tenth photo revealed → they walk toward each
other and meet in the middle → they turn to each other and he says his closing
line, if the author wrote one → both figures are replaced by one drawn embrace
pose → the light rises until it is all there is → results screen → main menu.

That differs from the v4 specification in two ways, both deliberate. There is no
`AnimationPlayer` keying two transforms: an extruded drawing has no joints, so
the hug is *drawn* (§16.2). And they meet in the middle rather than her walking
to him, because the ending can fire anywhere in a 27-metre hall and one figure
crossing all of it at an old woman's pace is most of a minute of nothing.

---

## 13. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| C# discovered to be a dead end late | **Critical** | Settled: GDScript. Strip `[dotnet]` at M0. |
| Claude produces a non-monotonic or hallucinated ladder | **Critical** | With ten rounds, one bad hint is 10% of the game. Three tiers in one call with per-tier constraints; source description shown beside every line; per-photo approval gates export. Opus, no cost pressure. |
| The transition doesn't land | **High** | It's the premise, and it's direction not tech. Prototype it early at M1 as a grey-box crossfade; don't leave it to M8 to discover it feels flat. |
| Mixed photo aspects break the frame art direction | High | Uniform outer frame + variable mat (§4.3), with clamping for extreme aspects. Solve at M2, before the hallway is built. |
| "Realistic" still not reached | Medium | Budget and Blender have both moved in your favour (§1.4). Go/no-go at M1 on the *web* build, before art investment. |
| Voxel figures look pasted in | Medium | Resolve at M1 with a lit test shot: shadow casting, contact shadows, shared light response. |
| Ten photos feels thin | Medium | Lean on pacing and craft rather than volume: `hangOrder` as dramatic structure, the degradation arc (§8.2), a keepsake results screen. Playtest at M9 will tell you plainly. |
| Editor source-folder grid stalls on a big folder | Medium | Virtualised grid, lazy decode, capped concurrency; scale-tested at M5 against a few thousand files. |
| Browser file-picker inconsistency | Medium | `webkitdirectory` + lazy handles as the base path (all four major browsers); File System Access API as enhancement; test Chrome, Firefox, Safari at M5. |
| `.pck` over 100 MB | Medium | A hard GitHub limit, not a preference. Two small spaces make it comfortable, but check every milestone — trim sheets are still the primary lever. |
| API key in browser IndexedDB | Medium | Editor-only, never in the shipped build, never committed; clear-key button; you are the only user. |
| Album schema churn | Low | `schemaVersion` + migration hook from day one; validator reports all problems; never remove a field, only deprecate. |
| Emotional subject matter mishandled | Medium | No fail states, no timers, no "game over." He never says anything you didn't approve. "Just walk" mode for anyone who'd rather not be tested. |

---

## 14. Next steps

In order, most valuable first.

1. **Deploy to Pages and open your own URL.** The build itself is verified in
   a browser (§16.8), but that deployment is not. Set Pages to "GitHub
   Actions" as its source and push.
2. **Run `python tools/fetch_geo.py` once** and commit `data/geo/coastlines.json`.
   Until then the map draws a graticule and the guess panel falls back to its
   place list (§16.6).
3. **Build one real album in the editor and play it.** Everything up to now
   has been exercised with generated test data; the first album made from real
   photographs is where the remaining gaps will show.
4. **Bake one real album's curator lines with Claude**, and read all thirty
   hint lines. Then tune the hint economy against them (M4).
5. **The art pass (M7).** Both spaces are grey-box and will stay convincing
   only up to a point.
6. **Playtest with someone who is not you**, before the gift is given.

---

## 15. Open question — answered

**Does the hospital scene bookend the game, or only open it?**

It only opens it. Confirmed 2026-09-16: *"the hospital scene is only at the
start, the game ends with the hug."* The implementation takes that literally —
nothing interrupts the hug, and the results screen waits for
`EventBus.ending_finished` rather than `session_completed`, so the numbers
arrive after the ending rather than on top of it.

---

## 16. Where the implementation departed from this plan

Each of these cost a bug, a render or an afternoon to learn. They are recorded
here because the code comments explain what the rule *is*, and this explains
why the plan says something else.

### 16.1 The gallery is bigger than §6.1 describes

Five bays a side, ten pictures, 9.2 m wide, 6.2 m high, 27.2 m long, with
clerestory windows above the art. Museum-scale: each picture's opening is
2.12 × 1.74 m. The clerestory is the only way to light both walls when both
walls hold art.

### 16.2 The characters are drawn, not voxelled (§10.1)

A voxel figure at a person's scale is nine voxels across the torso, which is
not pixel art, it is Minecraft. The figures are instead 34 × 56 *drawings*
extruded to three pixels of thickness: same greedy mesher, twenty-five times
the detail, a real cast shadow with the character's exact silhouette, and no
transparency to sort. Three views are drawn (front, side, back), the view is
chosen from where the camera is, and the sprite is then turned to camera about
Y — without that last step a flat drawing foreshortens into a plank as soon as
the camera is oblique.

The cost is that there are no joints. The walk is a bob and a lean rather than
swinging limbs, and any pose the game needs has to be drawn: hence
`EmbraceFigure` for the hug, and `RestingHead` for the man in the hospital bed.

### 16.3 Nothing in the data layer may reference an autoload

Autoload names are not registered as GDScript globals until *after* the script
passed to `--script` is compiled. Anything a headless tool or the test runner
touches therefore cannot name `Platform`, `GameState` or `EventBus`. That is
why logging is `CCLog` (a `class_name` with static members) rather than a `Log`
autoload, and why any tool that needs an autoload is split in two: a thin
`SceneTree` entry point that loads a `Node` script, which then may name
anything (`tests/test_host.gd`, `tools/ending_shots.gd`).

### 16.4 …and the tests need a live tree

Worse than the above: during a `SceneTree`'s `_initialize()` the root Window is
not yet inside the tree. `_ready` never fires, every `global_transform` returns
identity and logs an error, and `add_child` on the root fails outright during
its own `_ready` propagation. The round suite was passing 86 assertions against
nodes that were not really in a scene. The runner now adds a host node, waits
one `process_frame`, and runs the suites from there.

### 16.5 Fake volumetric light shafts do not survive this corridor

Built, wired up, and off by default. Additive slab geometry with
`cull_disabled` renders both faces of every box, the fade is evaluated at the
surface rather than integrated through the volume, and looking down the hall
stacks ten of them — which blew the upper frame to white at any energy high
enough to see. Revisit at M7 with either raymarched fog or one camera-facing
billboard per window.

### 16.6 The map's data cannot be committed from here

Every host that serves Natural Earth answers 403 at this environment's proxy,
from both the build container and the desktop VM. Rather than invent a
coastline that would look plausible and be wrong, the map takes its outline
from a pluggable loader (`CoastlineData`), `tools/fetch_geo.py` bakes the file,
and with no file present the map draws a graticule and the guess panel leads
with its place list instead.

The place list was built first, as scaffolding, and is now a feature: §10.6
wanted an easier mode for players who would rather not be tested on
coordinates, and that is exactly what it is.

### 16.7 Shadow bias, not corrugated plaster

Godot's default shadow bias (0.03 / 1.0) gives severe acne where a light
strikes a surface at a grazing angle, which is exactly what a clerestory does
to the opposite wall. Every render from M1 onward had regular horizontal
banding across the walls and ceiling that read as ribbed plaster. 0.08 / 4.0
removes it entirely while keeping the pictures' shadows attached to their
frames. `tools/diag_shadows.gd` is the four-way comparison that settled it.

### 16.8 The web build is verified in a browser, and how

`tools/verify_web.py` serves the export over HTTP, opens it in headless
Chromium with software GL, waits for the engine banner and for the gallery to
report itself built, and fails on any JavaScript error. Verified 2026-09-17:
WebGL 2 through the Compatibility renderer, Emscripten single-threaded, no
GDExtension, no page errors, ten frames and six windows built, keyboard input
reaching the game.

Two traps in writing that, both worth knowing:

- **Use a threading HTTP server.** A single-threaded one deadlocks: the
  browser opens several keep-alive connections at once for `index.js`,
  `index.wasm` and `index.pck`, and the unserved ones sit until they time out.
  The symptom is a build that appears never to boot.
- **Never `time.sleep` in a Playwright sync script.** The sync API only
  dispatches events while you are calling into it, so a poll loop that sleeps
  in Python receives no console messages at all — which looks exactly like a
  broken build. `page.wait_for_timeout` instead.

### 16.9 Look at it, always

Four rendering bugs, and everything in §16.2 and §16.7, were invisible in the
numbers and obvious in a picture: window spotlights firing through the wall,
ten panes rotated into one blown-out slab, light shafts running lengthwise down
the corridor, a figure whose hips sat below its own leg length, eyes drawn as
two-pixel bars that read as a blindfold, arms drawn over a chest that read as a
sash, a head twice life size, and an empty bed where a lambda had written
pixels into a copy of its own canvas.

Hence `tools/render_shots.gd`, `tools/render_ending.gd`,
`tools/render_hospital.gd`, `tools/diag_editor.gd` (which found "lat" stacked
as three vertical letters beside a spin box) and the other `diag_*` tools. They run headless under
xvfb with software GL, so CI can take them too. **Any change to geometry,
lighting or a drawn figure should be looked at before it is called done.**

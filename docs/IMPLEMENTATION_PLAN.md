# Chrono Cartographer — Implementation Plan

**Status:** v3 · 2026-09-16 · supersedes v2 (scale to 1000 photos; Blender available; hosting settled)
**Repo:** `C:\Users\victor\src\cartographer`
**Engine:** Godot 4.7, GDScript, Compatibility renderer
**Targets:** Web (primary) + Windows
**Scope:** personal gift · one album per load · albums up to 1000 photos · 10 photos per room

---

## 0. The premise, stated as a design brief

An old woman steps into her dying husband's mind. It has taken the shape of a mansion — heavy, sunlit, dusty — hung with the photographs of their life. She walks it with him. The photos start as fog. She has a map and a calendar and sixty years of memory, and she has to say *where* and *when*. He'll help if she asks, but asking costs her. At the end, they hug, and it fades out.

Three consequences govern everything downstream:

1. **The mansion is his mind, so it must feel inhabited.** This is where the art effort goes.
2. **The people are memories of people, so they don't need to be real.** Voxel characters in a believable room — the style clash *is* the statement.
3. **Helping is grief.** Every hint reveals more and scores less. The scoring loop and the emotional loop are the same loop, and must never be separated.

### Confirmed decisions

| Question | Decision |
|---|---|
| Language | **GDScript.** C# has no production web export (§1.1). |
| Renderer | **Compatibility (WebGL 2)** on both platforms. |
| AI curator | Pre-baked at authoring time using **Claude**. Shipped game makes zero AI calls. |
| Guessing | Real-world map, haversine distance + date scoring. |
| Camera / avatar | Third person. Player is the woman; the husband walks with her. |
| Husband's voice | **Text bubbles. No TTS.** |
| Album authoring | In-game editor. Point at a large folder, select ~10 at a time. |
| Platforms | **Web primary** + Windows. |
| Hosting | **GitHub Pages or self-hosted. No server side** — confirmed correct (§1.3). |
| Blender | **Available**, headless only (§7). |
| Album scale | **Up to 1000 photos, 10 per room → up to 100 rooms** (§2). |
| Google Photos | Phase 2, behind an interface (§12). |
| Ending | All photos guessed → they hug → fade out. |
| Albums | One album per load. No library. |
| Licensing | Personal gift; not a constraint. |

---

## 1. Platform constraints

### 1.1 GDScript, not C#

C# web export in Godot is still not production-ready in 2026: a draft PR exists but is single-threaded only, globalization is invariant-mode, browser API bindings are stubbed, and the tracking issue is locked with no target version. **Remove the `[dotnet]` block from `project.godot` at M0**, before any script exists.

The one real cost is losing NuGet, which means EXIF parsing must be hand-written in GDScript (~250 lines: JPEG APP1 → TIFF IFD → `DateTimeOriginal` 0x9003 + GPS IFD tags 1–4). At 1000-photo scale this is no longer optional — see §9.2.

### 1.2 Renderer: Compatibility / WebGL 2

Web export in 4.7 runs WebGL 2 through the Compatibility renderer; WebGPU did not land. Unavailable: SDFGI, VoxelGI, volumetric fog, SSAO, SSIL, SSR. `AreaLight3D` is very likely Forward+ only — **verify at M1 before designing lighting around it.**

Build for Compatibility on *both* platforms so the web build is the reference rather than a degraded afterthought. Forward+ stays available as an optional post-ship Windows upgrade via a per-platform override, but don't maintain two visual tiers during development.

### 1.3 Hosting — you're right, no server needed

Confirmed: **the entire game is static files.** Author picks a local folder → builds an album in the browser → `JavaScriptBridge.download_buffer()` hands them a `.ccalbum` → they send it however they like → recipient opens the same URL and picks that file from their own disk. Nothing is uploaded, nothing is hosted but the game itself. That property is worth protecting; it's why this still works in ten years.

GitHub Pages specifics that constrain the build:

- **1 GB site limit, 100 GB/month bandwidth** — irrelevant at our size.
- **100 MB per file** (a git limit, not a Pages limit — GitHub refuses pushes above it). Godot's web export emits a `.wasm` (~30–40 MB) plus a `.pck` holding all project assets. **So the `.pck` must stay under 100 MB.** That, plus the wasm, is where §1.4's budget number comes from.
- **No custom HTTP headers.** GitHub Pages can't send COOP/COEP, so `SharedArrayBuffer` — and therefore Godot's threads — are unavailable unless you add the `coi-serviceworker` shim, which achieves cross-origin isolation from inside the page. Self-hosting lets you just set the headers.

**Plan single-threaded regardless.** §4's blur-tier design makes threads an optimization rather than a requirement, which keeps your hosting options open. Add `coi-serviceworker` later only if profiling says so.

### 1.4 Download budget

**Hard budget: `.pck` under 100 MB, total download under 150 MB.** Check it at every milestone. Levers by power:

1. **Trim-sheet materials** — 3–4 shared material sets for *all* architecture rather than per-model textures. By far the biggest lever, and it gets stronger the more rooms you have.
2. **1K textures, not 4K.** At gallery viewing distances, indistinguishable.
3. **Per-platform VRAM compression** (ETC2/ASTC for web) via import settings.
4. **Procedural architecture ships as code**, not meshes — near-zero bytes (§7).
5. **Room types, not rooms.** 100 rooms built from ~10 parameterised types cost the same as 10 (§8.3).

The happy accident: **photos are supplied by the player at runtime and never count against the download.** The 150 MB is entirely mansion.

### 1.5 The creative answer to the renderer

No realtime GI, no volumetric fog, a 150 MB budget. That puts **photorealism out of reach**, and it's better said now than discovered at M7.

What's reachable suits the story better. It is a *memory*, so make the unreality diegetic: warm dusty light, strong value contrast, soft haze, heavy bloom, edges falling into darkness, detail pooled around each photograph with everything else merely suggested. Baked light plus dense prop dressing in a tight value range reads as convincing — this is how architectural visualisation looked for fifteen years and it looked good. The darkness hides the renderer's limits and does narrative work simultaneously.

Now that Blender is available, this gets materially better: **bake ambient occlusion, curvature and detail normals into the trim sheets in Blender** (§7.3). That recovers most of what losing SSAO costs, at zero runtime expense.

**Target: believable and richly dressed with strong art direction — not photoreal.** This is M1's go/no-go.

---

## 2. Scale: 1000 photos, and where your assumption holds

You said album size shouldn't matter because only 10 photos load at a time. **At runtime that's exactly right, and it's the reason this design works.** But it only holds if one thing changes, and two other costs move elsewhere. Worth being precise, because 1000 is a hundredfold jump from the numbers v2 assumed.

### 2.1 Runtime — you're right, with one required fix

Only the current room's 10 photos (plus neighbours) are ever resident, so VRAM and decode cost are flat regardless of album size. **But v2's album-loading approach would have broken this**, because it copied the whole `.ccalbum` into `user://` before reading it. At 1000 photos that file is 330–480 MB (§2.2), and writing that into IndexedDB in a browser is slow, memory-hungry and quota-fragile.

**The fix — read the archive by byte range, never copying it (§3.3).** A picked browser `File` is a lazy handle supporting `.slice(start, end).arrayBuffer()`, so you can read the ZIP's central directory from the last few KB, then read only the exact byte ranges of the 10 photos you need. Combined with **storing the image entries uncompressed** in the ZIP, extracting a photo becomes a pure byte-range read with no decompression at all. WebP is already compressed, so ZIP deflate would have gained nothing anyway.

That makes a 1000-photo album *genuinely* free at runtime — your assumption, made true. It's the single most important change in this revision.

### 2.2 File size — the cost that doesn't disappear, but doesn't matter much

Per photo, with 4 blur tiers: blur tiers ~62 KB + thumb ~20 KB + full-res ~250–400 KB (1600–2048 px WebP) ≈ **330–480 KB**. So:

| Album | Size |
|---|---|
| 60 photos | ~25 MB — email attachment |
| 200 photos | ~80 MB — email, just barely |
| 1000 photos | **330–480 MB** — Drive/Dropbox link |

A 1000-photo album is not emailable. But it's also never *downloaded by the game* — the recipient picks it off their own disk, so there's no hosting cost, no bandwidth, no load time. You transfer it once by link. Not a problem, just worth knowing.

If you want it smaller: drop full-res to 1600 px and raise WebP compression. Diminishing returns past that.

### 2.3 Authoring effort — the real bottleneck at this scale

This is the cost that actually bites. 1000 photos means 1000 descriptions, 1000 locations, 1000 dates. At 10 per batch that's 100 authoring sessions. Nobody finishes that by hand.

So the editor has to carry the weight, and §9 is now a much bigger milestone than it was in v2:

- **EXIF bulk prefill is essential, not a bonus.** Digital photos hand you date and GPS for free — that's two of three fields, for nothing.
- **Batch metadata operations.** Select 30 photos → "all of these are Florence, June 1978" → apply. Most photo sets cluster by trip, so this collapses most of the work.
- **Session persistence is mandatory.** Work-in-progress must survive closing the tab.
- **Bake cost is real money.** ~1000 Claude calls at roughly 1.5K output tokens each is about **$40–60 on `claude-opus-5`, or ~$10 on `claude-sonnet-5`**. Recommendation: Sonnet for the bulk pass, Opus to re-bake the photos that matter most. You review everything either way.

### 2.4 Playtime and repetition — a design conversation, not a technical one

1000 photos at 60–90 seconds each is **17–25 hours**, across 100 rooms. And 100 rooms built from 10 types will feel repetitive however well you dress them.

Two structural answers, both cheap:

1. **Wings.** Group rooms into wings of ~10 (100 photos each), each with its own palette, dressing set and light temperature — the west wing cool and blue, the sun room warm, the cellar dim. Ten distinct-feeling regions instead of 100 samey rooms, and it gives the mansion a geography she can remember.
2. **Make the ending player-chosen, not completion-gated.** Rather than the hug firing after photo 1000, let the final room become accessible early and have the husband wait there. She reaches it when she's ready. A 1000-photo album then becomes *a place to visit* rather than a 25-hour completion task — and someone who plays 80 photos across three evenings still gets the ending.

**I'd build for 1000 and gently expect 80–150 to be the sweet spot.** The format shouldn't constrain you either way, and (2) means it doesn't.

---

## 3. The album format — the keystone

Build this before any 3D work. Everything binds to it and it's expensive to change later.

### 3.1 Container

A single `*.ccalbum` file — a ZIP archive.

```
album.json                   # manifest (deflated; it's text)
photos/<photoId>/
  full.webp                  # STORED, uncompressed
  blur_0.webp … blur_3.webp  # STORED
  thumb.webp                 # STORED
cover.webp
```

**All image entries must use ZIP method 0 (STORE), not deflate.** This is load-bearing for §3.3: it makes extracting a photo a plain byte-range read with no inflate step, which is what keeps a 480 MB album free at runtime. WebP is already compressed, so you lose essentially nothing. `album.json` can be deflated — at 1000 photos it's 2–4 MB of text that compresses well.

No `audio/` — text bubbles only. Leave the path reserved in the spec so adding voice later needs no schema bump.

### 3.2 Manifest schema (v1)

```jsonc
{
  "schemaVersion": 1,
  "albumId": "uuid",
  "title": "Margaret & Tom, 1961–2024",
  "authorNote": "For Mum. — Ellie",
  "createdUtc": "2026-09-16T12:00:00Z",
  "coverPhotoId": "p_003",
  "curator": { "voiceName": "Tom", "style": "warm, a little wry, drifts when tired" },
  "scoring": {
    "maxDistanceScore": 5000, "maxDateScore": 2000,
    "distanceHalfLifeKm": 250,
    "unblurCostFraction": 0.20, "hintCosts": [0.10, 0.20, 0.35],
    "maxSpentFraction": 0.85
  },
  "wings": [
    { "id": "west", "title": "The West Wing", "palette": "cool",
      "roomIds": ["r_001", "…"] }
  ],
  "rooms": [
    { "id": "r_001", "type": "hall_long", "dressing": "study_a",
      "wing": "west", "photoIds": ["p_001", "…"] }   // exactly 10
  ],
  "photos": [
    {
      "id": "p_003",
      "files": {
        "full":  { "path": "photos/p_003/full.webp",  "offset": 8814213, "size": 402113 },
        "blurTiers": [ { "path": "…", "offset": 0, "size": 0 } ],
        "thumb": { "path": "…", "offset": 0, "size": 0 }
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
        "tags": ["honeymoon", "europe", "summer", "river"],
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
        "bake": { "model": "claude-sonnet-5", "bakedUtc": "…", "approvedByAuthor": true }
      }
    }
  ]
}
```

Details that matter:

- **`offset` and `size` per file.** The manifest caches each entry's byte range, so the game doesn't even need to parse the central directory in the common case — read `album.json`, and every photo is a direct range read. Treat them as a cache: verify against the local file header's signature on first read and fall back to a directory parse if they disagree.
- **`rooms` and `wings` live in the manifest**, not computed at load. The author controls which 10 photos share a room (§9.3), which is much better than a solver guessing — photos from one trip belong together.
- **`schemaVersion`** is checked on load with a migration hook.
- **`datePrecision`** (`day`|`month`|`year`|`decade`) drives calendar granularity *and* scoring tolerance. Scanned photos often only have a decade; don't punish that.
- **`locationPrecisionKm`** lets a photo say "anywhere in this city counts."
- **`privateNote` is never rendered.** Put that in a comment on the field too.
- **`approvedByAuthor`** gates export; an album with unapproved AI text warns loudly.

### 3.3 Reading the archive — byte-range, no copy

This replaces v2's approach entirely and is the key to §2.1.

```gdscript
# src/album/zip_range_reader.gd — ~200 lines, one implementation for both platforms
#
# open(source)         source is a JS File handle (web) or a path (Windows)
# read_range(off, len) -> PackedByteArray
# central_directory()  -> parsed entries (fallback / verification path)
#
# Web:     JS  file.slice(off, off+len).arrayBuffer()
#          →   JavaScriptBridge.js_buffer_to_packed_byte_array()
# Windows: FileAccess.seek(off); get_buffer(len)
```

Sequence on album load:

1. Read the last 64 KB → locate the End Of Central Directory record → parse the central directory (or, for 1000 photos, read only `album.json`'s entry and trust its cached offsets).
2. Inflate and parse `album.json`.
3. Per photo, on demand: read `[offset, offset+size)`, skip the 30-byte local file header plus filename, hand the remaining bytes straight to `Image.load_webp_from_buffer()`. **No inflate, because the entry is STOREd.**

Why hand-roll rather than use `ZIPReader`: `ZIPReader.open()` wants a complete file on a filesystem, which on web means copying 480 MB into IndexedDB first. The byte-range reader avoids that entirely and gives identical behaviour on both platforms from one code path. ZIP's central directory format is stable and simple; this is a contained, well-specified piece of work.

*(If `ZIPReader.open_buffer()` has landed in 4.7 — there's a long-standing proposal — it still doesn't help, since it needs the whole buffer in memory. The range reader remains correct.)*

Validation returns a **list** of problems rather than throwing on the first. Missing `truth.lat` is a hard error; a missing hint tier is a warning with a fallback to the place label.

---

## 4. Photo loading and the blur ladder

### 4.1 The insight that makes it cheap

A blurred photo carries almost no information, so **it doesn't need to be a big texture.** Bake the tiers at *descending resolution*:

| Tier | Meaning | Long edge | Blur | ≈ size |
|---|---|---|---|---|
| 0 | Opening — fog with a shape in it | 64 px | heavy | 2 KB |
| 1 | First unblur | 128 px | strong | 5 KB |
| 2 | | 256 px | moderate | 15 KB |
| 3 | Nearly there | 512 px | light | 40 KB |
| full | Revealed | 1600–2048 px | none | 250–400 KB |

Upscaling a 64 px image onto a 1.5 m canvas with bilinear filtering **is** a blur, and a good-looking one. The pre-reveal experience costs kilobytes; the expensive texture decodes only at reveal, while the player stands still and a dropped frame is invisible.

*(v2 had five tiers; four is better. Tier 4 at 1024 px was 120 KB — a third of the per-photo budget for a step barely distinguishable from the reveal. Dropping it saves ~120 MB across a 1000-photo album.)*

This pays off four ways: albums stay small, VRAM stays flat, single-threaded web decode is fine, and **it's why a 100-room mansion costs no more than a 3-room one.**

Bake the blur properly at authoring time with a separable gaussian — never at runtime in a shader, which would keep the full-res texture resident and defeat the whole point.

### 4.2 Godot mechanics

- Decode from bytes: `Image.load_webp_from_buffer()` / `load_jpg_from_buffer()` / `load_png_from_buffer()` — all exist, all take `PackedByteArray`. `Image.load_from_file()` is static but wants a real path, so it's useless for archive contents.
- `img.generate_mipmaps()`, then `img.compress(Image.COMPRESS_ETC2, Image.COMPRESS_SOURCE_SRGB)` on web / `COMPRESS_S3TC` on Windows, then `ImageTexture.create_from_image()`. Signature: `compress(mode, source = 0, profile = 0)`. `COMPRESS_SOURCE_SRGB` matters — the compressor weights colour channels differently. **Check the return and fall back to uncompressed** if a browser refuses.
- Frames use `StandardMaterial3D.albedo_texture`, swapped on tier change. Linear filter with mipmaps; match frame UVs to `aspect` so nothing stretches.
- Single-threaded: decode at most one texture per frame from a queue in `_process`. With threads, decode on `WorkerThreadPool` and create the `ImageTexture` on the main thread (image work is thread-safe; texture creation isn't).

### 4.3 Streaming at 100 rooms

- Resident set: tiers 0–2 for the current room and its immediate neighbours; nothing else.
- Full-res evicted when leaving a room; revealed state persists in the save and re-decodes on return.
- Cap resident photo VRAM — 192 MB web, 256 MB Windows — LRU beyond it.
- **Also stream the rooms themselves.** At 100 rooms you cannot instance them all: keep room *N* and its neighbours loaded, free the rest, and bake navigation per room rather than mansion-wide.

### 4.4 Honest caveat

Anyone can open a `.ccalbum` in a ZIP tool and see `full.webp` — more easily now that entries are uncompressed. Encryption isn't worth it; the audience is family playing a gift.

---

## 5. Loading photos from a folder in the browser

Your priority-one requirement. It works cleanly — via the proper callback API, not the `eval`-and-poll hack in the blog posts (which uses `readAsText` and corrupts image bytes).

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
        i.webkitdirectory = true;   // whole folder; omit for multi-select
        i.multiple = true;
        i.onchange = () => { window.__ccFiles = Array.from(i.files); window.__ccReady(); };
        i.click();
      })();
    """, true)
```

Confirmed APIs:

- `JavaScriptBridge.create_callback(callable)` — real callbacks, no polling. **Keep the returned object in a member variable** or it's garbage-collected before firing.
- `JavaScriptBridge.js_buffer_to_packed_byte_array(buf)` — JS `ArrayBuffer` → `PackedByteArray`. This is what makes binary loading work.
- `JavaScriptBridge.download_buffer(bytes, name, mime)` — triggers a browser download; how the editor exports a `.ccalbum`.

### 5.2 Why `webkitdirectory` handles a 1000-photo folder

Supported in Chrome, Edge, Safari and Firefox, and the `File` objects it yields are **lazy handles**: you get names, sizes and dates for 5,000 files instantly and pay nothing until you call `.arrayBuffer()`. So the editor lists everything immediately, decodes thumbnails only for the rows currently on screen, and reads full bytes only for the 10 being worked on.

The **File System Access API** (`window.showDirectoryPicker()`) is a worthwhile enhancement at this scale — it returns *persistent, re-grantable* handles, so an author resuming session 47 of 100 doesn't re-pick the folder. Chrome/Edge only, so it layers on top of `webkitdirectory` rather than replacing it. Given §2.3's authoring burden, this is high-value.

### 5.3 Windows build

Native `FileDialog` with `access = ACCESS_FILESYSTEM`, directory mode. Same `Image.load_*_from_buffer` path underneath, behind the platform interface.

---

## 6. Map, calendar, scoring

### 6.1 Bundled vector map, not tiles

Natural Earth: 1:110m countries + coastline for the wide view, 1:50m closer, populated places for labels. Public domain — "no permission is needed to use Natural Earth. Crediting the authors is unnecessary" — though `CREDITS.md` can carry their suggested "Made with Natural Earth" as a courtesy. Convert GeoJSON to compact binary at build time; draw with `Polygon2D`/`Line2D` or custom `_draw()`.

A few MB, no network, and — the real reason — **it can be painted**. A parchment-and-ink map belongs in a dying man's memory palace in a way satellite tiles never would.

Use **equirectangular projection** underneath: lat/lon → x/y is one line, and inverse-projecting a click is trivial. Paint distortion into the presentation if you like, but never let the pretty version and the math version diverge.

Online tiles are the wrong choice: internet dependency, attribution UI, OSM's tile ToS forbids app use, Mapbox costs per view, and it breaks the tone.

### 6.2 Distance scoring

```
effectiveKm   = max(0, distanceKm - locationPrecisionKm)     # haversine, r = 6371 km
distanceScore = maxDistanceScore * exp(-effectiveKm / distanceHalfLifeKm)
```

Exponential decay rewards real recognition steeply, still credits the right country, and tails to ~0 rather than going negative. Per-album `distanceHalfLifeKm` tunes difficulty: 250 km for globe-trotting, 15 km for one county.

### 6.3 Calendar

A dial revealing decade → year → month → day, only as deep as `datePrecision` requires.

```
dateScore = maxDateScore * exp(-abs(guessYear - truthYear) / 4)   # + month bonus when precision allows
```

A `decade`-precision photo scores full marks anywhere in the decade.

### 6.4 Hint economy

Unblurring and asking both draw from one budget, cost shown before committing:

```
roundScore = (distanceScore + dateScore) * (1 - clamp(totalSpent, 0, maxSpentFraction))
```

Never let it reach zero. A player who needed every hint still got it right, and this game should never punish that.

All constants live in the manifest with code defaults, and **a debug overlay showing live score math** ships at M3 — these numbers are only tunable against a real album with a real player.

---

## 7. Art production with headless Blender

You're installing Blender but can't use the UI, so **everything runs as `blender --background --python tools/blender/<script>.py`.** I write the scripts; you run a batch file. You never open the interface.

### 7.1 What makes what

| Asset class | How | Tool |
|---|---|---|
| Walls, floors, ceilings, cornices, wainscoting, door and window frames, staircases, banisters, skirting, picture frames, plinths | Procedural `ArrayMesh` generation — all boxes, extrusions and lathes, and 80% of the screen | GDScript |
| Voxel characters | A voxel model *is* a grid of coloured cubes — authored as data, greedy-meshed in code | GDScript |
| Character animation (walk, idle, look, **the hug**) | Hand-keyed on a parts hierarchy | Godot `AnimationPlayer` |
| Trim-sheet textures with baked AO, curvature, detail normals | **Bake from a high-poly source to a flat sheet** | Blender headless |
| CC0 prop optimisation — decimation, LOD, glTF re-export, atlas packing | Batch processing for the download budget | Blender headless |
| Furniture, drapes, chandeliers, vases, books, rugs | Downloaded CC0 `.glb`, assembled in the Godot editor | Poly Haven, Quaternius, ambientCG |

### 7.2 Why procedural architecture fits

What makes a room read as *a mansion* — tall walls, deep cornices, panelled wainscoting, arched doorways, a sweeping staircase, heavy frames — is all prismatic or lathe geometry. Generating it in code gives parameterised rooms (change one number, every cornice updates), near-zero download cost, and no asset pipeline. The remaining 20% — the soft, irregular, hand-made things — is what CC0 props supply.

### 7.3 What Blender specifically buys you

This is the biggest change from v2, and it lands exactly where the renderer hurts:

1. **Baked AO and detail normals in the trim sheets.** SSAO doesn't exist in Compatibility, so contact shading has to come from textures. Blender bakes it from a high-poly source once, and it costs nothing at runtime. This is the single highest-value use of Blender here.
2. **Baked GI per room type, into textures.** Rather than relying on `LightmapGI` — whose interaction with 100 instanced rooms is an open question — bake full Cycles GI into each room *type*'s textures. Instance-safe by construction, works in Compatibility, and sidesteps the problem entirely (§8.3).
3. **Prop budget enforcement.** Batch-decimate and re-atlas downloaded CC0 assets to hit §1.4. Doing this by hand across 100 rooms' worth of props is not feasible; as a script it's one command.
4. **Lightmap UV unwrapping** where you do want engine-side bakes — Blender's unwrapper is better than doing it procedurally.

Set up `tools/blender/` with a runner batch file at M1 so the pipeline exists before it's needed.

### 7.4 Lighting

- Baked GI in trim-sheet/room textures (§7.3) as the primary source. Baked light is what separates "hobby 3D scene" from "photograph of a room."
- No volumetric fog on web, so **fake the light shafts**: low-poly cones from each window with an additive, depth-faded, slightly animated shader. At these angles, barely distinguishable from the real thing.
- Dust motes as `GPUParticles3D` — survives Compatibility, enormous return per unit cost.
- A few realtime lights for accents and to break up instanced rooms.
- Post-process on a fullscreen quad: ACES-ish tonemap, bloom, vignette, grain, gentle chromatic aberration. **Restraint** — a photograph, not a filter.
- Verify `AreaLight3D` in Compatibility at M1.

---

## 8. The mansion at 100 rooms

### 8.1 Rooms hold exactly 10 photos

Fixed at 10 per your decision, which simplifies a great deal: room capacity is constant, the layout problem becomes trivial (`ceil(photoCount / 10)` rooms), and the author groups photos into rooms explicitly in the editor (§9.3). A trip's photos share a room because the author said so, not because a solver guessed.

### 8.2 Wings give the mansion a geography

Per §2.4, group rooms into wings of ~10 rooms / 100 photos, each with its own palette, dressing set and light temperature. Ten distinct regions rather than 100 samey rooms, at the cost of ten parameter sets. It also gives her somewhere to *remember* — "the blue corridor" — which is the right feeling for a memory palace.

### 8.3 Instancing, and the open technical question

100 rooms from ~10 types × ~4 dressing variants. Each type is a parameterised procedural scene; instances vary by dressing, palette, accent lights and prop placement seed.

**The open question: how `LightmapGI` behaves across many instances of one pre-baked room scene.** Mesh lightmaps live in UV2 space and should reuse correctly, but LightmapGI also stores world-positioned probe data for dynamic objects, and whether that survives instancing needs testing rather than assuming.

**The safe path, available now that Blender is here: bake GI into the room type's textures in Blender** (§7.3). Instance-safe by definition, no per-instance bake, no engine-version risk. The tradeoff is that lighting is fully static per room type — which is acceptable, and the wing palettes plus realtime accent lights supply the variation. **Test the `LightmapGI` route at M1; if it doesn't instance cleanly, the Blender bake is the answer and nothing downstream changes.**

### 8.4 Streaming and navigation

Load room *N* and its neighbours; free the rest. Bake navigation per room scene rather than mansion-wide — a single nav mesh across 100 rooms is both slow to bake and pointless when only three are resident. Rooms connect through standard door sockets so any room can follow any other.

---

## 9. The album editor — now the biggest milestone

At 1000 photos this is where the project's real effort sits (§2.3).

### 9.1 Screens

1. **Source** — pick folder (File System Access API when available, `webkitdirectory` otherwise); virtualised thumbnail grid over up to 5,000 files with lazy decode; filter by filename, date, folder.
2. **Batch select** — choose ~10 for the next room; shows which files are already in the album.
3. **Metadata** — per-photo form, plus **batch apply** across the whole selection (§9.2).
4. **Rooms & wings** — arrange rooms into wings, reorder, retitle, set dressing/palette.
5. **Bake** — Claude generation with per-field review, regenerate-one, approve; batch bake with progress and cost estimate.
6. **Validate & export** — full validator with jump-to-problem, then `.ccalbum` via `download_buffer`.

### 9.2 Making 1000 photos tractable

- **EXIF prefill** (GDScript reader, §1.1): `DateTimeOriginal` and GPS where present. Two of three fields free on digital photos.
- **Batch apply**: set place, date, precision, tags or people across an entire selection at once. Photo sets cluster by trip; this is where most of the savings come from.
- **Reverse geocode** lat/lon to a place label from the bundled places table, so EXIF GPS becomes a readable answer automatically.
- **Cluster suggestions**: group by EXIF date proximity and propose room groupings. The author confirms rather than composes.
- **Progress dashboard**: how many photos have a location, a date, a description, approved lines. At this scale the author needs to see the shape of the remaining work.
- **Scanned photos have no EXIF**, which for sixty-year-old photographs is the common case, not the edge case. Manual entry must be the comfortable path and EXIF the pleasant surprise.

### 9.3 Session persistence is mandatory

Work-in-progress (`album-draft.json`) autosaves to `user://` / IndexedDB after every change — metadata only, never images, so it stays small. On reopen, restore the draft and re-acquire the source folder (silently with a File System Access handle, or one click with `webkitdirectory`). **100 authoring sessions means losing one is unacceptable.** Also offer "export draft" so the author can keep a backup outside the browser.

### 9.4 Baking with Claude

Runs in the web editor per your decision. The Anthropic API supports direct browser calls via the `anthropic-dangerous-direct-browser-access: true` header. Your key is pasted into a field and stored in IndexedDB — **never in the shipped build, never committed.** Since you're the only person who opens the editor, the exposure is to yourself. Add a "clear key" button and a plain warning next to the field.

Model: `claude-sonnet-5` for the bulk pass (~$10 per 1000 photos), `claude-opus-5` for re-baking the ones that matter (~$40–60 for a full pass). Batch ~10 photos per request to cut overhead; respect rate limits with backoff; make the batch resumable, because a 1000-photo bake will be interrupted.

**The prompt's three hard constraints** — these *are* the quality bar:

1. **The ladder must be monotonic, generated in one call per photo.** Tier 1 gives sensory detail and emotion but no place name, country, language or landmark. Tier 2 narrows to region or country. Tier 3 names the place. Generating all three together keeps them consistent; never generate them independently.
2. **Voice, not narration.** He speaks *to her*, present tense, uses her name, has opinions about the day. Not "This photograph depicts…"
3. **Never invent facts.** Only the author's description and metadata. **Hallucinated detail in a memorial gift is this project's worst failure mode** — worse than a crash. Request strict JSON, and show the source description beside every generated line so drift is visible at a glance.

**Graceful degradation:** with no key or a failed call, a local template generator produces serviceable lines from metadata alone (`"Somewhere warm. Somewhere near water."` → `"We were in {country}."` → `"{placeLabel}."`), flagged as needing a human pass. The game must never depend on the bake having happened.

---

## 10. The curator in game

### 10.1 Text bubbles carry the whole performance

No TTS, so typography does the acting. This deserves real attention:

- Worldspace bubble above him — `Label3D`, or a billboarded `SubViewport` for proper rounded corners and a tail — with a screen-space fallback for long lines.
- **Character-by-character reveal with punctuation-aware pacing**: a comma pauses, a full stop pauses longer, an ellipsis pauses much longer. This is the single highest-value detail in the dialogue system; it's what makes text *feel* spoken.
- Dismiss on input, auto-advance after a generous dwell, never time-pressured.
- Large-text mode on by default (§11); bubbles auto-size.

### 10.2 The narrative hook worth building

He's dying. Make it mechanical: as a player takes more hints in a round, his bubbles degrade — slower reveal, a repeated word, a sentence trailing off — and the room dims a notch. Tier 3 should cost something that isn't points. Small work (a timing curve, a light-energy lerp), disproportionate return on the thing the game is actually about.

---

## 11. Characters, save, accessibility

### 11.1 Voxel pipeline

Characters are authored as data — a layer-stack of coloured grids per body part — and meshed in code with greedy meshing (a 16×32×16 figure drops from ~25k tris to a few hundred). Parts are separate `MeshInstance3D`s in a hierarchy: head, torso, upper/lower arms, hands, upper/lower legs, feet. That hierarchy is both the rig and the customization slot system.

Voxel figures in a lit realistic room need help not to look pasted on: they must **receive** the baked light and **cast** real shadows, plus a contact-shadow blob at the feet. **Get one voxel figure into a lit test room at M1** — if that shot doesn't read well, you want to know before building ten room types.

### 11.2 Customization

Slots: hair, head covering, glasses, dress/top, shawl, shoes, cane, jewellery. Colour via per-instance shader uniforms (skin, hair, two garment colours) — cheap, and multiplies the options. The customization scene doubles as the pre-game menu; saves to `user://profile.json`. Third-person camera means the avatar is always on screen, which is what justifies the feature.

### 11.3 The husband as companion

`NavigationAgent3D` on the current room's nav mesh; follows with a lag and a personal-space radius, and **stops to look at photos on his own** — that idle behaviour is most of the characterisation. Head aim at the player during dialogue, at the photo otherwise. Barks from `EventBus` with a cooldown. He should sometimes reach the next frame first and wait. Small thing; makes him a person.

### 11.4 Controller

`CharacterBody3D`, spring-arm camera with collision-aware arm length, walk and slow-walk (no run — wrong tone), ease to a framing position when examining rather than cutting. `Area3D` triggers on frames with a screen prompt.

### 11.5 Save and settings

One album per load, so no library. Progress in `user://progress/<albumId>.json` — revealed photos, scores, hints taken, current room. At 1000 photos that's ~100 KB of JSON, fine. `force_fs_sync()` after writes on web. Revealed photos **stay** revealed; free-roam unlocks after the ending with every photo clear and the husband willing to talk about any of them.

### 11.6 Accessibility is load-bearing

The plausible audience includes elderly players. Large text **on by default**, high-contrast UI option, no timers anywhere, no reflex requirements, adjustable walk speed, full keyboard-only and gamepad-only paths, and a "skip the guessing" toggle that lets someone just walk the gallery and listen. That last one sounds like it undermines the game. It's the option that makes it a gift.

---

## 12. Google Photos — phase 2

The old path is gone: since 31 March 2025 the Library API no longer reads a user's existing library, and the broad read scopes were removed. The **Picker API** is the only route (single scope `photospicker.mediaitems.readonly`), and it's well-designed — the user selects inside Google's own UI.

The costs: **OAuth verification is required** (workable for a gift by staying in testing mode with your users added — capped at 100, shows an "unverified app" warning), and **token exchange needs a backend**, which breaks §1.3's serverless property — the thing you specifically wanted.

**Recommendation: phase 2, behind a `PhotoSource` interface** with `LocalFolderSource` first, so `GooglePhotosSource` slots in without touching the ingest pipeline or album format. For sixty years of photographs, a folder of scans is the better source anyway.

---

## 13. Milestones

| # | Milestone | Contents | Exit criterion |
|---|---|---|---|
| **M0** | Foundation | `git init`; **strip `[dotnet]`**; Compatibility renderer; folder structure; autoloads; platform interface; debug overlay; **web + Windows exports working, web build hosted** | Both builds run. GitHub Pages deploy green. |
| **M1** | Grey-box + style test | Procedural grey-box room, third-person controller, one code-generated voxel figure, fake light shaft, post stack, `tools/blender/` runner. **Verify `AreaLight3D` and `LightmapGI`-across-instances (§8.3).** | The style-clash screenshot reads well **in a browser**. **Go/no-go on art direction (§1.5).** |
| **M2** | **Vertical slice** | Album schema v1, **byte-range ZIP reader (§3.3)**, blur tiers, texture pipeline, streaming, frame binding, round FSM, placeholder guess input, scoring | One hand-authored 3-photo `.ccalbum` playable in a browser |
| **M2.5** | **Scale test** | Synthetic 1000-photo album; 100-room streaming; memory and load profiling | 1000-photo album opens in under 3 s and holds frame rate. **Validates §2 before anything is built on it.** |
| **M3** | Map & calendar | Natural Earth bake, vector map, zoom/pan, pin input, calendar dial, real scoring, results screen, score debug overlay | Guess place and date properly, see the breakdown |
| **M4** | Curator | Text bubbles with punctuation pacing, hint ladder + costs, barks, tier-3 degradation, template fallback | Hints purchasable, monotonic, costly; bubbles feel spoken |
| **M5** | Editor core | Folder picker, virtualised grid, batch select, metadata forms, **batch apply**, EXIF reader, map/calendar pickers, blur baking, draft persistence, validator, export | You author a real 100-photo album from a real folder |
| **M6** | Editor bake | Claude integration, batching, resumable progress, review/approve, cost estimate, template fallback | A 100-photo album fully baked and approved |
| **M7** | Characters | Voxel generator, customization slots, palettes, profile save, companion navigation and idle behaviour | Avatar customizable; husband walks believably |
| **M8** | Mansion | 10 room types, 4 dressing variants, wings, Blender AO/GI bakes, prop dressing, **download budget check** | 1000-photo album holds frame rate in a browser; `.pck` under 100 MB |
| **M9** | Narrative | Opening, inter-room beats, **the hug + fade**, player-chosen ending (§2.4), free-roam, music, ambience | The game has a beginning and an ending |
| **M10** | Polish | Settings, accessibility pass, balance tuning, bug triage, final hosting | External playtest completed and acted on |

**Ordering notes.** **M2.5 is new and non-negotiable** — validate the 1000-photo claim on synthetic data before building the editor and mansion on top of it; a synthetic album is an afternoon's script and de-risks the whole design. M3 before M4, because hints are only tunable once real scoring exists. The editor (M5/M6) splits in two because it's now the largest body of work. M5 before M8, so rooms are built against real albums.

**The ending (M9), specified:** the final room becomes accessible early with the husband waiting there. Player approaches → one `AnimationPlayer` clip on a parent node keys *both* characters' transforms into the hug (far easier than two synchronised rigs; about fifteen keyframes) → light blooms out → fade → final card → free-roam unlocks. No Blender required.

---

## 14. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| C# discovered to be a dead end late | **Critical** | Settled: GDScript. Strip `[dotnet]` at M0. |
| Whole-album copy into IndexedDB at 1000 photos | **Critical** | Byte-range reader + STOREd entries (§3.3). **This is what makes the scale claim true.** Validate at M2.5. |
| 100 rooms feel repetitive | **High** | Wings with distinct palettes and dressing (§8.2); player-chosen ending so completion isn't forced (§2.4). |
| Authoring 1000 photos never finishes | **High** | EXIF prefill, batch apply, cluster suggestions, progress dashboard, mandatory draft persistence (§9.2–9.3). Honest expectation: 80–150 photos is the sweet spot. |
| "Realistic" unreachable on WebGL 2 | **High** | Reset target (§1.5); Blender-baked AO and GI (§7.3); make unreality diegetic. Go/no-go at M1 on the *web* build. |
| Web download exceeds a playable size | **High** | `.pck` under 100 MB (a hard GitHub limit, not a preference); trim sheets as primary lever; room *types* not rooms; procedural architecture ships as code. Checked every milestone. |
| Claude produces a non-monotonic or hallucinated ladder | **High** | Three tiers in one call with per-tier constraints; source description shown beside every line; per-photo approval gates export. |
| `LightmapGI` doesn't instance cleanly across 100 rooms | Medium | Test at M1. Fallback — Blender-baked GI into room-type textures — is instance-safe by construction and changes nothing downstream (§8.3). |
| Album schema churn breaks existing albums | Medium | `schemaVersion` + migration hook from day one; validator reports all problems; never remove a field, only deprecate. |
| Voxel figures look pasted in | Medium | Resolve at M1 with a lit test shot: shadow casting, contact shadows, shared light response. |
| Browser file-picker inconsistency | Medium | `webkitdirectory` + lazy handles as the base path (all four major browsers); File System Access API as enhancement; test Chrome, Firefox, Safari at M5. |
| API key in browser IndexedDB | Medium | Editor-only, never in the shipped build, never committed; clear-key button; you are the only user (§9.4). |
| Claude bake cost surprises | Low | Cost estimate shown before every batch; Sonnet for bulk, Opus for spot re-bakes. |
| Scoring feels arbitrary | Medium | Constants in manifest; live debug overlay; tune against a real album with a real player at M3. |
| Emotional subject matter mishandled | Medium | No fail states, no timers, no "game over." He never says anything you didn't approve. Free-roam after the ending. |

---

## 15. Immediate next steps

1. `git init` and commit current state (the repo isn't under version control yet).
2. **Remove the `[dotnet]` block from `project.godot`**; set `rendering/renderer/rendering_method` to `gl_compatibility`. Before writing any script.
3. Get **both** exports working and the web build live on GitHub Pages at M0. Export problems found now are an afternoon; found at M10 they're a crisis.
4. Write `src/album/` — schema, **byte-range ZIP reader**, validator — plus a hand-written 3-photo test album. **Before any 3D work.**
5. Write the M2.5 synthetic album generator early (a script that emits a valid 1000-photo `.ccalbum` from placeholder images). Cheap to build, and it's the thing that proves the architecture.
6. Build the M1 grey-box, look at it in a browser, make the art-direction call.

---

## 16. Remaining questions

Only two, and neither blocks M0–M2.

1. **Are you happy with the player-chosen ending (§2.4)?** With 1000 photos, gating the hug on completion puts it 20+ hours away, and anyone who plays 80 photos over a few evenings never sees it. Making the final room accessible early — the husband waiting whenever she's ready — means the album becomes a place to visit rather than a completion task. It's a real change to the emotional shape of the thing, so it's your call, not mine.
2. **How many photos will the first real album actually have?** Not a constraint — the format supports 1000 either way — but it decides how many room types and wings M8 needs to build, and whether the editor's batch tooling is the critical path or a convenience.

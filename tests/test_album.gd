extends RefCounted
## Album schema, validator, image pipeline and the full pack/load round trip.
## This is the keystone of the project, so it gets the most coverage.

static func run() -> TestFramework:
	var t := TestFramework.new("album")

	_test_schema_roundtrip(t)
	_test_validator(t)
	_test_image_pipeline(t)
	_test_pack_and_load(t)
	_test_hint_fallback(t)
	_test_guess_year_range(t)
	_test_dial_defaults(t)
	_test_hostile_manifests(t)
	_test_filenames(t)

	return t


# ---------------------------------------------------------------- schema

static func _test_schema_roundtrip(t: TestFramework) -> void:
	var album := AlbumSchema.Album.create_empty("Margaret & Tom")
	album.author_note = "For Mum."
	album.curator_voice_name = "Tom"
	album.curator_player_name = "Maggie"
	album.curator_style = "warm, a little wry"
	album.scoring.distance_half_life_km = 180.0

	var p := AlbumSchema.Photo.new()
	p.id = "p_001"
	p.aspect = 1.5
	p.full_path = "photos/p_001/full.webp"
	p.blur_paths = PackedStringArray(AlbumSchema.Photo.default_paths("p_001")["blurTiers"])
	p.thumb_path = "photos/p_001/thumb.webp"
	p.truth.lat = 43.7696
	p.truth.lon = 11.2558
	p.truth.place_label = "Florence, Italy"
	p.truth.country_code = "IT"
	p.truth.date.year = 1978
	p.truth.date.month = 6
	p.truth.date_precision = AlbumSchema.DatePrecision.MONTH
	p.content.description = "The bridge with the shops on it."
	p.content.private_note = "do not show"
	p.content.people = PackedStringArray(["Margaret", "Tom"])
	p.curator.hints = PackedStringArray(["Warm stone.", "We were in Italy.", "Florence, love."])
	p.curator.reveal_monologue = "June of '78."
	p.curator.approved_by_author = true
	album.photos.append(p)
	album.hang_order = PackedStringArray(["p_001"])

	# Serialise -> JSON text -> parse -> deserialise, so we exercise the real
	# path rather than passing a Dictionary straight back in.
	var text := JSON.stringify(album.to_dict())
	var reparsed: Variant = JSON.parse_string(text)
	t.eq(typeof(reparsed), TYPE_DICTIONARY, "manifest serialises to valid JSON")

	var back := AlbumSchema.Album.from_dict(reparsed)
	t.eq(back.title, "Margaret & Tom", "title survives round trip")
	t.eq(back.album_id, album.album_id, "album id survives round trip")
	t.eq(back.curator_player_name, "Maggie", "player name survives round trip")
	t.close(back.scoring.distance_half_life_km, 180.0, 0.001,
		"scoring config survives round trip")
	t.eq(back.photos.size(), 1, "photo count survives round trip")

	var bp := back.photos[0]
	t.eq(bp.id, "p_001", "photo id survives")
	t.close(bp.truth.lat, 43.7696, 0.00001, "latitude survives at full precision")
	t.close(bp.truth.lon, 11.2558, 0.00001, "longitude survives at full precision")
	t.eq(bp.truth.date.year, 1978, "year survives")
	t.eq(bp.truth.date.month, 6, "month survives")
	t.eq(bp.truth.date_precision, AlbumSchema.DatePrecision.MONTH,
		"date precision survives as an enum")
	t.eq(bp.content.people.size(), 2, "people list survives")
	t.eq(bp.curator.hints.size(), 3, "three hint tiers survive")
	t.eq(bp.curator.hints[2], "Florence, love.", "hint text survives")
	t.ok(bp.curator.approved_by_author, "approval flag survives")
	t.eq(bp.blur_paths.size(), AlbumSchema.BLUR_TIER_COUNT, "blur tier paths survive")

	# A null month must not come back as a spurious 0-vs-null mismatch.
	var year_only := AlbumSchema.PhotoDate.new()
	year_only.year = 1961
	var yo := AlbumSchema.PhotoDate.from_dict(year_only.to_dict())
	t.eq(yo.year, 1961, "year-only date survives")
	t.eq(yo.month, 0, "absent month round-trips as 0")
	t.eq(yo.label(), "1961", "year-only date labels as just the year")

	# An empty manifest must produce a usable (if invalid) object, never a crash.
	var empty := AlbumSchema.Album.from_dict({})
	t.ok(empty != null, "empty dict yields an object")
	t.eq(empty.photos.size(), 0, "empty dict yields no photos")

	# --- hang order ---
	var hang := _album_with_photos(3)
	hang.hang_order = PackedStringArray(["p_003", "p_001"])
	var hung := hang.hung_photos()
	t.eq(hung.size(), 3, "every photo is hung even if the order omits it")
	t.eq(hung[0].id, "p_003", "hang order is respected first")
	t.eq(hung[1].id, "p_001", "hang order is respected second")
	t.eq(hung[2].id, "p_002", "omitted photos are appended")

	var no_order := _album_with_photos(3)
	t.eq(no_order.hung_photos()[0].id, "p_001",
		"with no hang order, declaration order is used")

	# --- date precision names ---
	for name in ["day", "month", "year", "decade"]:
		var e := AlbumSchema.precision_from_string(name)
		t.eq(AlbumSchema.precision_to_string(e), name,
			"precision '%s' round-trips" % name)
	t.eq(AlbumSchema.precision_from_string("nonsense"),
		AlbumSchema.DatePrecision.YEAR, "unknown precision falls back to year")


# -------------------------------------------------------------- validator

static func _test_validator(t: TestFramework) -> void:
	var good := _album_with_photos(10)
	var problems := AlbumValidator.validate(good, false)
	t.ok(not AlbumValidator.has_errors(problems),
		"a well-formed album has no errors\n%s" % AlbumValidator.format_all(problems))

	# Export is stricter than load: it demands exactly ten approved photos.
	var export_problems := AlbumValidator.validate(good, true)
	t.ok(not AlbumValidator.has_errors(export_problems),
		"a well-formed album passes export validation\n%s"
		% AlbumValidator.format_all(export_problems))

	var nine := _album_with_photos(9)
	t.ok(not AlbumValidator.has_errors(AlbumValidator.validate(nine, false)),
		"nine photos is fine for loading")
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(nine, true)),
		"nine photos is an error on export — an album is exactly ten")

	# Missing answers are hard errors: there is nothing to guess.
	var no_lat := _album_with_photos(1)
	no_lat.photos[0].truth.lat = NAN
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(no_lat, false)),
		"a photo with no latitude is an error")

	var no_year := _album_with_photos(1)
	no_year.photos[0].truth.date.year = 0
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(no_year, false)),
		"a photo with no year is an error")

	# Precision that promises more than the data holds.
	var month_promised := _album_with_photos(1)
	month_promised.photos[0].truth.date_precision = AlbumSchema.DatePrecision.MONTH
	month_promised.photos[0].truth.date.month = 0
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(month_promised, false)),
		"month precision with no month is an error")

	# The hint ladder must not leak the answer at tier 1. With ten rounds one
	# spoiled hint is 10% of the game, so this is an error, not a warning.
	var leaky := _album_with_photos(1)
	leaky.photos[0].curator.hints = PackedStringArray([
		"We had a lovely time in Florence.", "Italy.", "Florence."])
	var leak_problems := AlbumValidator.validate(leaky, false)
	t.ok(AlbumValidator.has_errors(leak_problems),
		"tier 1 naming the place is an error")

	var clean_ladder := _album_with_photos(1)
	t.ok(not AlbumValidator.has_errors(AlbumValidator.validate(clean_ladder, false)),
		"a ladder that does not leak passes")

	# Duplicates and dangling references.
	var dupe := _album_with_photos(2)
	dupe.photos[1].id = dupe.photos[0].id
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(dupe, false)),
		"duplicate photo ids are an error")

	var bad_hang := _album_with_photos(2)
	bad_hang.hang_order = PackedStringArray(["p_001", "p_999"])
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(bad_hang, false)),
		"a hang order referencing an unknown photo is an error")

	var twice_hung := _album_with_photos(2)
	twice_hung.hang_order = PackedStringArray(["p_001", "p_001", "p_002"])
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(twice_hung, false)),
		"hanging the same photo twice is an error")

	# A future schema version must be refused with a clear message rather than
	# half-loaded.
	var future := _album_with_photos(1)
	future.schema_version = AlbumSchema.SCHEMA_VERSION + 5
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(future, false)),
		"an album from a newer build is an error")

	# Scoring config that would let a fully-assisted correct guess score zero.
	var cruel := _album_with_photos(1)
	cruel.scoring.max_spent_fraction = 1.0
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(cruel, false)),
		"maxSpentFraction of 1.0 is an error")

	# Unapproved AI text blocks export but not play, so a test album still runs.
	var unapproved := _album_with_photos(10)
	for p in unapproved.photos:
		p.curator.approved_by_author = false
	t.ok(not AlbumValidator.has_errors(AlbumValidator.validate(unapproved, false)),
		"unapproved lines still load")
	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(unapproved, true)),
		"unapproved lines block export")

	# Warnings must not be errors.
	var no_desc := _album_with_photos(1)
	no_desc.photos[0].content.description = ""
	var wp := AlbumValidator.validate(no_desc, false)
	t.ok(not AlbumValidator.has_errors(wp), "an empty description is only a warning")
	t.gt(float(AlbumValidator.count_of(wp, AlbumValidator.Severity.WARNING)), 0.0,
		"an empty description does produce a warning")

	t.ok(AlbumValidator.has_errors(AlbumValidator.validate(null, false)),
		"a null album is an error rather than a crash")


# --------------------------------------------------------- image pipeline

static func _test_image_pipeline(t: TestFramework) -> void:
	# A landscape source, larger than the full-res target so it gets scaled.
	var src := _test_image(2400, 1600)
	var png := src.save_png_to_buffer()
	t.ok(not png.is_empty(), "test image encodes to PNG")

	var proc := ImagePipeline.process(png, "test.png", "p_001")
	t.ok(proc.ok, "pipeline processes a PNG source (%s)" % proc.error)
	t.close(proc.aspect, 1.5, 0.01, "aspect is computed from the source")
	t.eq(proc.source_width, 2400, "source width recorded")
	t.eq(proc.source_height, 1600, "source height recorded")

	var paths := AlbumSchema.Photo.default_paths("p_001")
	t.ok(proc.assets.has(paths["full"]), "full-resolution asset produced")
	t.ok(proc.assets.has(paths["thumb"]), "thumbnail produced")
	for i in AlbumSchema.BLUR_TIER_COUNT:
		t.ok(proc.assets.has(paths["blurTiers"][i]), "blur tier %d produced" % i)

	# The blur ladder must be strictly increasing in size, because the whole
	# design rests on tier 0 being tiny (plan §4).
	var prev_size := 0
	for i in AlbumSchema.BLUR_TIER_COUNT:
		var bytes: PackedByteArray = proc.assets[paths["blurTiers"][i]]
		t.gt(float(bytes.size()), float(prev_size), "tier %d is larger than tier %d"
			% [i, i - 1])
		prev_size = bytes.size()

	var tier0: PackedByteArray = proc.assets[paths["blurTiers"][0]]
	t.lt(float(tier0.size()), 8000.0,
		"tier 0 is under 8 KB (it is 64 px; the frame does the blurring)")

	var full: PackedByteArray = proc.assets[paths["full"]]
	t.lt(float(full.size()), 900000.0, "full-resolution image is under 900 KB")
	t.gt(float(full.size()), float(prev_size), "full-resolution is the largest asset")

	# Decoded tier dimensions must match the declared ladder.
	for i in AlbumSchema.BLUR_TIER_COUNT:
		var img := ImagePipeline.decode(proc.assets[paths["blurTiers"][i]])
		t.ok(img != null, "tier %d decodes" % i)
		if img != null:
			t.eq(maxi(img.get_width(), img.get_height()),
				ImagePipeline.TIER_LONG_EDGES[i],
				"tier %d long edge is %d px" % [i, ImagePipeline.TIER_LONG_EDGES[i]])
			t.close(float(img.get_width()) / float(img.get_height()), 1.5, 0.05,
				"tier %d preserves aspect" % i)

	var full_img := ImagePipeline.decode(full)
	t.eq(maxi(full_img.get_width(), full_img.get_height()),
		ImagePipeline.FULL_LONG_EDGE, "full-resolution long edge is 2048 px")

	# --- portrait orientation ---
	var portrait := ImagePipeline.process(
		_test_image(1200, 1800).save_png_to_buffer(), "p.png", "p_002")
	t.ok(portrait.ok, "pipeline handles a portrait source")
	t.close(portrait.aspect, 1200.0 / 1800.0, 0.01, "portrait aspect is below 1")

	# --- a small scan must not be upscaled into mush ---
	var small := ImagePipeline.process(
		_test_image(300, 200).save_png_to_buffer(), "s.png", "p_003")
	t.ok(small.ok, "pipeline handles a small source")
	var small_full := ImagePipeline.decode(
		small.assets[AlbumSchema.Photo.default_paths("p_003")["full"]])
	t.eq(small_full.get_width(), 300, "a 300 px scan stays 300 px, never upscaled")

	# --- JPEG source, and format sniffing when the extension lies ---
	var jpg := _test_image(1000, 1000).save_jpg_to_buffer(0.9)
	t.ok(ImagePipeline.process(jpg, "square.jpg", "p_004").ok,
		"pipeline processes a JPEG source")
	t.ok(ImagePipeline.decode(png, "lying.jpg") != null,
		"a PNG named .jpg is still decoded (sniffed by content)")
	t.ok(ImagePipeline.decode(jpg, "lying.png") != null,
		"a JPEG named .png is still decoded")

	# --- failure paths return an error rather than crashing ---
	var empty := ImagePipeline.process(PackedByteArray(), "x.png", "p_005")
	t.ok(not empty.ok, "an empty file fails cleanly")
	t.ok(not empty.error.is_empty(), "an empty file explains why")
	var garbage := ImagePipeline.process(
		PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]), "x.png", "p_006")
	t.ok(not garbage.ok, "garbage bytes fail cleanly")
	t.ok(ImagePipeline.decode(PackedByteArray([1, 2, 3])) == null,
		"decode returns null for garbage")

	# --- EXIF findings are surfaced for the editor to prefill with ---
	# A rotated source (orientation 6) must come back with swapped dimensions.
	var oriented := ImagePipeline.process(
		_jpeg_with_orientation(_test_image(1200, 800), 6), "r.jpg", "p_007")
	t.ok(oriented.ok, "pipeline handles an orientation-tagged JPEG")
	t.close(oriented.aspect, 800.0 / 1200.0, 0.02,
		"orientation 6 is applied, so a landscape source becomes portrait")


# ------------------------------------------------------ pack / load cycle

static func _test_pack_and_load(t: TestFramework) -> void:
	var album := AlbumSchema.Album.create_empty("Round Trip")
	album.curator_player_name = "Maggie"
	album.curator_voice_name = "Tom"

	var assets := {}
	var order: PackedStringArray = PackedStringArray()

	for i in AlbumSchema.PHOTOS_PER_ALBUM:
		var pid := "p_%03d" % (i + 1)
		# The first photo is deliberately larger than the 2048 px target so the
		# archive round trip covers a downscaled image; the rest stay small to
		# keep the WebP encoding in this suite quick.
		var w := 2400 if i == 0 else 1200 + i * 10
		var h := 1600 if i == 0 else 800
		var proc := ImagePipeline.process(
			_test_image(w, h).save_png_to_buffer(), "%s.png" % pid, pid)
		if not proc.ok:
			t.ok(false, "pipeline failed for %s: %s" % [pid, proc.error])
			continue

		var photo := _make_photo(pid, i)
		photo.aspect = proc.aspect
		album.photos.append(photo)
		order.append(pid)
		assets.merge(proc.assets)

	album.hang_order = order
	album.cover_photo_id = "p_001"

	var bytes := AlbumIO.pack(album, assets)
	t.ok(not bytes.is_empty(), "album packs to bytes")

	# The whole point of a ten-photo album is that it attaches to an email.
	t.lt(float(bytes.size()), 12_000_000.0,
		"a ten-photo album is under 12 MB (%.1f MB)" % (bytes.size() / 1048576.0))

	# A ZIP starts with "PK\x03\x04".
	t.ok(bytes.size() > 4 and bytes[0] == 0x50 and bytes[1] == 0x4B,
		"packed album is a ZIP archive")

	var loaded := AlbumIO.load_from_bytes(bytes)
	t.ok(loaded.is_ok(), "packed album loads back\n%s"
		% AlbumValidator.format_all(loaded.problems))

	if loaded.album != null:
		t.eq(loaded.album.title, "Round Trip", "title survives the archive")
		t.eq(loaded.album.photos.size(), AlbumSchema.PHOTOS_PER_ALBUM,
			"all ten photos survive the archive")
		t.eq(loaded.album.curator_player_name, "Maggie",
			"curator config survives the archive")
		t.eq(loaded.album.hung_photos().size(), AlbumSchema.PHOTOS_PER_ALBUM,
			"hang order resolves to ten photos")

		var first := loaded.album.photos[0]
		t.close(first.truth.lat, 43.7696, 0.00001, "latitude survives the archive")
		t.eq(first.truth.date.year, 1978, "year survives the archive")

		# Assets must be readable and must decode.
		for tier in first.blur_paths.size():
			var raw := loaded.read_asset(first.blur_paths[tier])
			t.ok(not raw.is_empty(), "tier %d asset reads from the archive" % tier)
			t.ok(ImagePipeline.decode(raw) != null,
				"tier %d asset decodes from the archive" % tier)

		var full_raw := loaded.read_asset(first.full_path)
		t.ok(not full_raw.is_empty(), "full-resolution asset reads from the archive")
		var full_img := ImagePipeline.decode(full_raw)
		t.ok(full_img != null, "full-resolution asset decodes")
		if full_img != null:
			t.eq(maxi(full_img.get_width(), full_img.get_height()),
				ImagePipeline.FULL_LONG_EDGE,
				"archived full-resolution image is downscaled to 2048 px")

		t.ok(not loaded.has_asset("photos/nope/full.webp"),
			"a missing asset reports as missing")
		t.ok(loaded.read_asset("photos/nope/full.webp").is_empty(),
			"reading a missing asset returns empty rather than crashing")

	loaded.close()

	# --- a manifest that promises an asset the archive does not contain ---
	var liar := AlbumSchema.Album.create_empty("Liar")
	liar.photos.append(_make_photo("p_001", 0))
	liar.hang_order = PackedStringArray(["p_001"])
	var liar_bytes := AlbumIO.pack(liar, {})   # manifest only, no images
	var liar_loaded := AlbumIO.load_from_bytes(liar_bytes)
	t.ok(not liar_loaded.is_ok(),
		"a manifest referencing missing assets fails to load")
	liar_loaded.close()

	# --- hostile input ---
	t.ok(not AlbumIO.load_from_bytes(PackedByteArray()).is_ok(),
		"empty bytes fail to load")
	t.ok(not AlbumIO.load_from_bytes(
		PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])).is_ok(),
		"garbage bytes fail to load")

	# A valid ZIP that is not an album.
	var not_album := AlbumIO.pack(AlbumSchema.Album.create_empty("x"), {})
	var na := AlbumIO.load_from_bytes(not_album)
	t.ok(not na.is_ok(), "a ZIP with no photos fails to load")
	na.close()

	# --- filename suggestion must be safe to email ---
	var named := AlbumSchema.Album.create_empty("Margaret & Tom: 1961/2024")
	var fname := AlbumIO.suggested_filename(named)
	t.ok(fname.ends_with(".ccalbum"), "suggested filename has the right extension")
	t.ok(not fname.contains("/"), "suggested filename has no path separators")
	t.ok(not fname.contains(":"), "suggested filename has no colons")


# ------------------------------------------------------------- fallbacks

static func _test_hint_fallback(t: TestFramework) -> void:
	# A half-baked album must still be playable: missing hints fall back down
	# the ladder, and an empty ladder falls back to the place label.
	var c := AlbumSchema.CuratorLines.new()
	c.hints = PackedStringArray(["Warm stone.", "", ""])
	t.eq(c.hint_for_tier(1, "Florence"), "Warm stone.", "tier 1 uses its own text")
	t.eq(c.hint_for_tier(2, "Florence"), "Warm stone.",
		"an empty tier 2 falls back to tier 1")
	t.eq(c.hint_for_tier(3, "Florence"), "Warm stone.",
		"an empty tier 3 falls back down the ladder")

	var none := AlbumSchema.CuratorLines.new()
	t.eq(none.hint_for_tier(1, "Florence, Italy"), "Florence, Italy",
		"with no hints at all, the place label is the fallback")
	t.eq(none.hint_for_tier(3, "Florence, Italy"), "Florence, Italy",
		"the fallback works at every tier")

	# --- ScoringConfig hint costs out of range ---
	var cfg := AlbumSchema.ScoringConfig.new()
	t.close(cfg.hint_cost(1), 0.10, 0.0001, "hint tier 1 cost")
	t.close(cfg.hint_cost(3), 0.35, 0.0001, "hint tier 3 cost")
	t.close(cfg.hint_cost(0), 0.0, 0.0001, "tier 0 costs nothing")
	t.close(cfg.hint_cost(99), 0.0, 0.0001, "an out-of-range tier costs nothing")


# ------------------------------------------------------------- utilities

static func _album_with_photos(n: int) -> AlbumSchema.Album:
	var a := AlbumSchema.Album.create_empty("Test Album")
	a.curator_voice_name = "Tom"
	a.curator_player_name = "Maggie"
	var order: PackedStringArray = PackedStringArray()
	for i in n:
		var pid := "p_%03d" % (i + 1)
		a.photos.append(_make_photo(pid, i))
		order.append(pid)
	a.hang_order = order
	a.cover_photo_id = "p_001"
	return a


static func _make_photo(pid: String, index: int) -> AlbumSchema.Photo:
	var p := AlbumSchema.Photo.new()
	p.id = pid
	p.aspect = 1.5
	var paths := AlbumSchema.Photo.default_paths(pid)
	p.full_path = paths["full"]
	p.blur_paths = PackedStringArray(paths["blurTiers"])
	p.thumb_path = paths["thumb"]
	p.truth.lat = 43.7696
	p.truth.lon = 11.2558
	p.truth.place_label = "Florence, Italy"
	p.truth.country_code = "IT"
	p.truth.location_precision_km = 5.0
	p.truth.date.year = 1978
	p.truth.date.month = 6
	p.truth.date_precision = AlbumSchema.DatePrecision.MONTH
	p.content.title = "Photo %d" % (index + 1)
	p.content.description = "Something that happened, described by the author."
	# Deliberately does not name the city at tier 1 — the validator checks this.
	p.curator.hints = PackedStringArray([
		"Warm stone, and you complained about the heat all week.",
		"We were somewhere in Italy that summer.",
		"The bridge with the little shops on it, love.",
	])
	p.curator.reveal_monologue = "June of that year. You wore the green dress."
	p.curator.idle_barks = PackedStringArray(["You always liked this one."])
	p.curator.approved_by_author = true
	return p


## Stand-in for a photograph.
##
## Generated with FastNoiseLite rather than a set_pixel loop: a multi-megapixel
## GDScript loop takes minutes, while Noise.get_image() runs in native code.
## Fractal noise is also the right *kind* of content for these tests — it has
## detail at several scales, like a real photo, so the blur tiers compress the
## way a photograph's would. A flat colour or a smooth gradient would compress
## to almost nothing and make the size assertions meaningless.
static func _test_image(w: int, h: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 20260916
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.frequency = 0.012

	var img := noise.get_image(w, h)
	img.convert(Image.FORMAT_RGB8)
	return img


## Wrap a JPEG in a minimal EXIF block carrying only an orientation tag.
static func _jpeg_with_orientation(img: Image, orientation: int) -> PackedByteArray:
	var jpg := img.save_jpg_to_buffer(0.92)

	var sp := StreamPeerBuffer.new()
	sp.big_endian = false
	sp.put_u8(0x49); sp.put_u8(0x49)
	sp.put_u16(42)
	sp.put_u32(8)
	sp.put_u16(1)
	sp.put_u16(ExifReader.TAG_ORIENTATION)
	sp.put_u16(ExifReader.T_SHORT)
	sp.put_u32(1)
	sp.put_u16(orientation)
	sp.put_u16(0)
	sp.put_u32(0)
	var tiff := sp.data_array

	var out := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1])
	var seg_len := 2 + 6 + tiff.size()
	out.append((seg_len >> 8) & 0xFF)
	out.append(seg_len & 0xFF)
	out.append_array("Exif".to_ascii_buffer())
	out.append(0x00); out.append(0x00)
	out.append_array(tiff)
	# Append the original JPEG minus its own SOI marker.
	out.append_array(jpg.slice(2))
	return out


## The calendar dial's ends. Plan §7.3: the author may set them, and when they
## do not, the album pads its own range — because a dial whose ends are the
## earliest and latest photographs hands her two of the ten answers.
static func _test_guess_year_range(t: TestFramework) -> void:
	var album := AlbumSchema.Album.create_empty("Dial")
	for year in [1961, 1974, 2003]:
		var photo := AlbumSchema.Photo.new()
		photo.id = "p_%d" % year
		photo.truth.date.year = year
		album.photos.append(photo)

	var auto := album.guess_year_range()
	t.lt(float(auto.x), 1961.0, "the dial starts before the earliest photograph")
	t.gt(float(auto.y), 2003.0, "and ends after the latest")
	t.gt(float(auto.x), 1900.0, "but not absurdly early (%d)" % auto.x)
	t.lt(float(auto.y), 2050.0, "or absurdly late (%d)" % auto.y)

	# The author's own ends win.
	album.guess_year_min = 1940
	album.guess_year_max = 2010
	var explicit := album.guess_year_range()
	t.eq(explicit.x, 1940, "an author's own start is used as given")
	t.eq(explicit.y, 2010, "and their own end")

	# One end set, one left to the photographs.
	album.guess_year_max = 0
	var half := album.guess_year_range()
	t.eq(half.x, 1940, "a start on its own is still honoured")
	t.gt(float(half.y), 2003.0, "and the end is worked out")

	# Nonsense is corrected rather than obeyed.
	album.guess_year_min = 2000
	album.guess_year_max = 1900
	var swapped := album.guess_year_range()
	t.gt(float(swapped.y), float(swapped.x), "an inverted range is fixed")
	album.guess_year_min = 1200
	album.guess_year_max = 3000
	var clamped := album.guess_year_range()
	t.gt(float(clamped.x), 1825.0, "a start before photography is clamped")
	t.lt(float(clamped.y), 2101.0, "and an end past the plausible")

	# An album with no dates at all still gives a usable dial.
	var undated := AlbumSchema.Album.create_empty("Undated")
	var blank := AlbumSchema.Photo.new()
	blank.id = "p_blank"
	undated.photos.append(blank)
	var fallback := undated.guess_year_range()
	t.gt(float(fallback.y), float(fallback.x) + 20.0,
		"an undated album still spans a lifetime (%d..%d)"
			% [fallback.x, fallback.y])

	# And it survives a save and load, like every other field.
	album.guess_year_min = 1955
	album.guess_year_max = 2015
	var back := AlbumSchema.Album.from_dict(album.to_dict())
	t.eq(back.guess_year_min, 1955, "the dial's start round-trips")
	t.eq(back.guess_year_max, 2015, "and its end")
	var bare := AlbumSchema.Album.from_dict({"schemaVersion": 1})
	t.eq(bare.guess_year_min, 0, "a manifest without them defaults to auto")

## The dial's ends when nobody has set them, which is the common case — and the
## specific failure that prompted this: a zip of scanned prints carries the day
## each print was SCANNED, so ten photographs of a 1970s holiday arrive stamped
## with this year and used to hand her a dial running to 2040, three quarters
## of it in the future.
static func _test_dial_defaults(t: TestFramework) -> void:
	var this_year := AlbumSchema.current_year()
	t.gt(float(this_year), 2024.0, "the calendar knows what year it is (%d)"
		% this_year)

	# Nothing dated at all: their lifetime, ending now.
	var undated := AlbumSchema.Album.create_empty("Undated")
	for i in 3:
		var blank := AlbumSchema.Photo.new()
		blank.id = "p_%d" % i
		undated.photos.append(blank)
	var span := undated.guess_year_range()
	t.lt(float(span.x), 1990.0, "an undated album starts early enough (%d)"
		% span.x)
	t.lt(float(span.y), float(this_year) + 1.0,
		"and does not end in the future (%d)" % span.y)
	t.gt(float(span.y), float(this_year) - 12.0,
		"but does come up to about now")

	# Every photograph stamped with this year — the scanned-folder case.
	var scans := AlbumSchema.Album.create_empty("Scans")
	for i in 4:
		var photo := AlbumSchema.Photo.new()
		photo.id = "s_%d" % i
		photo.truth.date.year = this_year
		scans.photos.append(photo)
	var scanned := scans.guess_year_range()
	t.lt(float(scanned.y), float(this_year) + 1.0,
		"a folder of scans does not push the dial into the future (%d)"
			% scanned.y)
	t.gt(float(scanned.y - scanned.x), float(AlbumSchema.DIAL_MIN_SPAN) - 1.0,
		"and it is still a dial you could lose on (%d..%d)"
			% [scanned.x, scanned.y])

	# One recent photograph among old ones must not drag the end forward
	# either, but it must still be reachable.
	var mixed := AlbumSchema.Album.create_empty("Mixed")
	for year in [1961, 1974, this_year]:
		var photo := AlbumSchema.Photo.new()
		photo.id = "m_%d" % year
		photo.truth.date.year = year
		mixed.photos.append(photo)
	var either := mixed.guess_year_range()
	t.lt(float(either.y), float(this_year) + 1.0,
		"the end stops at this year (%d)" % either.y)
	t.ok(either.y >= this_year, "and still reaches the newest photograph")
	t.lt(float(either.x), 1961.0, "while starting before the oldest")

	# An author who names an end means it, even when the other end is worked
	# out and the span comes out narrow.
	var mine := AlbumSchema.Album.create_empty("Mine")
	var one := AlbumSchema.Photo.new()
	one.id = "o_1"
	one.truth.date.year = this_year
	mine.photos.append(one)
	mine.guess_year_min = this_year - 4
	var narrow := mine.guess_year_range()
	t.eq(narrow.x, this_year - 4, "my own start is left exactly where I put it")
	t.gt(float(narrow.y - narrow.x), 3.0, "and the other end is widened instead")

	# Both ends mine: obeyed as given, however odd, short of nonsense.
	mine.guess_year_min = 1990
	mine.guess_year_max = 1995
	var both := mine.guess_year_range()
	t.eq(both.x, 1990, "both ends of my own dial are mine")
	t.eq(both.y, 1995, "even a five-year one")

	t.eq(AlbumSchema.DIAL_DEFAULT_MIN, 1980,
		"and the default start is the one the brief asked for")

## A manifest that is valid JSON but hostile in shape. from_dict() promises to
## be permissive and never throw, and the editor's whole error display depends
## on that promise: it wants a LIST of problems, not an engine error halfway
## through parsing.
##
## The hole was JSON nulls. `Dictionary.get(key, {})` returns the stored null
## when the key exists, so `"truth": null` — which any exporter that writes
## nulls for empty objects produces — handed Nil to a Dictionary-typed
## variable, and the load died instead of being reported.
static func _test_hostile_manifests(t: TestFramework) -> void:
	var nulls := {
		"schemaVersion": 1,
		"title": "Nulls",
		"curator": null,
		"guessing": null,
		"scoring": null,
		"hangOrder": null,
		"photos": [
			{
				"id": "p_001",
				"truth": null,
				"content": null,
				"curator": null,
				"files": null,
			},
			{
				"id": "p_002",
				"truth": {"date": null, "admin": null, "lat": null, "lon": null},
				"content": {"people": null, "tags": null},
				"curator": {"hints": null, "bake": null},
				"files": {"blurTiers": null},
			},
		],
	}

	var album := AlbumSchema.Album.from_dict(nulls)
	t.ok(album != null, "a manifest full of nulls still loads")
	t.eq(album.title, "Nulls", "and keeps what it does say")
	t.eq(album.photos.size(), 2, "with both photographs")

	for i in album.photos.size():
		var photo := album.photos[i]
		t.ok(photo != null, "photograph %d is a real object" % i)
		if photo == null:
			continue
		t.ok(photo.truth != null, "photograph %d has a truth block" % i)
		t.ok(photo.content != null, "and a content block")
		t.ok(photo.curator != null, "and a curator block")
		t.ok(not photo.truth.date.is_set(), "with no date, rather than a wrong one")
		t.ok(not photo.truth.has_location(), "and no location")
		t.eq(photo.blur_paths.size(), 0, "and no blur tiers")

	# Which the validator can then report on, which is the whole point.
	var problems := AlbumValidator.validate(album, true)
	t.gt(float(problems.size()), 0.0,
		"and the validator has plenty to say about it (%d problems)"
			% problems.size())

	# An empty hint-cost list is not an instruction to make hints free: the
	# tier that names the answer outright used to cost nothing.
	var free_hints := AlbumSchema.Album.from_dict({
		"schemaVersion": 1,
		"scoring": {"hintCosts": []},
	})
	t.gt(free_hints.scoring.hint_costs.size(), 0,
		"an empty hint-cost list falls back to the defaults")
	t.gt(free_hints.scoring.hint_cost(3), 0.0, "so the last hint still costs")

	# And the whole thing, with nothing in it at all.
	var bare := AlbumSchema.Album.from_dict({})
	t.ok(bare != null, "an empty dictionary loads")
	t.eq(bare.photos.size(), 0, "with no photographs")


## The suggested filename. It has to survive a title with digits in it, which
## no other test in this file has.
static func _test_filenames(t: TestFramework) -> void:
	var album := AlbumSchema.Album.create_empty("Trip 2019")
	t.eq(AlbumIO.suggested_filename(album), "Trip_2019.ccalbum",
		"digits survive (got %s)" % AlbumIO.suggested_filename(album))

	album.title = "For Maggie"
	t.eq(AlbumIO.suggested_filename(album), "For_Maggie.ccalbum",
		"spaces become underscores")

	album.title = "Mum & Dad / 1961-2003"
	var safe := AlbumIO.suggested_filename(album)
	t.ok(safe.ends_with(".ccalbum"), "the extension is right (%s)" % safe)
	t.ok(not safe.contains("/"), "and nothing that breaks a path survives")
	t.ok(safe.contains("1961"), "while the years do")

	album.title = ""
	t.eq(AlbumIO.suggested_filename(album), "album.ccalbum",
		"a nameless album still gets a filename")

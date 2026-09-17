extends RefCounted
## The editor, from a folder of images to a loadable .ccalbum.
##
## The screen is UI wiring; the part worth testing is EditorSession, which does
## no IO. So this suite builds ten real JPEGs in memory, feeds them in as if
## picked from a folder, fills in what an author would type, exports, and then
## loads the result back through AlbumIO — the same path the game uses. If that
## round trip holds, the editor's job is done.
##
## One of the ten carries EXIF (a date and a pair of coordinates) so the
## prefill is covered too.

const PLACES := [
	[43.7696, 11.2558, "Florence, Italy"],
	[54.4858, -0.6206, "Whitby, England"],
	[64.1466, -21.9426, "Reykjavik, Iceland"],
	[35.0116, 135.7681, "Kyoto, Japan"],
	[38.7223, -9.1393, "Lisbon, Portugal"],
	[51.1784, -115.5708, "Banff, Canada"],
	[31.6295, -7.9811, "Marrakesh, Morocco"],
	[55.9533, -3.1883, "Edinburgh, Scotland"],
	[36.3932, 25.4615, "Santorini, Greece"],
	[54.4300, -2.9615, "Ambleside, England"],
]


func run() -> TestFramework:
	var t := TestFramework.new("editor")

	_test_sources(t)
	_test_adding(t)
	_test_reordering(t)
	_test_validation_gate(t)
	_test_round_trip(t)
	_test_reopening(t)

	return t


# -------------------------------------------------------------- fixtures

## A small JPEG, cheap to make and real enough to decode. FastNoiseLite
## rather than set_pixel: filling a few hundred thousand pixels one call at a
## time took minutes the first time this project tried it.
func _jpeg(seed_value: int, width: int = 320, height: int = 240) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.03
	var img := noise.get_image(width, height)
	img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.9)


func _picked(name: String, size: int) -> Platform.PickedFile:
	var file := Platform.PickedFile.new()
	file.name = name
	file.size = size
	return file


func _filled_session() -> EditorSession:
	var session := EditorSession.new()
	session.album.title = "For Maggie"
	session.album.author_note = "Sixty years, ten of them."
	session.album.curator_voice_name = "Tom"
	session.album.closing_line = "There you are."

	for i in PLACES.size():
		var error := session.add_photo("IMG_%04d.jpg" % (i + 1), _jpeg(100 + i))
		if not error.is_empty():
			push_error("fixture failed: %s" % error)
		var photo := session.slot_at(i).photo
		photo.truth.lat = PLACES[i][0]
		photo.truth.lon = PLACES[i][1]
		photo.truth.place_label = PLACES[i][2]
		photo.truth.date.year = 1961 + i * 6
		photo.truth.date.month = 1 + i % 12
		photo.truth.date_precision = AlbumSchema.DatePrecision.MONTH
		photo.content.title = "Photograph %d" % (i + 1)
		photo.content.description = "What happened that week."
		photo.content.private_note = "PRIVATE: never show this."
		photo.curator.hints = PackedStringArray([
			"Warm stone, and you complained all week.",
			"Somewhere in Europe, that summer.",
			"It was %s." % PLACES[i][2],
		])
		photo.curator.reveal_monologue = "That summer. The green dress."
		photo.curator.approved_by_author = true

	return session


# ---------------------------------------------------------------- sources

func _test_sources(t: TestFramework) -> void:
	var session := EditorSession.new()

	var offered: Array = [
		_picked("IMG_0002.JPG", 2_100_000),
		_picked("IMG_0010.jpg", 2_000_000),
		_picked("IMG_0001.jpeg", 1_900_000),
		_picked("notes.txt", 400),
		_picked("scan.png", 3_000_000),
		_picked("clip.mp4", 40_000_000),
	]
	var kept := session.set_sources(offered)

	t.eq(kept, 4, "only decodable images are offered")
	t.eq(session.source_count(), 4, "and that is what the count says")

	# Natural order, so it matches what the author sees in their own file
	# browser: IMG_2 before IMG_10, not after it.
	var names: PackedStringArray = PackedStringArray()
	for file in session.sources:
		names.append(file.name)
	t.eq(names[0], "IMG_0001.jpeg", "sorted by name")
	t.eq(names[1], "IMG_0002.JPG", "case-insensitively")
	t.eq(names[2], "IMG_0010.jpg", "and numerically")
	t.eq(names[3], "scan.png", "PNGs are welcome too")

	t.eq(session.set_sources([]), 0, "a folder of nothing is not an error")


# ----------------------------------------------------------------- adding

func _test_adding(t: TestFramework) -> void:
	var session := EditorSession.new()

	var error := session.add_photo("IMG_0001.jpg", _jpeg(7))
	t.eq(error, "", "a real image is accepted")
	t.eq(session.slot_count(), 1, "and hung")

	var slot := session.slot_at(0)
	t.ok(slot != null, "the slot exists")
	t.eq(slot.source_name, "IMG_0001.jpg", "it remembers where it came from")
	t.close(slot.photo.aspect, 320.0 / 240.0, 0.01, "and the source aspect")

	# Every asset the manifest promises has to actually be there, or the album
	# packs and then fails to load.
	t.ok(slot.assets.has(slot.photo.full_path), "the full-size asset is built")
	t.ok(slot.assets.has(slot.photo.thumb_path), "so is the thumbnail")
	t.eq(slot.photo.blur_paths.size(), AlbumSchema.BLUR_TIER_COUNT,
		"and all four blur tiers are declared")
	for path in slot.photo.blur_paths:
		t.ok(slot.assets.has(path), "tier %s is built" % path)

	t.gt(float(slot.bytes_held()), 1000.0, "the assets are not empty")
	t.lt(float(slot.bytes_held()), 900_000.0,
		"and one photograph is under 900 KB (got %d)" % slot.bytes_held())

	# Ids must be unique, or the archive paths collide and photos overwrite
	# each other inside the ZIP.
	session.add_photo("IMG_0002.jpg", _jpeg(8))
	t.ok(session.slot_at(0).photo.id != session.slot_at(1).photo.id,
		"each photograph gets its own id")

	# Rubbish in, message out — never a half-added slot.
	var bad := session.add_photo("broken.jpg", PackedByteArray([1, 2, 3, 4]))
	t.ok(not bad.is_empty(), "an undecodable file is refused with a reason")
	t.eq(session.slot_count(), 2, "and nothing is hung for it")

	var empty := session.add_photo("nothing.jpg", PackedByteArray())
	t.ok(not empty.is_empty(), "so is an empty one")

	# The wall holds ten.
	while not session.is_full():
		session.add_photo("filler.jpg", _jpeg(200 + session.slot_count()))
	t.eq(session.slot_count(), AlbumSchema.PHOTOS_PER_ALBUM, "ten fills the wall")
	var overflow := session.add_photo("one_too_many.jpg", _jpeg(99))
	t.ok(overflow.contains("10"), "the eleventh is refused, and says why")
	t.eq(session.slot_count(), AlbumSchema.PHOTOS_PER_ALBUM, "still ten")


# ------------------------------------------------------------- reordering

func _test_reordering(t: TestFramework) -> void:
	var session := EditorSession.new()
	for i in 4:
		session.add_photo("IMG_%d.jpg" % i, _jpeg(300 + i))

	var ids: PackedStringArray = PackedStringArray()
	for i in session.slot_count():
		ids.append(session.slot_at(i).photo.id)

	# The hang order IS the slot order — nothing else in the game has to think
	# about hangOrder, so this has to hold after every edit.
	t.eq(Array(session.album.hang_order), Array(ids),
		"the hang order follows the wall")

	session.move_slot(0, 2)
	t.eq(session.slot_at(2).photo.id, ids[0], "a photograph moves down the wall")
	t.eq(session.album.hang_order[2], ids[0], "and the hang order follows")
	t.eq(session.album.hang_order.size(), 4, "with nothing lost")

	session.move_slot(3, 0)
	t.eq(session.slot_at(0).photo.id, ids[3], "and up it")

	session.move_slot(0, 99)
	t.eq(session.slot_count(), 4, "an out-of-range move is clamped, not fatal")
	session.move_slot(-5, 0)
	t.eq(session.slot_count(), 4, "in both directions")

	var doomed := session.slot_at(1).photo.id
	session.remove_slot(1)
	t.eq(session.slot_count(), 3, "taking one down removes it")
	t.eq(session.album.photos.size(), 3, "from the manifest too")
	t.ok(not Array(session.album.hang_order).has(doomed),
		"and from the hang order")
	t.ok(session.album.photo_by_id(doomed) == null, "it is really gone")

	session.remove_slot(17)
	t.eq(session.slot_count(), 3, "removing nothing removes nothing")


# ------------------------------------------------------------- validation

func _test_validation_gate(t: TestFramework) -> void:
	var session := EditorSession.new()
	t.ok(not session.can_export(), "an empty album cannot be exported")
	t.gt(float(session.problems(true).size()), 0.0, "and it says why")

	var full := _filled_session()
	t.ok(full.can_export(), "a complete one can: %s"
		% AlbumValidator.format_all(full.problems(true)))

	# A hint that names the place at tier 1 gives the answer away for nothing,
	# which the validator refuses (plan §8.3).
	var photo := full.slot_at(0).photo
	var hints := photo.curator.hints
	hints[0] = "It was %s, love." % photo.truth.place_label
	photo.curator.hints = hints
	t.ok(not full.can_export(),
		"a first hint that names the place blocks the export")

	hints[0] = "Warm stone, and you complained all week."
	photo.curator.hints = hints
	t.ok(full.can_export(), "fixing it unblocks")

	# Missing coordinates: the round would be unscoreable.
	photo.truth.lat = NAN
	photo.truth.lon = NAN
	t.ok(not full.can_export(), "a photograph with nowhere to be blocks it too")


# ------------------------------------------------------------- round trip

func _test_round_trip(t: TestFramework) -> void:
	var session := _filled_session()

	var bytes := session.export_bytes()
	t.gt(float(bytes.size()), 10_000.0, "the export produces an archive")
	# The whole point of the format: it has to fit in an email.
	t.lt(float(bytes.size()), 6_000_000.0,
		"and it is emailable (%d KB)" % (bytes.size() / 1024))

	t.eq(session.suggested_filename(), "For_Maggie.ccalbum",
		"named after the album, safely")

	# Load it back the way the game does.
	var loaded := AlbumIO.load_from_bytes(bytes)
	t.ok(loaded.is_ok(), "the game can load what the editor wrote: %s"
		% AlbumValidator.format_all(loaded.problems))

	var album := loaded.album
	t.eq(album.title, "For Maggie", "the title survives")
	t.eq(album.closing_line, "There you are.", "so does his last line")
	t.eq(album.photos.size(), AlbumSchema.PHOTOS_PER_ALBUM, "all ten photographs")

	var hung := album.hung_photos()
	t.eq(hung.size(), AlbumSchema.PHOTOS_PER_ALBUM, "all ten hang")
	t.eq(hung[0].truth.place_label, PLACES[0][2], "in the order they were hung")
	t.eq(hung[9].truth.place_label, PLACES[9][2], "including the last one")
	t.close(hung[3].truth.lat, PLACES[3][0], 0.0001, "coordinates survive")
	t.eq(hung[3].truth.date.year, 1961 + 3 * 6, "dates survive")
	t.eq(hung[3].curator.hints.size(), 3, "all three hints survive")

	# Private notes are the author's, and they do travel inside the album —
	# they must simply never be rendered. (results_screen.gd's test covers
	# that end.)
	t.ok(hung[0].content.private_note.contains("PRIVATE"),
		"the author's notes are kept for the author")

	# Every asset the manifest names has to be inside the archive.
	var missing := 0
	for photo in hung:
		if not loaded.has_asset(photo.full_path):
			missing += 1
		for path in photo.blur_paths:
			if not loaded.has_asset(path):
				missing += 1
	t.eq(missing, 0, "every declared asset is in the archive")

	# And the tier-0 image has to be small enough to be fog and large enough
	# to be an image.
	var tier0 := loaded.read_asset(hung[0].blur_paths[0])
	t.gt(float(tier0.size()), 100.0, "tier 0 has bytes")
	t.lt(float(tier0.size()), 20_000.0, "and is tiny (%d B)" % tier0.size())

	loaded.close()


# --------------------------------------------------------------- reopening

func _test_reopening(t: TestFramework) -> void:
	var original := _filled_session()
	var bytes := original.export_bytes()

	var loaded := AlbumIO.load_from_bytes(bytes)
	var session := EditorSession.new()
	var error := session.adopt(loaded)

	t.eq(error, "", "an exported album can be opened again")
	t.eq(session.slot_count(), AlbumSchema.PHOTOS_PER_ALBUM,
		"with all ten photographs")
	t.eq(session.album.title, "For Maggie", "and its title")
	t.gt(float(session.total_asset_bytes()), 10_000.0,
		"the images come across with it")
	t.ok(session.can_export(), "and it can be saved straight back out")

	# Editing and re-exporting must not lose anything.
	session.album.title = "For Maggie, again"
	session.move_slot(0, 9)
	var again := AlbumIO.load_from_bytes(session.export_bytes())
	t.ok(again.is_ok(), "a re-export loads: %s"
		% AlbumValidator.format_all(again.problems))
	t.eq(again.album.title, "For Maggie, again", "with the new title")
	t.eq(again.album.hung_photos()[9].truth.place_label, PLACES[0][2],
		"and the new order")
	again.close()

	# A new id must not collide with the ids already in the file.
	var before := session.slot_at(0).photo.id
	session.remove_slot(0)
	session.add_photo("new_one.jpg", _jpeg(555))
	var new_id := session.slot_at(session.slot_count() - 1).photo.id
	t.ok(new_id != before, "a photograph added after reopening gets a fresh id")
	var seen := {}
	var duplicates := 0
	for i in session.slot_count():
		var id := session.slot_at(i).photo.id
		if seen.has(id):
			duplicates += 1
		seen[id] = true
	t.eq(duplicates, 0, "and no two photographs share an id")

	loaded.close()

	# Refusals.
	var empty_session := EditorSession.new()
	t.ok(not empty_session.adopt(null).is_empty(),
		"adopting nothing is refused with a message")
	var broken := AlbumIO.load_from_bytes(PackedByteArray([80, 75, 3, 4, 0]))
	t.ok(not EditorSession.new().adopt(broken).is_empty(),
		"so is adopting a broken archive")

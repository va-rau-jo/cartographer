extends RefCounted
## Opening a .zip of photographs — a Google Photos download or a Takeout
## export — and getting an album out of the other end.
##
## The whole point of reading Takeout's JSON sidecars is that they carry the
## date and the coordinates even when the image's own EXIF does not, so most of
## these assertions are about that metadata surviving the trip: into the
## archive, into the editor's slot, into the manifest, and back out of a
## packed .ccalbum.
##
## The zips are built here rather than committed as fixtures, so the shapes
## Google actually writes are visible in the test instead of hidden in a binary.

const ZIP_PATH := "user://test_photo_archive.zip"

## 2013-06-01, 2003-02-24 and 1991-01-01 UTC.
const TAKEN_2013 := 1370044800
const TAKEN_2003 := 1046057400
const TAKEN_1991 := 662688000


func run() -> TestFramework:
	var t := TestFramework.new("archive")

	_test_plain_zip(t)
	_test_takeout_sidecars(t)
	_test_sidecar_shapes(t)
	_test_no_stolen_metadata(t)
	_test_staging_is_per_archive(t)
	_test_refusals(t)
	_test_into_the_editor(t)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(ZIP_PATH))
	return t


# -------------------------------------------------------------- fixtures

func _jpeg(seed_value: int, width: int = 240, height: int = 180) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.04
	var img := noise.get_image(width, height)
	img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.9)


## Write a zip. `files` maps path inside the archive -> PackedByteArray.
func _zip(files: Dictionary) -> PackedByteArray:
	var packer := ZIPPacker.new()
	if packer.open(ZIP_PATH) != OK:
		return PackedByteArray()
	for path in files.keys():
		packer.start_file(String(path))
		packer.write_file(files[path])
		packer.close_file()
	packer.close()

	var f := FileAccess.open(ZIP_PATH, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes


func _sidecar(title: String, unix: int, lat: float, lon: float,
		description: String = "", people: Array = []) -> PackedByteArray:
	var geo := {}
	if not is_nan(lat):
		geo = {"latitude": lat, "longitude": lon, "altitude": 12.0}
	else:
		# What Takeout writes for a photograph with no location.
		geo = {"latitude": 0.0, "longitude": 0.0, "altitude": 0.0}

	var folk: Array = []
	for who in people:
		folk.append({"name": String(who)})

	return JSON.stringify({
		"title": title,
		"description": description,
		"imageViews": "7",
		"creationTime": {"timestamp": "1600000000", "formatted": "uploaded"},
		"photoTakenTime": {"timestamp": str(unix), "formatted": "taken"},
		"geoData": geo,
		"geoDataExif": geo,
		"people": folk,
	}).to_utf8_buffer()


# ------------------------------------------------------------ a plain zip

func _test_plain_zip(t: TestFramework) -> void:
	var archive := PhotoArchive.from_bytes(_zip({
		"holiday/IMG_0002.JPG": _jpeg(2),
		"holiday/IMG_0010.jpg": _jpeg(10),
		"holiday/IMG_0001.jpeg": _jpeg(1),
		"holiday/scan.png": _jpeg(3),
		"holiday/notes.txt": "not a photograph".to_utf8_buffer(),
		"holiday/Thumbs.db": PackedByteArray([0, 1, 2]),
		"__MACOSX/holiday/._IMG_0001.jpeg": PackedByteArray([0, 0]),
		"holiday/.DS_Store": PackedByteArray([0]),
	}))

	t.ok(archive.is_ok(), "a plain zip of photographs opens")
	t.eq(archive.count(), 4, "four photographs, and only those")
	t.eq(archive.skipped_count(), 2, "the text file and Thumbs.db are counted out")
	t.eq(archive.with_sidecar_count(), 0, "no metadata, because there is none")

	# Resource forks decode as garbage, so they must not be offered at all.
	for entry in archive.entries():
		t.ok(not entry.path.begins_with("__MACOSX"),
			"%s is not a resource fork" % entry.name)
		t.ok(not entry.name.begins_with("."), "%s is not a dotfile" % entry.name)

	# Natural order, as the author's own file browser shows it.
	var names: PackedStringArray = PackedStringArray()
	for entry in archive.entries():
		names.append(entry.name)
	t.eq(names[0], "IMG_0001.jpeg", "sorted naturally: 1 first")
	t.eq(names[1], "IMG_0002.JPG", "then 2, case-insensitively")
	t.eq(names[2], "IMG_0010.jpg", "then 10, not before 2")

	# And the bytes come back out.
	var bytes := archive.read_image(archive.entries()[0])
	t.gt(float(bytes.size()), 500.0, "a photograph reads out of the zip")
	var decoded := ImagePipeline.decode(bytes, "IMG_0001.jpeg")
	t.ok(decoded != null, "and it is still a decodable image")
	if decoded != null:
		t.eq(decoded.get_width(), 240, "at its original width")

	archive.close()


# ------------------------------------------------------------- Takeout

func _test_takeout_sidecars(t: TestFramework) -> void:
	var archive := PhotoArchive.from_bytes(_zip({
		# The usual shape: a sidecar per photograph, same directory.
		"Takeout/Google Photos/Paris/IMG_0001.JPG": _jpeg(11),
		"Takeout/Google Photos/Paris/IMG_0001.JPG.json":
			_sidecar("IMG_0001.JPG", TAKEN_2013, 48.8566, 2.3522,
				"The morning we got lost", ["Maggie", "Tom"]),
		# No location: Takeout writes zeroes rather than omitting the block.
		"Takeout/Google Photos/Paris/IMG_0002.JPG": _jpeg(12),
		"Takeout/Google Photos/Paris/IMG_0002.JPG.json":
			_sidecar("IMG_0002.JPG", TAKEN_2003, NAN, NAN, "Somewhere indoors"),
		# No sidecar at all.
		"Takeout/Google Photos/Paris/IMG_0003.JPG": _jpeg(13),
		# Album-level metadata, which is not a photograph's sidecar.
		"Takeout/Google Photos/Paris/metadata.json":
			'{"title": "Paris"}'.to_utf8_buffer(),
	}))

	t.eq(archive.count(), 3, "three photographs")
	t.eq(archive.with_sidecar_count(), 2, "two of them with metadata")

	var first := archive.entries()[0]
	t.eq(first.name, "IMG_0001.JPG", "the first is the one with everything")
	t.ok(first.had_sidecar, "its sidecar was found")
	t.ok(first.has_date(), "it has a date")
	t.eq(first.date.year, 2013, "the year Google recorded")
	t.eq(first.date.month, 6, "the month")
	t.eq(first.date.day, 1, "and the day")
	t.ok(first.has_location(), "it has a location")
	t.close(first.lat, 48.8566, 0.0001, "the latitude")
	t.close(first.lon, 2.3522, 0.0001, "the longitude")
	t.eq(first.description, "The morning we got lost", "and the caption")
	t.eq(first.people.size(), 2, "and who was in it")
	t.eq(first.people[0], "Maggie", "by name")

	# creationTime is when it was uploaded — decades out for a scan — so it
	# must never be mistaken for photoTakenTime.
	t.ok(first.date.year != 2020, "the upload date is not used as the date")

	var second := archive.entries()[1]
	t.ok(second.had_sidecar, "the second one's sidecar was found too")
	t.ok(second.has_date(), "with its date")
	t.eq(second.date.year, 2003, "from 2003")
	t.ok(not second.has_location(),
		"but zeroed coordinates count as no location, not as Null Island")
	t.eq(second.description, "Somewhere indoors", "its caption still arrives")

	var third := archive.entries()[2]
	t.ok(not third.had_sidecar, "a photograph with no sidecar says so")
	t.ok(not third.has_date(), "and knows nothing")
	t.ok(not third.has_location(), "about where it was either")

	archive.close()


## Takeout has changed its sidecar naming more than once, and truncates long
## names. All of these shapes have to find their photograph.
func _test_sidecar_shapes(t: TestFramework) -> void:
	var long_name := "PXL_20230704_101530123.PORTRAIT-01.COVER.jpg"
	var archive := PhotoArchive.from_bytes(_zip({
		"a/IMG_0001.JPG": _jpeg(21),
		"a/IMG_0001.JPG.supplemental-metadata.json":
			_sidecar("IMG_0001.JPG", TAKEN_1991, 54.4858, -0.6206),
		"a/IMG_0002.JPG": _jpeg(22),
		"a/IMG_0002.json":
			_sidecar("IMG_0002.JPG", TAKEN_2003, 64.1466, -21.9426),
		"a/%s" % long_name: _jpeg(23),
		# Truncated, as Takeout does with long filenames.
		"a/PXL_20230704_101530123.PORTRAIT-01.CO.json":
			_sidecar(long_name, TAKEN_2013, 35.0116, 135.7681),
	}))

	t.eq(archive.count(), 3, "three photographs with three naming shapes")
	t.eq(archive.with_sidecar_count(), 3, "and all three sidecars found")

	for entry in archive.entries():
		t.ok(entry.has_location(), "%s got its coordinates" % entry.name)
		t.ok(entry.has_date(), "%s got its date" % entry.name)

	archive.close()


func _test_refusals(t: TestFramework) -> void:
	var empty := PhotoArchive.from_bytes(PackedByteArray())
	t.ok(not empty.is_ok(), "an empty file is not an archive")
	t.gt(float(empty.problems.size()), 0.0, "and it says so")

	var rubbish := PhotoArchive.from_bytes(
		"this is not a zip at all, not even slightly".to_utf8_buffer())
	t.ok(not rubbish.is_ok(), "nor is a text file")
	t.gt(float(rubbish.problems.size()), 0.0, "with a reason")

	var no_photos := PhotoArchive.from_bytes(_zip({
		"readme.txt": "nothing here".to_utf8_buffer(),
	}))
	t.ok(not no_photos.is_ok(), "a zip with no photographs in it is refused")
	t.eq(no_photos.count(), 0, "because there is nothing to offer")

	# A sidecar that is not JSON must not take the photograph down with it.
	var broken := PhotoArchive.from_bytes(_zip({
		"b/IMG_0001.JPG": _jpeg(31),
		"b/IMG_0001.JPG.json": "{ this is not json".to_utf8_buffer(),
	}))
	t.ok(broken.is_ok(), "a broken sidecar still leaves a usable archive")
	t.eq(broken.count(), 1, "with the photograph")
	t.ok(not broken.entries()[0].has_date(), "just without its metadata")
	t.gt(float(broken.problems.size()), 0.0, "and a note about it")
	broken.close()


# -------------------------------------------------------- into the editor

func _test_into_the_editor(t: TestFramework) -> void:
	var files := {}
	const PLACES := [
		[48.8566, 2.3522, "Paris"],
		[54.4858, -0.6206, "Whitby"],
		[64.1466, -21.9426, "Reykjavik"],
	]
	for i in PLACES.size():
		var name := "IMG_%04d.JPG" % (i + 1)
		files["Photos/%s" % name] = _jpeg(40 + i)
		files["Photos/%s.json" % name] = _sidecar(name,
			TAKEN_1991 + i * 31_536_000, PLACES[i][0], PLACES[i][1],
			"What happened at %s" % PLACES[i][2], ["Maggie"])

	var session := EditorSession.new()
	var error := session.set_archive(PhotoArchive.from_bytes(_zip(files)))
	t.eq(error, "", "the editor takes the archive")
	t.eq(session.source_count(), 3, "and offers its photographs")
	t.ok(session.archive != null, "and knows it is working from a zip")

	# The source list says what each photograph already knows, so the author
	# can see which ones will not need typing.
	var label := session.source_label(0)
	t.ok(label.contains("IMG_0001.JPG"), "the list shows the name (%s)" % label)
	t.ok(label.contains("located"), "and that it has a location")

	t.eq(session.add_from_archive(0), "", "a photograph adds straight from the zip")
	t.eq(session.slot_count(), 1, "and is hung")

	var slot := session.slot_at(0)
	t.ok(slot.from_sidecar, "the slot records that Google's export filled it in")
	t.ok(slot.photo.truth.has_location(), "it has somewhere to be")
	t.close(slot.photo.truth.lat, 48.8566, 0.001, "the right latitude")
	t.close(slot.photo.truth.lon, 2.3522, 0.001, "the right longitude")
	t.eq(slot.photo.truth.date.year, 1991, "and the right year")
	t.eq(slot.photo.content.description, "What happened at Paris",
		"the caption becomes the description his hints are drawn from")
	t.eq(slot.photo.content.people.size(), 1, "and the people come across")

	# Precision follows what the sidecar actually knew — a full timestamp is a
	# day, and the calendar dial will ask for one.
	t.eq(slot.photo.truth.date_precision, AlbumSchema.DatePrecision.DAY,
		"a full timestamp is day precision")

	# What the author types always wins over what Google said.
	slot.photo.truth.place_label = "Paris, France"
	slot.photo.content.description = "My own words"
	t.eq(session.slot_at(0).photo.content.description, "My own words",
		"the author's own description is not overwritten")

	# The rest of the way: a packed album that the game can load.
	session.add_from_archive(1)
	session.add_from_archive(2)
	t.eq(session.slot_count(), 3, "three of the zip's photographs are hung")

	var packed := session.export_bytes()
	t.gt(float(packed.size()), 5000.0, "it packs")
	var loaded := AlbumIO.load_from_bytes(packed)
	t.ok(loaded.album != null, "and loads back")
	if loaded.album != null:
		var hung := loaded.album.hung_photos()
		t.eq(hung.size(), 3, "with all three")
		t.close(hung[0].truth.lat, 48.8566, 0.001,
			"and the coordinates that came out of Google's export")
	loaded.close()

	# Switching to a folder must let go of the zip.
	session.set_sources([])
	t.ok(session.archive == null, "choosing a folder closes the archive")
	t.eq(session.source_count(), 0, "and replaces its listing")

## A sidecar may only be shared by NAME, never by coincidence.
##
## The truncated-name match used to accept any sidecar whose name was a prefix
## of the photograph's, so a photograph with no sidecar of its own quietly took
## a neighbour's — and a sidecar carries the place and the date the player is
## scored against. The answer to one photograph became the answer to another,
## silently, in the album the author then gave away.
func _test_no_stolen_metadata(t: TestFramework) -> void:
	var archive := PhotoArchive.from_bytes(_zip({
		# beach.jpg has its own sidecar. beach2.jpg does not, and its name
		# begins with "beach".
		"a/beach.jpg": _jpeg(41),
		"a/beach.jpg.json": _sidecar("beach.jpg", TAKEN_1991, 48.8566, 2.3522),
		"a/beach2.jpg": _jpeg(42),
		# Same shape one level down: a shorter name and a longer one.
		"b/holiday_0.jpg": _jpeg(43),
		"b/holiday_0.jpg.json":
			_sidecar("holiday_0.jpg", TAKEN_2003, 64.1466, -21.9426),
		"b/holiday_02.jpg": _jpeg(44),
	}))
	t.ok(archive.is_ok(), "the archive opens")

	var by_name := {}
	for entry in archive.entries():
		by_name[entry.name] = entry

	t.eq(by_name.size(), 4, "all four photographs are listed")

	var owner: PhotoArchive.Entry = by_name.get("beach.jpg")
	t.ok(owner != null and owner.had_sidecar,
		"the photograph the sidecar is named after gets it")
	if owner != null:
		t.ok(owner.has_location(), "with its coordinates")
		t.close(owner.lat, 48.8566, 0.001, "which are Paris")

	var thief: PhotoArchive.Entry = by_name.get("beach2.jpg")
	t.ok(thief != null, "the other photograph is there")
	if thief != null:
		t.ok(not thief.had_sidecar,
			"but it has no sidecar of its own, and takes nobody else's")
		t.ok(not thief.has_location(),
			"so it has no location — not Paris")
		t.ok(not thief.has_date(), "and no date")

	var longer: PhotoArchive.Entry = by_name.get("holiday_02.jpg")
	t.ok(longer != null and not longer.had_sidecar,
		"nor does a longer name take a shorter name's sidecar")
	if longer != null:
		t.ok(not longer.has_location(), "and it stays without coordinates")

	t.eq(archive.with_sidecar_count(), 2,
		"exactly the two photographs that have one are counted")

	archive.close()


## A staged archive is the caller's to keep only until it is closed.
func _test_staging_is_per_archive(t: TestFramework) -> void:
	var first := PhotoArchive.from_bytes(_zip({
		"one/IMG_0001.jpg": _jpeg(51),
	}))
	t.ok(first.is_ok(), "the first archive opens")

	# A second archive must not truncate the file the first one is reading.
	var second := PhotoArchive.from_bytes(_zip({
		"two/IMG_9001.jpg": _jpeg(52),
		"two/IMG_9002.jpg": _jpeg(53),
	}))
	t.ok(second.is_ok(), "the second archive opens")
	t.eq(second.count(), 2, "with its own two photographs")
	t.eq(first.count(), 1, "and the first still has its one")

	# The real test: the first archive can still READ, and reads its own bytes.
	var image := first.read_image(first.entries()[0])
	t.ok(not image.is_empty(),
		"the first archive can still read its photograph")
	t.eq(first.entries()[0].name, "IMG_0001.jpg",
		"and it is still its own photograph")

	first.close()
	second.close()

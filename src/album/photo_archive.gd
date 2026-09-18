class_name PhotoArchive
extends RefCounted
## A .zip of photographs, opened for browsing: Google Photos' "download all",
## a Google Takeout export, or any zip somebody made by hand.
##
## This is the answer to "a zip makes more sense than picking a folder". A
## Google Photos album downloads as one zip, and the browser can hand a zip
## straight here — no folder picker, no thousand lazy file handles, and on the
## web no `webkitdirectory` (which phones do not offer at all).
##
## It is NOT a .ccalbum. A .ccalbum is also a zip, but it holds the four blur
## tiers per photograph and the album.json the game plays from; this is raw
## photographs on their way in. The editor reads one of these and writes one of
## those — see EditorSession.
##
## Takeout sidecars are the reason this is worth having rather than just
## unzipping by hand. Google exports a JSON file beside each photograph with
## the date, the coordinates, the description and the people in it, and its
## coordinates survive even when the image's own EXIF has been stripped. Those
## are exactly the fields the editor would otherwise make the author type.
## Sidecar naming has changed more than once, so the matching happens in two
## passes — exact names, then truncated ones. See `_scan`.

const IMAGE_EXTENSIONS := ["jpg", "jpeg", "png", "webp"]

## The fewest characters a sidecar name may share with a photograph's before
## it can be treated as that photograph's truncated sidecar. The real
## protection is that the sidecar must not already belong to another
## photograph in the archive — see `_truncated_sidecar_for` — and this is only
## a floor against absurd matches.
const MIN_TRUNCATED_PREFIX := 6

## Where an archive handed over as bytes is written before it is read. Unique
## per archive: a single fixed path was truncated by the NEXT archive while the
## previous one's ZIPReader was still open on it, so after opening a second zip
## that turned out to have no photographs in it, the first archive — still the
## active one — read every image out of the second zip's bytes.
const STAGING_PREFIX := "user://tmp_photo_archive"


static func _staging_path() -> String:
	return "%s_%d.zip" % [STAGING_PREFIX, Time.get_ticks_usec()]

## Takeout writes 0,0 for a photograph with no location. It is also a real
## place in the Gulf of Guinea, but no photograph of anyone's life is there.
const NULL_ISLAND_EPSILON := 0.0001


## One photograph inside the archive, with whatever its sidecar said.
class Entry extends RefCounted:
	var path: String = ""          ## path inside the zip
	var name: String = ""          ## basename
	var size: int = 0

	## From the sidecar, where there was one. NAN / 0 / "" when absent.
	var date: AlbumSchema.PhotoDate = null
	var lat: float = NAN
	var lon: float = NAN
	var description: String = ""
	var people: PackedStringArray = PackedStringArray()
	var had_sidecar: bool = false

	func has_location() -> bool:
		return not (is_nan(lat) or is_nan(lon))

	func has_date() -> bool:
		return date != null and date.is_set()


var problems: PackedStringArray = PackedStringArray()

var _zip: ZIPReader = null
var _entries: Array[Entry] = []
var _skipped := 0
var _source := ""
## Set when WE wrote the file being read, so closing can delete it. A zip the
## author picked off their own disk is left alone.
var _staged := ""


func is_ok() -> bool:
	return _zip != null and not _entries.is_empty()


func entries() -> Array[Entry]:
	return _entries


func count() -> int:
	return _entries.size()


## Files in the zip that were neither photographs nor sidecars: album.html,
## metadata for the album itself, Windows' Thumbs.db, and so on.
func skipped_count() -> int:
	return _skipped


func with_sidecar_count() -> int:
	var n := 0
	for entry in _entries:
		if entry.had_sidecar:
			n += 1
	return n


func source() -> String:
	return _source


## Bytes for one photograph. Read on demand: a zip of a thousand photographs
## is opened instantly and only the chosen ten are ever decoded.
func read_image(entry: Entry) -> PackedByteArray:
	if _zip == null or entry == null:
		return PackedByteArray()
	if not _zip.file_exists(entry.path):
		CCLog.error("archive", "missing from archive: %s" % entry.path)
		return PackedByteArray()
	return _zip.read_file(entry.path)


func close() -> void:
	if _zip != null:
		_zip.close()
		_zip = null
	if not _staged.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_staged))
		_staged = ""


# ------------------------------------------------------------------ opening

static func from_bytes(bytes: PackedByteArray) -> PhotoArchive:
	var archive := PhotoArchive.new()
	if bytes.is_empty():
		archive.problems.append("that file is empty")
		return archive

	var staged := _staging_path()
	var f := FileAccess.open(staged, FileAccess.WRITE)
	if f == null:
		archive.problems.append("cannot stage the archive (error %d)"
			% FileAccess.get_open_error())
		return archive
	f.store_buffer(bytes)
	f.close()

	var opened := from_path(staged)
	# Ours to delete, unlike a zip the author picked off their own disk.
	opened._staged = staged
	return opened


static func from_path(path: String) -> PhotoArchive:
	var archive := PhotoArchive.new()
	archive._source = path

	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		archive.problems.append("that is not a readable zip (error %d)" % err)
		return archive

	archive._zip = zip
	archive._scan()
	return archive


func _scan() -> void:
	var images: Array[Entry] = []
	var sidecars := {}

	for path in _zip.get_files():
		var file_path := String(path)
		if file_path.ends_with("/"):
			continue
		var base := file_path.get_file()
		# __MACOSX/ resource forks and dotfiles are noise, and the resource
		# forks decode as garbage images if let through.
		if base.begins_with(".") or file_path.begins_with("__MACOSX"):
			continue

		var extension := base.get_extension().to_lower()
		if extension in IMAGE_EXTENSIONS:
			var entry := Entry.new()
			entry.path = file_path
			entry.name = base
			images.append(entry)
		elif extension == "json":
			sidecars[file_path] = true
		else:
			_skipped += 1

	# Natural order, so the list matches what the author sees in their own
	# file browser rather than the zip's internal order.
	images.sort_custom(func(a: Entry, b: Entry) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)

	# Two passes, and the order is the whole point.
	#
	# Pass one gives every photograph the sidecar that is named after it
	# exactly. Pass two lets a photograph with no such sidecar claim one whose
	# name is a PREFIX of its own — which is how Takeout writes a sidecar for a
	# name too long for its filename limit — but only from the sidecars pass
	# one did not claim, and only one photograph per sidecar.
	#
	# Done in one pass it was a data-corruption bug: `beach2.jpg` with no
	# sidecar of its own matched `beach.jpg.json` on the prefix, so the lat,
	# lon and date the player is scored against for one photograph were
	# silently copied onto another.
	var taken := {}
	var unmatched: Array[Entry] = []

	for entry in images:
		var exact := _exact_sidecar_for(entry.path, sidecars)
		if exact.is_empty():
			unmatched.append(entry)
			continue
		taken[exact] = true
		_apply_sidecar(entry, exact)

	for entry in unmatched:
		var truncated := _truncated_sidecar_for(entry.path, sidecars, taken)
		if truncated.is_empty():
			continue
		taken[truncated] = true
		_apply_sidecar(entry, truncated)

	_entries = images
	CCLog.info("archive", "%d photographs, %d with metadata, %d other files"
		% [_entries.size(), with_sidecar_count(), _skipped])


## The sidecar named after this photograph exactly. Takeout has used at least
## these shapes:
##   IMG_0001.JPG.json
##   IMG_0001.JPG.supplemental-metadata.json
##   IMG_0001.json
func _exact_sidecar_for(image_path: String, sidecars: Dictionary) -> String:
	var directory := image_path.get_base_dir()
	var base := image_path.get_file()
	var stem := base.get_basename()

	var candidates: PackedStringArray = PackedStringArray([
		"%s.json" % base,
		"%s.supplemental-metadata.json" % base,
		"%s.suppl.json" % base,
		"%s.json" % stem,
	])
	for candidate in candidates:
		var full := candidate if directory.is_empty() \
			else "%s/%s" % [directory, candidate]
		if sidecars.has(full):
			return full
	return ""


## A sidecar whose name is a PREFIX of this photograph's, which is how Takeout
## writes one for a name too long for its filename limit. `taken` holds the
## sidecars already claimed by a photograph they are named after exactly, and
## those are never candidates here: a sidecar that belongs to a photograph in
## this same archive is not a truncation of a different one.
##
## Shortest match wins, since that is the closest to the photograph's own name.
func _truncated_sidecar_for(image_path: String, sidecars: Dictionary,
		taken: Dictionary) -> String:
	var directory := image_path.get_base_dir()
	var base := image_path.get_file()
	var stem := base.get_basename()

	var best := ""
	for path in sidecars.keys():
		var sidecar_path := String(path)
		if taken.has(sidecar_path):
			continue
		if sidecar_path.get_base_dir() != directory:
			continue
		var sidecar_name := sidecar_path.get_file()
		var prefix := sidecar_name.get_basename()
		# A handful of characters in common is a coincidence, not a cut name.
		if prefix.length() < MIN_TRUNCATED_PREFIX:
			continue
		if base.begins_with(prefix) or stem.begins_with(prefix.get_basename()):
			if best.is_empty() or sidecar_name.length() < best.get_file().length():
				best = sidecar_path
	return best


func _apply_sidecar(entry: Entry, path: String) -> void:
	var raw := _zip.read_file(path)
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		problems.append("%s is not valid JSON; ignored" % path.get_file())
		return

	var data: Dictionary = parsed
	entry.had_sidecar = true

	entry.description = str(data.get("description", "")).strip_edges()

	for person in data.get("people", []):
		if typeof(person) == TYPE_DICTIONARY:
			var who := str(person.get("name", "")).strip_edges()
			if not who.is_empty():
				entry.people.append(who)

	entry.date = _date_from(data)

	# geoData is the user-visible location (which they may have corrected by
	# hand); geoDataExif is what the camera recorded. Prefer the former.
	var coords := _coords_from(data.get("geoData", {}))
	if is_nan(coords.x):
		coords = _coords_from(data.get("geoDataExif", {}))
	entry.lat = coords.x
	entry.lon = coords.y


## Takeout dates are unix seconds in a string. photoTakenTime is when the
## photograph was taken; creationTime is when it was uploaded, which for a
## scanned print is decades out — so only the former is used.
static func _date_from(data: Dictionary) -> AlbumSchema.PhotoDate:
	var taken: Dictionary = data.get("photoTakenTime", {})
	var raw := str(taken.get("timestamp", "")).strip_edges()
	if raw.is_empty() or not raw.is_valid_int():
		return null
	var unix := int(raw)
	if unix <= 0:
		return null

	var parts := Time.get_datetime_dict_from_unix_time(unix)
	var date := AlbumSchema.PhotoDate.new()
	date.year = int(parts.get("year", 0))
	date.month = int(parts.get("month", 0))
	date.day = int(parts.get("day", 0))
	return date if date.is_set() else null


## Returns (lat, lon), or (NAN, NAN) when the block is missing or is the
## all-zero "no location" placeholder.
static func _coords_from(block: Variant) -> Vector2:
	if typeof(block) != TYPE_DICTIONARY:
		return Vector2(NAN, NAN)
	var data: Dictionary = block
	if not data.has("latitude") or not data.has("longitude"):
		return Vector2(NAN, NAN)

	var lat := float(data.get("latitude", 0.0))
	var lon := float(data.get("longitude", 0.0))
	if absf(lat) < NULL_ISLAND_EPSILON and absf(lon) < NULL_ISLAND_EPSILON:
		return Vector2(NAN, NAN)
	if not Geo.is_valid_lat(lat) or not Geo.is_valid_lon(lon):
		return Vector2(NAN, NAN)
	return Vector2(lat, lon)

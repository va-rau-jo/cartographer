class_name EditorSession
extends RefCounted
## The album under construction: ten slots, their images, and everything the
## author types about them.
##
## Deliberately has no UI and does no file IO. The screen reads bytes (from a
## folder on Windows, from a lazy File handle on the web) and hands them here;
## this owns the model, the image processing, the EXIF prefill, the validation
## and the packing. That split is what makes the editor testable at all — the
## whole pipeline from "here are ten JPEGs" to "here is a .ccalbum" runs
## headlessly.

signal changed()

const MAX_PHOTOS := AlbumSchema.PHOTOS_PER_ALBUM


## One hung photograph: its manifest entry, where it came from, and the
## encoded assets built from it.
class Slot extends RefCounted:
	var photo: AlbumSchema.Photo = null
	## Basename of the file it was made from, for the author's own reference.
	var source_name: String = ""
	## archive path -> WebP bytes, as ImagePipeline produced them.
	var assets: Dictionary = {}
	var source_width := 0
	var source_height := 0

	## What EXIF gave us, kept separately so the UI can say "from the photo"
	## and so re-prefilling never clobbers something typed by hand.
	var exif_date: AlbumSchema.PhotoDate = null
	var exif_lat := NAN
	var exif_lon := NAN
	## True when a Google sidecar contributed something to this slot.
	var from_sidecar := false

	var _thumbnail: ImageTexture = null

	func has_exif_location() -> bool:
		return not (is_nan(exif_lat) or is_nan(exif_lon))

	## The thumbnail as a texture, decoded once and kept. The editor's lists
	## and its preview pane all want the same one.
	func thumbnail() -> ImageTexture:
		if _thumbnail != null:
			return _thumbnail
		if photo == null or not assets.has(photo.thumb_path):
			return null
		var img := ImagePipeline.decode(assets[photo.thumb_path], photo.thumb_path)
		if img == null:
			return null
		_thumbnail = ImageTexture.create_from_image(img)
		return _thumbnail


	func bytes_held() -> int:
		var n := 0
		for path in assets.keys():
			n += (assets[path] as PackedByteArray).size()
		return n


var album: AlbumSchema.Album = null
var slots: Array[Slot] = []

## Files offered by the source folder, already filtered to images we can
## decode. Kept as Platform.PickedFile so a thousand-file folder stays lazy.
var sources: Array = []

## Set instead of `sources` when the author handed us a zip — a Google Photos
## download or a Takeout export. Its entries carry the sidecar metadata, and
## bytes come from the zip rather than from Platform.
var archive: PhotoArchive = null

var _next_id := 1


func _init() -> void:
	album = AlbumSchema.Album.create_empty("Untitled album")


# ------------------------------------------------------------------ sources

## Take a folder listing. Anything we cannot decode is dropped rather than
## shown and then failing later, and the rest is sorted by name so the order
## matches what the author sees in their own file browser.
func set_sources(files: Array) -> int:
	_close_archive()
	sources = []
	for file in files:
		var picked: Platform.PickedFile = file
		if picked != null and picked.is_supported_image():
			sources.append(picked)
	sources.sort_custom(func(a, b) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)
	changed.emit()
	return sources.size()


func source_count() -> int:
	if archive != null:
		return archive.count()
	return sources.size()


## Take a zip of photographs as the source. Replaces any folder listing.
## Returns "" on success.
func set_archive(new_archive: PhotoArchive) -> String:
	if new_archive == null:
		return "no archive"
	if not new_archive.is_ok():
		var why := "there are no photographs in that zip"
		if not new_archive.problems.is_empty():
			why = new_archive.problems[0]
		new_archive.close()
		return why

	_close_archive()
	sources = []
	archive = new_archive
	changed.emit()
	return ""


func _close_archive() -> void:
	if archive != null:
		archive.close()
		archive = null


## One row of the source list, whichever kind of source is loaded: the name,
## the size, and what its metadata already knows.
func source_label(index: int) -> String:
	if archive != null:
		if index < 0 or index >= archive.count():
			return ""
		var entry := archive.entries()[index]
		var notes: PackedStringArray = PackedStringArray()
		if entry.has_date():
			notes.append(entry.date.label())
		if entry.has_location():
			notes.append("located")
		if notes.is_empty():
			return entry.name
		return "%s   (%s)" % [entry.name, ", ".join(notes)]

	if index < 0 or index >= sources.size():
		return ""
	var picked: Platform.PickedFile = sources[index]
	var kb := picked.size / 1024
	if kb >= 1024:
		return "%s   %.1f MB" % [picked.name, float(kb) / 1024.0]
	return "%s   %d KB" % [picked.name, kb]


## The name of source `index`, for status messages.
func source_name(index: int) -> String:
	if archive != null:
		if index < 0 or index >= archive.count():
			return ""
		return archive.entries()[index].name
	if index < 0 or index >= sources.size():
		return ""
	return (sources[index] as Platform.PickedFile).name


# -------------------------------------------------------------------- slots

func slot_count() -> int:
	return slots.size()


func is_full() -> bool:
	return slots.size() >= MAX_PHOTOS


func slot_at(index: int) -> Slot:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## Add source `index`, reading its bytes from the zip. Folder sources are read
## through Platform by the screen (it can await); this cannot, and does not
## need to.
func add_from_archive(index: int) -> String:
	if archive == null:
		return "no archive is loaded"
	if index < 0 or index >= archive.count():
		return "no such photograph"

	var entry := archive.entries()[index]
	var bytes := archive.read_image(entry)
	if bytes.is_empty():
		return "could not read %s out of the zip" % entry.name
	return add_photo(entry.name, bytes, entry)


## Decode a chosen file and add it as the next photograph. `from_archive`, when
## given, is the zip entry it came from, whose sidecar fills in anything the
## image's own EXIF did not carry.
## Returns "" on success, or a message to show the author.
func add_photo(filename: String, bytes: PackedByteArray,
		from_archive: PhotoArchive.Entry = null) -> String:
	if is_full():
		return "This album already has %d photographs." % MAX_PHOTOS

	var photo_id := "p_%03d" % _next_id
	var processed := ImagePipeline.process(bytes, filename, photo_id)
	if not processed.ok:
		return processed.error

	_next_id += 1

	var photo := AlbumSchema.Photo.new()
	photo.id = photo_id
	photo.aspect = processed.aspect
	var paths := AlbumSchema.Photo.default_paths(photo_id)
	photo.full_path = paths["full"]
	photo.blur_paths = PackedStringArray(paths["blurTiers"])
	photo.thumb_path = paths["thumb"]

	var slot := Slot.new()
	slot.photo = photo
	slot.source_name = filename.get_file()
	slot.assets = processed.assets
	slot.source_width = processed.source_width
	slot.source_height = processed.source_height
	slot.exif_date = processed.exif_date
	slot.exif_lat = processed.exif_lat
	slot.exif_lon = processed.exif_lon

	_prefill_from_exif(slot)
	if from_archive != null:
		_prefill_from_sidecar(slot, from_archive)

	slots.append(slot)
	album.photos.append(photo)
	_rebuild_hang_order()
	changed.emit()

	CCLog.info("editor", "added %s (%s, %dx%d, %d KB of assets)"
		% [slot.source_name, photo_id, slot.source_width, slot.source_height,
		   slot.bytes_held() / 1024])
	return ""


## EXIF is free information and the author can overwrite all of it. Date
## precision follows what the photo actually carries: a scan with only a year
## must not be scored against a month (plan §6.3).
func _prefill_from_exif(slot: Slot) -> void:
	if slot.exif_date != null and slot.exif_date.is_set():
		slot.photo.truth.date = slot.exif_date
		if slot.exif_date.day > 0:
			slot.photo.truth.date_precision = AlbumSchema.DatePrecision.DAY
		elif slot.exif_date.month > 0:
			slot.photo.truth.date_precision = AlbumSchema.DatePrecision.MONTH
		else:
			slot.photo.truth.date_precision = AlbumSchema.DatePrecision.YEAR

	if slot.has_exif_location():
		slot.photo.truth.lat = slot.exif_lat
		slot.photo.truth.lon = slot.exif_lon


## What Google knew about the photograph, for anything EXIF did not say. EXIF
## wins where both have an answer: it is the camera's own record, while a
## sidecar's location may have been typed in by whoever uploaded it.
##
## The description is the exception — it is the only place a caption can come
## from, and it is what his hints are drawn from, so it is always taken.
func _prefill_from_sidecar(slot: Slot, entry: PhotoArchive.Entry) -> void:
	if not entry.had_sidecar:
		return

	slot.from_sidecar = true

	if not entry.description.is_empty():
		slot.photo.content.description = entry.description
	if not entry.people.is_empty():
		slot.photo.content.people = entry.people

	if not slot.photo.truth.date.is_set() and entry.has_date():
		slot.photo.truth.date = entry.date
		slot.photo.truth.date_precision = AlbumSchema.DatePrecision.DAY \
			if entry.date.day > 0 else AlbumSchema.DatePrecision.MONTH

	if not slot.photo.truth.has_location() and entry.has_location():
		slot.photo.truth.lat = entry.lat
		slot.photo.truth.lon = entry.lon


func remove_slot(index: int) -> void:
	var slot := slot_at(index)
	if slot == null:
		return
	slots.remove_at(index)
	album.photos.erase(slot.photo)
	_rebuild_hang_order()
	changed.emit()


## Move a photograph up or down the wall. The hang order is dramatic
## structure, not chronology (plan §3.2), so this is a real editing operation
## rather than a convenience.
func move_slot(from: int, to: int) -> void:
	if from < 0 or from >= slots.size():
		return
	var target := clampi(to, 0, slots.size() - 1)
	if target == from:
		return
	var slot: Slot = slots[from]
	slots.remove_at(from)
	slots.insert(target, slot)
	_rebuild_hang_order()
	changed.emit()


## The wall order IS the slot order. Keeping them in sync here means nothing
## else has to think about hangOrder at all.
func _rebuild_hang_order() -> void:
	var order: PackedStringArray = PackedStringArray()
	for slot in slots:
		order.append(slot.photo.id)
	album.hang_order = order


## Announce a change made through a photo's own fields by the UI.
func touch() -> void:
	changed.emit()


# --------------------------------------------------------------- validation

## Everything wrong with the album, worst first. `for_export` turns on the
## stricter rules (ten photos exactly, hints present, and so on).
func problems(for_export: bool = false) -> Array[AlbumValidator.Problem]:
	return AlbumValidator.validate(album, for_export)


func can_export() -> bool:
	return not AlbumValidator.has_errors(problems(true))


# ------------------------------------------------------------------- export

## Pack the album. Returns empty on failure; check can_export() first if you
## want to tell the author why.
func export_bytes() -> PackedByteArray:
	var assets := {}
	for slot in slots:
		for path in slot.assets.keys():
			assets[path] = slot.assets[path]
	return AlbumIO.pack(album, assets)


func suggested_filename() -> String:
	return AlbumIO.suggested_filename(album)


func total_asset_bytes() -> int:
	var n := 0
	for slot in slots:
		n += slot.bytes_held()
	return n


# --------------------------------------------------------------- reopening

## Adopt an album that was loaded from a .ccalbum, so an existing gift can be
## edited rather than rebuilt. The assets come across as they are: there is no
## need to re-encode images that are already in the right form, and no way to
## recover the originals anyway.
func adopt(loaded: AlbumIO.LoadedAlbum) -> String:
	if loaded == null or not loaded.is_ok():
		return "That album could not be read."

	# A COPY, not the object the loader is holding. Taking the reference meant
	# every keystroke in the editor mutated the album behind
	# AlbumService.album() — so opening a gift from the preview screen, typing
	# a new title and a few hints, and then pressing Back left the preview and
	# the gallery playing those unsaved edits as though they had been saved.
	# The manifest round trip is the same one the file itself goes through.
	album = AlbumSchema.Album.from_dict(loaded.album.to_dict())
	slots = []
	_next_id = 1

	for photo in album.hung_photos():
		var slot := Slot.new()
		slot.photo = photo
		# source_width/source_height stay at zero: nothing is decoded here and
		# the manifest does not record the original pixel size, only the
		# aspect. The editor's source line leaves the dimensions out when they
		# are zero rather than printing "0 × 0", which is what it used to do
		# for every photograph in a reopened album.
		slot.source_name = "(from the album)"
		for path in _asset_paths(photo):
			var bytes := loaded.read_asset(path)
			if not bytes.is_empty():
				slot.assets[path] = bytes
		slots.append(slot)

		# Keep generated ids unique against whatever the file already used.
		var suffix := photo.id.get_slice("_", photo.id.get_slice_count("_") - 1)
		if suffix.is_valid_int():
			_next_id = maxi(_next_id, int(suffix) + 1)

	_rebuild_hang_order()
	changed.emit()
	CCLog.info("editor", "adopted '%s': %d photographs, %d KB of assets"
		% [album.title, slots.size(), total_asset_bytes() / 1024])
	return ""


static func _asset_paths(photo: AlbumSchema.Photo) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	if not photo.full_path.is_empty():
		paths.append(photo.full_path)
	if not photo.thumb_path.is_empty():
		paths.append(photo.thumb_path)
	for p in photo.blur_paths:
		paths.append(p)
	return paths

class_name AlbumIO
extends RefCounted
## Reading and writing .ccalbum files.
##
## An album is a ZIP of exactly ten photos and a manifest — about 5 MB, so it
## attaches to an email and loads in well under a second. That smallness is
## why this file is simple: we hand the whole thing to ZIPReader and read
## assets on demand, with no streaming, eviction or byte-range machinery.
##
## Godot's ZIPReader wants a real file path, and on web the picked file arrives
## as bytes in memory, so load_from_bytes() stages it to user:// first. At 5 MB
## that write is instant even through IndexedDB.

const MANIFEST_PATH := "album.json"
const STAGING_PATH := "user://tmp_album.ccalbum"
const PACK_STAGING_PATH := "user://tmp_pack.ccalbum"
const ALBUM_EXTENSION := "ccalbum"


## An opened album: the parsed manifest plus a live reader for its assets.
## Call close() when done, or let it fall out of scope.
class LoadedAlbum extends RefCounted:
	var album: AlbumSchema.Album = null
	var problems: Array[AlbumValidator.Problem] = []
	var _zip: ZIPReader = null
	var _source: String = ""

	func is_ok() -> bool:
		return album != null and not AlbumValidator.has_errors(problems)

	## Raw bytes for an asset path from the manifest, e.g. a blur tier.
	func read_asset(path: String) -> PackedByteArray:
		if _zip == null:
			return PackedByteArray()
		if not _zip.file_exists(path):
			CCLog.error("album", "asset missing from archive: %s" % path)
			return PackedByteArray()
		return _zip.read_file(path)

	func has_asset(path: String) -> bool:
		return _zip != null and _zip.file_exists(path)

	## Safe to call more than once. ZIPReader also releases its handle when it
	## is freed, so an un-closed LoadedAlbum leaks nothing — this just makes
	## the release deterministic.
	func close() -> void:
		if _zip != null:
			_zip.close()
			_zip = null


## Load from raw bytes (the web path, and the desktop path too since it costs
## nothing at this size).
static func load_from_bytes(bytes: PackedByteArray) -> LoadedAlbum:
	if bytes.is_empty():
		return _failed("album file is empty")

	var f := FileAccess.open(STAGING_PATH, FileAccess.WRITE)
	if f == null:
		return _failed("cannot stage album to %s (error %d)"
			% [STAGING_PATH, FileAccess.get_open_error()])
	f.store_buffer(bytes)
	f.close()
	# Deliberately no sync_user_fs() here. This staging file is scratch — it
	# does not need to survive a page refresh — and AlbumIO must stay free of
	# any dependency on the Platform autoload, so that headless tools and the
	# test runner can use the data layer. Callers that need durability sync
	# their own writes.

	return load_from_path(STAGING_PATH)


static func load_from_path(path: String) -> LoadedAlbum:
	var zip := ZIPReader.new()
	var err := zip.open(path)
	if err != OK:
		return _failed("not a readable archive: %s (error %d)" % [path, err])

	if not zip.file_exists(MANIFEST_PATH):
		zip.close()
		return _failed("archive has no %s — is this a .ccalbum?" % MANIFEST_PATH)

	var manifest_bytes := zip.read_file(MANIFEST_PATH)
	var manifest_text := manifest_bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(manifest_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		zip.close()
		return _failed("%s is not valid JSON" % MANIFEST_PATH)

	var dict: Dictionary = parsed
	var migrate_problem := _migrate(dict)

	var result := LoadedAlbum.new()
	result._zip = zip
	result._source = path
	result.album = AlbumSchema.Album.from_dict(dict)

	if migrate_problem != null:
		result.problems.append(migrate_problem)

	result.problems.append_array(AlbumValidator.validate(result.album, false))
	_check_assets_present(result)

	var errors := AlbumValidator.count_of(result.problems, AlbumValidator.Severity.ERROR)
	var warnings := AlbumValidator.count_of(result.problems, AlbumValidator.Severity.WARNING)
	CCLog.info("album", "loaded '%s': %d photos, %d errors, %d warnings"
		% [result.album.title, result.album.photos.size(), errors, warnings])
	if errors > 0:
		CCLog.error("album", "problems:\n%s" % AlbumValidator.format_all(result.problems))

	return result


## Write an album to bytes. `assets` maps archive path -> file bytes, e.g.
## {"photos/p_001/full.webp": <PackedByteArray>, ...}.
## Returns an empty array on failure.
static func pack(album: AlbumSchema.Album, assets: Dictionary) -> PackedByteArray:
	var packer := ZIPPacker.new()
	var err := packer.open(PACK_STAGING_PATH)
	if err != OK:
		CCLog.error("album", "cannot open packer at %s (error %d)" % [PACK_STAGING_PATH, err])
		return PackedByteArray()

	album.schema_version = AlbumSchema.SCHEMA_VERSION
	var manifest := JSON.stringify(album.to_dict(), "  ")

	if not _write_entry(packer, MANIFEST_PATH, manifest.to_utf8_buffer()):
		packer.close()
		return PackedByteArray()

	for path in assets.keys():
		var data: PackedByteArray = assets[path]
		if data == null or data.is_empty():
			CCLog.warn("album", "skipping empty asset %s" % path)
			continue
		if not _write_entry(packer, String(path), data):
			packer.close()
			return PackedByteArray()

	packer.close()

	var f := FileAccess.open(PACK_STAGING_PATH, FileAccess.READ)
	if f == null:
		CCLog.error("album", "packed archive vanished")
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()

	CCLog.info("album", "packed '%s': %d assets, %d bytes"
		% [album.title, assets.size(), bytes.size()])
	return bytes


static func suggested_filename(album: AlbumSchema.Album) -> String:
	var base := album.title.strip_edges()
	if base.is_empty():
		base = "album"
	# Keep it safe for every filesystem and for an email attachment.
	var safe := ""
	for ch in base:
		safe += ch if ch.is_valid_identifier() or ch in " -_" else "_"
	safe = safe.strip_edges().replace(" ", "_")
	return "%s.%s" % [safe, ALBUM_EXTENSION]


# --- internals ---

static func _write_entry(packer: ZIPPacker, path: String, data: PackedByteArray) -> bool:
	var err := packer.start_file(path)
	if err != OK:
		CCLog.error("album", "start_file failed for %s (error %d)" % [path, err])
		return false
	err = packer.write_file(data)
	if err != OK:
		CCLog.error("album", "write_file failed for %s (error %d)" % [path, err])
		return false
	err = packer.close_file()
	if err != OK:
		CCLog.error("album", "close_file failed for %s (error %d)" % [path, err])
		return false
	return true


static func _failed(message: String) -> LoadedAlbum:
	var r := LoadedAlbum.new()
	r.problems.append(AlbumValidator.Problem.new(
		AlbumValidator.Severity.ERROR, "album", message))
	CCLog.error("album", message)
	return r


## Every asset the manifest promises must actually be in the archive. A
## manifest that references a missing blur tier would otherwise fail silently
## with an invisible photo halfway down the hall.
static func _check_assets_present(result: LoadedAlbum) -> void:
	if result.album == null:
		return
	for i in result.album.photos.size():
		var p := result.album.photos[i]
		var base := "photos[%d]" % i
		if not p.full_path.is_empty() and not result.has_asset(p.full_path):
			result.problems.append(AlbumValidator.Problem.new(
				AlbumValidator.Severity.ERROR, base + ".files.full",
				"archive is missing %s" % p.full_path, p.id))
		for t in p.blur_paths.size():
			var bp := p.blur_paths[t]
			if not bp.is_empty() and not result.has_asset(bp):
				result.problems.append(AlbumValidator.Problem.new(
					AlbumValidator.Severity.ERROR, "%s.files.blurTiers[%d]" % [base, t],
					"archive is missing %s" % bp, p.id))


## Migrate a manifest dict in place. Returns a Problem if the version cannot be
## handled, else null. Written now, while there is only one version, so the
## first real migration has somewhere to go.
static func _migrate(dict: Dictionary) -> AlbumValidator.Problem:
	var version := int(dict.get("schemaVersion", 0))

	if version == AlbumSchema.SCHEMA_VERSION:
		return null

	if version <= 0:
		return AlbumValidator.Problem.new(AlbumValidator.Severity.ERROR,
			"schemaVersion", "manifest does not declare a schema version")

	if version > AlbumSchema.SCHEMA_VERSION:
		return AlbumValidator.Problem.new(AlbumValidator.Severity.ERROR,
			"schemaVersion",
			"album is version %d; this build understands up to %d"
			% [version, AlbumSchema.SCHEMA_VERSION])

	# Future: chain migrations here, e.g.
	#   if version == 1: _v1_to_v2(dict); version = 2
	return AlbumValidator.Problem.new(AlbumValidator.Severity.ERROR,
		"schemaVersion", "no migration path from version %d" % version)

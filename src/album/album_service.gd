extends Node
## Autoload: AlbumService
##
## Owns the loaded album and its textures. With exactly ten photos there is no
## streaming, no eviction and no VRAM budget: all four blur tiers for all ten
## photos are about 600 KB of image data, so we decode them up front and keep
## them. Only the full-resolution images are deferred, one per reveal.

var loaded: AlbumIO.LoadedAlbum = null

## photo id -> Array[ImageTexture], index = tier
var _tier_textures: Dictionary = {}
## photo id -> ImageTexture
var _full_textures: Dictionary = {}


func has_album() -> bool:
	return loaded != null and loaded.is_ok()


func album() -> AlbumSchema.Album:
	return loaded.album if loaded != null else null


## Load from raw bytes and decode every blur tier. Returns true on success;
## on failure the problems are on `loaded.problems` and also emitted.
func load_album_bytes(bytes: PackedByteArray) -> bool:
	unload()

	var result := AlbumIO.load_from_bytes(bytes)
	loaded = result

	if not result.is_ok():
		EventBus.album_load_failed.emit(result.problems)
		return false

	_decode_all_tiers()
	GameState.reset_for_album(result.album.hung_photos().size())
	EventBus.album_loaded.emit(result.album)
	return true


## Start a fresh playthrough of whatever is already loaded. The loop is one
## ten-picture room and then back to the menu (plan §2.1), so "play again"
## means clearing the round state — not re-reading the ZIP and re-decoding
## forty images.
func reset_session() -> void:
	var count := AlbumSchema.PHOTOS_PER_ALBUM
	if has_album():
		count = album().hung_photos().size()
	GameState.reset_for_album(count)


func unload() -> void:
	if loaded != null:
		loaded.close()
	loaded = null
	_tier_textures.clear()
	_full_textures.clear()


## Texture for a photo at a blur tier. Tier is clamped into range, so callers
## can pass a tier that ran off the end without checking.
func tier_texture(photo_id: String, tier: int) -> ImageTexture:
	var arr: Array = _tier_textures.get(photo_id, [])
	if arr.is_empty():
		return null
	return arr[clampi(tier, 0, arr.size() - 1)]


## Full-resolution texture, decoded on first request. Call this one frame
## before the reveal animation so the ~40 ms decode is already paid for.
func full_texture(photo_id: String) -> ImageTexture:
	if _full_textures.has(photo_id):
		return _full_textures[photo_id]

	var photo := album().photo_by_id(photo_id) if album() != null else null
	if photo == null or loaded == null:
		return null

	var tex := _decode_texture(loaded.read_asset(photo.full_path),
		"%s/full" % photo_id)
	if tex != null:
		_full_textures[photo_id] = tex
	return tex


## Kick the full-res decode without using the result, so the reveal is smooth.
func prewarm_full(photo_id: String) -> void:
	full_texture(photo_id)


# --- internals ---

func _decode_all_tiers() -> void:
	var t0 := Time.get_ticks_msec()
	var decoded := 0

	for photo in loaded.album.photos:
		var textures: Array = []
		for i in photo.blur_paths.size():
			var tex := _decode_texture(loaded.read_asset(photo.blur_paths[i]),
				"%s/blur_%d" % [photo.id, i])
			if tex != null:
				textures.append(tex)
				decoded += 1
		_tier_textures[photo.id] = textures

	CCLog.info("album", "decoded %d blur tiers in %d ms"
		% [decoded, Time.get_ticks_msec() - t0])


func _decode_texture(bytes: PackedByteArray, label: String) -> ImageTexture:
	if bytes.is_empty():
		CCLog.error("album", "no bytes for %s" % label)
		return null

	var img := ImagePipeline.decode(bytes)
	if img == null:
		CCLog.error("album", "could not decode %s" % label)
		return null

	img.generate_mipmaps()

	# VRAM compression is a big win but browsers vary in what they accept, so
	# check the result and fall back rather than shipping a black frame.
	var mode := Image.COMPRESS_ETC2 if OS.has_feature("web") else Image.COMPRESS_S3TC
	var before := img.get_format()
	var err := img.compress(mode, Image.COMPRESS_SOURCE_SRGB)
	if err != OK or img.get_format() == before:
		# Uncompressed is correct, just heavier. At ten photos we can afford it.
		img = ImagePipeline.decode(bytes)
		if img == null:
			return null
		img.generate_mipmaps()

	return ImageTexture.create_from_image(img)

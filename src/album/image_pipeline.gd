class_name ImagePipeline
extends RefCounted
## Turns a source photo into the assets an album carries.
##
## The blur ladder is built out of RESOLUTION, not a CPU blur pass. A 64 px
## image stretched across a 1.5 m canvas is already fog, so each tier is just a
## Lanczos downscale — which runs in native code, costs nothing, and keeps the
## tier files tiny (2 KB for tier 0).
##
## The softening that turns bilinear upscale facets into a convincing haze
## happens on the GPU instead, in the frame shader, with a per-tier radius.
## This is a refinement on plan §4: same result, no GDScript pixel loops, and
## smaller files. What the plan warns against — blurring the FULL-RES image at
## runtime — we still never do, because at guess time the full-res texture is
## not even loaded.
##
## Tier sizes are long-edge pixels. Tier 0 is what she sees first.
const TIER_LONG_EDGES := [64, 128, 256, 512]
const FULL_LONG_EDGE := 2048
const THUMB_LONG_EDGE := 256

const FULL_WEBP_QUALITY := 0.86
const TIER_WEBP_QUALITY := 0.92   ## tiers are tiny; don't add compression mush
const THUMB_WEBP_QUALITY := 0.80


class ProcessedPhoto extends RefCounted:
	var ok: bool = false
	var error: String = ""
	var aspect: float = 1.0
	var source_width: int = 0
	var source_height: int = 0
	## archive path -> encoded WebP bytes
	var assets: Dictionary = {}
	## EXIF findings, for the editor to prefill with
	var exif_date: AlbumSchema.PhotoDate = null
	var exif_lat: float = NAN
	var exif_lon: float = NAN


## Decode a source image and produce every asset for one photo.
## `photo_id` decides the archive paths. `filename` is only used for the
## extension sniff and error messages.
static func process(bytes: PackedByteArray, filename: String,
		photo_id: String) -> ProcessedPhoto:
	var out := ProcessedPhoto.new()

	if bytes.is_empty():
		out.error = "file is empty"
		return out

	var img := decode(bytes, filename)
	if img == null:
		out.error = "could not decode %s" % filename
		return out

	# EXIF first: orientation is needed before we resize, and the date and GPS
	# are the editor's free prefill.
	var exif := ExifReader.read(bytes)
	if exif.has_date():
		out.exif_date = exif.to_photo_date()
	out.exif_lat = exif.lat
	out.exif_lon = exif.lon
	_apply_orientation(img, exif.orientation)

	out.source_width = img.get_width()
	out.source_height = img.get_height()
	if out.source_height <= 0:
		out.error = "decoded image has no height"
		return out
	out.aspect = float(out.source_width) / float(out.source_height)

	# Photos never need alpha, and RGB8 saves a quarter of the bytes.
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)

	var paths := AlbumSchema.Photo.default_paths(photo_id)

	var full := _resized(img, FULL_LONG_EDGE)
	var full_bytes := full.save_webp_to_buffer(true, FULL_WEBP_QUALITY)
	if full_bytes.is_empty():
		out.error = "WebP encode failed for full-resolution image"
		return out
	out.assets[paths["full"]] = full_bytes

	var tier_paths: Array = paths["blurTiers"]
	for i in TIER_LONG_EDGES.size():
		var tier := _resized(img, TIER_LONG_EDGES[i])
		var tier_bytes := tier.save_webp_to_buffer(true, TIER_WEBP_QUALITY)
		if tier_bytes.is_empty():
			out.error = "WebP encode failed for blur tier %d" % i
			return out
		out.assets[tier_paths[i]] = tier_bytes

	var thumb := _resized(img, THUMB_LONG_EDGE)
	out.assets[paths["thumb"]] = thumb.save_webp_to_buffer(true, THUMB_WEBP_QUALITY)

	out.ok = true
	return out


## Decode by magic bytes, ignoring the filename entirely.
##
## Browsers hand us whatever the user picked, and a .jpg that is really a PNG
## is common enough to matter — especially with scans, where whatever software
## digitised them may have renamed things freely. All three formats we accept
## have reliable magic, so content always wins over extension.
##
## Returns null for anything we do not recognise, without attempting
## speculative decodes: guessing produces a wall of engine errors for what is
## usually just a stray .txt in the user's photo folder.
static func decode(bytes: PackedByteArray, _filename: String = "") -> Image:
	var img := Image.new()
	var err := ERR_INVALID_DATA

	if _looks_like_png(bytes):
		err = img.load_png_from_buffer(bytes)
	elif _looks_like_jpeg(bytes):
		err = img.load_jpg_from_buffer(bytes)
	elif _looks_like_webp(bytes):
		err = img.load_webp_from_buffer(bytes)
	else:
		return null

	if err == OK and img.get_width() > 0:
		return img
	return null


## Scale so the long edge is `long_edge`, preserving aspect. Never upscales —
## a small scan stays small rather than being blown up into mush.
static func _resized(src: Image, long_edge: int) -> Image:
	var img := Image.new()
	img.copy_from(src)

	var w := img.get_width()
	var h := img.get_height()
	var current_long := maxi(w, h)
	if current_long <= long_edge:
		return img

	var scale := float(long_edge) / float(current_long)
	var nw := maxi(1, int(round(w * scale)))
	var nh := maxi(1, int(round(h * scale)))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return img


## EXIF orientation values 1..8. Applied before any resizing.
static func _apply_orientation(img: Image, orientation: int) -> void:
	match orientation:
		2:
			img.flip_x()
		3:
			img.rotate_180()
		4:
			img.flip_y()
		5:
			img.rotate_90(CLOCKWISE)
			img.flip_x()
		6:
			img.rotate_90(CLOCKWISE)
		7:
			img.rotate_90(COUNTERCLOCKWISE)
			img.flip_x()
		8:
			img.rotate_90(COUNTERCLOCKWISE)
		_:
			pass


static func _looks_like_png(b: PackedByteArray) -> bool:
	return b.size() > 8 and b[0] == 0x89 and b[1] == 0x50 and b[2] == 0x4E and b[3] == 0x47


static func _looks_like_jpeg(b: PackedByteArray) -> bool:
	return b.size() > 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF


static func _looks_like_webp(b: PackedByteArray) -> bool:
	if b.size() < 12:
		return false
	return b[0] == 0x52 and b[1] == 0x49 and b[2] == 0x46 and b[3] == 0x46 \
		and b[8] == 0x57 and b[9] == 0x45 and b[10] == 0x42 and b[11] == 0x50

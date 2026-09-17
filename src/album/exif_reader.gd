class_name ExifReader
extends RefCounted
## Minimal EXIF reader for JPEG files: capture date, GPS position, orientation.
##
## Godot has no EXIF support and GDScript has no package manager, so this is
## hand-rolled. It reads exactly the three things the editor prefills with and
## ignores everything else, which keeps it to one readable file.
##
## Scanned photographs — the common case for a sixty-year marriage — carry no
## EXIF at all. That is expected, not an error: read() returns an empty result
## and the author types the date in. EXIF is the pleasant surprise, not the
## happy path.
##
## Structure being walked:
##   JPEG segments -> APP1 ("Exif\0\0") -> TIFF header -> IFD0
##     IFD0  0x0112 orientation, 0x0132 DateTime
##           0x8769 -> Exif sub-IFD, 0x8825 -> GPS sub-IFD
##     Exif  0x9003 DateTimeOriginal, 0x9004 DateTimeDigitized
##     GPS   0x0001/2 latitude ref + value, 0x0003/4 longitude ref + value

# TIFF field types
const T_BYTE := 1
const T_ASCII := 2
const T_SHORT := 3
const T_LONG := 4
const T_RATIONAL := 5

const TYPE_SIZES := {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8}

# Tags
const TAG_ORIENTATION := 0x0112
const TAG_DATETIME := 0x0132
const TAG_EXIF_IFD := 0x8769
const TAG_GPS_IFD := 0x8825
const TAG_DATETIME_ORIGINAL := 0x9003
const TAG_DATETIME_DIGITIZED := 0x9004
const TAG_GPS_LAT_REF := 0x0001
const TAG_GPS_LAT := 0x0002
const TAG_GPS_LON_REF := 0x0003
const TAG_GPS_LON := 0x0004


class Result extends RefCounted:
	var orientation: int = 1
	var year: int = 0
	var month: int = 0
	var day: int = 0
	var lat: float = NAN
	var lon: float = NAN

	func has_date() -> bool:
		return year > 0

	func has_location() -> bool:
		return not (is_nan(lat) or is_nan(lon))

	func to_photo_date() -> AlbumSchema.PhotoDate:
		var d := AlbumSchema.PhotoDate.new()
		d.year = year
		d.month = month
		d.day = day
		return d


## Never throws and never logs an error for a file that simply has no EXIF.
static func read(bytes: PackedByteArray) -> Result:
	var out := Result.new()
	if bytes.size() < 4:
		return out

	var tiff_start := _find_exif_tiff_start(bytes)
	if tiff_start < 0:
		return out

	# Byte order mark, then the magic 42.
	if tiff_start + 8 > bytes.size():
		return out
	var b0 := bytes[tiff_start]
	var b1 := bytes[tiff_start + 1]
	var little := false
	if b0 == 0x49 and b1 == 0x49:      # "II"
		little = true
	elif b0 == 0x4D and b1 == 0x4D:    # "MM"
		little = false
	else:
		return out

	if _u16(bytes, tiff_start + 2, little) != 42:
		return out

	var ifd0_offset := _u32(bytes, tiff_start + 4, little)
	if ifd0_offset <= 0:
		return out

	var ifd0 := _read_ifd(bytes, tiff_start, tiff_start + ifd0_offset, little)
	if ifd0.is_empty():
		return out

	# --- orientation ---
	if ifd0.has(TAG_ORIENTATION):
		var o := _entry_ints(bytes, tiff_start, ifd0[TAG_ORIENTATION], little)
		if not o.is_empty():
			out.orientation = clampi(o[0], 1, 8)

	# --- date: prefer the moment the shutter fired ---
	var date_str := ""
	var exif_ptr := _pointer(bytes, tiff_start, ifd0, TAG_EXIF_IFD, little)
	if exif_ptr > 0:
		var exif_ifd := _read_ifd(bytes, tiff_start, tiff_start + exif_ptr, little)
		date_str = _entry_string(bytes, tiff_start, exif_ifd, TAG_DATETIME_ORIGINAL, little)
		if date_str.is_empty():
			date_str = _entry_string(bytes, tiff_start, exif_ifd, TAG_DATETIME_DIGITIZED, little)
	if date_str.is_empty():
		date_str = _entry_string(bytes, tiff_start, ifd0, TAG_DATETIME, little)
	_parse_exif_datetime(date_str, out)

	# --- GPS ---
	var gps_ptr := _pointer(bytes, tiff_start, ifd0, TAG_GPS_IFD, little)
	if gps_ptr > 0:
		var gps := _read_ifd(bytes, tiff_start, tiff_start + gps_ptr, little)
		out.lat = _gps_coord(bytes, tiff_start, gps, TAG_GPS_LAT, TAG_GPS_LAT_REF, "S", little)
		out.lon = _gps_coord(bytes, tiff_start, gps, TAG_GPS_LON, TAG_GPS_LON_REF, "W", little)
		# 0,0 in the Gulf of Guinea is what a camera writes when it had no fix.
		if out.has_location() and absf(out.lat) < 0.0001 and absf(out.lon) < 0.0001:
			out.lat = NAN
			out.lon = NAN

	return out


# --- JPEG segment walk ---

static func _find_exif_tiff_start(b: PackedByteArray) -> int:
	if not (b.size() > 3 and b[0] == 0xFF and b[1] == 0xD8):
		return -1   # not a JPEG; PNG/WebP EXIF is out of scope

	var i := 2
	while i + 4 <= b.size():
		if b[i] != 0xFF:
			# Not aligned on a marker — resync rather than give up, since some
			# cameras pad between segments.
			i += 1
			continue
		var marker := b[i + 1]
		if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
			i += 2
			continue
		if marker == 0xDA or marker == 0xD9:
			return -1   # start of scan / end of image: no EXIF before the pixels
		var seg_len := (b[i + 2] << 8) | b[i + 3]
		if seg_len < 2:
			return -1
		if marker == 0xE1:
			var data_start := i + 4
			if data_start + 6 <= b.size() \
					and b[data_start] == 0x45 and b[data_start + 1] == 0x78 \
					and b[data_start + 2] == 0x69 and b[data_start + 3] == 0x66 \
					and b[data_start + 4] == 0x00:
				return data_start + 6
		i += 2 + seg_len
	return -1


# --- IFD reading ---

## Returns {tag: {"type": int, "count": int, "value_offset": int}}.
static func _read_ifd(b: PackedByteArray, tiff_start: int, ifd_pos: int,
		little: bool) -> Dictionary:
	var out := {}
	if ifd_pos < 0 or ifd_pos + 2 > b.size():
		return out
	var count := _u16(b, ifd_pos, little)
	if count <= 0 or count > 4096:
		return out

	for n in count:
		var e := ifd_pos + 2 + n * 12
		if e + 12 > b.size():
			break
		out[_u16(b, e, little)] = {
			"type": _u16(b, e + 2, little),
			"count": _u32(b, e + 4, little),
			"value_offset": e + 8,
		}
	return out


## Absolute byte position of an entry's data, resolving the inline-vs-offset
## rule: values of 4 bytes or fewer live in the entry itself.
static func _data_pos(b: PackedByteArray, tiff_start: int, entry: Dictionary,
		little: bool) -> int:
	var type_size: int = TYPE_SIZES.get(int(entry["type"]), 1)
	var total: int = type_size * int(entry["count"])
	if total <= 4:
		return int(entry["value_offset"])
	return tiff_start + _u32(b, int(entry["value_offset"]), little)


static func _entry_ints(b: PackedByteArray, tiff_start: int, entry: Dictionary,
		little: bool) -> Array[int]:
	var out: Array[int] = []
	var pos := _data_pos(b, tiff_start, entry, little)
	var type: int = int(entry["type"])
	var count: int = mini(int(entry["count"]), 16)
	for i in count:
		match type:
			T_SHORT:
				if pos + i * 2 + 2 <= b.size():
					out.append(_u16(b, pos + i * 2, little))
			T_LONG:
				if pos + i * 4 + 4 <= b.size():
					out.append(_u32(b, pos + i * 4, little))
			T_BYTE:
				if pos + i < b.size():
					out.append(b[pos + i])
	return out


static func _entry_string(b: PackedByteArray, tiff_start: int, ifd: Dictionary,
		tag: int, little: bool) -> String:
	if not ifd.has(tag):
		return ""
	var entry: Dictionary = ifd[tag]
	if int(entry["type"]) != T_ASCII:
		return ""
	var pos := _data_pos(b, tiff_start, entry, little)
	var count: int = int(entry["count"])
	if pos < 0 or count <= 0 or pos + count > b.size():
		return ""
	var slice := b.slice(pos, pos + count)
	return slice.get_string_from_ascii().strip_escapes().strip_edges()


static func _pointer(b: PackedByteArray, tiff_start: int, ifd: Dictionary,
		tag: int, little: bool) -> int:
	if not ifd.has(tag):
		return -1
	var vals := _entry_ints(b, tiff_start, ifd[tag], little)
	return vals[0] if not vals.is_empty() else -1


static func _rationals(b: PackedByteArray, tiff_start: int, entry: Dictionary,
		little: bool) -> Array[float]:
	var out: Array[float] = []
	if int(entry["type"]) != T_RATIONAL:
		return out
	var pos := _data_pos(b, tiff_start, entry, little)
	var count: int = mini(int(entry["count"]), 8)
	for i in count:
		var p := pos + i * 8
		if p + 8 > b.size():
			break
		var num := _u32(b, p, little)
		var den := _u32(b, p + 4, little)
		out.append(0.0 if den == 0 else float(num) / float(den))
	return out


static func _gps_coord(b: PackedByteArray, tiff_start: int, gps: Dictionary,
		value_tag: int, ref_tag: int, negative_ref: String, little: bool) -> float:
	if not gps.has(value_tag):
		return NAN
	var parts := _rationals(b, tiff_start, gps[value_tag], little)
	if parts.size() < 2:
		return NAN

	var deg := parts[0]
	var minutes := parts[1]
	var seconds := parts[2] if parts.size() > 2 else 0.0
	var value := deg + minutes / 60.0 + seconds / 3600.0

	var ref := _entry_string(b, tiff_start, gps, ref_tag, little).to_upper()
	if ref.begins_with(negative_ref):
		value = -value

	if is_nan(value) or absf(value) > 180.0:
		return NAN
	return value


static func _parse_exif_datetime(s: String, out: Result) -> void:
	# "YYYY:MM:DD HH:MM:SS", sometimes with a blank or zeroed date.
	if s.length() < 10:
		return
	var date_part := s.substr(0, 10)
	var bits := date_part.split(":")
	if bits.size() < 3:
		bits = date_part.split("-")
	if bits.size() < 3:
		return
	var y := int(bits[0])
	var m := int(bits[1])
	var d := int(bits[2])
	if y < 1826 or y > 2200:
		return
	out.year = y
	out.month = m if m >= 1 and m <= 12 else 0
	out.day = d if d >= 1 and d <= 31 else 0


# --- byte readers ---

static func _u16(b: PackedByteArray, p: int, little: bool) -> int:
	if p + 2 > b.size() or p < 0:
		return 0
	return (b[p] | (b[p + 1] << 8)) if little else ((b[p] << 8) | b[p + 1])


static func _u32(b: PackedByteArray, p: int, little: bool) -> int:
	if p + 4 > b.size() or p < 0:
		return 0
	if little:
		return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)
	return (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]

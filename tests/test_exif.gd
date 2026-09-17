extends RefCounted
## EXIF reader. Builds real JPEG/TIFF byte layouts in memory rather than
## shipping binary fixtures, so the test documents the format it parses.

const FLORENCE_LAT := 43.7696
const FLORENCE_LON := 11.2558


static func run() -> TestFramework:
	var t := TestFramework.new("exif")

	# --- a full, well-formed little-endian EXIF block ---
	var le := _build_jpeg_with_exif(false, 6, 1978, 6, 15,
		[43.0, 46.0, 10.56], "N", [11.0, 15.0, 20.88], "E")
	var r := ExifReader.read(le)
	t.eq(r.orientation, 6, "little-endian orientation")
	t.eq(r.year, 1978, "little-endian year")
	t.eq(r.month, 6, "little-endian month")
	t.eq(r.day, 15, "little-endian day")
	t.close(r.lat, FLORENCE_LAT, 0.0002, "little-endian latitude")
	t.close(r.lon, FLORENCE_LON, 0.0002, "little-endian longitude")
	t.ok(r.has_date(), "reports having a date")
	t.ok(r.has_location(), "reports having a location")

	# --- the same data big-endian ("MM"), which older cameras write ---
	var be := _build_jpeg_with_exif(true, 1, 2004, 11, 2,
		[51.0, 30.0, 26.64], "N", [0.0, 7.0, 39.84], "W")
	var rb := ExifReader.read(be)
	t.eq(rb.orientation, 1, "big-endian orientation")
	t.eq(rb.year, 2004, "big-endian year")
	t.eq(rb.month, 11, "big-endian month")
	t.close(rb.lat, 51.5074, 0.0002, "big-endian latitude")
	# A western longitude must come back negative.
	t.close(rb.lon, -0.1278, 0.0002, "big-endian negative (west) longitude")
	t.ok(rb.lon < 0.0, "west longitude is negative")

	# --- southern hemisphere ---
	var south := _build_jpeg_with_exif(false, 1, 1999, 3, 8,
		[33.0, 52.0, 7.68], "S", [151.0, 12.0, 33.48], "E")
	var rs := ExifReader.read(south)
	t.ok(rs.lat < 0.0, "south latitude is negative")
	t.close(rs.lat, -33.8688, 0.0002, "south latitude value")

	# --- a scanned photo: JPEG with no EXIF at all. The common case. ---
	var bare := PackedByteArray([0xFF, 0xD8, 0xFF, 0xD9])
	var rn := ExifReader.read(bare)
	t.eq(rn.orientation, 1, "no EXIF defaults orientation to 1")
	t.ok(not rn.has_date(), "no EXIF means no date")
	t.ok(not rn.has_location(), "no EXIF means no location")

	# --- malformed input must never crash, only return empty ---
	for junk in [
		PackedByteArray(),
		PackedByteArray([0x00]),
		PackedByteArray([0xFF, 0xD8]),
		PackedByteArray([0x89, 0x50, 0x4E, 0x47]),                  # a PNG
		PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1, 0x00, 0x02]),      # truncated APP1
		PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1, 0xFF, 0xFF, 0x45, 0x78, 0x69, 0x66]),
	]:
		var rj := ExifReader.read(junk)
		t.ok(not rj.has_date(), "malformed input yields no date (%d bytes)" % junk.size())
		t.eq(rj.orientation, 1, "malformed input yields default orientation")

	# --- a truncated EXIF block: header promises data that is not there ---
	var truncated := le.slice(0, le.size() / 2)
	var rt := ExifReader.read(truncated)
	t.ok(rt != null, "truncated EXIF returns a result rather than crashing")

	# --- a camera with no GPS fix writes 0/0, which is not a real position ---
	var nofix := _build_jpeg_with_exif(false, 1, 2010, 1, 1,
		[0.0, 0.0, 0.0], "N", [0.0, 0.0, 0.0], "E")
	var rz := ExifReader.read(nofix)
	t.ok(not rz.has_location(), "0,0 is treated as no GPS fix, not the Gulf of Guinea")
	t.ok(rz.has_date(), "a no-fix photo still yields its date")

	# --- implausible dates are rejected rather than stored ---
	var bad_year := _build_jpeg_with_exif(false, 1, 1500, 6, 15,
		[43.0, 46.0, 10.56], "N", [11.0, 15.0, 20.88], "E")
	t.ok(not ExifReader.read(bad_year).has_date(), "year 1500 is rejected")

	# --- orientation is clamped into the legal 1..8 range ---
	var bad_orient := _build_jpeg_with_exif(false, 99, 1978, 6, 15,
		[43.0, 46.0, 10.56], "N", [11.0, 15.0, 20.88], "E")
	var ro := ExifReader.read(bad_orient)
	t.ok(ro.orientation >= 1 and ro.orientation <= 8, "orientation clamped to 1..8")

	# --- to_photo_date carries through ---
	var pd := r.to_photo_date()
	t.eq(pd.year, 1978, "to_photo_date year")
	t.eq(pd.month, 6, "to_photo_date month")
	t.eq(pd.label(), "15 June 1978", "date label reads naturally")

	return t


# ---------------------------------------------------------------------------
# Byte-level builders. The layout below is the actual EXIF-in-JPEG structure:
#
#   FFD8                          SOI
#   FFE1 <len> "Exif\0\0"         APP1
#     "II"|"MM" 002A <ifd0_off>   TIFF header (all later offsets relative here)
#     IFD0:  orientation, ExifIFD pointer, GPS IFD pointer
#     Exif:  DateTimeOriginal
#     GPS:   lat ref + lat, lon ref + lon
#   FFD9                          EOI
# ---------------------------------------------------------------------------

static func _build_jpeg_with_exif(big_endian: bool, orientation: int,
		year: int, month: int, day: int,
		lat_dms: Array, lat_ref: String,
		lon_dms: Array, lon_ref: String) -> PackedByteArray:

	# Fixed layout, computed once so the offsets below are readable.
	const IFD0_OFF := 8
	const EXIF_IFD_OFF := 50
	const DATETIME_OFF := 68
	const GPS_IFD_OFF := 88
	const LAT_VALUE_OFF := 150
	const LON_VALUE_OFF := 174

	var sp := StreamPeerBuffer.new()
	sp.big_endian = big_endian

	# TIFF header
	if big_endian:
		sp.put_u8(0x4D); sp.put_u8(0x4D)
	else:
		sp.put_u8(0x49); sp.put_u8(0x49)
	sp.put_u16(42)
	sp.put_u32(IFD0_OFF)

	# --- IFD0 (3 entries) ---
	sp.put_u16(3)
	_put_entry(sp, ExifReader.TAG_ORIENTATION, ExifReader.T_SHORT, 1, orientation, true)
	_put_entry(sp, ExifReader.TAG_EXIF_IFD, ExifReader.T_LONG, 1, EXIF_IFD_OFF, false)
	_put_entry(sp, ExifReader.TAG_GPS_IFD, ExifReader.T_LONG, 1, GPS_IFD_OFF, false)
	sp.put_u32(0)   # no IFD1

	# --- Exif sub-IFD (1 entry) ---
	_pad_to(sp, EXIF_IFD_OFF)
	sp.put_u16(1)
	_put_entry(sp, ExifReader.TAG_DATETIME_ORIGINAL, ExifReader.T_ASCII, 20,
		DATETIME_OFF, false)
	sp.put_u32(0)

	# --- the date string, 19 characters plus a NUL ---
	_pad_to(sp, DATETIME_OFF)
	var stamp := "%04d:%02d:%02d 12:30:00" % [year, month, day]
	for i in 19:
		sp.put_u8(stamp.unicode_at(i) if i < stamp.length() else 0x20)
	sp.put_u8(0)

	# --- GPS sub-IFD (4 entries) ---
	_pad_to(sp, GPS_IFD_OFF)
	sp.put_u16(4)
	_put_ascii_inline(sp, ExifReader.TAG_GPS_LAT_REF, lat_ref)
	_put_entry(sp, ExifReader.TAG_GPS_LAT, ExifReader.T_RATIONAL, 3,
		LAT_VALUE_OFF, false)
	_put_ascii_inline(sp, ExifReader.TAG_GPS_LON_REF, lon_ref)
	_put_entry(sp, ExifReader.TAG_GPS_LON, ExifReader.T_RATIONAL, 3,
		LON_VALUE_OFF, false)
	sp.put_u32(0)

	# --- the coordinate rationals ---
	_pad_to(sp, LAT_VALUE_OFF)
	_put_dms(sp, lat_dms)
	_pad_to(sp, LON_VALUE_OFF)
	_put_dms(sp, lon_dms)

	var tiff := sp.data_array

	# Wrap in a JPEG. APP1 length counts itself plus "Exif\0\0" plus the TIFF.
	var out := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE1])
	var seg_len := 2 + 6 + tiff.size()
	out.append((seg_len >> 8) & 0xFF)
	out.append(seg_len & 0xFF)
	out.append_array("Exif".to_ascii_buffer())
	out.append(0x00)
	out.append(0x00)
	out.append_array(tiff)
	out.append(0xFF)
	out.append(0xD9)
	return out


## One 12-byte IFD entry. `inline` means the value sits in the entry itself,
## which is the rule for anything four bytes or smaller.
static func _put_entry(sp: StreamPeerBuffer, tag: int, type: int, count: int,
		value: int, inline: bool) -> void:
	sp.put_u16(tag)
	sp.put_u16(type)
	sp.put_u32(count)
	if inline and type == ExifReader.T_SHORT:
		# A SHORT occupies the first two bytes of the value field; the byte
		# order of those two bytes follows the file's byte order.
		sp.put_u16(value)
		sp.put_u16(0)
	else:
		sp.put_u32(value)


static func _put_ascii_inline(sp: StreamPeerBuffer, tag: int, s: String) -> void:
	sp.put_u16(tag)
	sp.put_u16(ExifReader.T_ASCII)
	sp.put_u32(2)
	sp.put_u8(s.unicode_at(0) if s.length() > 0 else 0x4E)
	sp.put_u8(0)
	sp.put_u8(0)
	sp.put_u8(0)


## Degrees, minutes and seconds as three RATIONALs. Seconds carry two decimal
## places, which is how cameras actually write them.
static func _put_dms(sp: StreamPeerBuffer, dms: Array) -> void:
	sp.put_u32(int(dms[0])); sp.put_u32(1)
	sp.put_u32(int(dms[1])); sp.put_u32(1)
	sp.put_u32(int(round(float(dms[2]) * 100.0))); sp.put_u32(100)


static func _pad_to(sp: StreamPeerBuffer, target: int) -> void:
	while sp.get_position() < target:
		sp.put_u8(0)

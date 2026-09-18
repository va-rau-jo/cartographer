class_name AlbumSchema
extends RefCounted
## Typed model for a .ccalbum manifest, plus JSON (de)serialisation.
##
## This is the keystone of the project: the 3D game, the editor and the bake
## pipeline all bind to these shapes. Two rules keep it stable:
##
##   * SCHEMA_VERSION is checked on load and migrations go in album_io.gd.
##   * Never remove a field. Deprecate it and stop writing it.
##
## from_dict() is deliberately permissive — it fills defaults and never throws.
## Deciding whether a manifest is *usable* is album_validator.gd's job, so that
## the editor can show the author a list of everything wrong at once.

const SCHEMA_VERSION := 1
const PHOTOS_PER_ALBUM := 10
const BLUR_TIER_COUNT := 4

## The calendar dial's default ends, used when the author has not set their own
## and the photographs cannot say. 1980 to this year: a span an old couple's
## photographs actually live in, and one nobody has to scroll through the 1920s
## to reach. See Album.guess_year_range.
const DIAL_DEFAULT_MIN := 1980
## The narrowest the dial may be when it is worked out from the photographs.
## Ten photographs that all carry the same year — a folder of scans stamped
## with the day they were scanned — must not become a ten-year dial.
const DIAL_MIN_SPAN := 30
## Nothing before this was photographed, and nothing after it has happened.
const DIAL_FLOOR := 1826


## This year, as the calendar knows it. Wrapped so the dial and the validator
## agree, and so a test can reason about it.
static func current_year() -> int:
	return int(Time.get_date_dict_from_system(true).get("year",
		DIAL_DEFAULT_MIN))

enum DatePrecision { DAY, MONTH, YEAR, DECADE }

const DATE_PRECISION_NAMES := {
	DatePrecision.DAY: "day",
	DatePrecision.MONTH: "month",
	DatePrecision.YEAR: "year",
	DatePrecision.DECADE: "decade",
}


static func precision_from_string(s: String) -> DatePrecision:
	match s.to_lower():
		"day": return DatePrecision.DAY
		"month": return DatePrecision.MONTH
		"year": return DatePrecision.YEAR
		"decade": return DatePrecision.DECADE
	return DatePrecision.YEAR


static func precision_to_string(p: DatePrecision) -> String:
	return DATE_PRECISION_NAMES.get(p, "year")


# ---------------------------------------------------------------- PhotoDate

class PhotoDate extends RefCounted:
	var year: int = 0
	var month: int = 0   ## 0 = unknown
	var day: int = 0     ## 0 = unknown

	static func from_dict(d: Dictionary) -> PhotoDate:
		var pd := PhotoDate.new()
		pd.year = int(d.get("year", 0))
		pd.month = int(d.get("month", 0)) if d.get("month") != null else 0
		pd.day = int(d.get("day", 0)) if d.get("day") != null else 0
		return pd

	func to_dict() -> Dictionary:
		return {
			"year": year,
			"month": month if month > 0 else null,
			"day": day if day > 0 else null,
		}

	func is_set() -> bool:
		return year > 0

	## Human label at the precision actually available.
	func label() -> String:
		if year <= 0:
			return "unknown"
		if month > 0 and day > 0:
			return "%d %s %d" % [day, _month_name(month), year]
		if month > 0:
			return "%s %d" % [_month_name(month), year]
		return str(year)

	func _month_name(m: int) -> String:
		const NAMES := ["January", "February", "March", "April", "May", "June",
			"July", "August", "September", "October", "November", "December"]
		return NAMES[clampi(m - 1, 0, 11)]


# ------------------------------------------------------------------- Truth

class Truth extends RefCounted:
	var lat: float = NAN
	var lon: float = NAN
	var place_label: String = ""
	var country_code: String = ""
	var region: String = ""
	## Radius within which a guess scores as exact. Lets a photo say
	## "anywhere in this city counts" rather than punishing a 3 km miss.
	var location_precision_km: float = 2.0
	var date := PhotoDate.new()
	var date_precision: DatePrecision = DatePrecision.YEAR

	static func from_dict(d: Dictionary) -> Truth:
		var t := Truth.new()
		t.lat = float(d.get("lat", NAN)) if d.get("lat") != null else NAN
		t.lon = float(d.get("lon", NAN)) if d.get("lon") != null else NAN
		t.place_label = str(d.get("placeLabel", ""))
		var admin: Dictionary = d.get("admin", {})
		t.country_code = str(admin.get("country", ""))
		t.region = str(admin.get("region", ""))
		t.location_precision_km = float(d.get("locationPrecisionKm", 2.0))
		t.date = PhotoDate.from_dict(d.get("date", {}))
		t.date_precision = AlbumSchema.precision_from_string(str(d.get("datePrecision", "year")))
		return t

	func to_dict() -> Dictionary:
		return {
			"lat": null if is_nan(lat) else lat,
			"lon": null if is_nan(lon) else lon,
			"placeLabel": place_label,
			"admin": {"country": country_code, "region": region},
			"locationPrecisionKm": location_precision_km,
			"date": date.to_dict(),
			"datePrecision": AlbumSchema.precision_to_string(date_precision),
		}

	func has_location() -> bool:
		return not (is_nan(lat) or is_nan(lon))


# ----------------------------------------------------------------- Content

class Content extends RefCounted:
	var title: String = ""
	var description: String = ""
	var people: PackedStringArray = PackedStringArray()
	var tags: PackedStringArray = PackedStringArray()
	## Author's own reference. NEVER RENDERED IN GAME — not in the HUD, not in
	## a tooltip, not in the results screen. It exists so the author can keep
	## notes without them leaking into the gift.
	var private_note: String = ""

	static func from_dict(d: Dictionary) -> Content:
		var c := Content.new()
		c.title = str(d.get("title", ""))
		c.description = str(d.get("description", ""))
		c.people = PackedStringArray(d.get("people", []))
		c.tags = PackedStringArray(d.get("tags", []))
		c.private_note = str(d.get("privateNote", ""))
		return c

	func to_dict() -> Dictionary:
		return {
			"title": title,
			"description": description,
			"people": Array(people),
			"tags": Array(tags),
			"privateNote": private_note,
		}


# ------------------------------------------------------------- CuratorLines

class CuratorLines extends RefCounted:
	## hints[0..2] — tier 1 sensory only, tier 2 region/country, tier 3 names it.
	## Monotonic by construction; see plan §8.3.
	var hints: PackedStringArray = PackedStringArray()
	var idle_barks: PackedStringArray = PackedStringArray()
	var wrong_guess_far: PackedStringArray = PackedStringArray()
	var wrong_guess_near: PackedStringArray = PackedStringArray()
	var reveal_monologue: String = ""
	var bake_model: String = ""
	var baked_utc: String = ""
	var approved_by_author: bool = false

	static func from_dict(d: Dictionary) -> CuratorLines:
		var c := CuratorLines.new()
		for h in d.get("hints", []):
			if typeof(h) == TYPE_DICTIONARY:
				c.hints.append(str(h.get("text", "")))
			else:
				c.hints.append(str(h))
		c.idle_barks = PackedStringArray(d.get("idleBarks", []))
		c.wrong_guess_far = PackedStringArray(d.get("wrongGuessFar", []))
		c.wrong_guess_near = PackedStringArray(d.get("wrongGuessNear", []))
		c.reveal_monologue = str(d.get("revealMonologue", ""))
		var bake: Dictionary = d.get("bake", {})
		c.bake_model = str(bake.get("model", ""))
		c.baked_utc = str(bake.get("bakedUtc", ""))
		c.approved_by_author = bool(bake.get("approvedByAuthor", false))
		return c

	func to_dict() -> Dictionary:
		var hint_dicts: Array = []
		for i in hints.size():
			hint_dicts.append({"tier": i + 1, "text": hints[i]})
		return {
			"hints": hint_dicts,
			"idleBarks": Array(idle_barks),
			"wrongGuessFar": Array(wrong_guess_far),
			"wrongGuessNear": Array(wrong_guess_near),
			"revealMonologue": reveal_monologue,
			"bake": {
				"model": bake_model,
				"bakedUtc": baked_utc,
				"approvedByAuthor": approved_by_author,
			},
		}

	## Hint text for tier 1..3, falling back down the ladder then to the place
	## label, so a half-baked album still plays.
	func hint_for_tier(tier: int, fallback_place: String) -> String:
		var idx := tier - 1
		if idx >= 0 and idx < hints.size() and not hints[idx].is_empty():
			return hints[idx]
		for i in range(mini(idx, hints.size() - 1), -1, -1):
			if not hints[i].is_empty():
				return hints[i]
		return fallback_place


# ------------------------------------------------------------------- Photo

class Photo extends RefCounted:
	var id: String = ""
	var full_path: String = ""
	var blur_paths: PackedStringArray = PackedStringArray()
	var thumb_path: String = ""
	## width / height of the source image. Drives the frame's mat window so
	## mixed portrait/landscape photos hang in identical frames (plan §4.3).
	var aspect: float = 1.0
	var truth := Truth.new()
	var content := Content.new()
	var curator := CuratorLines.new()

	static func from_dict(d: Dictionary) -> Photo:
		var p := Photo.new()
		p.id = str(d.get("id", ""))
		var files: Dictionary = d.get("files", {})
		p.full_path = str(files.get("full", ""))
		p.blur_paths = PackedStringArray(files.get("blurTiers", []))
		p.thumb_path = str(files.get("thumb", ""))
		p.aspect = float(d.get("aspect", 1.0))
		p.truth = Truth.from_dict(d.get("truth", {}))
		p.content = Content.from_dict(d.get("content", {}))
		p.curator = CuratorLines.from_dict(d.get("curatorLines", {}))
		return p

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"files": {
				"full": full_path,
				"blurTiers": Array(blur_paths),
				"thumb": thumb_path,
			},
			"aspect": aspect,
			"truth": truth.to_dict(),
			"content": content.to_dict(),
			"curatorLines": curator.to_dict(),
		}

	## Default asset paths for a given id, so the editor and the packer agree.
	static func default_paths(photo_id: String) -> Dictionary:
		var blurs: Array = []
		for i in AlbumSchema.BLUR_TIER_COUNT:
			blurs.append("photos/%s/blur_%d.webp" % [photo_id, i])
		return {
			"full": "photos/%s/full.webp" % photo_id,
			"blurTiers": blurs,
			"thumb": "photos/%s/thumb.webp" % photo_id,
		}


# ------------------------------------------------------------------ Scoring

class ScoringConfig extends RefCounted:
	var max_distance_score: float = 5000.0
	var max_date_score: float = 2000.0
	var distance_half_life_km: float = 250.0
	var unblur_cost_fraction: float = 0.20
	var hint_costs: PackedFloat32Array = PackedFloat32Array([0.10, 0.20, 0.35])
	## Cap on total spend. A player who took every hint and still got it right
	## must not score zero — see plan §7.2.
	var max_spent_fraction: float = 0.85

	static func from_dict(d: Dictionary) -> ScoringConfig:
		var s := ScoringConfig.new()
		s.max_distance_score = float(d.get("maxDistanceScore", 5000.0))
		s.max_date_score = float(d.get("maxDateScore", 2000.0))
		s.distance_half_life_km = float(d.get("distanceHalfLifeKm", 250.0))
		s.unblur_cost_fraction = float(d.get("unblurCostFraction", 0.20))
		if d.has("hintCosts"):
			s.hint_costs = PackedFloat32Array(d.get("hintCosts"))
		s.max_spent_fraction = float(d.get("maxSpentFraction", 0.85))
		return s

	func to_dict() -> Dictionary:
		return {
			"maxDistanceScore": max_distance_score,
			"maxDateScore": max_date_score,
			"distanceHalfLifeKm": distance_half_life_km,
			"unblurCostFraction": unblur_cost_fraction,
			"hintCosts": Array(hint_costs),
			"maxSpentFraction": max_spent_fraction,
		}

	func hint_cost(tier: int) -> float:
		var idx := tier - 1
		if idx < 0 or idx >= hint_costs.size():
			return 0.0
		return hint_costs[idx]

	func max_round_score() -> float:
		return max_distance_score + max_date_score


# ------------------------------------------------------------------- Album

class Album extends RefCounted:
	var schema_version: int = AlbumSchema.SCHEMA_VERSION
	var album_id: String = ""
	var title: String = ""
	var author_note: String = ""
	var created_utc: String = ""
	var cover_photo_id: String = ""

	var curator_voice_name: String = ""
	## He should use her name. Small field, large effect.
	var curator_player_name: String = ""
	var curator_style: String = ""
	## The one thing he says at the end, before the hug. Left empty by default
	## and never generated: the last line of someone's gift is the author's to
	## write, and no line at all is better than a line he would not have said.
	var closing_line: String = ""

	## The ends of the calendar dial she guesses with. Zero means "work it out
	## from the photographs", which is the default and is usually right; set
	## them when the album's own range would give the answer away, or when a
	## lifetime of dates should be on the dial whatever these ten happen to
	## cover. See guess_year_range().
	var guess_year_min: int = 0
	var guess_year_max: int = 0

	var scoring := ScoringConfig.new()
	## Wall order down the hallway. Dramatic, not chronological: open warm,
	## close with the one that hurts.
	var hang_order: PackedStringArray = PackedStringArray()
	var photos: Array[Photo] = []

	static func from_dict(d: Dictionary) -> Album:
		var a := Album.new()
		a.schema_version = int(d.get("schemaVersion", 0))
		a.album_id = str(d.get("albumId", ""))
		a.title = str(d.get("title", ""))
		a.author_note = str(d.get("authorNote", ""))
		a.created_utc = str(d.get("createdUtc", ""))
		a.cover_photo_id = str(d.get("coverPhotoId", ""))

		var cur: Dictionary = d.get("curator", {})
		a.curator_voice_name = str(cur.get("voiceName", ""))
		a.curator_player_name = str(cur.get("playerName", ""))
		a.curator_style = str(cur.get("style", ""))
		a.closing_line = str(cur.get("closingLine", ""))

		var guessing: Dictionary = d.get("guessing", {})
		a.guess_year_min = int(guessing.get("yearMin", 0))
		a.guess_year_max = int(guessing.get("yearMax", 0))

		a.scoring = ScoringConfig.from_dict(d.get("scoring", {}))
		a.hang_order = PackedStringArray(d.get("hangOrder", []))

		for pd in d.get("photos", []):
			if typeof(pd) == TYPE_DICTIONARY:
				a.photos.append(Photo.from_dict(pd))
		return a

	func to_dict() -> Dictionary:
		var photo_dicts: Array = []
		for p in photos:
			photo_dicts.append(p.to_dict())
		return {
			"schemaVersion": schema_version,
			"albumId": album_id,
			"title": title,
			"authorNote": author_note,
			"createdUtc": created_utc,
			"coverPhotoId": cover_photo_id,
			"curator": {
				"voiceName": curator_voice_name,
				"playerName": curator_player_name,
				"style": curator_style,
				"closingLine": closing_line,
			},
			"guessing": {
				"yearMin": guess_year_min,
				"yearMax": guess_year_max,
			},
			"scoring": scoring.to_dict(),
			"hangOrder": Array(hang_order),
			"photos": photo_dicts,
		}

	## The dial's ends, as the guess panel should show them: the author's own
	## values where they gave any, and otherwise a padded span around the
	## photographs' own dates.
	##
	## The padding matters. Without it the earliest and latest photographs sit
	## exactly at the ends of the dial, which tells her their dates for free.
	func guess_year_range() -> Vector2i:
		var lo := guess_year_min
		var hi := guess_year_max
		var this_year := AlbumSchema.current_year()

		var lo_is_mine := lo > 0
		var hi_is_mine := hi > 0

		if lo <= 0 or hi <= 0:
			var found_lo := 9999
			var found_hi := 0
			for p in photos:
				if not p.truth.date.is_set():
					continue
				found_lo = mini(found_lo, p.truth.date.year)
				found_hi = maxi(found_hi, p.truth.date.year)
			if found_lo > found_hi:
				# Nothing dated at all. A lifetime, ending now: a dial running
				# to 2040 spends a quarter of its travel on years that have not
				# happened, and one starting in 1920 on years before the two of
				# them.
				found_lo = DIAL_DEFAULT_MIN
				found_hi = this_year
			if lo <= 0:
				lo = (found_lo / 10) * 10 - 10
			if hi <= 0:
				# Padded past the latest photograph, but never into the future:
				# scans and phone exports are full of upload dates, and one
				# photograph stamped this year used to drag the whole dial
				# forward to 2040.
				hi = mini(((found_hi / 10) + 1) * 10 + 10, this_year)

			# A dial nobody could lose on is not a dial. Photographs that all
			# carry the same wrong year — a folder of scans, say — would
			# otherwise give her a ten-year range. Only an end the author left
			# to us is moved: an author who said "start at 2010" meant it.
			if hi - lo < DIAL_MIN_SPAN:
				if not lo_is_mine:
					lo = hi - DIAL_MIN_SPAN
				elif not hi_is_mine:
					hi = lo + DIAL_MIN_SPAN

		# Photography's own span, and then a sane ordering.
		lo = clampi(lo, 1826, 2100)
		hi = clampi(hi, 1826, 2100)
		if hi <= lo:
			hi = lo + 10
		return Vector2i(lo, hi)


	func photo_by_id(photo_id: String) -> Photo:
		for p in photos:
			if p.id == photo_id:
				return p
		return null

	## Photos in wall order. Any photo missing from hang_order is appended in
	## declaration order, so a hand-written manifest without hangOrder works.
	func hung_photos() -> Array[Photo]:
		var out: Array[Photo] = []
		var seen := {}
		for pid in hang_order:
			var p := photo_by_id(pid)
			if p != null and not seen.has(pid):
				out.append(p)
				seen[pid] = true
		for p in photos:
			if not seen.has(p.id):
				out.append(p)
				seen[p.id] = true
		return out

	static func create_empty(album_title: String = "Untitled") -> Album:
		var a := Album.new()
		a.schema_version = AlbumSchema.SCHEMA_VERSION
		a.album_id = _uuid4()
		a.title = album_title
		a.created_utc = Time.get_datetime_string_from_system(true) + "Z"
		return a

	static func _uuid4() -> String:
		var b := PackedByteArray()
		b.resize(16)
		for i in 16:
			b[i] = randi() % 256
		b[6] = (b[6] & 0x0f) | 0x40
		b[8] = (b[8] & 0x3f) | 0x80
		var hex := b.hex_encode()
		return "%s-%s-%s-%s-%s" % [
			hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4),
			hex.substr(16, 4), hex.substr(20, 12)]

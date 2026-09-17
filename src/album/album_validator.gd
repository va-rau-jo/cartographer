class_name AlbumValidator
extends RefCounted
## Validates an Album and returns EVERY problem, not just the first.
##
## The editor shows this list with jump-to-photo, so an author fixes ten things
## in one pass rather than playing whack-a-mole. Severity decides what blocks:
##
##   ERROR   — album cannot be played or exported.
##   WARNING — playable, but the gift is worse for it. Export warns loudly.
##   NOTE    — worth knowing. Never blocks anything.

enum Severity { NOTE, WARNING, ERROR }


class Problem extends RefCounted:
	var severity: Severity = Severity.ERROR
	var field: String = ""        ## dotted path, e.g. "photos[2].truth.lat"
	var photo_id: String = ""     ## "" for album-level problems
	var message: String = ""

	func _init(sev: Severity = Severity.ERROR, fld: String = "",
			msg: String = "", pid: String = "") -> void:
		severity = sev
		field = fld
		message = msg
		photo_id = pid

	func _to_string() -> String:
		const NAMES := ["NOTE", "WARN", "ERROR"]
		return "[%s] %s: %s" % [NAMES[severity], field, message]


## Set `for_export` when the author is exporting rather than the game loading:
## it adds the stricter checks (exactly ten photos, curator lines approved)
## that a hand-written test album is allowed to skip.
static func validate(album: AlbumSchema.Album, for_export: bool = false) -> Array[Problem]:
	var problems: Array[Problem] = []

	if album == null:
		problems.append(Problem.new(Severity.ERROR, "album", "manifest is missing or unparseable"))
		return problems

	_check_album_level(album, for_export, problems)
	_check_photos(album, for_export, problems)
	_check_hang_order(album, problems)

	return problems


static func has_errors(problems: Array[Problem]) -> bool:
	for p in problems:
		if p.severity == Severity.ERROR:
			return true
	return false


static func count_of(problems: Array[Problem], sev: Severity) -> int:
	var n := 0
	for p in problems:
		if p.severity == sev:
			n += 1
	return n


static func format_all(problems: Array[Problem]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for p in problems:
		lines.append(str(p))
	return "\n".join(lines)


# --- internals ---

static func _check_album_level(album: AlbumSchema.Album, for_export: bool,
		out: Array[Problem]) -> void:
	if album.schema_version <= 0:
		out.append(Problem.new(Severity.ERROR, "schemaVersion",
			"missing; cannot tell which format this album is"))
	elif album.schema_version > AlbumSchema.SCHEMA_VERSION:
		out.append(Problem.new(Severity.ERROR, "schemaVersion",
			"album is version %d but this build understands up to %d — update the game"
			% [album.schema_version, AlbumSchema.SCHEMA_VERSION]))

	if album.album_id.is_empty():
		out.append(Problem.new(Severity.ERROR, "albumId", "missing"))

	if album.title.strip_edges().is_empty():
		out.append(Problem.new(Severity.WARNING, "title",
			"album has no title; the menu will look unfinished"))

	if album.curator_player_name.strip_edges().is_empty():
		out.append(Problem.new(Severity.WARNING, "curator.playerName",
			"he will not be able to use her name, which costs more warmth than it looks like"))

	if album.curator_voice_name.strip_edges().is_empty():
		out.append(Problem.new(Severity.NOTE, "curator.voiceName",
			"no name for the husband; bubbles will be unattributed"))

	var cfg := album.scoring
	if cfg.distance_half_life_km <= 0.0:
		out.append(Problem.new(Severity.ERROR, "scoring.distanceHalfLifeKm",
			"must be greater than zero"))
	if cfg.max_spent_fraction >= 1.0:
		out.append(Problem.new(Severity.ERROR, "scoring.maxSpentFraction",
			"must be below 1.0, or a fully-assisted correct guess scores nothing"))
	if cfg.hint_costs.size() < 3:
		out.append(Problem.new(Severity.WARNING, "scoring.hintCosts",
			"expected 3 costs for the 3 hint tiers, found %d" % cfg.hint_costs.size()))

	if for_export and album.photos.size() != AlbumSchema.PHOTOS_PER_ALBUM:
		out.append(Problem.new(Severity.ERROR, "photos",
			"an album is exactly %d photos; this one has %d"
			% [AlbumSchema.PHOTOS_PER_ALBUM, album.photos.size()]))

	if album.photos.is_empty():
		out.append(Problem.new(Severity.ERROR, "photos", "album contains no photos"))

	if not album.cover_photo_id.is_empty() and album.photo_by_id(album.cover_photo_id) == null:
		out.append(Problem.new(Severity.WARNING, "coverPhotoId",
			"points at '%s', which is not in this album" % album.cover_photo_id))


static func _check_photos(album: AlbumSchema.Album, for_export: bool,
		out: Array[Problem]) -> void:
	var seen_ids := {}

	for i in album.photos.size():
		var p := album.photos[i]
		var base := "photos[%d]" % i
		var pid := p.id

		if pid.is_empty():
			out.append(Problem.new(Severity.ERROR, base + ".id", "missing", pid))
		elif seen_ids.has(pid):
			out.append(Problem.new(Severity.ERROR, base + ".id",
				"duplicate id '%s'" % pid, pid))
		else:
			seen_ids[pid] = true

		# --- files ---
		if p.full_path.is_empty():
			out.append(Problem.new(Severity.ERROR, base + ".files.full",
				"no full-resolution image", pid))
		if p.blur_paths.size() != AlbumSchema.BLUR_TIER_COUNT:
			out.append(Problem.new(Severity.ERROR, base + ".files.blurTiers",
				"expected %d blur tiers, found %d"
				% [AlbumSchema.BLUR_TIER_COUNT, p.blur_paths.size()], pid))
		if p.aspect <= 0.0 or is_nan(p.aspect):
			out.append(Problem.new(Severity.ERROR, base + ".aspect",
				"must be a positive ratio; the frame mat is cut from it", pid))
		elif p.aspect > 4.0 or p.aspect < 0.25:
			out.append(Problem.new(Severity.WARNING, base + ".aspect",
				"extreme aspect %.2f will be clamped in the frame" % p.aspect, pid))

		# --- truth: the answers. hard requirements. ---
		var t := p.truth
		if not Geo.is_valid_lat(t.lat):
			out.append(Problem.new(Severity.ERROR, base + ".truth.lat",
				"missing or out of range; there is nothing to guess", pid))
		if not Geo.is_valid_lon(t.lon):
			out.append(Problem.new(Severity.ERROR, base + ".truth.lon",
				"missing or out of range; there is nothing to guess", pid))
		if not t.date.is_set():
			out.append(Problem.new(Severity.ERROR, base + ".truth.date.year",
				"missing; the calendar half of the round cannot be scored", pid))
		else:
			var this_year: int = int(Time.get_date_dict_from_system(true).get("year", 2026))
			if t.date.year < 1826 or t.date.year > this_year:
				out.append(Problem.new(Severity.WARNING, base + ".truth.date.year",
					"%d looks wrong" % t.date.year, pid))
		if t.date_precision == AlbumSchema.DatePrecision.MONTH and t.date.month <= 0:
			out.append(Problem.new(Severity.ERROR, base + ".truth.date.month",
				"precision is 'month' but no month is set", pid))
		if t.date_precision == AlbumSchema.DatePrecision.DAY and t.date.day <= 0:
			out.append(Problem.new(Severity.ERROR, base + ".truth.date.day",
				"precision is 'day' but no day is set", pid))
		if t.place_label.strip_edges().is_empty():
			out.append(Problem.new(Severity.WARNING, base + ".truth.placeLabel",
				"no readable place name; the reveal and the hint fallback both need one", pid))
		if t.location_precision_km < 0.0:
			out.append(Problem.new(Severity.ERROR, base + ".truth.locationPrecisionKm",
				"cannot be negative", pid))

		# --- content ---
		if p.content.description.strip_edges().is_empty():
			out.append(Problem.new(Severity.WARNING, base + ".content.description",
				"empty; this is the source material for the curator's lines", pid))

		# --- curator lines ---
		_check_curator(p, base, for_export, out)


static func _check_curator(p: AlbumSchema.Photo, base: String, for_export: bool,
		out: Array[Problem]) -> void:
	var c := p.curator
	var pid := p.id

	if c.hints.size() < 3:
		out.append(Problem.new(Severity.WARNING, base + ".curatorLines.hints",
			"only %d of 3 hint tiers; missing tiers fall back down the ladder"
			% c.hints.size(), pid))

	# The ladder must not leak the answer early. This cannot be checked
	# perfectly, but the obvious failure — tier 1 naming the place — is worth
	# catching, because with ten rounds one spoiled hint is 10% of the game.
	if c.hints.size() >= 1 and not p.truth.place_label.is_empty():
		var place_parts := p.truth.place_label.split(",")
		var city := place_parts[0].strip_edges()
		if city.length() >= 4 and c.hints[0].to_lower().contains(city.to_lower()):
			out.append(Problem.new(Severity.ERROR, base + ".curatorLines.hints[0]",
				"tier 1 names '%s' — it must give sensory detail only, never the place" % city,
				pid))

	if c.reveal_monologue.strip_edges().is_empty():
		out.append(Problem.new(Severity.WARNING, base + ".curatorLines.revealMonologue",
			"nothing to say when the photo clears; the best moment in the round", pid))

	if for_export and not c.approved_by_author:
		out.append(Problem.new(Severity.ERROR, base + ".curatorLines.bake.approvedByAuthor",
			"generated lines have not been reviewed — read them before this ships", pid))


static func _check_hang_order(album: AlbumSchema.Album, out: Array[Problem]) -> void:
	if album.hang_order.is_empty():
		out.append(Problem.new(Severity.NOTE, "hangOrder",
			"not set; photos will hang in declaration order"))
		return

	var seen := {}
	for pid in album.hang_order:
		if album.photo_by_id(pid) == null:
			out.append(Problem.new(Severity.ERROR, "hangOrder",
				"references unknown photo '%s'" % pid))
		if seen.has(pid):
			out.append(Problem.new(Severity.ERROR, "hangOrder",
				"photo '%s' is hung twice" % pid))
		seen[pid] = true

	for p in album.photos:
		if not seen.has(p.id):
			out.append(Problem.new(Severity.WARNING, "hangOrder",
				"photo '%s' is not in the hang order; it will be appended" % p.id, p.id))

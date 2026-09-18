class_name Scoring
extends RefCounted
## Round scoring. Pure functions so the numbers are testable and the debug
## overlay can recompute them live (plan §7.2).
##
##   effectiveKm   = max(0, distanceKm - locationPrecisionKm)
##   distanceScore = maxDistance * exp(-effectiveKm / halfLifeKm)
##   dateScore     = maxDate * exp(-yearError / 4)   (+ month bonus)
##   roundScore    = (distance + date) * (1 - clamp(spent, 0, maxSpent))
##
## Exponential decay rather than linear: it rewards real recognition steeply,
## still credits "right country", and tails toward zero instead of going
## negative.

const DATE_DECAY_YEARS := 4.0
## Share of the date score reserved for getting the month right, when the
## photo's precision actually asks for a month.
const MONTH_BONUS_FRACTION := 0.25


## Full breakdown for one round. Returns a Dictionary so the results screen and
## the debug overlay can show every term rather than just the total.
static func score_round(
		photo: AlbumSchema.Photo,
		guess_lat: float,
		guess_lon: float,
		guess_date: AlbumSchema.PhotoDate,
		spent_fraction: float,
		cfg: AlbumSchema.ScoringConfig) -> Dictionary:

	var truth := photo.truth

	var distance_km := INF
	var distance_score := 0.0
	if truth.has_location() and Geo.is_valid_lat(guess_lat) and Geo.is_valid_lon(guess_lon):
		distance_km = Geo.haversine_km(guess_lat, guess_lon, truth.lat, truth.lon)
		distance_score = distance_component(distance_km, truth.location_precision_km, cfg)

	var date_score := date_component(guess_date, truth.date, truth.date_precision, cfg)

	var raw := distance_score + date_score
	var spent := clampf(spent_fraction, 0.0, cfg.max_spent_fraction)
	var total := raw * (1.0 - spent)

	return {
		"distance_km": distance_km,
		"distance_score": distance_score,
		"date_score": date_score,
		"year_error": _year_error(guess_date, truth.date),
		# Whether the date scored everything it could. The results screen needs
		# this: a decade-precision photograph scores full marks anywhere inside
		# the right decade, and the row used to say "and 4 years out" about a
		# date that had just been given full credit.
		"date_exact": date_score >= cfg.max_date_score - 0.001,
		"raw_score": raw,
		"spent_fraction": spent,
		"total_score": total,
		"error_band": Geo.describe_error(distance_km) if is_finite(distance_km) else &"far",
	}


static func distance_component(
		distance_km: float,
		location_precision_km: float,
		cfg: AlbumSchema.ScoringConfig) -> float:
	var effective := maxf(0.0, distance_km - maxf(0.0, location_precision_km))
	var half_life := maxf(1.0, cfg.distance_half_life_km)
	return cfg.max_distance_score * exp(-effective / half_life)


static func date_component(
		guess: AlbumSchema.PhotoDate,
		truth: AlbumSchema.PhotoDate,
		precision: AlbumSchema.DatePrecision,
		cfg: AlbumSchema.ScoringConfig) -> float:
	if not truth.is_set() or not guess.is_set():
		return 0.0

	# A decade-precision photo scores full marks anywhere inside the decade:
	# sixty-year-old scans often only carry a decade, and the game must not
	# punish the author for that.
	if precision == AlbumSchema.DatePrecision.DECADE:
		var same_decade := int(floor(guess.year / 10.0)) == int(floor(truth.year / 10.0))
		return cfg.max_date_score if same_decade else _year_decay(
			_year_error(guess, truth), cfg.max_date_score)

	var wants_month := precision == AlbumSchema.DatePrecision.MONTH \
		or precision == AlbumSchema.DatePrecision.DAY
	var year_pool := cfg.max_date_score
	if wants_month and truth.month > 0:
		year_pool = cfg.max_date_score * (1.0 - MONTH_BONUS_FRACTION)

	var score := _year_decay(_year_error(guess, truth), year_pool)

	if wants_month and truth.month > 0 and guess.month > 0:
		var month_err := _circular_month_error(guess.month, truth.month)
		var bonus_pool := cfg.max_date_score * MONTH_BONUS_FRACTION
		# Only pay the month bonus when the year is already close; naming June
		# of the wrong decade should not earn anything.
		if _year_error(guess, truth) <= 1:
			score += bonus_pool * maxf(0.0, 1.0 - float(month_err) / 3.0)

	return minf(score, cfg.max_date_score)


## Cost of having unblurred up to `tier` (0 = untouched) plus hints taken.
static func spent_fraction(
		unblur_tier: int,
		hint_tiers_taken: Array,
		cfg: AlbumSchema.ScoringConfig) -> float:
	var spent := float(maxi(0, unblur_tier)) * cfg.unblur_cost_fraction
	for t in hint_tiers_taken:
		spent += cfg.hint_cost(int(t))
	return clampf(spent, 0.0, cfg.max_spent_fraction)


# --- internals ---

static func _year_decay(year_error: int, pool: float) -> float:
	return pool * exp(-float(year_error) / DATE_DECAY_YEARS)


static func _year_error(a: AlbumSchema.PhotoDate, b: AlbumSchema.PhotoDate) -> int:
	if not a.is_set() or not b.is_set():
		return 9999
	return absi(a.year - b.year)


static func _circular_month_error(a: int, b: int) -> int:
	var d := absi(a - b)
	return mini(d, 12 - d)

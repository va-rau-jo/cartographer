extends RefCounted
## Scoring. These tests encode the design intent from plan §7.2, so a failure
## here means either a bug or a deliberate design change.

static func _photo(lat: float, lon: float, year: int, month: int = 0,
		precision: String = "year", precision_km: float = 2.0) -> AlbumSchema.Photo:
	var p := AlbumSchema.Photo.new()
	p.id = "t"
	p.truth.lat = lat
	p.truth.lon = lon
	p.truth.location_precision_km = precision_km
	p.truth.date.year = year
	p.truth.date.month = month
	p.truth.date_precision = AlbumSchema.precision_from_string(precision)
	return p


static func _date(year: int, month: int = 0) -> AlbumSchema.PhotoDate:
	var d := AlbumSchema.PhotoDate.new()
	d.year = year
	d.month = month
	return d


static func run() -> TestFramework:
	var t := TestFramework.new("scoring")
	var cfg := AlbumSchema.ScoringConfig.new()

	# --- distance component ---
	t.close(Scoring.distance_component(0.0, 2.0, cfg), cfg.max_distance_score, 0.01,
		"a perfect pin scores the maximum")
	t.close(Scoring.distance_component(2.0, 5.0, cfg), cfg.max_distance_score, 0.01,
		"inside locationPrecisionKm still scores the maximum")

	var at_half_life := Scoring.distance_component(cfg.distance_half_life_km, 0.0, cfg)
	t.close(at_half_life, cfg.max_distance_score * exp(-1.0), 1.0,
		"one half-life out scores max * e^-1")

	# Monotonic decay, and it must never go negative however far off she is.
	var prev := INF
	for km in [0.0, 10.0, 50.0, 250.0, 1000.0, 5000.0, 20000.0]:
		var s := Scoring.distance_component(km, 0.0, cfg)
		t.lt(s, prev + 0.001, "distance score decreases at %.0f km" % km)
		t.ok(s >= 0.0, "distance score stays non-negative at %.0f km" % km)
		prev = s

	# --- date component ---
	t.close(Scoring.date_component(_date(1978), _date(1978),
		AlbumSchema.DatePrecision.YEAR, cfg), cfg.max_date_score, 0.01,
		"exact year scores the maximum")

	var four_off := Scoring.date_component(_date(1982), _date(1978),
		AlbumSchema.DatePrecision.YEAR, cfg)
	t.close(four_off, cfg.max_date_score * exp(-1.0), 1.0,
		"four years out scores max * e^-1")

	# Decade precision must not punish a scan that only carries a decade.
	var in_decade := Scoring.date_component(_date(1975), _date(1978),
		AlbumSchema.DatePrecision.DECADE, cfg)
	t.close(in_decade, cfg.max_date_score, 0.01,
		"any year inside the decade scores full marks at decade precision")
	var out_decade := Scoring.date_component(_date(1969), _date(1978),
		AlbumSchema.DatePrecision.DECADE, cfg)
	t.lt(out_decade, cfg.max_date_score, "wrong decade scores less than full")

	# Month bonus only pays when the year is already close.
	var right_month := Scoring.date_component(_date(1978, 6), _date(1978, 6),
		AlbumSchema.DatePrecision.MONTH, cfg)
	var wrong_month := Scoring.date_component(_date(1978, 12), _date(1978, 6),
		AlbumSchema.DatePrecision.MONTH, cfg)
	t.close(right_month, cfg.max_date_score, 0.01,
		"right year and month scores the maximum")
	t.lt(wrong_month, right_month, "wrong month scores less than right month")
	t.gt(wrong_month, 0.0, "wrong month with right year still scores")

	var right_month_wrong_decade := Scoring.date_component(_date(1968, 6),
		_date(1978, 6), AlbumSchema.DatePrecision.MONTH, cfg)
	t.lt(right_month_wrong_decade, wrong_month,
		"naming June of the wrong decade earns no month bonus")

	# Month error is circular: December to January is one month, not eleven.
	var dec_to_jan := Scoring.date_component(_date(1978, 12), _date(1978, 1),
		AlbumSchema.DatePrecision.MONTH, cfg)
	var dec_to_jun := Scoring.date_component(_date(1978, 12), _date(1978, 6),
		AlbumSchema.DatePrecision.MONTH, cfg)
	t.gt(dec_to_jan, dec_to_jun, "December guessed for January beats December for June")

	t.close(Scoring.date_component(_date(0), _date(1978),
		AlbumSchema.DatePrecision.YEAR, cfg), 0.0, 0.01,
		"no guess scores nothing")

	# --- spend ---
	t.close(Scoring.spent_fraction(0, [], cfg), 0.0, 0.0001, "no help costs nothing")
	t.close(Scoring.spent_fraction(1, [], cfg), 0.20, 0.0001, "one unblur costs 0.20")
	t.close(Scoring.spent_fraction(0, [1], cfg), 0.10, 0.0001, "hint tier 1 costs 0.10")
	t.close(Scoring.spent_fraction(1, [1, 2], cfg), 0.50, 0.0001,
		"one unblur plus two hints costs 0.50")
	t.close(Scoring.spent_fraction(4, [1, 2, 3], cfg), cfg.max_spent_fraction, 0.0001,
		"total reliance is capped at maxSpentFraction")

	# --- whole round ---
	var photo := _photo(43.7696, 11.2558, 1978, 6, "month", 5.0)

	var perfect := Scoring.score_round(photo, 43.7696, 11.2558, _date(1978, 6), 0.0, cfg)
	t.close(float(perfect["total_score"]), cfg.max_round_score(), 0.01,
		"a perfect unassisted round scores everything")
	t.close(float(perfect["distance_km"]), 0.0, 0.001, "perfect round has zero error")

	# The most important property in the whole scoring system: a player who
	# needed every hint and still got it right must not score zero.
	var fully_helped := Scoring.score_round(photo, 43.7696, 11.2558,
		_date(1978, 6), 1.0, cfg)
	t.gt(float(fully_helped["total_score"]), 0.0,
		"a fully-assisted correct guess still scores something")
	t.close(float(fully_helped["total_score"]),
		cfg.max_round_score() * (1.0 - cfg.max_spent_fraction), 0.01,
		"fully-assisted score is exactly the uncapped remainder")

	# Wrong continent, right year: partial credit, never negative.
	var far := Scoring.score_round(photo, -33.8688, 151.2093, _date(1978, 6), 0.0, cfg)
	t.ok(float(far["total_score"]) >= 0.0, "a wild miss never scores negative")
	t.lt(float(far["distance_score"]), 1.0, "a wild miss earns almost no distance score")
	t.gt(float(far["date_score"]), 0.0, "a wild miss still earns the date score")
	t.eq(far["error_band"], &"far", "a wild miss is reported as far")

	# A photo with no location cannot be scored on distance, but the date half
	# must still work rather than the whole round returning nothing.
	var no_loc := _photo(NAN, NAN, 1978)
	var partial := Scoring.score_round(no_loc, 43.0, 11.0, _date(1978), 0.0, cfg)
	t.close(float(partial["distance_score"]), 0.0, 0.01,
		"missing truth location scores no distance")
	t.close(float(partial["date_score"]), cfg.max_date_score, 0.01,
		"missing truth location still scores the date")

	return t

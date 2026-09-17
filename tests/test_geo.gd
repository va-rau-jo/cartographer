extends RefCounted
## Geo maths. Distances checked against known great-circle values.

static func run() -> TestFramework:
	var t := TestFramework.new("geo")

	# --- haversine against known distances ---
	# London (51.5074, -0.1278) to Paris (48.8566, 2.3522) is ~344 km.
	t.close(Geo.haversine_km(51.5074, -0.1278, 48.8566, 2.3522), 344.0, 5.0,
		"London to Paris")

	# New York (40.7128, -74.0060) to London is ~5570 km.
	t.close(Geo.haversine_km(40.7128, -74.0060, 51.5074, -0.1278), 5570.0, 30.0,
		"New York to London")

	# Sydney (-33.8688, 151.2093) to Auckland (-36.8485, 174.7633) is ~2155 km.
	t.close(Geo.haversine_km(-33.8688, 151.2093, -36.8485, 174.7633), 2155.0, 20.0,
		"Sydney to Auckland (southern hemisphere)")

	t.close(Geo.haversine_km(43.7696, 11.2558, 43.7696, 11.2558), 0.0, 0.001,
		"zero distance to itself")

	# Antipodes: half the circumference. This is where a naive acos()
	# implementation trips over float error and returns NaN.
	var antipodal := Geo.haversine_km(0.0, 0.0, 0.0, 180.0)
	t.close(antipodal, PI * Geo.EARTH_RADIUS_KM, 1.0, "antipodal distance")
	t.ok(not is_nan(antipodal), "antipodal distance is not NaN")

	# Crossing the date line the short way: 179 E to 179 W is ~222 km, not
	# most of the way round the planet.
	t.lt(Geo.haversine_km(0.0, 179.0, 0.0, -179.0), 300.0,
		"date line crossed the short way")

	# --- projection round trip ---
	var cases := [
		Vector2(0.0, 0.0),
		Vector2(51.5074, -0.1278),
		Vector2(-33.8688, 151.2093),
		Vector2(90.0, -180.0),
		Vector2(-90.0, 179.9999),
	]
	for c in cases:
		var unit := Geo.to_unit(c.x, c.y)
		var back := Geo.from_unit(unit)
		t.close(back.x, c.x, 0.0001, "lat round trip for %s" % str(c))
		t.close(back.y, c.y, 0.0001, "lon round trip for %s" % str(c))

	# --- unit space corners ---
	var top_left := Geo.to_unit(90.0, -180.0)
	t.close(top_left.x, 0.0, 0.0001, "lon -180 maps to x=0")
	t.close(top_left.y, 0.0, 0.0001, "lat +90 maps to y=0 (top)")

	var bottom_right := Geo.to_unit(-90.0, 179.99999)
	t.close(bottom_right.x, 1.0, 0.0001, "lon +180 maps to x=1")
	t.close(bottom_right.y, 1.0, 0.0001, "lat -90 maps to y=1 (bottom)")

	var origin := Geo.to_unit(0.0, 0.0)
	t.close(origin.x, 0.5, 0.0001, "null island x")
	t.close(origin.y, 0.5, 0.0001, "null island y")

	# --- longitude wrapping ---
	t.close(Geo.wrap_lon(190.0), -170.0, 0.0001, "190 wraps to -170")
	t.close(Geo.wrap_lon(-190.0), 170.0, 0.0001, "-190 wraps to 170")
	t.close(Geo.wrap_lon(0.0), 0.0, 0.0001, "0 stays 0")
	t.close(Geo.wrap_lon(-180.0), -180.0, 0.0001, "-180 stays -180")
	t.close(Geo.wrap_lon(540.0), -180.0, 0.0001, "540 wraps to -180")

	# --- validity ---
	t.ok(Geo.is_valid_lat(0.0), "lat 0 valid")
	t.ok(Geo.is_valid_lat(-90.0), "lat -90 valid")
	t.ok(not Geo.is_valid_lat(90.1), "lat 90.1 invalid")
	t.ok(not Geo.is_valid_lat(NAN), "lat NaN invalid")
	t.ok(Geo.is_valid_lon(-180.0), "lon -180 valid")
	t.ok(not Geo.is_valid_lon(180.1), "lon 180.1 invalid")
	t.ok(not Geo.is_valid_lon(NAN), "lon NaN invalid")

	# --- error bands, used by the curator's wrong-guess lines ---
	t.eq(Geo.describe_error(5.0), &"exact", "5 km is exact")
	t.eq(Geo.describe_error(100.0), &"near", "100 km is near")
	t.eq(Geo.describe_error(500.0), &"region", "500 km is region")
	t.eq(Geo.describe_error(2000.0), &"continent", "2000 km is continent")
	t.eq(Geo.describe_error(9000.0), &"far", "9000 km is far")

	return t

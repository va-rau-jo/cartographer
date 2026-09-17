class_name Geo
extends RefCounted
## Geographic maths for the map widget and distance scoring.
##
## The projection used for the *presentation* may be painted and distorted, but
## everything here stays plain equirectangular so that lat/lon <-> pixel is a
## one-liner and inverse-projecting a click is exact. Never let the pretty
## version and the maths version diverge (plan §7.1).

const EARTH_RADIUS_KM := 6371.0


## Great-circle distance in kilometres.
static func haversine_km(lat_a: float, lon_a: float, lat_b: float, lon_b: float) -> float:
	var phi_a := deg_to_rad(lat_a)
	var phi_b := deg_to_rad(lat_b)
	var d_phi := phi_b - phi_a
	var d_lambda := deg_to_rad(lon_b - lon_a)

	var s := sin(d_phi * 0.5) * sin(d_phi * 0.5) \
		+ cos(phi_a) * cos(phi_b) * sin(d_lambda * 0.5) * sin(d_lambda * 0.5)
	# Clamp guards against a hair over 1.0 from float error at antipodes.
	return 2.0 * EARTH_RADIUS_KM * asin(sqrt(clampf(s, 0.0, 1.0)))


## lat/lon -> normalised map position, x and y both in 0..1.
## x = 0 at -180 lon, y = 0 at +90 lat (top of the map).
static func to_unit(lat: float, lon: float) -> Vector2:
	return Vector2(
		(wrap_lon(lon) + 180.0) / 360.0,
		(90.0 - clampf(lat, -90.0, 90.0)) / 180.0
	)


## Inverse of to_unit(). Input outside 0..1 is clamped.
static func from_unit(p: Vector2) -> Vector2:
	var lon := clampf(p.x, 0.0, 1.0) * 360.0 - 180.0
	var lat := 90.0 - clampf(p.y, 0.0, 1.0) * 180.0
	return Vector2(lat, lon)


## Normalise longitude into [-180, 180).
static func wrap_lon(lon: float) -> float:
	var l := fposmod(lon + 180.0, 360.0) - 180.0
	return l


static func is_valid_lat(lat: float) -> bool:
	return not is_nan(lat) and lat >= -90.0 and lat <= 90.0


static func is_valid_lon(lon: float) -> bool:
	return not is_nan(lon) and lon >= -180.0 and lon <= 180.0


## Rough human phrasing for a miss, used by the curator's wrong-guess lines.
static func describe_error(km: float) -> StringName:
	if km < 25.0:
		return &"exact"
	if km < 150.0:
		return &"near"
	if km < 800.0:
		return &"region"
	if km < 3000.0:
		return &"continent"
	return &"far"

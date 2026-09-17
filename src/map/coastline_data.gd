class_name CoastlineData
extends RefCounted
## The world's outline, as polylines in degrees — or nothing at all.
##
## The map has to draw *some* land or a pin is meaningless, and the data for
## that is Natural Earth's 110m coastline, which is 200 KB of public-domain
## GeoJSON. It cannot be committed by the tool that wrote this file: every
## Natural Earth host is blocked from this environment (403 at the proxy, from
## both the build container and the desktop). So the map takes its outline from
## a *pluggable loader* and behaves sensibly when there is none:
##
##   * data present  — the map draws coastlines, and it is a map.
##   * data absent   — the map draws a graticule only, and the guess panel
##                     keeps the place list as its default instead.
##
## `tools/fetch_geo.py` produces the file, from the network or from a GeoJSON
## already on disk. Nothing here invents coordinates: a made-up coastline would
## look plausible and be wrong, which is worse than an empty one.
##
## Format (data/geo/coastlines.json), deliberately boring:
##
##   {
##     "schema": 1,
##     "source": "Natural Earth 110m physical coastline (public domain)",
##     "simplifiedDeg": 0.35,
##     "lines": [[lon, lat, lon, lat, ...], ...]
##   }
##
## Flat number arrays rather than [[lon,lat],...] pairs: same information, about
## half the parse time and two thirds the bytes.

const SCHEMA := 1
const DEFAULT_PATH := "res://data/geo/coastlines.json"

## Polylines in lon/lat degrees. x = longitude, y = latitude.
var lines: Array[PackedVector2Array] = []
var source := ""
var simplified_deg := 0.0


func is_empty() -> bool:
	return lines.is_empty()


func polyline_count() -> int:
	return lines.size()


func point_count() -> int:
	var n := 0
	for line in lines:
		n += line.size()
	return n


## Load from a JSON file. Returns an empty instance when the file is missing or
## unusable — the map degrades, it does not fail.
static func load_baked(path: String = DEFAULT_PATH) -> CoastlineData:
	if not FileAccess.file_exists(path):
		CCLog.info("map", "no coastline data at %s; graticule only" % path)
		return CoastlineData.new()

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		CCLog.warn("map", "coastline file at %s is empty" % path)
		return CoastlineData.new()

	return from_json(text)


static func from_json(text: String) -> CoastlineData:
	var data := CoastlineData.new()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		CCLog.warn("map", "coastline data is not an object")
		return data

	var dict: Dictionary = parsed
	var schema := int(dict.get("schema", 0))
	if schema != SCHEMA:
		# Same rule as the album manifest: refuse rather than guess.
		CCLog.warn("map", "coastline schema %d, expected %d" % [schema, SCHEMA])
		return data

	data.source = str(dict.get("source", ""))
	data.simplified_deg = float(dict.get("simplifiedDeg", 0.0))

	for raw in dict.get("lines", []):
		if typeof(raw) != TYPE_ARRAY:
			continue
		var flat: Array = raw
		# Odd-length runs are truncated rather than dropped: a coastline with a
		# half-written last point is still a coastline.
		var pairs := flat.size() / 2
		if pairs < 2:
			continue
		var line := PackedVector2Array()
		line.resize(pairs)
		for i in pairs:
			line[i] = Vector2(float(flat[i * 2]), float(flat[i * 2 + 1]))
		data.lines.append(line)

	CCLog.info("map", "coastlines: %d lines, %d points%s"
		% [data.polyline_count(), data.point_count(),
		   "" if data.source.is_empty() else " (%s)" % data.source])
	return data


## Serialise back out. Used by the tests and by anything that wants to bake a
## reduced set; the Python tool writes the same shape.
func to_json() -> String:
	var out: Array = []
	for line in lines:
		var flat: Array = []
		for p in line:
			flat.append(snappedf(p.x, 0.0001))
			flat.append(snappedf(p.y, 0.0001))
		out.append(flat)
	return JSON.stringify({
		"schema": SCHEMA,
		"source": source,
		"simplifiedDeg": simplified_deg,
		"lines": out,
	})


## Lon/lat bounding box of everything loaded, as (min_lon, min_lat) to
## (max_lon, max_lat). Zero-size when empty.
func bounds() -> Rect2:
	if lines.is_empty():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for line in lines:
		for p in line:
			lo.x = minf(lo.x, p.x)
			lo.y = minf(lo.y, p.y)
			hi.x = maxf(hi.x, p.x)
			hi.y = maxf(hi.y, p.y)
	return Rect2(lo, hi - lo)


## Drop points inside `tolerance` degrees of the line between their
## neighbours (Douglas-Peucker). The Python tool does this once, offline; this
## exists so a hand-made or hi-res file can be thinned at load time without
## re-running the tool.
func simplified(tolerance: float) -> CoastlineData:
	var out := CoastlineData.new()
	out.source = source
	out.simplified_deg = maxf(simplified_deg, tolerance)
	for line in lines:
		var kept := _simplify_line(line, tolerance)
		if kept.size() >= 2:
			out.lines.append(kept)
	return out


static func _simplify_line(line: PackedVector2Array,
		tolerance: float) -> PackedVector2Array:
	if line.size() <= 2 or tolerance <= 0.0:
		return line

	# Iterative Douglas-Peucker: a recursive one blows the stack on a coastline
	# with thousands of points in a single ring.
	var keep := PackedByteArray()
	keep.resize(line.size())
	keep.fill(0)
	keep[0] = 1
	keep[line.size() - 1] = 1

	var stack: Array[Vector2i] = [Vector2i(0, line.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1.0
		var worst_at := -1
		for i in range(span.x + 1, span.y):
			var d := _point_line_distance(line[i], line[span.x], line[span.y])
			if d > worst:
				worst = d
				worst_at = i
		if worst > tolerance and worst_at > 0:
			keep[worst_at] = 1
			stack.append(Vector2i(span.x, worst_at))
			stack.append(Vector2i(worst_at, span.y))

	var out := PackedVector2Array()
	for i in line.size():
		if keep[i] == 1:
			out.append(line[i])
	return out


static func _point_line_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

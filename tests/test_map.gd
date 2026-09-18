extends RefCounted
## The map widget and its coastline layer.
##
## The widget is tested with a synthetic outline rather than the real Natural
## Earth data, because that data is not in the repository (see
## tools/fetch_geo.py). That is fine for what has to be true here: the
## assertions are about the projection, the pin and the no-data behaviour, none
## of which care what shape the land is.
##
## The assertion that matters most is the round trip. A pin's coordinates are
## whatever pixel_to_lat_lon says they are, and that number goes straight into
## the haversine — so if the drawing projection and the scoring projection ever
## drift apart, the game silently marks correct answers wrong.

## Three rings and two specks, as the Python tool's own fixture. Flat
## [lon, lat, ...] runs, which is the format CoastlineData reads.
const FIXTURE := """
{
  "schema": 1,
  "source": "synthetic test fixture",
  "simplifiedDeg": 0.35,
  "lines": [
    [-80, -40, -40, -40, -40, 20, -80, 20, -80, -40],
    [-10, 35, 40, 35, 40, 60, -10, 60, -10, 35],
    [110, -40, 150, -40, 150, -10, 110, -10, 110, -40]
  ]
}
"""

var _holder: Node = null


func run() -> TestFramework:
	var t := TestFramework.new("map")

	_holder = Node.new()
	_holder.name = "MapTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	_test_regions(t)
	_test_coastline_parsing(t)
	_test_simplify(t)
	_test_projection(t)
	_test_pin(t)
	_test_no_data(t)
	_test_formatting(t)

	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null
	return t


# ---------------------------------------------------------------- regions

## The two-stage map: zoomed out a click navigates, zoomed in it answers.
func _test_regions(t: TestFramework) -> void:
	# Well-known places land in the region a person would name.
	t.eq(MapWidget.region_name(MapWidget.region_at(48.8566, 2.3522)),
		"Europe", "Paris is in Europe")
	t.eq(MapWidget.region_name(MapWidget.region_at(35.0116, 135.7681)),
		"Asia", "Kyoto is in Asia")
	t.eq(MapWidget.region_name(MapWidget.region_at(-33.8688, 151.2093)),
		"Oceania", "Sydney is in Oceania")
	t.eq(MapWidget.region_name(MapWidget.region_at(-1.2921, 36.8219)),
		"Africa", "Nairobi is in Africa")
	t.eq(MapWidget.region_name(MapWidget.region_at(40.7128, -74.0060)),
		"North America", "New York is in North America")
	t.eq(MapWidget.region_name(MapWidget.region_at(-22.9068, -43.1729)),
		"South America", "Rio is in South America")
	t.eq(MapWidget.region_name(MapWidget.region_at(-77.8, 166.7)),
		"Antarctica", "McMurdo is in Antarctica")

	# The overlap that always needs a tie-break: Europe's box and Asia's box
	# both cover Turkey and western Russia.
	var istanbul := MapWidget.region_name(MapWidget.region_at(41.0, 29.0))
	t.ok(istanbul == "Europe" or istanbul == "Asia",
		"Istanbul resolves to one of its two regions (got %s)" % istanbul)

	# Open ocean belongs to nobody.
	t.eq(MapWidget.region_at(-30.0, -140.0), -1,
		"the middle of the Pacific is in no region")

	var map := _widget(800.0, 400.0)
	t.ok(map.is_world_view(), "a fresh map is in world view")

	# A click in world view zooms instead of pinning.
	var paris := map.unit_to_pixel(Geo.to_unit(48.8566, 2.3522))
	map._click(paris)
	t.ok(not map.has_pin(), "the first click does not place a pin")
	t.gt(map.zoom(), 1.5, "it zooms in (x%.1f)" % map.zoom())
	t.ok(not map.is_world_view(), "so the next click will pin")

	# And Europe is what is now on screen.
	var middle: Vector2 = map.pixel_to_lat_lon(Vector2(400.0, 200.0))
	t.eq(MapWidget.region_name(MapWidget.region_at(middle.x, middle.y)),
		"Europe", "the view is centred on Europe (%.1f, %.1f)"
			% [middle.x, middle.y])

	# The second click is the answer, and it is exact.
	map._click(Vector2(410.0, 190.0))
	t.ok(map.has_pin(), "the second click places the pin")
	var expected := map.pixel_to_lat_lon(Vector2(410.0, 190.0))
	var pin := map.pin_lat_lon()
	t.close(pin.x, expected.x, 0.01, "at exactly the pixel clicked (lat)")
	t.close(pin.y, expected.y, 0.01, "and lon")

	# Zoomed in, a pin this close to the truth must still score as a hit: the
	# whole reason for the two stages is that the world view cannot do this.
	var km := Geo.haversine_km(pin.x, pin.y, expected.x, expected.y)
	t.lt(km, 1.0, "with no measurable error")

	map.reset_view()
	t.ok(map.is_world_view(), "back to the world, and back to navigating")
	t.ok(map.has_pin(), "without losing the pin she already placed")

	# Open water still zooms — "click to zoom in" has to mean something
	# everywhere, or the map feels broken over the Pacific.
	map.reset_view()
	var pacific := map.unit_to_pixel(Geo.to_unit(-30.0, -140.0))
	map._click(pacific)
	t.gt(map.zoom(), 1.5, "a click on open water zooms too")
	var water: Vector2 = map.pixel_to_lat_lon(Vector2(400.0, 200.0))
	t.close(water.x, -30.0, 6.0, "centred near where she clicked (lat)")
	t.close(water.y, -140.0, 12.0, "and lon")

	# Focusing on a box is bounded: a tiny box must not zoom past the limit.
	map.focus_on_box(2.0, 48.0, 2.1, 48.1)
	t.lt(map.zoom(), MapWidget.MAX_ZOOM + 0.01, "a tiny box clamps to max zoom")
	t.gt(map.zoom(), 1.0, "and does zoom")

	# Antarctica spans the whole width, including the antimeridian.
	map.reset_view()
	map.focus_on_region(6)
	t.gt(map.zoom(), MapWidget.PIN_ZOOM,
		"Antarctica zooms in despite spanning every longitude (x%.1f)"
			% map.zoom())
	t.lt(map.zoom(), MapWidget.MAX_ZOOM, "without going to full zoom")
	t.ok(not map.is_world_view(), "so a click there pins rather than zooming")
	# Not "centred on Antarctica": at this zoom the visible band of latitude is
	# wide enough that centring on -73 would show the view running off the
	# bottom of the world, and _clamp_centre correctly refuses. What has to be
	# true is that the continent is on screen.
	var bottom: Vector2 = map.pixel_to_lat_lon(Vector2(400.0, 399.0))
	t.lt(bottom.x, -62.0, "and Antarctica is in view (bottom edge %.1f)"
		% bottom.x)

	map.get_parent().remove_child(map)
	map.free()


# ------------------------------------------------------------------- data

func _test_coastline_parsing(t: TestFramework) -> void:
	var data := CoastlineData.from_json(FIXTURE)
	t.eq(data.polyline_count(), 3, "three outlines parse")
	t.eq(data.point_count(), 15, "with five points each")
	t.eq(data.source, "synthetic test fixture", "the source is recorded")
	t.ok(not data.is_empty(), "and it is not empty")

	# x is longitude and y is latitude, in that order. Getting this backwards
	# would put Europe in the Southern Ocean.
	var first := data.lines[0][0]
	t.close(first.x, -80.0, 0.001, "x is longitude")
	t.close(first.y, -40.0, 0.001, "y is latitude")

	var box := data.bounds()
	t.close(box.position.x, -80.0, 0.001, "the bounds start at the west edge")
	t.close(box.end.x, 150.0, 0.001, "and end at the east")

	# A round trip through to_json has to survive, because the same shape is
	# what the Python tool writes.
	var again := CoastlineData.from_json(data.to_json())
	t.eq(again.point_count(), data.point_count(), "a round trip keeps the points")
	t.eq(again.source, data.source, "and the provenance")

	# Refusals, all of which must degrade rather than throw.
	t.ok(CoastlineData.from_json("not json at all").is_empty(),
		"garbage parses to nothing")
	t.ok(CoastlineData.from_json('{"schema": 99, "lines": []}').is_empty(),
		"a future schema is refused, not guessed at")
	t.ok(CoastlineData.from_json('{"schema": 1, "lines": [[1, 2]]}').is_empty(),
		"a one-point line is not a line")
	t.ok(CoastlineData.load_baked("res://nothing/here.json").is_empty(),
		"a missing file is an empty map, not a crash")


func _test_simplify(t: TestFramework) -> void:
	# A straight run of points with one spike in it.
	var line := PackedVector2Array()
	for i in 21:
		line.append(Vector2(float(i), 0.0))
	line[10] = Vector2(10.0, 5.0)

	var data := CoastlineData.new()
	data.lines = [line]

	var thinned := data.simplified(0.5)
	t.eq(thinned.polyline_count(), 1, "the line survives")
	# Not three: Douglas-Peucker also keeps the shoulders on either side of the
	# spike, because they are far from the new segments through it. The point
	# is that twenty-one becomes a handful.
	t.lt(float(thinned.point_count()), 8.0,
		"a straight run with one spike collapses to a handful (got %d)"
			% thinned.point_count())
	t.gt(float(thinned.point_count()), 2.0, "but not to a bare segment")
	# The spike is the point that must not be dropped.
	var kept := thinned.lines[0]
	var has_spike := false
	for p in kept:
		if absf(p.y - 5.0) < 0.001:
			has_spike = true
	t.ok(has_spike, "and the spike is what it keeps")

	t.eq(data.simplified(0.0).point_count(), 21,
		"zero tolerance changes nothing")


# ------------------------------------------------------------- projection

func _widget(width: float, height: float) -> MapWidget:
	var map := MapWidget.new()
	map.setup(CoastlineData.from_json(FIXTURE))
	_holder.add_child(map)
	map.size = Vector2(width, height)
	return map


func _test_projection(t: TestFramework) -> void:
	var map := _widget(800.0, 400.0)

	# Round trip: a pixel to degrees and back to the same pixel.
	for probe in [Vector2(10.0, 10.0), Vector2(400.0, 200.0),
			Vector2(790.0, 390.0), Vector2(123.0, 301.0)]:
		var degrees: Vector2 = map.pixel_to_lat_lon(probe)
		var back: Vector2 = map.unit_to_pixel(Geo.to_unit(degrees.x, degrees.y))
		t.close(back.x, probe.x, 0.6, "pixel %d,%d survives a round trip (x)"
			% [int(probe.x), int(probe.y)])
		t.close(back.y, probe.y, 0.6, "pixel %d,%d survives a round trip (y)"
			% [int(probe.x), int(probe.y)])

	# The centre of an unzoomed view is 0,0 — the Gulf of Guinea.
	var middle: Vector2 = map.pixel_to_lat_lon(Vector2(400.0, 200.0))
	t.close(middle.x, 0.0, 0.5, "the middle of the map is the equator")
	t.close(middle.y, 0.0, 0.5, "and the prime meridian")

	# East is right and north is up. Both have been wrong in this project
	# before, in other coordinate systems.
	var right: Vector2 = map.pixel_to_lat_lon(Vector2(700.0, 200.0))
	t.gt(right.y, middle.y, "east is to the right")
	var up: Vector2 = map.pixel_to_lat_lon(Vector2(400.0, 40.0))
	t.gt(up.x, middle.x, "north is up")

	# Zooming about a point leaves that point where it was: the whole reason
	# wheel-zoom feels right or wrong.
	var anchor := Vector2(600.0, 120.0)
	var before: Vector2 = map.pixel_to_lat_lon(anchor)
	map._zoom_about(anchor, 2.0)
	var after: Vector2 = map.pixel_to_lat_lon(anchor)
	t.close(after.x, before.x, 0.35, "zoom keeps the latitude under the cursor")
	t.close(after.y, before.y, 0.35, "and the longitude")
	t.gt(map.zoom(), 1.5, "and it did zoom")

	map.reset_view()
	t.close(map.zoom(), MapWidget.MIN_ZOOM, 0.001, "reset undoes the zoom")

	# Zoom is bounded at both ends.
	for _i in 30:
		map._zoom_about(anchor, 2.0)
	t.close(map.zoom(), MapWidget.MAX_ZOOM, 0.001, "zoom stops at the maximum")
	for _i in 60:
		map._zoom_about(anchor, 0.5)
	t.close(map.zoom(), MapWidget.MIN_ZOOM, 0.001, "and at the minimum")

	# The graticule has to be evenly spaced, or the projection is not linear
	# and a click near the edge means something different from a click in the
	# middle. Easier to check as numbers than to judge by eye in a render.
	map.reset_view()
	var spacings: Array[float] = []
	# Only to 150: Geo.to_unit wraps +180 round to the left edge, which is
	# exactly why the widget draws the antimeridian from unit space instead.
	for lon in range(-180, 151, 30):
		spacings.append(map.unit_to_pixel(Geo.to_unit(0.0, float(lon))).x)
	var gap := spacings[1] - spacings[0]
	for i in range(1, spacings.size()):
		t.close(spacings[i] - spacings[i - 1], gap, 0.01,
			"meridian %d is evenly spaced" % (-180 + i * 30))

	# A coastline that crosses the 180th meridian must be drawn as two runs,
	# not as one line streaking across the whole map.
	var crossing := PackedVector2Array([
		Vector2(170.0, -20.0), Vector2(178.0, -21.0),
		Vector2(-178.0, -22.0), Vector2(-170.0, -23.0)])
	var runs := MapWidget._split_at_antimeridian(crossing)
	t.eq(runs.size(), 2, "a line across the antimeridian splits in two")
	t.eq(runs[0].size(), 2, "with the eastern half intact")
	t.eq(runs[1].size(), 2, "and the western half")

	var plain := PackedVector2Array([
		Vector2(10.0, 0.0), Vector2(20.0, 5.0), Vector2(30.0, 10.0)])
	var whole := MapWidget._split_at_antimeridian(plain)
	t.eq(whole.size(), 1, "an ordinary line is left alone")
	t.eq(whole[0].size(), 3, "with all its points")

	map.get_parent().remove_child(map)
	map.free()


func _test_pin(t: TestFramework) -> void:
	var map := _widget(800.0, 400.0)

	t.ok(not map.has_pin(), "there is no pin until she places one")
	var nothing := map.pin_lat_lon()
	t.ok(is_nan(nothing.x), "and no coordinates to submit")

	var reported: Array = []
	map.pin_moved.connect(func(lat: float, lon: float) -> void:
		reported.append(Vector2(lat, lon)))

	# Paris, as a known pair.
	map.set_pin_lat_lon(48.8566, 2.3522)
	t.ok(map.has_pin(), "placing a pin registers")
	var pin := map.pin_lat_lon()
	t.close(pin.x, 48.8566, 0.25, "the pin keeps its latitude")
	t.close(pin.y, 2.3522, 0.25, "and its longitude")
	t.eq(reported.size(), 1, "and it says so once")

	# The distance from the pin to the truth is what the round is scored on, so
	# the error a pin introduces has to be tiny.
	var km := Geo.haversine_km(pin.x, pin.y, 48.8566, 2.3522)
	t.lt(km, 30.0, "a placed pin lands within 30 km of the coordinates given")

	# Clicking places it where the click was.
	map._place_pin(Vector2(200.0, 100.0))
	var clicked := map.pin_lat_lon()
	var expected := map.pixel_to_lat_lon(Vector2(200.0, 100.0))
	t.close(clicked.x, expected.x, 0.01, "a click pins that latitude")
	t.close(clicked.y, expected.y, 0.01, "and that longitude")

	var cleared := [false]
	map.pin_cleared.connect(func() -> void: cleared[0] = true)
	map.clear_pin()
	t.ok(not map.has_pin(), "and it can be taken back")
	t.ok(cleared[0], "which is announced too")

	map.get_parent().remove_child(map)
	map.free()


## With no coastline file the map still has to work as a coordinate picker.
func _test_no_data(t: TestFramework) -> void:
	var map := MapWidget.new()
	map.setup(CoastlineData.new())
	_holder.add_child(map)
	map.size = Vector2(600.0, 300.0)

	t.ok(map.coastlines.is_empty(), "the map knows it has no outline")
	t.ok(map.clip_contents,
		"the map clips its own drawing (zoomed lines escaped the panel once)")
	map._place_pin(Vector2(300.0, 150.0))
	t.ok(map.has_pin(), "a pin can still be placed")
	var pin := map.pin_lat_lon()
	t.close(pin.x, 0.0, 0.6, "and it still means something")
	t.close(pin.y, 0.0, 0.6, "in both axes")

	map.get_parent().remove_child(map)
	map.free()


func _test_formatting(t: TestFramework) -> void:
	t.eq(MapWidget.format_lat_lon(48.8566, 2.3522), "48.9 N, 2.4 E",
		"northern and eastern read as N and E")
	t.eq(MapWidget.format_lat_lon(-33.8688, 151.2093), "33.9 S, 151.2 E",
		"southern reads as S, without a minus sign")
	t.eq(MapWidget.format_lat_lon(-22.9068, -43.1729), "22.9 S, 43.2 W",
		"and western as W")

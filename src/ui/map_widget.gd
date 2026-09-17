class_name MapWidget
extends Control
## The map she pins. Equirectangular, pannable, zoomable, and exact.
##
## Two rules from plan §7.1, both load-bearing:
##
##   1. The projection used for drawing and the projection used for scoring are
##      the same one. Every pixel here goes through Geo.to_unit/from_unit, so a
##      pin's coordinates are whatever the picture says they are.
##   2. The coastline is a *layer*, not a requirement. With no data loaded this
##      still draws a graticule and still returns exact coordinates; it just
##      is not much help to look at. See CoastlineData.
##
## Interaction: left-click to drop the pin, drag to pan, wheel to zoom about the
## cursor, double-click to reset the view. No pin exists until she places one —
## a map that opens with a pin in the Atlantic invites her to just accept it.

signal pin_moved(lat: float, lon: float)
signal pin_cleared()

const MIN_ZOOM := 1.0
const MAX_ZOOM := 12.0
const ZOOM_STEP := 1.22

## Degrees of latitude the equirectangular map covers vertically. The full
## -90..90 leaves a lot of empty ice; this is the usual compromise.
const LAT_SPAN := 170.0

const COLOR_OCEAN := Color(0.078, 0.094, 0.118)
const COLOR_LAND := Color(0.36, 0.40, 0.36)
const COLOR_COAST := Color(0.62, 0.66, 0.60)
const COLOR_GRID := Color(0.20, 0.23, 0.27)
const COLOR_EQUATOR := Color(0.30, 0.34, 0.38)
const COLOR_PIN := Color(0.94, 0.62, 0.36)
const COLOR_TEXT := Color(0.72, 0.75, 0.72)

var coastlines: CoastlineData = null

var _zoom := 1.0
## Centre of the view in unit map space (0..1 both axes).
var _centre := Vector2(0.5, 0.5)
var _pin_unit := Vector2(-1, -1)
var _has_pin := false
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_centre := Vector2.ZERO
var _hover_unit := Vector2(-1, -1)
var _font: Font = null


func setup(data: CoastlineData) -> void:
	coastlines = data
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Without this, draw_line and draw_polyline happily paint outside the
	# control's own rectangle: zoomed in, the coastlines ran off across the
	# whole panel and out over the page behind it.
	clip_contents = true
	if coastlines == null:
		coastlines = CoastlineData.load_baked()
	_font = ThemeDB.fallback_font
	queue_redraw()


# ------------------------------------------------------------------- state

func has_pin() -> bool:
	return _has_pin


## The pin in degrees, or a NAN pair when she has not placed one.
func pin_lat_lon() -> Vector2:
	if not _has_pin:
		return Vector2(NAN, NAN)
	return Geo.from_unit(_pin_unit)


func clear_pin() -> void:
	_has_pin = false
	_pin_unit = Vector2(-1, -1)
	pin_cleared.emit()
	queue_redraw()


## Place the pin at a known position — for restoring a guess in progress, and
## for the tests.
func set_pin_lat_lon(lat: float, lon: float) -> void:
	_pin_unit = Geo.to_unit(lat, Geo.wrap_lon(lon))
	_has_pin = true
	var degrees := Geo.from_unit(_pin_unit)
	pin_moved.emit(degrees.x, degrees.y)
	queue_redraw()


func zoom() -> float:
	return _zoom


func reset_view() -> void:
	_zoom = MIN_ZOOM
	_centre = Vector2(0.5, 0.5)
	queue_redraw()


# -------------------------------------------------------------- projection

## Unit map space (0..1) -> a pixel inside this control.
func unit_to_pixel(unit: Vector2) -> Vector2:
	var span := _view_span()
	var origin := _centre - span * 0.5
	return Vector2(
		(unit.x - origin.x) / span.x * size.x,
		(unit.y - origin.y) / span.y * size.y)


## The inverse, which is what makes a click into a guess.
func pixel_to_unit(pixel: Vector2) -> Vector2:
	var span := _view_span()
	var origin := _centre - span * 0.5
	return Vector2(
		origin.x + pixel.x / maxf(size.x, 1.0) * span.x,
		origin.y + pixel.y / maxf(size.y, 1.0) * span.y)


func pixel_to_lat_lon(pixel: Vector2) -> Vector2:
	return Geo.from_unit(pixel_to_unit(pixel))


## How much of the unit map is on screen. The aspect correction is what stops
## the world stretching when the panel is not 2:1.
func _view_span() -> Vector2:
	var lat_fraction := LAT_SPAN / 180.0
	var span := Vector2(1.0, lat_fraction) / _zoom
	var want_aspect := maxf(size.x, 1.0) / maxf(size.y, 1.0)
	var map_aspect := (span.x * 360.0) / maxf(span.y * 180.0, 0.001)
	if map_aspect > want_aspect:
		# Too wide for the box: show more latitude rather than squashing.
		span.y = span.x * 2.0 / want_aspect
	else:
		span.x = span.y * want_aspect * 0.5
	return span


## Keep the view over the map. Panning past the edge is disorienting and there
## is nothing out there.
func _clamp_centre() -> void:
	var span := _view_span()
	var half := span * 0.5
	if span.x >= 1.0:
		_centre.x = 0.5
	else:
		_centre.x = clampf(_centre.x, half.x, 1.0 - half.x)
	if span.y >= 1.0:
		_centre.y = 0.5
	else:
		_centre.y = clampf(_centre.y, half.y, 1.0 - half.y)


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)


func _handle_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.double_click:
				reset_view()
				accept_event()
				return
			if event.pressed:
				_dragging = true
				_drag_from = event.position
				_drag_centre = _centre
			else:
				# A press that did not travel is a pin, not a pan.
				if _drag_from.distance_to(event.position) < 4.0:
					_place_pin(event.position)
				_dragging = false
			accept_event()
		MOUSE_BUTTON_WHEEL_UP:
			_zoom_about(event.position, ZOOM_STEP)
			accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_about(event.position, 1.0 / ZOOM_STEP)
			accept_event()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				clear_pin()
			accept_event()


func _handle_motion(event: InputEventMouseMotion) -> void:
	_hover_unit = pixel_to_unit(event.position)
	if _dragging:
		var span := _view_span()
		var moved := event.position - _drag_from
		_centre = _drag_centre - Vector2(
			moved.x / maxf(size.x, 1.0) * span.x,
			moved.y / maxf(size.y, 1.0) * span.y)
		_clamp_centre()
	queue_redraw()


func _place_pin(pixel: Vector2) -> void:
	_pin_unit = pixel_to_unit(pixel)
	_pin_unit.x = clampf(_pin_unit.x, 0.0, 1.0)
	_pin_unit.y = clampf(_pin_unit.y, 0.0, 1.0)
	_has_pin = true
	var degrees := Geo.from_unit(_pin_unit)
	pin_moved.emit(degrees.x, degrees.y)
	queue_redraw()


## Zoom about a point, so the place under the cursor stays under the cursor.
func _zoom_about(pixel: Vector2, factor: float) -> void:
	var before := pixel_to_unit(pixel)
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var after := pixel_to_unit(pixel)
	_centre += before - after
	_clamp_centre()
	queue_redraw()


# ----------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_OCEAN, true)
	_draw_graticule()
	_draw_coastlines()
	_draw_pin()
	_draw_readout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.34, 0.37, 0.34), false, 1.0)


func _draw_graticule() -> void:
	# Every 30 degrees, with the equator and the prime meridian picked out.
	#
	# Stops at 150, not 180: Geo.to_unit wraps longitude into [-180, 180), so
	# asking it for +180 gives the LEFT edge of the map and the right edge ends
	# up with no line on it. The antimeridian is drawn from unit space instead.
	for lon in range(-180, 151, 30):
		var a := unit_to_pixel(Geo.to_unit(90.0, float(lon)))
		var b := unit_to_pixel(Geo.to_unit(-90.0, float(lon)))
		var colour := COLOR_EQUATOR if lon == 0 else COLOR_GRID
		draw_line(Vector2(a.x, 0.0), Vector2(b.x, size.y), colour, 1.0)

	var edge := unit_to_pixel(Vector2(1.0, 0.0))
	draw_line(Vector2(edge.x, 0.0), Vector2(edge.x, size.y), COLOR_GRID, 1.0)

	for lat in range(-60, 61, 30):
		var a := unit_to_pixel(Geo.to_unit(float(lat), -180.0))
		var b := unit_to_pixel(Geo.to_unit(float(lat), 180.0))
		var colour := COLOR_EQUATOR if lat == 0 else COLOR_GRID
		draw_line(Vector2(0.0, a.y), Vector2(size.x, b.y), colour, 1.0)


func _draw_coastlines() -> void:
	if coastlines == null or coastlines.is_empty():
		_draw_no_data_notice()
		return

	# Thicker as she zooms in, but never hairline-thin and never a ribbon.
	var width := clampf(1.0 + (_zoom - 1.0) * 0.12, 1.0, 2.2)
	for line in coastlines.lines:
		for run in _split_at_antimeridian(line):
			_draw_run(run, width)


## Draw one continuous run of lon/lat points, skipping it entirely when none
## of it is anywhere near the screen.
func _draw_run(run: PackedVector2Array, width: float) -> void:
	if run.size() < 2:
		return
	var pixels := PackedVector2Array()
	pixels.resize(run.size())
	var visible := false
	for i in run.size():
		var p := unit_to_pixel(Geo.to_unit(run[i].y, run[i].x))
		pixels[i] = p
		if not visible and p.x > -40.0 and p.x < size.x + 40.0 \
				and p.y > -40.0 and p.y < size.y + 40.0:
			visible = true
	if visible:
		draw_polyline(pixels, COLOR_COAST, width, true)


## Break a polyline wherever it jumps the 180th meridian.
##
## On an equirectangular map the two sides of the antimeridian are opposite
## edges of the picture, so a coastline that crosses it (Chukotka, Fiji, the
## Antarctic ring — and Natural Earth has points at exactly +-180) would
## otherwise be drawn as a line streaking right across the world.
static func _split_at_antimeridian(line: PackedVector2Array) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	for i in line.size():
		if i > 0 and absf(line[i].x - line[i - 1].x) > 180.0:
			if current.size() >= 2:
				runs.append(current)
			current = PackedVector2Array()
		current.append(line[i])
	if current.size() >= 2:
		runs.append(current)
	return runs


## Say so, rather than showing an empty blue rectangle and letting her wonder
## whether the map is broken.
func _draw_no_data_notice() -> void:
	if _font == null:
		return
	var text := "No map data — run tools/fetch_geo.py"
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	draw_string(_font, Vector2((size.x - width) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.46, 0.50, 0.54))


func _draw_pin() -> void:
	if not _has_pin:
		return
	var at := unit_to_pixel(_pin_unit)
	# A ring and a stem, not a filled dot: a dot hides the pixel it is on, and
	# the pixel it is on is the answer.
	draw_arc(at, 7.0, 0.0, TAU, 24, COLOR_PIN, 1.8, true)
	draw_line(at + Vector2(0, -3), at + Vector2(0, 3), COLOR_PIN, 1.2)
	draw_line(at + Vector2(-3, 0), at + Vector2(3, 0), COLOR_PIN, 1.2)


func _draw_readout() -> void:
	if _font == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	if _has_pin:
		var pin := Geo.from_unit(_pin_unit)
		lines.append("pin  %s" % format_lat_lon(pin.x, pin.y))
	if _hover_unit.x >= 0.0:
		var hover := Geo.from_unit(_hover_unit)
		lines.append(format_lat_lon(hover.x, hover.y))
	if _zoom > 1.01:
		lines.append("x%.1f" % _zoom)
	if lines.is_empty():
		return

	var y := size.y - 10.0
	for i in range(lines.size() - 1, -1, -1):
		draw_string(_font, Vector2(10.0, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_TEXT)
		y -= 17.0


## "48.9 N, 2.4 E" — hemispheres rather than signs, because a minus sign in
## front of a latitude is not what anyone means by south.
static func format_lat_lon(lat: float, lon: float) -> String:
	var ns := "N" if lat >= 0.0 else "S"
	var ew := "E" if lon >= 0.0 else "W"
	return "%.1f %s, %.1f %s" % [absf(lat), ns, absf(lon), ew]

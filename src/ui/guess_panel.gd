extends CanvasLayer
## Where and when. The guessing half of a round.
##
## The WHERE half has two forms, and which one leads depends on whether the
## map has any data:
##
##   * MapWidget, pinned — the real thing (plan §7.1), available once
##     data/geo/coastlines.json exists. tools/fetch_geo.py bakes it; no host
##     that serves Natural Earth is reachable from the machine that wrote this,
##     so the file cannot be committed here.
##   * A place list — every place in the album, shuffled. It was built first
##     because it made the round loop playable, and it stays: plan §10.6 wants
##     an easier mode for players who would rather not be tested on
##     coordinates, and this is precisely that.
##
## Both score through the same haversine path, because the list carries real
## coordinates and the map's pixels go through the same projection as the
## scoring.
##
## The WHEN half is the real calendar dial: decade, then year, then month, and
## it only asks for as much precision as the photograph actually carries.

const BODY_SIZE := 20
const HEADING_SIZE := 26

enum WhereMode { MAP, LIST }

var rounds: RoundController = null
var album: AlbumSchema.Album = null

var _root: Control = null
var _place_list: ItemList = null
var _map: MapWidget = null
var _map_box: VBoxContainer = null
var _list_box: VBoxContainer = null
var _mode_button: Button = null
var _where_mode: WhereMode = WhereMode.LIST
var _decade: HSlider = null
var _year: HSlider = null
var _month: OptionButton = null
var _date_label: Label = null
var _month_row: HBoxContainer = null
var _submit: Button = null
var _heading: Label = null

## Place label -> lat/lon, and the display order. Shuffled once per session so
## the list is not a giveaway of the hang order.
var _places: Array[Dictionary] = []
## Only used before setup() runs — the album's own dial always wins. Kept in
## step with AlbumSchema's defaults so a gallery walked with no album loaded
## shows the same dial as one with an undated album.
var _min_year := AlbumSchema.DIAL_DEFAULT_MIN
var _max_year := AlbumSchema.current_year()


func setup(controller: RoundController, a: AlbumSchema.Album,
		coastlines: CoastlineData = null) -> void:
	rounds = controller
	album = a
	_collect_places()
	_configure_year_range()

	var data := coastlines if coastlines != null else CoastlineData.load_baked()
	if _map != null:
		_map.setup(data)
	# The map leads when there is a map to look at; otherwise the list does,
	# and the toggle is there either way.
	_set_where_mode(WhereMode.MAP if not data.is_empty() else WhereMode.LIST)


func _ready() -> void:
	layer = 12
	_build()
	_root.visible = false

	EventBus.round_started.connect(_on_round_started)
	EventBus.guess_submitted.connect(_on_guess_submitted)


# ------------------------------------------------------------------ data

## Every place in the album becomes a candidate, so the answer is always
## present and the distractors are always plausible.
func _collect_places() -> void:
	_places.clear()
	if album == null:
		return

	var seen := {}
	for photo in album.photos:
		var label := photo.truth.place_label.strip_edges()
		if label.is_empty() or seen.has(label):
			continue
		if not photo.truth.has_location():
			continue
		seen[label] = true
		_places.append({
			"label": label,
			"lat": photo.truth.lat,
			"lon": photo.truth.lon,
		})

	_places.shuffle()


## The dial's ends. The album decides: the author's own values if they set
## any in the editor, otherwise a padded span around the photographs' dates
## (Album.guess_year_range does the padding — without it the earliest and
## latest photographs sit exactly at the ends and give themselves away).
func _configure_year_range() -> void:
	if album == null:
		return
	var span := album.guess_year_range()
	_min_year = span.x
	_max_year = span.y


# ----------------------------------------------------------------- build

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.018, 0.016, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.068, 0.060, 0.97)
	style.border_color = Color(0.36, 0.32, 0.27)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.offset_left = -560
	panel.offset_right = -40
	panel.offset_top = -330
	panel.offset_bottom = 330
	_root.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	_heading = _label("Where, and when?", HEADING_SIZE, Color(0.95, 0.92, 0.85))
	column.add_child(_heading)

	var where_row := HBoxContainer.new()
	where_row.add_theme_constant_override("separation", 12)
	where_row.add_child(_label("Where was this taken?", BODY_SIZE,
		Color(0.70, 0.66, 0.60)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where_row.add_child(spacer)
	_mode_button = Button.new()
	_mode_button.add_theme_font_size_override("font_size", 15)
	_mode_button.pressed.connect(_on_mode_pressed)
	where_row.add_child(_mode_button)
	column.add_child(where_row)

	_map_box = VBoxContainer.new()
	_map_box.add_theme_constant_override("separation", 6)
	column.add_child(_map_box)

	_map = MapWidget.new()
	_map.custom_minimum_size = Vector2(0, 250)
	_map.pin_moved.connect(_on_pin_moved)
	_map.pin_cleared.connect(_on_pin_cleared)
	_map_box.add_child(_map)
	_map_box.add_child(_label(
		"click a continent to zoom in, then click again to place your pin"
		+ " · drag to move · wheel to zoom",
		14, Color(0.50, 0.47, 0.43)))

	_list_box = VBoxContainer.new()
	column.add_child(_list_box)

	_place_list = ItemList.new()
	_place_list.custom_minimum_size = Vector2(0, 230)
	_place_list.add_theme_font_size_override("font_size", BODY_SIZE)
	_place_list.allow_reselect = true
	_place_list.item_selected.connect(_on_place_selected)
	_list_box.add_child(_place_list)

	column.add_child(_separator())

	column.add_child(_label("And when?", BODY_SIZE, Color(0.70, 0.66, 0.60)))

	_date_label = _label("", HEADING_SIZE, Color(0.95, 0.92, 0.85))
	column.add_child(_date_label)

	# Decade first, then year within it: two coarse steps beat one long slider
	# when the range is a whole lifetime.
	column.add_child(_label("Decade", 16, Color(0.60, 0.57, 0.52)))
	_decade = _slider(1.0)
	_decade.value_changed.connect(_on_date_changed)
	column.add_child(_decade)

	column.add_child(_label("Year", 16, Color(0.60, 0.57, 0.52)))
	_year = _slider(1.0)
	_year.min_value = 0
	_year.max_value = 9
	_year.value_changed.connect(_on_date_changed)
	column.add_child(_year)

	_month_row = HBoxContainer.new()
	_month_row.add_theme_constant_override("separation", 10)
	_month_row.add_child(_label("Month", 16, Color(0.60, 0.57, 0.52)))
	_month = OptionButton.new()
	_month.add_theme_font_size_override("font_size", BODY_SIZE)
	_month.add_item("(not sure)", 0)
	const MONTHS := ["January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December"]
	for i in MONTHS.size():
		_month.add_item(MONTHS[i], i + 1)
	_month.item_selected.connect(func(_i: int) -> void: _refresh_date_label())
	_month_row.add_child(_month)
	column.add_child(_month_row)

	column.add_child(_separator())

	_submit = Button.new()
	_submit.text = "That's my answer"
	_submit.custom_minimum_size = Vector2(0, 52)
	_submit.add_theme_font_size_override("font_size", 22)
	_submit.disabled = true
	_submit.pressed.connect(_on_submit)
	column.add_child(_submit)

	column.add_child(_label(
		"U  clear the photograph a little      H  ask him      Esc  step back",
		15, Color(0.52, 0.49, 0.45)))


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _slider(step: float) -> HSlider:
	var s := HSlider.new()
	s.step = step
	s.custom_minimum_size = Vector2(0, 30)
	return s


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 14)
	return sep


# ---------------------------------------------------------------- rounds

func _on_round_started(_index: int) -> void:
	_populate()
	_root.visible = true
	_place_list.deselect_all()
	# The month goes back to "(not sure)" every round. It used to persist, so
	# two month-precision photographs in a row meant the second one opened
	# already answered with the first one's month — and submitting without
	# touching it scored that month as her guess.
	if _month != null:
		_month.select(0)
	if _map != null:
		_map.clear_pin()
		_map.reset_view()
	_refresh_submit()

	var photo := rounds.active_photo()
	var precision := AlbumSchema.DatePrecision.YEAR
	if photo != null:
		precision = photo.truth.date_precision

	# Only ask for the precision the photograph actually carries: a scan that
	# only knows its decade must not be scored against a month (plan §6.3).
	_month_row.visible = precision == AlbumSchema.DatePrecision.MONTH \
		or precision == AlbumSchema.DatePrecision.DAY
	_year.editable = precision != AlbumSchema.DatePrecision.DECADE

	_heading.text = "Where, and when?"
	if precision == AlbumSchema.DatePrecision.DECADE:
		_heading.text = "Where, and roughly when?"

	_refresh_date_label()


func _populate() -> void:
	_place_list.clear()
	_configure_dial()

	if _places.is_empty():
		# Walking the gallery with no album loaded: the pictures are
		# placeholders and have no answers behind them. Say so rather than
		# showing an empty box.
		_place_list.add_item("No album loaded — nothing to guess")
		_place_list.set_item_disabled(0, true)
		_place_list.add_item("Load a .ccalbum from the menu to play")
		_place_list.set_item_disabled(1, true)
		return

	for place in _places:
		_place_list.add_item(String(place["label"]))


## The two sliders' travel, from the dial's ends.
##
## This used to live at the end of _populate, after its early return — so a
## gallery walked with no album never configured the sliders at all and the
## decade slider kept Range's default 0..100, which let the dial read 2900.
func _configure_dial() -> void:
	var decades := (_max_year - _min_year) / 10
	_decade.min_value = 0
	_decade.max_value = maxi(1, decades)
	if _decade.value < _decade.min_value or _decade.value > _decade.max_value:
		_decade.value = float(decades) * 0.5


func _set_where_mode(mode: WhereMode) -> void:
	_where_mode = mode
	var have_map := _map != null and _map.coastlines != null \
		and not _map.coastlines.is_empty()
	if _map_box != null:
		_map_box.visible = mode == WhereMode.MAP
	if _list_box != null:
		_list_box.visible = mode == WhereMode.LIST
	if _mode_button != null:
		_mode_button.text = "Use the list instead" if mode == WhereMode.MAP \
			else "Use the map instead"
		# Offering a map with nothing on it is not an offer.
		_mode_button.disabled = not have_map and mode == WhereMode.LIST
	_refresh_submit()


func _on_mode_pressed() -> void:
	_set_where_mode(WhereMode.LIST if _where_mode == WhereMode.MAP \
		else WhereMode.MAP)


func _on_pin_moved(_lat: float, _lon: float) -> void:
	_refresh_submit()


func _on_pin_cleared() -> void:
	_refresh_submit()


## She can answer once she has said where, by whichever means is showing.
func _refresh_submit() -> void:
	if _submit == null:
		return
	if _where_mode == WhereMode.MAP:
		_submit.disabled = _map == null or not _map.has_pin()
	else:
		_submit.disabled = _places.is_empty() \
			or _place_list.get_selected_items().is_empty()


func _on_place_selected(_index: int) -> void:
	_refresh_submit()


func _on_date_changed(_value: float) -> void:
	_refresh_date_label()


func _guess_year() -> int:
	# Clamped to the dial's own ends: the decade slider moves in tens and the
	# year slider adds nine, so the last notch of a dial ending in 2026 could
	# otherwise be answered as 2029.
	return clampi(_min_year + int(_decade.value) * 10 + int(_year.value),
		_min_year, _max_year)


func _refresh_date_label() -> void:
	var year := _guess_year()
	var month := _month.get_selected_id() if _month_row.visible else 0
	if month > 0:
		var d := AlbumSchema.PhotoDate.new()
		d.year = year
		d.month = month
		_date_label.text = d.label()
	else:
		_date_label.text = str(year)


func _on_submit() -> void:
	if rounds == null:
		return

	var date := AlbumSchema.PhotoDate.new()
	date.year = _guess_year()
	if _month_row.visible:
		date.month = _month.get_selected_id()

	var lat := NAN
	var lon := NAN
	var label := ""

	if _where_mode == WhereMode.MAP:
		if _map == null or not _map.has_pin():
			return
		var pin := _map.pin_lat_lon()
		lat = pin.x
		lon = pin.y
		# What she gets told back is where she pointed, in words.
		label = MapWidget.format_lat_lon(lat, lon)
	else:
		var selected := _place_list.get_selected_items()
		if selected.is_empty():
			return
		var place: Dictionary = _places[selected[0]]
		lat = float(place["lat"])
		lon = float(place["lon"])
		label = String(place["label"])

	_root.visible = false
	rounds.submit_guess(lat, lon, date, label)


func _on_guess_submitted(_index: int) -> void:
	_root.visible = false


# ----------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return

	if event.is_action_pressed(&"ui_cancel_custom"):
		_root.visible = false
		rounds.cancel_guessing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"unblur"):
		rounds.purchase_unblur()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ask_hint"):
		rounds.purchase_hint()
		get_viewport().set_input_as_handled()

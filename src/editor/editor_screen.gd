extends Control
## "Create settings": everything that goes into one playable file, in three
## steps.
##
##   1. GENERAL     the title, the note at the end, the two characters, the
##                  last line, and the calendar range.
##   2. PHOTOGRAPHS the source folder or zip, the wall in hang order, and
##                  everything about the selected photograph.
##   3. SAVE        what is still missing, and the button that writes it.
##
## Tabs rather than one screen. All of it used to be visible at once — three
## columns, forty controls, and the file's own fields above them — so the first
## thing an author saw was all of it. Each tab ends with the button that goes
## to the next one, so there is an order to follow if you want one.
##
## All the model logic lives in EditorSession, which does no IO; this reads
## bytes through Platform and hands them over. On the web that means a lazy
## File handle per source file, so a folder with a thousand photographs in it
## costs nothing until one is actually chosen (plan §5.2).
##
## Built in code rather than as a .tscn for the same reason the menu is: it is
## mostly wiring, and a scene file of two hundred nodes is harder to change
## than this.

const BODY := 16
const LABEL := 14
const HEADING := 22

var session: EditorSession = null

var _selected := -1
var _pending_source := -1

# --- columns ---
var _source_list: ItemList = null
var _wall_list: ItemList = null
var _detail: VBoxContainer = null
var _problem_text: RichTextLabel = null
var _status: Label = null

# --- album-level fields ---
var _title: LineEdit = null
var _tabs: TabContainer = null
var _cast_editor: CastEditor = null
var _summary: Label = null
var _guess_from: SpinBox = null
var _guess_to: SpinBox = null
var _dial_note: Label = null

# --- per-photo fields ---
var _photo_title: LineEdit = null
var _description: TextEdit = null
var _place: LineEdit = null
var _lat: SpinBox = null
var _lon: SpinBox = null
var _precision: OptionButton = null
var _year: SpinBox = null
var _month: SpinBox = null
var _day: SpinBox = null
var _hints: Array[TextEdit] = []
var _monologue: TextEdit = null
var _approved: CheckBox = null
var _private: TextEdit = null
var _map: MapWidget = null
var _source_note: Label = null
var _preview: TextureRect = null
var _date_note: Label = null
## What an in-flight export will be called, kept so the status line can report
## the truth once the platform says whether it was written.
var _pending_export := ""
## Why "Edit this album" could not open the loaded album, if it could not.
var _adopt_failed := ""

var _choose_folder: Button = null
var _choose_archive: Button = null
var _add_button: Button = null
var _export_button: Button = null


func _ready() -> void:
	GameState.phase = GameState.Phase.EDITOR
	session = EditorSession.new()
	session.changed.connect(_refresh)

	_build()

	Platform.files_picked.connect(_on_files_picked)
	Platform.pick_cancelled.connect(_on_pick_cancelled)
	Platform.file_delivered.connect(_on_file_delivered)

	# Arrived from the album preview's "Edit this album": the album is already
	# loaded in AlbumService, and the flag is the only thing a scene change
	# could carry across.
	if GameState.take_edit_request() and AlbumService.has_album():
		var error := session.adopt(AlbumService.loaded)
		if error.is_empty():
			_read_album_fields()
			_select(0 if session.slot_count() > 0 else -1)
			_set_status("Editing '%s'. Saving writes a new file; the one you"
				% session.album.title
				+ " opened is left alone.")
			return
		# Say why, and do not then overwrite it with the cheerful line at the
		# bottom of this function: the author pressed "Edit this album" and
		# needs to know it did not happen.
		_adopt_failed = error

	# A new album starts with a dial that spans their lifetime rather than two
	# zeroes: 1980 to this year. The author can move either end, or put a zero
	# back to have it worked out from the photographs.
	session.album.guess_year_min = AlbumSchema.DIAL_DEFAULT_MIN
	session.album.guess_year_max = AlbumSchema.current_year()

	# And with two characters already in it, from this machine's own default.
	# They travel inside the file, so the person it is made for meets the
	# author's two characters and not whatever their own machine has saved.
	var cast := CastProfile.load_saved()
	session.album.cast = cast.to_dict()
	session.album.curator_player_name = cast.main_name()
	session.album.curator_voice_name = cast.side_name()
	_read_album_fields()

	_refresh()
	if _adopt_failed.is_empty():
		_set_status("")
	else:
		_set_status("%s Starting new settings instead." % _adopt_failed)


# ------------------------------------------------------------------- build

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.050, 0.046)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)

	# One tab per step, in the order they are done. Everything used to be on
	# screen at once — three columns, forty controls and the album's own fields
	# above them — which meant the first thing an author saw was all of it.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	_tabs.add_theme_font_size_override("font_size", BODY)
	rows.add_child(_tabs)

	# A TabContainer titles its tabs from the child node's NAME, and a node
	# name may not contain a dot — "1. General" came out as "1_ General". So
	# the names are plain and the titles are set after.
	var general := _build_general()
	general.name = "General"
	_tabs.add_child(general)

	var photos := _build_photos()
	photos.name = "Photographs"
	_tabs.add_child(photos)

	var review := _build_review()
	review.name = "Save"
	_tabs.add_child(review)

	_tabs.set_tab_title(0, "  1 · General  ")
	_tabs.set_tab_title(1, "  2 · Photographs  ")
	_tabs.set_tab_title(2, "  3 · Save  ")

	rows.add_child(_build_footer())


## The step-through button at the bottom of a tab. A tab that is the end of
## the flow gets none.
func _next_button(text: String, to_tab: int) -> Control:
	var row := HBoxContainer.new()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var go := func() -> void:
		if _tabs != null:
			_tabs.current_tab = to_tab
	row.add_child(_action(text, go, 220))
	return row


# ---------------------------------------------------------------- 1. general

## Title, note, the two characters, and the calendar range — everything that is
## true of the whole file rather than of one photograph.
func _build_general() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_heading("Title"))
	_title = LineEdit.new()
	_title.placeholder_text = "For Maggie"
	_title.text_changed.connect(func(t: String) -> void:
		session.album.title = t)
	column.add_child(_title)

	column.add_child(_separator())
	column.add_child(_heading("Characters"))

	_cast_editor = CastEditor.new()
	_cast_editor.custom_minimum_size = Vector2(0, 700)
	_cast_editor.setup(CastProfile.for_album(session.album))
	_cast_editor.changed.connect(_on_cast_changed)
	column.add_child(_cast_editor)

	column.add_child(_separator())
	column.add_child(_heading("Set guessing range"))

	var dial := HBoxContainer.new()
	dial.add_theme_constant_override("separation", 8)
	dial.add_child(_fixed_small("from", 40))
	# Bounded by photography at one end and today at the other. The old boxes
	# went to 2100, which let a file ship a dial with seventy years of future
	# on it — and a zip of scans stamped with this year's upload date used to
	# drag the worked-out end there by itself.
	_guess_from = _spin(0.0, float(AlbumSchema.current_year()), 1.0, 96)
	_guess_from.value_changed.connect(func(v: float) -> void:
		session.album.guess_year_min = int(v)
		_refresh_dial_note())
	# _spin() expands to fill, which is what the narrow detail column needs;
	# out here the row is 1500 px wide and two expanding boxes came out half a
	# screen each. Let them keep their own width and give the rest to the
	# spacer.
	_guess_from.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dial.add_child(_guess_from)
	dial.add_child(_fixed_small("to", 24))
	_guess_to = _spin(0.0, float(AlbumSchema.current_year()), 1.0, 96)
	_guess_to.value_changed.connect(func(v: float) -> void:
		session.album.guess_year_max = int(v)
		_refresh_dial_note())
	_guess_to.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	dial.add_child(_guess_to)
	var dial_spacer := Control.new()
	dial_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dial.add_child(dial_spacer)
	column.add_child(dial)

	_dial_note = _small("")
	column.add_child(_dial_note)

	column.add_child(_separator())
	column.add_child(_next_button("Photographs  →", 1))

	return scroll


## The cast is part of the file, so a change to it is a change to the file.
func _on_cast_changed() -> void:
	if _cast_editor == null or _cast_editor.cast == null:
		return
	session.album.cast = _cast_editor.cast.to_dict()
	# The names the lines are written with follow the characters, rather than
	# being typed a second time in two fields of their own.
	session.album.curator_player_name = _cast_editor.cast.main_name()
	session.album.curator_voice_name = _cast_editor.cast.side_name()
	_refresh_problems()


## Say what the dial will actually show, whether the author set the ends or
## left them to the photographs. Guessing what "0" means is not the author's
## job.
func _refresh_dial_note() -> void:
	if _dial_note == null or session == null:
		return
	var span := session.album.guess_year_range()
	var how := "from your own ends"
	if session.album.guess_year_min <= 0 or session.album.guess_year_max <= 0:
		how = "worked out from the photographs"
	_dial_note.text = "the dial will run from %d to %d (%s)" \
		% [span.x, span.y, how]


# ------------------------------------------------------------- 2. photographs

func _build_photos() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)

	columns.add_child(_build_sources())
	columns.add_child(_build_wall())
	columns.add_child(_build_detail())

	column.add_child(_next_button("Save  →", 2))
	return column


# ------------------------------------------------------------------ 3. save

func _build_review() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_heading("What is left to do"))

	_problem_text = RichTextLabel.new()
	_problem_text.bbcode_enabled = true
	_problem_text.fit_content = true
	_problem_text.custom_minimum_size = Vector2(0, 260)
	_problem_text.add_theme_font_size_override("normal_font_size", BODY)
	column.add_child(_problem_text)

	column.add_child(_separator())

	_summary = _small("")
	column.add_child(_summary)

	var save_row := HBoxContainer.new()
	_export_button = _action("Save the settings", _on_export, 260)
	save_row.add_child(_export_button)
	var save_spacer := Control.new()
	save_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(save_spacer)
	column.add_child(save_row)

	return scroll


func _build_sources() -> Control:
	var box := _panel()
	box.custom_minimum_size = Vector2(300, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	column.add_child(_heading("Load photos"))

	_choose_folder = Button.new()
	_choose_folder.text = "Choose a folder…"
	_choose_folder.pressed.connect(_on_choose_folder)
	column.add_child(_choose_folder)

	_choose_archive = Button.new()
	_choose_archive.text = "Open a .zip…"
	_choose_archive.tooltip_text = "A Google Photos download, or a Takeout" \
		+ " export. Dates and locations come across with it."
	_choose_archive.pressed.connect(_on_choose_archive)
	column.add_child(_choose_archive)

	_source_list = ItemList.new()
	_source_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_source_list.add_theme_font_size_override("font_size", LABEL)
	# Through the same guard as the button: on web `Platform.read_file` awaits
	# a JS callback, and a second double-click during it re-entered _on_add and
	# hung the same photograph twice.
	_source_list.item_activated.connect(func(_i: int) -> void:
		if _pending_source < 0 and not session.is_full():
			_on_add())
	column.add_child(_source_list)

	_add_button = Button.new()
	_add_button.text = "Select"
	_add_button.pressed.connect(_on_add)
	column.add_child(_add_button)

	return box


func _build_wall() -> Control:
	var box := _panel()
	box.custom_minimum_size = Vector2(300, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	column.add_child(_heading("Selected Photos"))

	_wall_list = ItemList.new()
	_wall_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wall_list.add_theme_font_size_override("font_size", LABEL)
	# Thumbnails beside the lines: ten filenames all look alike, ten
	# photographs do not.
	_wall_list.fixed_icon_size = Vector2i(56, 42)
	_wall_list.icon_mode = ItemList.ICON_MODE_LEFT
	_wall_list.item_selected.connect(_on_wall_selected)
	column.add_child(_wall_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	column.add_child(buttons)
	buttons.add_child(_action("Up", func() -> void:
		if _selected > 0:
			session.move_slot(_selected, _selected - 1)
			_select(_selected - 1)))
	buttons.add_child(_action("Down", func() -> void:
		if _selected >= 0 and _selected < session.slot_count() - 1:
			session.move_slot(_selected, _selected + 1)
			_select(_selected + 1)))
	buttons.add_child(_action("Take down", func() -> void:
		if _selected >= 0:
			session.remove_slot(_selected)
			_select(mini(_selected, session.slot_count() - 1))))

	return box


func _build_detail() -> Control:
	var box := _panel()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_detail)

	# The picture itself, at the top, because "which one is this" is the
	# question every other field on this panel depends on.
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(0, 200)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail.add_child(_preview)

	_source_note = _small("")
	_detail.add_child(_source_note)

	_detail.add_child(_small("Title"))
	_photo_title = LineEdit.new()
	_photo_title.text_changed.connect(func(t: String) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.content.title = t))
	_detail.add_child(_photo_title)

	_detail.add_child(_small("Description"))
	_description = _text_area(70)
	_description.text_changed.connect(func() -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.content.description = _description.text))
	_detail.add_child(_description)

	_detail.add_child(_separator())
	_detail.add_child(_small("Place"))

	_place = LineEdit.new()
	_place.placeholder_text = "Whitby, England"
	_place.text_changed.connect(func(t: String) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.truth.place_label = t))
	_detail.add_child(_place)

	_map = MapWidget.new()
	_map.custom_minimum_size = Vector2(0, 190)
	_map.pin_moved.connect(_on_map_pin)
	_detail.add_child(_map)

	var coords := HBoxContainer.new()
	coords.add_theme_constant_override("separation", 8)
	coords.add_child(_fixed_small("lat", 30))
	_lat = _spin(-90.0, 90.0, 0.0001, 92)
	_lat.value_changed.connect(func(v: float) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.truth.lat = v)
		_sync_map())
	coords.add_child(_lat)
	coords.add_child(_fixed_small("lon", 30))
	_lon = _spin(-180.0, 180.0, 0.0001, 92)
	_lon.value_changed.connect(func(v: float) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.truth.lon = v)
		_sync_map())
	coords.add_child(_lon)
	_detail.add_child(coords)

	_detail.add_child(_separator())
	_detail.add_child(_small("When"))

	# THE DATE ROW. This was one HBox of four controls at 108 px each plus
	# their labels — about 560 px of contents in a column that is often 400
	# wide, inside a ScrollContainer with horizontal scrolling switched off.
	# The year box was half cut off and the month and day boxes were off the
	# edge entirely, so a photograph that arrived without a date had nowhere to
	# be given one. Two rows, and boxes narrow enough to fit.
	_date_note = _small("")
	_detail.add_child(_date_note)

	# Four columns, so the three boxes wrap onto two short rows instead of one
	# long one. The detail column is about 350 px wide on a 1024-wide window
	# and the old single row needed six hundred.
	var when := GridContainer.new()
	when.columns = 4
	when.add_theme_constant_override("h_separation", 6)
	when.add_theme_constant_override("v_separation", 4)
	when.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	when.add_child(_fixed_small("year", 34))
	_year = _spin(0.0, float(AlbumSchema.current_year()), 1.0, 72)
	when.add_child(_year)
	when.add_child(_fixed_small("month", 42))
	_month = _spin(0.0, 12.0, 1.0, 58)
	when.add_child(_month)
	when.add_child(_fixed_small("day", 28))
	_day = _spin(0.0, 31.0, 1.0, 58)
	when.add_child(_day)
	for spin in [_year, _month, _day]:
		spin.value_changed.connect(func(_v: float) -> void: _write_date())
	_detail.add_child(when)

	# Stacked, not side by side: two buttons in a row needed 346 px of the
	# column's 320. In here, vertical space is cheap and horizontal is not.
	var when_buttons := VBoxContainer.new()
	when_buttons.add_theme_constant_override("separation", 4)
	when_buttons.add_child(_action("Year from the one above",
		_on_copy_year, 0))
	when_buttons.add_child(_action("Fill in the blank years",
		_on_fill_years, 0))
	_detail.add_child(when_buttons)

	_detail.add_child(_small("Scored to"))
	_precision = OptionButton.new()
	_precision.add_item("to the day", AlbumSchema.DatePrecision.DAY)
	_precision.add_item("the month", AlbumSchema.DatePrecision.MONTH)
	_precision.add_item("the year", AlbumSchema.DatePrecision.YEAR)
	_precision.add_item("the decade", AlbumSchema.DatePrecision.DECADE)
	_precision.item_selected.connect(func(_i: int) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.truth.date_precision = _precision.get_selected_id() as AlbumSchema.DatePrecision))
	_detail.add_child(_precision)

	_detail.add_child(_separator())
	_detail.add_child(_small("Hints — each one costs more than the last"))

	const HINT_LABELS := ["Hint 1", "Hint 2", "Hint 3"]
	_hints.clear()
	for i in 3:
		_detail.add_child(_small(HINT_LABELS[i]))
		var field := _text_area(46)
		var index := i
		field.text_changed.connect(func() -> void: _write_hint(index))
		_detail.add_child(field)
		_hints.append(field)

	# The validator refuses to export until this is ticked, per photograph.
	# Baked lines are the one part of the album the author did not write, so
	# somebody has to say they have read them (plan §8.3).
	_approved = CheckBox.new()
	# Short, because a Button's width is its text and this column is narrow:
	# the long version of this line needed 381 px in a 320 px column and hung
	# off the edge. The Save tab is where an unticked photograph is named.
	_approved.text = "Hints approved"
	_approved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_approved.add_theme_font_size_override("font_size", LABEL)
	_approved.toggled.connect(func(on: bool) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.curator.approved_by_author = on))
	_detail.add_child(_approved)

	_detail.add_child(_small("Line when it is revealed"))
	_monologue = _text_area(60)
	_monologue.text_changed.connect(func() -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.curator.reveal_monologue = _monologue.text))
	_detail.add_child(_monologue)

	_detail.add_child(_separator())
	_detail.add_child(_small("Private note"))
	_private = _text_area(46)
	_private.text_changed.connect(func() -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.content.private_note = _private.text))
	_detail.add_child(_private)

	return box


func _build_footer() -> Control:
	var box := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", LABEL)
	_status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	row.add_child(_status)

	var back := func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
	row.add_child(_action("Back to the menu", back, 170))

	return box


# ------------------------------------------------------------- small parts

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.078, 0.070)
	style.border_color = Color(0.24, 0.22, 0.19)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", HEADING)
	l.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	return l


func _small(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", LABEL)
	l.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52))
	return l


## A label that will not be squeezed into a vertical column of letters by the
## row it is in. "lat" next to a SpinBox came out as l-a-t stacked.
func _fixed_small(text: String, width: int) -> Label:
	var l := _small(text)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(width, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _text_area(height: int) -> TextEdit:
	var t := TextEdit.new()
	t.custom_minimum_size = Vector2(0, height)
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.add_theme_font_size_override("font_size", BODY)
	return t


func _spin(low: float, high: float, step: float, width: int = 108) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.allow_greater = false
	s.allow_lesser = false
	s.custom_minimum_size = Vector2(width, 0)
	# Otherwise a box in a full-width row keeps its minimum and the row's
	# labels take the rest, which is what pushed the date fields off the edge.
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _action(text: String, handler: Callable, width: int = 180) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 34)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", BODY)
	b.pressed.connect(handler)
	return b


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	return sep


# ------------------------------------------------------------------ picking

## Nothing is disabled while a dialog is open; see main_menu.gd for why.
func _on_choose_folder() -> void:
	if Platform.is_picking():
		_set_status("There is already a file dialog open.")
		return
	_set_status("Choose the folder your photographs are in…")
	Platform.pick_image_folder()


func _on_choose_archive() -> void:
	if Platform.is_picking():
		_set_status("There is already a file dialog open.")
		return
	_set_status("Choose a .zip of photographs — a Google Photos download, or"
		+ " a Takeout export…")
	Platform.pick_photo_archive()


func _on_open_album() -> void:
	if Platform.is_picking():
		_set_status("There is already a file dialog open.")
		return
	_set_status("Choose a settings file to open…")
	Platform.pick_album_file()


func _on_pick_cancelled() -> void:
	_set_status("")


## One handler for both pickers, because Platform has one signal. An album
## file arrives as a single .ccalbum; a folder arrives as many images.
func _on_files_picked(files: Array) -> void:
	if files.is_empty():
		return

	var first: Platform.PickedFile = files[0]
	if files.size() == 1 and first.extension() == AlbumIO.ALBUM_EXTENSION:
		await _open_album_file(first)
		return
	if files.size() == 1 and first.extension() == "zip":
		await _open_archive_file(first)
		return

	var kept := session.set_sources(files)
	_set_status("%d photograph%s in that folder%s."
		% [kept, "" if kept == 1 else "s",
		   "" if kept == files.size()
		   else " (%d other files ignored)" % (files.size() - kept)])


func _open_album_file(file: Platform.PickedFile) -> void:
	var bytes: PackedByteArray = await Platform.read_file(file)
	if bytes.is_empty():
		_set_status("Could not read %s." % file.name)
		return

	var loaded := AlbumIO.load_from_bytes(bytes)
	var error := session.adopt(loaded)
	if not error.is_empty():
		# The loader opened a ZIPReader to get this far; a failed adopt used to
		# walk away and leave it open, one handle per attempt.
		loaded.close()
		_set_status(error)
		return

	_read_album_fields()
	_select(0 if session.slot_count() > 0 else -1)
	_set_status("Opened '%s'." % session.album.title)


## A zip of photographs: a Google Photos album download, or a Takeout export.
func _open_archive_file(file: Platform.PickedFile) -> void:
	_set_status("Opening %s…" % file.name)

	var bytes: PackedByteArray = await Platform.read_file(file)
	if bytes.is_empty():
		_set_status("Could not read %s." % file.name)
		return

	var archive := PhotoArchive.from_bytes(bytes)
	var error := session.set_archive(archive)
	if not error.is_empty():
		_set_status("%s: %s" % [file.name, error])
		return

	_select(-1)
	var with_metadata := session.archive.with_sidecar_count()
	_set_status("%d photographs in %s, %d of them with Google's own dates and"
		% [session.archive.count(), file.name, with_metadata]
		+ " locations. Pick the ten you want.")


func _on_add() -> void:
	var chosen := _source_list.get_selected_items()
	if chosen.is_empty():
		_set_status("Pick a photograph from your folder first.")
		return
	if session.is_full():
		_set_status("The wall is full. Take one down to hang another.")
		return

	var index: int = chosen[0]
	if index < 0 or index >= session.source_count():
		return

	var source_name := session.source_name(index)
	_pending_source = index
	_set_status("Reading %s…" % source_name)
	_add_button.disabled = true

	var error := ""
	if session.archive != null:
		# Straight out of the zip: no await, and no Platform round trip.
		error = session.add_from_archive(index)
	else:
		var file: Platform.PickedFile = session.sources[index]
		var bytes: PackedByteArray = await Platform.read_file(file)
		if bytes.is_empty():
			error = "could not read it"
		else:
			error = session.add_photo(file.name, bytes)

	_add_button.disabled = false
	_pending_source = -1

	if not error.is_empty():
		_set_status("%s: %s" % [source_name, error])
		return

	_select(session.slot_count() - 1)
	_set_status("Hung %s.%s" % [source_name, _what_came_with_it()])


## What the photograph brought with it, so the author knows which fields they
## do not have to type.
func _what_came_with_it() -> String:
	var slot := session.slot_at(_selected)
	if slot == null:
		return ""

	var found: PackedStringArray = PackedStringArray()
	if slot.photo.truth.has_location():
		found.append("where it was taken")
	if slot.photo.truth.date.is_set():
		found.append("when")
	if not slot.photo.content.description.is_empty():
		found.append("its caption")
	if found.is_empty():
		return ""

	var source := "The photograph knew"
	if slot.from_sidecar:
		source = "Google's export knew"
	return " %s %s." % [source, _join_english(found)]


static func _join_english(parts: PackedStringArray) -> String:
	if parts.size() <= 1:
		return "" if parts.is_empty() else parts[0]
	if parts.size() == 2:
		return "%s and %s" % [parts[0], parts[1]]
	var head: PackedStringArray = PackedStringArray()
	for i in parts.size() - 1:
		head.append(parts[i])
	return "%s and %s" % [", ".join(head), parts[parts.size() - 1]]


# ---------------------------------------------------------------- selection

func _on_wall_selected(index: int) -> void:
	_select(index)


func _select(index: int) -> void:
	_selected = index
	_refresh()
	_read_photo_fields()


func _current() -> AlbumSchema.Photo:
	var slot := session.slot_at(_selected)
	return slot.photo if slot != null else null


func _have_selection() -> bool:
	return session.slot_at(_selected) != null


## Run `action` against the selected photograph, if there is one. Every field
## handler goes through this so none of them has to null-check.
func _with_photo(action: Callable) -> void:
	var photo := _current()
	if photo == null:
		return
	action.call(photo)
	_refresh_problems()
	_refresh_wall_labels()


## The year off the photograph above this one on the wall. A folder of scans
## from the same summer is the common case, and typing 1974 ten times is not
## the author's job.
func _on_copy_year() -> void:
	if not _have_selection():
		_set_status("Pick a photograph on the wall first.")
		return
	if _selected <= 0:
		_set_status("There is nothing above this one to copy a year from.")
		return
	var above := session.slot_at(_selected - 1)
	if above == null or not above.photo.truth.date.is_set():
		_set_status("The one above it has no year either.")
		return

	var year := above.photo.truth.date.year
	_year.set_value_no_signal(float(year))
	_write_date()
	_read_photo_fields()
	_set_status("Dated %d, the same as the one above it." % year)


## Stamp this year onto every photograph that has none. Nothing that already
## carries a date is touched — the point is the scans that arrived blank.
func _on_fill_years() -> void:
	# The year box belongs to the selected photograph. With nothing selected it
	# still held the LAST one's value and still stamped it onto everything —
	# which `_open_archive_file` made reachable, because it deselects while
	# photographs are still hung.
	if not _have_selection():
		_set_status("Pick a photograph on the wall first.")
		return
	var year := int(_year.value)
	if year <= 0:
		_set_status("Put a year in the box first.")
		return

	var filled := 0
	for i in session.slot_count():
		var photo := session.slot_at(i).photo
		if photo.truth.date.is_set():
			continue
		photo.truth.date.year = year
		filled += 1

	if filled == 0:
		_set_status("They all have a year already.")
		return
	_refresh()
	_read_photo_fields()
	_set_status("Gave %d photograph%s the year %d. The ones that already had"
		% [filled, "" if filled == 1 else "s", year]
		+ " a date were left alone.")


func _write_date() -> void:
	_with_photo(func(p: AlbumSchema.Photo) -> void:
		p.truth.date.year = int(_year.value)
		p.truth.date.month = int(_month.value)
		p.truth.date.day = int(_day.value))


func _write_hint(index: int) -> void:
	_with_photo(func(p: AlbumSchema.Photo) -> void:
		var hints := p.curator.hints
		while hints.size() < 3:
			hints.append("")
		hints[index] = _hints[index].text
		p.curator.hints = hints)


func _on_map_pin(lat: float, lon: float) -> void:
	_lat.set_value_no_signal(lat)
	_lon.set_value_no_signal(lon)
	_with_photo(func(p: AlbumSchema.Photo) -> void:
		p.truth.lat = lat
		p.truth.lon = lon)


func _sync_map() -> void:
	var photo := _current()
	if photo == null or _map == null:
		return
	if photo.truth.has_location():
		_map.set_pin_lat_lon(photo.truth.lat, photo.truth.lon)
		# Zoom to where it already is, so the next click nudges the pin rather
		# than navigating. In the editor the author is correcting a location,
		# not being quizzed on it.
		if _map.is_world_view():
			_map.focus_around(photo.truth.lat, photo.truth.lon)
	else:
		_map.clear_pin()


# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	_refresh_dial_note()
	_refresh_summary()
	_refresh_sources()
	_refresh_wall_labels()
	_refresh_problems()

	var have := _selected >= 0 and _selected < session.slot_count()
	_detail.modulate.a = 1.0 if have else 0.45
	# Actually inert, not just faded: a field nothing can be written to must
	# not accept typing.
	_detail.mouse_filter = Control.MOUSE_FILTER_PASS if have \
		else Control.MOUSE_FILTER_IGNORE
	_detail.process_mode = Node.PROCESS_MODE_INHERIT if have \
		else Node.PROCESS_MODE_DISABLED
	_add_button.disabled = session.is_full() or _pending_source >= 0
	_export_button.disabled = not session.can_export()


func _refresh_sources() -> void:
	var previous := _source_list.get_selected_items()
	_source_list.clear()
	for i in session.source_count():
		_source_list.add_item(session.source_label(i))
	if not previous.is_empty() and previous[0] < _source_list.item_count:
		_source_list.select(previous[0])


func _refresh_wall_labels() -> void:
	_wall_list.clear()
	for i in session.slot_count():
		var slot := session.slot_at(i)
		var photo := slot.photo
		var where := photo.truth.place_label
		if where.is_empty():
			where = "(nowhere yet)"
		var when := photo.truth.date.label() if photo.truth.date.is_set() \
			else "(no date)"
		_wall_list.add_item("%d.  %s — %s" % [i + 1, where, when],
			slot.thumbnail())
	if _selected >= 0 and _selected < _wall_list.item_count:
		_wall_list.select(_selected)


func _refresh_problems() -> void:
	var problems := session.problems(true)
	var errors := AlbumValidator.count_of(problems, AlbumValidator.Severity.ERROR)
	var warnings := AlbumValidator.count_of(problems, AlbumValidator.Severity.WARNING)

	# "Ready to save" when there is nothing left that stops a save, not only
	# when the list is literally empty: an album whose one remaining problem is
	# a NOTE used to print "0 things to fix, 0 worth a look" over an empty
	# list, with the Save button enabled.
	if errors == 0 and warnings == 0:
		_problem_text.text = "[color=#8fbf8f]Ready to save.[/color]"
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%d thing%s to fix[/b], %d worth a look"
		% [errors, "" if errors == 1 else "s", warnings])

	# Counted over the ones that are actually listed. The tail used to be
	# `problems.size() - shown`, which included the notes it had just skipped,
	# so it said "and 8 more" when seven remained — and "and 0 more" when the
	# list happened to end exactly at the limit.
	var listed := errors + warnings
	var shown := 0
	for problem in problems:
		if problem.severity == AlbumValidator.Severity.NOTE:
			continue
		var colour := "#e08080" if problem.severity == AlbumValidator.Severity.ERROR \
			else "#d8c070"
		# Which photograph, by its place on the wall rather than by its id: the
		# author never sees an id anywhere else, and the same complaint about
		# three different photographs otherwise reads as one repeated line.
		var where := ""
		var at := _wall_position(problem.photo_id)
		if at >= 0:
			where = "[color=#8d8478]%d.[/color] " % (at + 1)
		lines.append("[color=%s]•[/color] %s%s" % [colour, where, problem.message])
		shown += 1
		if shown >= 5:
			if listed > shown:
				lines.append("  …and %d more." % (listed - shown))
			break

	_problem_text.text = "\n".join(lines)


## Where a photo id sits on the wall, or -1 if it is not hung.
func _wall_position(photo_id: String) -> int:
	if photo_id.is_empty():
		return -1
	for i in session.slot_count():
		if session.slot_at(i).photo.id == photo_id:
			return i
	return -1


func _read_album_fields() -> void:
	_title.text = session.album.title
	_guess_from.set_value_no_signal(float(session.album.guess_year_min))
	_guess_to.set_value_no_signal(float(session.album.guess_year_max))
	if _cast_editor != null:
		_cast_editor.setup(CastProfile.for_album(session.album))
	_refresh_dial_note()


## Pull the selected photograph into the fields. Set with no_signal where it
## exists, so filling the form does not immediately write it back.
func _read_photo_fields() -> void:
	var slot := session.slot_at(_selected)
	if slot == null:
		_source_note.text = "Nothing hung yet — pick one from your folder."
		_preview.texture = null
		if _date_note != null:
			_date_note.text = ""
		_clear_photo_fields()
		return
	var photo := slot.photo

	# The dimensions only when they are known: an album reopened from a file
	# decodes nothing, so they are zero, and "0 × 0" is worse than silence.
	if slot.source_width > 0 and slot.source_height > 0:
		_source_note.text = "%s · %d × %d · %s" % [slot.source_name,
			slot.source_width, slot.source_height, _kb(slot.bytes_held())]
	else:
		_source_note.text = "%s · %s" % [slot.source_name,
			_kb(slot.bytes_held())]
	_preview.texture = slot.thumbnail()

	_photo_title.text = photo.content.title
	_description.text = photo.content.description
	_place.text = photo.truth.place_label
	_lat.set_value_no_signal(0.0 if is_nan(photo.truth.lat) else photo.truth.lat)
	_lon.set_value_no_signal(0.0 if is_nan(photo.truth.lon) else photo.truth.lon)
	_precision.select(_precision.get_item_index(photo.truth.date_precision))
	_year.set_value_no_signal(float(photo.truth.date.year))
	_month.set_value_no_signal(float(photo.truth.date.month))
	_day.set_value_no_signal(float(photo.truth.date.day))
	_refresh_date_note(photo)

	for i in _hints.size():
		_hints[i].text = photo.curator.hints[i] if i < photo.curator.hints.size() \
			else ""
	_approved.set_pressed_no_signal(photo.curator.approved_by_author)
	_monologue.text = photo.curator.reveal_monologue
	_private.text = photo.content.private_note

	_sync_map()


## The Save tab's one line: what this file is, at a glance.
func _refresh_summary() -> void:
	if _summary == null or session == null:
		return
	var cast := _cast_editor.cast if _cast_editor != null else null
	var title := session.album.title.strip_edges()
	var parts: PackedStringArray = PackedStringArray()
	parts.append("'%s'" % title if not title.is_empty() else "(no title yet)")
	parts.append("%d of %d photographs"
		% [session.slot_count(), EditorSession.MAX_PHOTOS])
	if cast != null:
		parts.append("%s walks, %s waits" % [cast.main_name(), cast.side_name()])
	var span := session.album.guess_year_range()
	parts.append("dial %d to %d" % [span.x, span.y])
	_summary.text = "  ·  ".join(parts)


## Whether this photograph brought a date with it, and where from. An undated
## scan is the normal case and the author needs to be told, not left to notice
## three empty boxes.
func _refresh_date_note(photo: AlbumSchema.Photo) -> void:
	if _date_note == null:
		return
	if not photo.truth.date.is_set():
		_date_note.text = "This one came with no date. Set it here — a year on"
		_date_note.text += " its own is enough."
		return

	var slot := session.slot_at(_selected)
	var came_from := "off the photograph"
	if slot != null and slot.from_sidecar:
		# Worth naming: Google's date is when the file was made, which for a
		# scanned print is the day it was scanned, not the day it was taken.
		came_from = "out of Google's export — check it, a scan is dated the" \
			+ " day it was scanned"
	_date_note.text = "%s, %s." % [photo.truth.date.label(), came_from]


## Empty the detail column and stop it taking input.
##
## Dimming it was not enough: `_refresh` only set `modulate.a`, which is
## purely visual, so with nothing selected every field still held the previous
## photograph's text and was still typable — and what was typed went nowhere,
## silently, because `_with_photo` had nothing to write to.
func _clear_photo_fields() -> void:
	_photo_title.text = ""
	_description.text = ""
	_place.text = ""
	_lat.set_value_no_signal(0.0)
	_lon.set_value_no_signal(0.0)
	_year.set_value_no_signal(0.0)
	_month.set_value_no_signal(0.0)
	_day.set_value_no_signal(0.0)
	for field in _hints:
		field.text = ""
	_monologue.text = ""
	_private.text = ""
	_approved.set_pressed_no_signal(false)
	if _map != null:
		_map.clear_pin()


# ------------------------------------------------------------------- export

func _on_export() -> void:
	if not session.can_export():
		_set_status("Not yet — this tab says what is missing.")
		return

	var bytes := session.export_bytes()
	if bytes.is_empty():
		_set_status("Could not write the settings.")
		return

	# Say what is about to happen, not that it has: on desktop this only opens
	# a save dialog, and the editor used to report "Saved …" on the next line
	# whether the author chose a path or pressed Cancel. Platform tells us how
	# it actually went, through _on_file_delivered below.
	var filename := session.suggested_filename()
	_pending_export = "%s — %d KB, %d photographs" \
		% [filename, bytes.size() / 1024, session.slot_count()]
	_set_status("Choose where to put %s…" % filename)
	Platform.deliver_file(bytes, filename, "application/zip")


func _on_file_delivered(ok: bool, path: String) -> void:
	var what := _pending_export
	_pending_export = ""
	if what.is_empty():
		return
	if not ok:
		_set_status("Nothing was saved. Everything is still here — press Save"
			+ " the settings when you are ready.")
		return
	_set_status("Saved %s.%s" % [what,
		"" if path.is_empty() else "\n%s" % path])


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


static func _kb(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / 1048576.0)
	return "%d KB" % (bytes / 1024)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel_custom"):
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
		get_viewport().set_input_as_handled()

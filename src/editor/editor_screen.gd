extends Control
## The "load game" page: choose ten photographs out of a folder and write down
## what they are.
##
## Three columns. Left: the source folder. Middle: the wall, in hang order.
## Right: everything about the selected photograph — where, when, what it is,
## and the three things he can be asked. Along the bottom: what is still wrong,
## and the button that writes the .ccalbum.
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
var _author_note: TextEdit = null
var _voice_name: LineEdit = null
var _player_name: LineEdit = null
var _closing_line: LineEdit = null
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

var _choose_folder: Button = null
var _choose_archive: Button = null
var _source_note_footer: Label = null
var _add_button: Button = null
var _export_button: Button = null


func _ready() -> void:
	GameState.phase = GameState.Phase.EDITOR
	session = EditorSession.new()
	session.changed.connect(_refresh)

	_build()

	Platform.files_picked.connect(_on_files_picked)
	Platform.pick_cancelled.connect(_on_pick_cancelled)

	_refresh()
	_set_status("Choose a folder of photographs to begin.")


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
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	margin.add_child(rows)

	rows.add_child(_build_header())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)

	columns.add_child(_build_sources())
	columns.add_child(_build_wall())
	columns.add_child(_build_detail())

	rows.add_child(_build_footer())


func _build_header() -> Control:
	var box := _panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)

	left.add_child(_small("Album title"))
	_title = LineEdit.new()
	_title.placeholder_text = "For Maggie"
	_title.text_changed.connect(func(t: String) -> void:
		session.album.title = t)
	left.add_child(_title)

	left.add_child(_small("A note from you — shown at the very end"))
	_author_note = _text_area(48)
	_author_note.text_changed.connect(func() -> void:
		session.album.author_note = _author_note.text)
	left.add_child(_author_note)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)

	right.add_child(_small("His name, as she would say it"))
	_voice_name = LineEdit.new()
	_voice_name.placeholder_text = "Tom"
	_voice_name.text_changed.connect(func(t: String) -> void:
		session.album.curator_voice_name = t)
	right.add_child(_voice_name)

	right.add_child(_small("Her name, as he would say it"))
	_player_name = LineEdit.new()
	_player_name.placeholder_text = "Maggie"
	_player_name.text_changed.connect(func(t: String) -> void:
		session.album.curator_player_name = t)
	right.add_child(_player_name)

	right.add_child(_small("The last thing he says, before the hug"))
	_closing_line = LineEdit.new()
	_closing_line.placeholder_text = "(leave empty for silence)"
	_closing_line.text_changed.connect(func(t: String) -> void:
		session.album.closing_line = t)
	right.add_child(_closing_line)

	right.add_child(_small("The calendar dial she guesses with. Leave both at"
		+ " zero to work it out from the photographs."))
	var dial := HBoxContainer.new()
	dial.add_theme_constant_override("separation", 8)
	dial.add_child(_fixed_small("from", 40))
	_guess_from = _spin(0.0, 2100.0, 1.0)
	_guess_from.value_changed.connect(func(v: float) -> void:
		session.album.guess_year_min = int(v)
		_refresh_dial_note())
	dial.add_child(_guess_from)
	dial.add_child(_fixed_small("to", 24))
	_guess_to = _spin(0.0, 2100.0, 1.0)
	_guess_to.value_changed.connect(func(v: float) -> void:
		session.album.guess_year_max = int(v)
		_refresh_dial_note())
	dial.add_child(_guess_to)
	right.add_child(dial)

	_dial_note = _small("")
	right.add_child(_dial_note)

	return box


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
	_dial_note.text = "she will turn the dial between %d and %d (%s)" \
		% [span.x, span.y, how]


func _build_sources() -> Control:
	var box := _panel()
	box.custom_minimum_size = Vector2(300, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	column.add_child(_heading("Your folder"))

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
	_source_list.item_activated.connect(func(_i: int) -> void: _on_add())
	column.add_child(_source_list)

	_add_button = Button.new()
	_add_button.text = "Hang this one →"
	_add_button.pressed.connect(_on_add)
	column.add_child(_add_button)

	_source_note_footer = _small("Nothing is copied out of your folder. Only"
		+ " the ten you choose are read.")
	column.add_child(_source_note_footer)

	return box


func _build_wall() -> Control:
	var box := _panel()
	box.custom_minimum_size = Vector2(300, 0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)

	column.add_child(_heading("The wall"))
	column.add_child(_small("In the order she will walk past them. Open warm,"
		+ " close with the one that hurts."))

	_wall_list = ItemList.new()
	_wall_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wall_list.add_theme_font_size_override("font_size", LABEL)
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

	_detail.add_child(_heading("This photograph"))
	_source_note = _small("")
	_detail.add_child(_source_note)

	_detail.add_child(_small("What it is"))
	_photo_title = LineEdit.new()
	_photo_title.text_changed.connect(func(t: String) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.content.title = t))
	_detail.add_child(_photo_title)

	_detail.add_child(_small("What you remember about it — this is what he"
		+ " draws his hints from"))
	_description = _text_area(70)
	_description.text_changed.connect(func() -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.content.description = _description.text))
	_detail.add_child(_description)

	_detail.add_child(_separator())
	_detail.add_child(_small("Where"))

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
	_lat = _spin(-90.0, 90.0, 0.0001)
	_lat.value_changed.connect(func(v: float) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.truth.lat = v)
		_sync_map())
	coords.add_child(_lat)
	coords.add_child(_fixed_small("lon", 30))
	_lon = _spin(-180.0, 180.0, 0.0001)
	_lon.value_changed.connect(func(v: float) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void: p.truth.lon = v)
		_sync_map())
	coords.add_child(_lon)
	_detail.add_child(coords)

	_detail.add_child(_separator())
	_detail.add_child(_small("When — and how sure you are"))

	var when := HBoxContainer.new()
	when.add_theme_constant_override("separation", 8)
	_precision = OptionButton.new()
	_precision.add_item("to the day", AlbumSchema.DatePrecision.DAY)
	_precision.add_item("the month", AlbumSchema.DatePrecision.MONTH)
	_precision.add_item("the year", AlbumSchema.DatePrecision.YEAR)
	_precision.add_item("the decade", AlbumSchema.DatePrecision.DECADE)
	_precision.item_selected.connect(func(_i: int) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.truth.date_precision = _precision.get_selected_id() as AlbumSchema.DatePrecision))
	when.add_child(_precision)

	when.add_child(_fixed_small("year", 38))
	_year = _spin(0.0, 2100.0, 1.0)
	when.add_child(_year)
	when.add_child(_fixed_small("month", 46))
	_month = _spin(0.0, 12.0, 1.0)
	when.add_child(_month)
	when.add_child(_fixed_small("day", 34))
	_day = _spin(0.0, 31.0, 1.0)
	when.add_child(_day)
	for spin in [_year, _month, _day]:
		spin.value_changed.connect(func(_v: float) -> void: _write_date())
	_detail.add_child(when)

	_detail.add_child(_separator())
	_detail.add_child(_small("What he says if she asks. Each one costs her"
		+ " more than the last, so each one should give more away."))

	const HINT_LABELS := [
		"1 — a feeling, a smell, the weather. Never the place.",
		"2 — the region, the country, the season.",
		"3 — say it outright.",
	]
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
	_approved.text = "I have read these three lines and he would say them"
	_approved.add_theme_font_size_override("font_size", LABEL)
	_approved.toggled.connect(func(on: bool) -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.curator.approved_by_author = on))
	_detail.add_child(_approved)

	_detail.add_child(_small("What he says once it is revealed"))
	_monologue = _text_area(60)
	_monologue.text_changed.connect(func() -> void:
		_with_photo(func(p: AlbumSchema.Photo) -> void:
			p.curator.reveal_monologue = _monologue.text))
	_detail.add_child(_monologue)

	_detail.add_child(_separator())
	_detail.add_child(_small("Your own notes. Never shown in the game, not"
		+ " anywhere, not ever."))
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

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)

	_problem_text = RichTextLabel.new()
	_problem_text.bbcode_enabled = true
	_problem_text.fit_content = true
	_problem_text.custom_minimum_size = Vector2(0, 92)
	_problem_text.add_theme_font_size_override("normal_font_size", LABEL)
	left.add_child(_problem_text)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", LABEL)
	_status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	left.add_child(_status)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	row.add_child(buttons)

	buttons.add_child(_action("Open an album…", _on_open_album))
	_export_button = _action("Save the album", _on_export)
	buttons.add_child(_export_button)
	buttons.add_child(_action("Back to the menu", func() -> void:
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")))

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


func _spin(low: float, high: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = low
	s.max_value = high
	s.step = step
	s.allow_greater = false
	s.allow_lesser = false
	s.custom_minimum_size = Vector2(108, 0)
	return s


func _action(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 34)
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
	_set_status("Choose a .ccalbum to open…")
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


## Run `action` against the selected photograph, if there is one. Every field
## handler goes through this so none of them has to null-check.
func _with_photo(action: Callable) -> void:
	var photo := _current()
	if photo == null:
		return
	action.call(photo)
	_refresh_problems()
	_refresh_wall_labels()


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
	_refresh_sources()
	_refresh_wall_labels()
	_refresh_problems()

	var have := _selected >= 0 and _selected < session.slot_count()
	_detail.modulate.a = 1.0 if have else 0.45
	_add_button.disabled = session.is_full() or _pending_source >= 0
	_export_button.disabled = not session.can_export()


func _refresh_sources() -> void:
	var previous := _source_list.get_selected_items()
	_source_list.clear()
	for i in session.source_count():
		_source_list.add_item(session.source_label(i))
	if not previous.is_empty() and previous[0] < _source_list.item_count:
		_source_list.select(previous[0])

	if _source_note_footer != null:
		if session.archive != null:
			var located := session.archive.with_sidecar_count()
			_source_note_footer.text = ("From the zip. %d of %d came with"
				+ " Google's own dates and locations; those fill themselves"
				+ " in.") % [located, session.archive.count()]
		else:
			_source_note_footer.text = ("Nothing is copied out of your folder."
				+ " Only the ten you choose are read.")


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
		_wall_list.add_item("%d.  %s — %s" % [i + 1, where, when])
	if _selected >= 0 and _selected < _wall_list.item_count:
		_wall_list.select(_selected)


func _refresh_problems() -> void:
	var problems := session.problems(true)
	if problems.is_empty():
		_problem_text.text = "[color=#8fbf8f]Ready to save.[/color]"
		return

	var lines: PackedStringArray = PackedStringArray()
	var errors := AlbumValidator.count_of(problems, AlbumValidator.Severity.ERROR)
	var warnings := AlbumValidator.count_of(problems, AlbumValidator.Severity.WARNING)
	lines.append("[b]%d thing%s to fix[/b], %d worth a look"
		% [errors, "" if errors == 1 else "s", warnings])

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
			lines.append("  …and %d more." % (problems.size() - shown))
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
	_author_note.text = session.album.author_note
	_voice_name.text = session.album.curator_voice_name
	_player_name.text = session.album.curator_player_name
	_closing_line.text = session.album.closing_line
	_guess_from.set_value_no_signal(float(session.album.guess_year_min))
	_guess_to.set_value_no_signal(float(session.album.guess_year_max))
	_refresh_dial_note()


## Pull the selected photograph into the fields. Set with no_signal where it
## exists, so filling the form does not immediately write it back.
func _read_photo_fields() -> void:
	var slot := session.slot_at(_selected)
	if slot == null:
		_source_note.text = "Nothing selected."
		return
	var photo := slot.photo

	_source_note.text = "%s · %d × %d · %s" % [slot.source_name,
		slot.source_width, slot.source_height, _kb(slot.bytes_held())]

	_photo_title.text = photo.content.title
	_description.text = photo.content.description
	_place.text = photo.truth.place_label
	_lat.set_value_no_signal(0.0 if is_nan(photo.truth.lat) else photo.truth.lat)
	_lon.set_value_no_signal(0.0 if is_nan(photo.truth.lon) else photo.truth.lon)
	_precision.select(_precision.get_item_index(photo.truth.date_precision))
	_year.set_value_no_signal(float(photo.truth.date.year))
	_month.set_value_no_signal(float(photo.truth.date.month))
	_day.set_value_no_signal(float(photo.truth.date.day))

	for i in _hints.size():
		_hints[i].text = photo.curator.hints[i] if i < photo.curator.hints.size() \
			else ""
	_approved.set_pressed_no_signal(photo.curator.approved_by_author)
	_monologue.text = photo.curator.reveal_monologue
	_private.text = photo.content.private_note

	_sync_map()


# ------------------------------------------------------------------- export

func _on_export() -> void:
	if not session.can_export():
		_set_status("Not yet — the list below says what is missing.")
		return

	var bytes := session.export_bytes()
	if bytes.is_empty():
		_set_status("Could not write the album.")
		return

	var filename := session.suggested_filename()
	Platform.deliver_file(bytes, filename, "application/zip")
	_set_status("Saved %s — %d KB, %d photographs."
		% [filename, bytes.size() / 1024, session.slot_count()])


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

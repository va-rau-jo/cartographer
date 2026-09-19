extends Control
## What you get after loading a settings file: is this the right one, and what
## do you want to do with it.
##
## Two people arrive here and they need opposite things.
##
##   * The player has just loaded the gift. They need to know it is the right
##     file and then press Begin. They must NOT see the ten photographs — they
##     are the game.
##   * The author has just loaded their own work in progress. They need to see
##     it and get into the editor.
##
## So the tiles show each photograph at blur tier 0, which is the fog met in
## the hall: enough to tell one file from another, nothing given away. "Show
## the photographs" reveals them, off by default, with the warning attached —
## the author's need does not get to spoil the player's game by default.

const HEADING := 34
const LABEL := 15
const BODY := 17

## Four across reads as a wall; five is a filmstrip.
const COLUMNS := 5
const TILE := Vector2(210, 150)

var album: AlbumSchema.Album = null

var _grid: GridContainer = null
var _tiles: Array[TextureRect] = []
var _captions: Array[Label] = []
var _title_label: Label = null
var _note_label: Label = null
var _facts_label: Label = null
var _reveal: CheckBox = null
var _status: Label = null
var _play: Button = null
var _revealed := false


func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	album = AlbumService.album()
	_build()
	_populate()


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
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	_title_label = _label("", HEADING, Color(0.94, 0.90, 0.82))
	column.add_child(_title_label)

	_note_label = _label("", BODY, Color(0.68, 0.64, 0.58))
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note_label)

	_facts_label = _label("", LABEL, Color(0.56, 0.53, 0.48))
	column.add_child(_facts_label)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 12)
	column.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_reveal = CheckBox.new()
	_reveal.text = "Show the photographs — only if these settings are yours;" \
		+ " it gives the game away"
	_reveal.add_theme_font_size_override("font_size", LABEL)
	_reveal.toggled.connect(_on_reveal_toggled)
	column.add_child(_reveal)

	_status = _label("", LABEL, Color(0.62, 0.58, 0.52))
	column.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	_play = _button("Begin", _on_play)
	buttons.add_child(_play)
	buttons.add_child(_button("Edit these settings", _on_edit))
	buttons.add_child(_button("Load a different file", _on_load_another))
	buttons.add_child(_button("Back to the menu", _on_back))


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", BODY)
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- contents

func _populate() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_tiles.clear()
	_captions.clear()

	if album == null:
		_title_label.text = "No settings loaded"
		_note_label.text = "Load a settings file from the menu, or create one."
		_facts_label.text = ""
		_play.disabled = true
		return

	_title_label.text = album.title if not album.title.is_empty() \
		else "Settings with no name"
	_note_label.text = album.author_note
	_facts_label.text = _facts()

	var hung := album.hung_photos()
	for i in hung.size():
		_grid.add_child(_build_tile(i, hung[i]))

	_play.disabled = hung.is_empty()
	_status.text = ""


## The things worth knowing without looking at the pictures: how many, what
## years they span, and who he is.
func _facts() -> String:
	var hung := album.hung_photos()
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d photograph%s" % [hung.size(), "" if hung.size() == 1 else "s"])

	var lo := 9999
	var hi := 0
	for photo in hung:
		if photo.truth.date.is_set():
			lo = mini(lo, photo.truth.date.year)
			hi = maxi(hi, photo.truth.date.year)
	if lo <= hi:
		parts.append("%d to %d" % [lo, hi] if lo != hi else str(lo))

	var cast := CastProfile.for_album(album)
	parts.append("%s and %s" % [cast.main_name(), cast.side_name()])

	var problems := AlbumValidator.validate(album, false)
	var warnings := AlbumValidator.count_of(problems,
		AlbumValidator.Severity.WARNING)
	if warnings > 0:
		parts.append("%d warning%s" % [warnings, "" if warnings == 1 else "s"])

	return "  ·  ".join(parts)


## One tile: the photograph as fog, its number, and — once revealed — where
## and when it was. The place and date are part of the answer, so they are
## hidden with the picture.
func _build_tile(index: int, photo: AlbumSchema.Photo) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.068, 0.060)
	style.border_color = Color(0.24, 0.22, 0.19)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var image := TextureRect.new()
	image.custom_minimum_size = TILE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture = _texture_for(photo, false)
	# A blurred photograph stretched to a tile is exactly the fog she meets in
	# the hall; nearest-neighbour would show it as 64 hard squares instead.
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.set_meta("photo_id", photo.id)
	box.add_child(image)
	_tiles.append(image)

	var caption := _label("%d." % (index + 1), LABEL, Color(0.58, 0.55, 0.50))
	caption.set_meta("photo_id", photo.id)
	box.add_child(caption)
	_captions.append(caption)

	return panel


func _texture_for(photo: AlbumSchema.Photo, revealed: bool) -> Texture2D:
	if revealed:
		var thumb := AlbumService.thumb_texture(photo.id)
		if thumb != null:
			return thumb
	# Tier 0 is the 64-pixel fog the round starts at.
	return AlbumService.tier_texture(photo.id, 0)


func _on_reveal_toggled(on: bool) -> void:
	_revealed = on
	if album == null:
		return

	var hung := album.hung_photos()
	for i in _tiles.size():
		if i >= hung.size():
			continue
		_tiles[i].texture = _texture_for(hung[i], on)

	for i in _captions.size():
		if i >= hung.size():
			continue
		var photo := hung[i]
		if on:
			var where := photo.truth.place_label if not photo.truth.place_label.is_empty() \
				else "(nowhere recorded)"
			var when := photo.truth.date.label() if photo.truth.date.is_set() \
				else "(no date)"
			_captions[i].text = "%d.  %s — %s" % [i + 1, where, when]
		else:
			_captions[i].text = "%d." % (i + 1)

	_status.text = "" if not on else "Showing the answers. Close this before" \
		+ " anyone else plays it."


# ----------------------------------------------------------------- actions

func _on_play() -> void:
	AlbumService.reset_session()
	var err := get_tree().change_scene_to_file("res://scenes/hospital/hospital.tscn")
	if err != OK:
		_status.text = "Could not start the game (error %d)." % err


## Hand the loaded settings to the editor. They are already in AlbumService;
## the flag is how the editor knows to adopt them rather than starting empty.
func _on_edit() -> void:
	GameState.edit_loaded_album = true
	var err := get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")
	if err != OK:
		GameState.edit_loaded_album = false
		_status.text = "Could not open the editor (error %d)." % err


func _on_load_another() -> void:
	if Platform.is_picking():
		_status.text = "There is already a file dialog open."
		return
	_status.text = "Choose a settings file…"
	if not Platform.files_picked.is_connected(_on_files_picked):
		Platform.files_picked.connect(_on_files_picked)
		Platform.pick_cancelled.connect(func() -> void: _status.text = "")
	Platform.pick_album_file()


func _on_files_picked(files: Array) -> void:
	if files.is_empty():
		return
	var file: Platform.PickedFile = files[0]
	_status.text = "Reading %s…" % file.name

	var bytes: PackedByteArray = await Platform.read_file(file)
	if bytes.is_empty():
		_status.text = "Could not read %s." % file.name
		return

	# Whether it loaded or not, this screen now describes whatever the service
	# holds — and on a failure it holds NOTHING, because load_album_bytes
	# unloads before it tries. Repopulating is what stops the screen keeping
	# the old album's title and tiles with Begin still armed over an empty
	# service, which sent the player into the hospital with no album at all.
	var ok := AlbumService.load_album_bytes(bytes)
	album = AlbumService.album()
	_reveal.set_pressed_no_signal(false)
	_revealed = false
	_populate()

	if not ok:
		var problems := AlbumService.loaded.problems if AlbumService.loaded != null \
			else []
		_status.text = "%s could not be loaded.%s" % [file.name,
			_first_problems(problems)]


## The reasons, on this screen. They used to be left to the menu's own handler
## for EventBus.album_load_failed — but the menu was freed on the way here, so
## nothing showed them anywhere.
func _first_problems(problems: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for p in problems:
		var problem: AlbumValidator.Problem = p
		if problem.severity != AlbumValidator.Severity.ERROR:
			continue
		lines.append("  • %s" % problem.message)
		if lines.size() >= 3:
			break
	if lines.is_empty():
		return ""
	return "\n" + "\n".join(lines)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel_custom"):
		_on_back()
		get_viewport().set_input_as_handled()

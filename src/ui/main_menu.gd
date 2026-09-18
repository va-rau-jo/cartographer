extends Control
## The main menu, and for now the only screen.
##
## Built in code rather than in a .tscn: this screen is mostly wiring and it
## will be replaced wholesale at M9 when the real art direction arrives, so
## there is no value in maintaining a scene file for it yet.
##
## The session shape it serves (plan §2.1):
##   menu -> load album -> play -> hospital -> gallery -> ending -> menu

const TITLE := "CHRONO CARTOGRAPHER"
const SUBTITLE := "A gallery in a dying man's mind."

var _status: RichTextLabel = null
var _play_button: Button = null
var _load_button: Button = null


func _ready() -> void:
	GameState.phase = GameState.Phase.MENU
	_build()

	Platform.files_picked.connect(_on_files_picked)
	Platform.pick_cancelled.connect(_on_pick_cancelled)
	EventBus.album_loaded.connect(_on_album_loaded)
	EventBus.album_load_failed.connect(_on_album_load_failed)

	_refresh()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.048, 0.042)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 96)
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_right", 96)
	margin.add_theme_constant_override("margin_bottom", 72)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)

	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = SUBTITLE
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	column.add_child(subtitle)

	column.add_child(_spacer(28))

	_load_button = _make_button("Load album…", _on_load_pressed)
	column.add_child(_load_button)

	_play_button = _make_button("Begin", _on_play_pressed)
	column.add_child(_play_button)

	column.add_child(_make_button("Walk the gallery (no album)", _enter_gallery))

	column.add_child(_make_button("Build an album", _on_editor_pressed))

	if not OS.has_feature("web"):
		column.add_child(_make_button("Quit", _on_quit_pressed))

	column.add_child(_spacer(20))

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(620, 120)
	_status.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_status)

	var hint := Label.new()
	hint.text = "WASD to walk · F11 debug overlay · Esc to release the mouse"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.38, 0.35))
	column.add_child(hint)


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(handler)
	return b


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


# --- actions ---

## The button is NOT disabled while the dialog is open. A cancelled native
## dialog does not always report itself, and a disabled button with nothing to
## re-enable it is unusable for the rest of the session — which is exactly
## what happened. Platform refuses a second pick on its own.
func _on_load_pressed() -> void:
	if Platform.is_picking():
		_set_status("[color=gray]There is already a file dialog open.[/color]")
		return
	_set_status("[color=gray]Choose a .ccalbum file…[/color]")
	Platform.pick_album_file()


## The real start: the hospital room, which hands over to the gallery itself
## once she goes in. "Walk the gallery" below skips it.
func _on_play_pressed() -> void:
	AlbumService.reset_session()
	var err := get_tree().change_scene_to_file("res://scenes/hospital/hospital.tscn")
	if err != OK:
		_set_status("[color=#e08080]Could not open the opening scene (error %d).[/color]"
			% err)


## The gallery hangs placeholder images when no album is loaded, so the space
## can be walked and judged before the round logic exists.
func _enter_gallery() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var err := get_tree().change_scene_to_file("res://scenes/gallery/gallery.tscn")
	if err != OK:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_status("[color=#e08080]Could not open the gallery (error %d).[/color]" % err)


func _on_editor_pressed() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/editor/editor.tscn")
	if err != OK:
		_set_status("[color=#e08080]Could not open the editor (error %d).[/color]"
			% err)


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- platform / album callbacks ---

func _on_files_picked(files: Array) -> void:
	if files.is_empty():
		return

	var file: Platform.PickedFile = files[0]
	_set_status("[color=gray]Reading %s…[/color]" % file.name)

	var bytes: PackedByteArray = await Platform.read_file(file)
	if bytes.is_empty():
		_set_status("[color=#e08080]Could not read %s.[/color]" % file.name)
		return

	AlbumService.load_album_bytes(bytes)


func _on_pick_cancelled() -> void:
	_set_status("")


func _on_album_loaded(album: RefCounted) -> void:
	var a: AlbumSchema.Album = album
	var hung := a.hung_photos()

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b] — %d photographs" % [a.title, hung.size()])
	if not a.author_note.is_empty():
		lines.append("[i]%s[/i]" % a.author_note)

	var warnings := AlbumValidator.count_of(
		AlbumService.loaded.problems, AlbumValidator.Severity.WARNING)
	if warnings > 0:
		lines.append("[color=#d8c070]%d warning(s) — playable, but worth a look.[/color]"
			% warnings)

	_set_status("\n".join(lines))
	_refresh()


func _on_album_load_failed(problems: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#e08080][b]That album could not be loaded.[/b][/color]")
	var shown := 0
	for p in problems:
		var problem: AlbumValidator.Problem = p
		if problem.severity != AlbumValidator.Severity.ERROR:
			continue
		lines.append("  • %s" % problem.message)
		shown += 1
		if shown >= 6:
			lines.append("  • …and more; see the log.")
			break
	_set_status("\n".join(lines))
	_refresh()


func _refresh() -> void:
	_play_button.disabled = not AlbumService.has_album()


func _set_status(bbcode: String) -> void:
	if _status != null:
		_status.text = bbcode

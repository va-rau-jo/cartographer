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
const SUBTITLE := "A gallery in a dying mind."

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

	# Three groups, in the order they matter, with air between them:
	#
	#   1. playing, which is what almost everybody opening this wants;
	#   2. the settings file that makes playing possible;
	#   3. everything else.
	#
	# Start game sits at the top even though it is disabled until a file is
	# loaded, because where a button IS should not move depending on state —
	# and its being greyed out is itself the answer to "why can I not play".
	_play_button = _make_button("Start game", _on_play_pressed)
	column.add_child(_play_button)

	column.add_child(_group_gap())

	column.add_child(_make_button("Create settings", _on_editor_pressed))

	_load_button = _make_button("Load settings…", _on_load_pressed)
	column.add_child(_load_button)

	column.add_child(_group_gap())

	column.add_child(_make_button("Walk the gallery (no settings)",
		_enter_gallery))

	column.add_child(_make_button("Characters", _on_customize_pressed))

	# On the web the tab is the quit button, and a Quit that cannot quit is
	# worse than no Quit at all.
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


## The air between two groups of buttons: a gap and a hairline the width of the
## buttons, so the grouping reads as deliberate rather than as loose spacing.
func _group_gap() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(_spacer(10))
	# Two pixels, not one: a one-pixel rule lands on a half-pixel at some
	# window sizes and vanishes, which it did — one of the two dividers drew
	# and the other did not.
	var rule := ColorRect.new()
	rule.color = Color(0.26, 0.24, 0.21)
	rule.custom_minimum_size = Vector2(260, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(rule)
	box.add_child(_spacer(10))
	return box


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
	_set_status("[color=gray]Choose a settings file…[/color]")
	Platform.pick_album_file()


## Begin shows the settings' own page first. It is one click more, and it is
## where "are these the right settings" gets answered — pressing Begin and
## landing in a hospital room with no idea what is coming is worse.
func _on_play_pressed() -> void:
	var err := get_tree().change_scene_to_file(
		"res://scenes/menu/album_preview.tscn")
	if err != OK:
		_set_status("[color=#e08080]Could not open the settings (error %d).[/color]"
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


## The two characters: their names and how they look.
func _on_customize_pressed() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/menu/customize.tscn")
	if err != OK:
		_set_status("[color=#e08080]Could not open the characters screen"
			+ " (error %d).[/color]" % err)


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


## Loaded settings go straight to the preview screen: the file's own page,
## where you can see what it is and choose to play it or to edit it. The menu
## does not try to summarise it in a status line any more.
func _on_album_loaded(album: RefCounted) -> void:
	var a: AlbumSchema.Album = album
	_set_status("[b]%s[/b] — %d photographs"
		% [a.title, a.hung_photos().size()])
	_refresh()

	var err := get_tree().change_scene_to_file(
		"res://scenes/menu/album_preview.tscn")
	if err != OK:
		_set_status("[color=#e08080]Could not open the settings (error %d).[/color]"
			% err)


func _on_album_load_failed(problems: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#e08080][b]Those settings could not be loaded."
		+ "[/b][/color]")
	var errors := AlbumValidator.count_of(problems, AlbumValidator.Severity.ERROR)
	var shown := 0
	for p in problems:
		var problem: AlbumValidator.Problem = p
		if problem.severity != AlbumValidator.Severity.ERROR:
			continue
		lines.append("  • %s" % problem.message)
		shown += 1
		if shown >= 6:
			# Only when there really are more: with exactly six errors this
			# promised a seventh that was not there.
			if errors > shown:
				lines.append("  • …and %d more; see the log." % (errors - shown))
			break
	_set_status("\n".join(lines))
	_refresh()


func _refresh() -> void:
	_play_button.disabled = not AlbumService.has_album()


func _set_status(bbcode: String) -> void:
	if _status != null:
		_status.text = bbcode

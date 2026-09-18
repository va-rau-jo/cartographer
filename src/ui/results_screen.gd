extends CanvasLayer
## What she got right, shown after the hug — never before it.
##
## The game ends with the hug (that was the brief), so this waits for
## EventBus.ending_finished rather than session_completed. It is deliberately
## quiet: no banner, no fanfare, no "SCORE". Ten lines of where and when, the
## total underneath, and a way back to the menu.
##
## The author's private notes are never shown here. See Content.private_note.

const ROW_SIZE := 19
const HEADING_SIZE := 34
const TOTAL_SIZE := 28

## Seconds for the list to arrive, one line at a time.
const ROW_STAGGER := 0.16
const FADE_IN := 1.4

var album: AlbumSchema.Album = null

var _root: Control = null
var _rows: VBoxContainer = null
var _total: Label = null
var _heading: Label = null
var _note: Label = null
var _back: Button = null
var _row_nodes: Array[Control] = []
var _clock := 0.0
var _revealing := false


func setup(a: AlbumSchema.Album) -> void:
	album = a


func _ready() -> void:
	layer = 20
	_build()
	_root.visible = false
	EventBus.ending_finished.connect(show_results)


# ----------------------------------------------------------------- build

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = Color(0.028, 0.025, 0.022, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 90)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 48)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)

	_heading = _label("", HEADING_SIZE, Color(0.94, 0.90, 0.82))
	column.add_child(_heading)

	_note = _label("", ROW_SIZE, Color(0.62, 0.58, 0.53))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	column.add_child(_separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	column.add_child(_separator())

	_total = _label("", TOTAL_SIZE, Color(0.97, 0.93, 0.84))
	column.add_child(_total)

	_back = Button.new()
	_back.text = "Back to the beginning"
	_back.custom_minimum_size = Vector2(0, 54)
	_back.add_theme_font_size_override("font_size", 22)
	_back.pressed.connect(_on_back)
	column.add_child(_back)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	return sep


# --------------------------------------------------------------- populate

func show_results() -> void:
	_populate()
	_root.visible = true
	_root.modulate.a = 0.0
	_clock = 0.0
	_revealing = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_back.grab_focus()


func _populate() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_row_nodes.clear()

	var title := "Ten photographs"
	if album != null and not album.title.is_empty():
		title = album.title
	_heading.text = title

	_note.text = ""
	if album != null and not album.author_note.is_empty():
		_note.text = album.author_note

	var hung: Array[AlbumSchema.Photo] = []
	if album != null:
		hung = album.hung_photos()

	for i in GameState.results.size():
		var photo: AlbumSchema.Photo = hung[i] if i < hung.size() else null
		var row := _build_row(i, photo, GameState.results[i])
		row.modulate.a = 0.0
		_rows.add_child(row)
		_row_nodes.append(row)

	_total.text = "%s   ·   %.0f" % [_verdict(), GameState.total_score()]


## One photograph: what it was, what she said, and what it was worth.
func _build_row(index: int, photo: AlbumSchema.Photo,
		breakdown: Variant) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.050, 0.045, 0.9)
	style.border_color = Color(0.22, 0.20, 0.17)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(11)
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)

	var num := _label("%2d" % (index + 1), ROW_SIZE, Color(0.45, 0.42, 0.38))
	num.custom_minimum_size = Vector2(34, 0)
	row.add_child(num)

	var truth := VBoxContainer.new()
	truth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	truth.add_theme_constant_override("separation", 3)
	row.add_child(truth)

	var place := "—"
	var when := ""
	if photo != null:
		place = photo.truth.place_label if not photo.truth.place_label.is_empty() \
			else "(no place recorded)"
		when = photo.truth.date.label()
	truth.add_child(_label(place, ROW_SIZE + 3, Color(0.92, 0.88, 0.81)))
	truth.add_child(_label(when, ROW_SIZE - 3, Color(0.58, 0.55, 0.50)))

	var said := VBoxContainer.new()
	said.add_theme_constant_override("separation", 3)
	said.alignment = BoxContainer.ALIGNMENT_CENTER
	said.custom_minimum_size = Vector2(340, 0)
	row.add_child(said)

	var score := _label("", ROW_SIZE + 3, Color(0.88, 0.84, 0.76))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score.custom_minimum_size = Vector2(120, 0)
	row.add_child(score)

	if typeof(breakdown) != TYPE_DICTIONARY:
		said.add_child(_label("not played", ROW_SIZE - 1,
			Color(0.45, 0.42, 0.38)))
		score.text = "—"
		return panel

	var b: Dictionary = breakdown
	said.add_child(_label(_said_line(b), ROW_SIZE - 1, Color(0.70, 0.66, 0.60)))
	said.add_child(_label(_help_line(b), ROW_SIZE - 4, Color(0.50, 0.47, 0.43)))
	score.text = "%.0f" % float(b.get("total_score", 0.0))
	return panel


func _said_line(b: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var label := String(b.get("guess_label", ""))
	var km: float = b.get("distance_km", INF)
	if not label.is_empty():
		if is_finite(km) and km < 1.0:
			parts.append("you said %s — exactly" % label)
		elif is_finite(km):
			parts.append("you said %s, %s out" % [label, _distance(km)])
		else:
			parts.append("you said %s" % label)
	elif is_finite(km):
		parts.append("%s out" % _distance(km))

	var date_label := String(b.get("guess_date_label", ""))
	if not date_label.is_empty() and date_label != "unknown":
		var years := int(b.get("year_error", 0))
		if years == 0:
			parts.append("and the right year")
		elif bool(b.get("date_exact", false)):
			# Full date credit with a year error: a decade-precision
			# photograph, where anywhere inside the decade is right. Saying
			# "4 years out" here contradicts the score on the same row.
			parts.append("and the right decade")
		elif years < 9000:
			parts.append("and %s" % _years_out(years))
		else:
			parts.append("and %s" % date_label)

	return "  ".join(parts)


func _help_line(b: Dictionary) -> String:
	var hints := int(b.get("hints_used", 0))
	var tier := int(b.get("unblur_tier", 0))
	if hints == 0 and tier == 0:
		return "no help"
	var bits: PackedStringArray = PackedStringArray()
	if hints == 1:
		bits.append("one question")
	elif hints > 1:
		bits.append("%d questions" % hints)
	if tier == 1:
		bits.append("cleared once")
	elif tier > 1:
		bits.append("cleared %d times" % tier)
	return ", ".join(bits)


func _distance(km: float) -> String:
	if km < 10.0:
		return "%.1f km" % km
	return "%.0f km" % km


func _years_out(years: int) -> String:
	if years == 1:
		return "a year out"
	return "%d years out" % years


## A sentence rather than a grade. This is a gift, not a leaderboard.
func _verdict() -> String:
	var played := GameState.photos_played()
	if played == 0:
		return "Nothing guessed"
	var cfg := album.scoring if album != null else AlbumSchema.ScoringConfig.new()
	var ceiling := cfg.max_round_score() * float(played)
	if ceiling <= 0.0:
		return "Ten photographs"
	var share := GameState.total_score() / ceiling
	if share >= 0.85:
		return "You remembered nearly all of it"
	if share >= 0.6:
		return "You remembered most of it"
	if share >= 0.35:
		return "You remembered a good deal of it"
	if share >= 0.15:
		return "You remembered some of it"
	return "He remembered it for you"


# ---------------------------------------------------------------- reveal

func _process(delta: float) -> void:
	if not _revealing:
		return

	_clock += delta
	_root.modulate.a = clampf(_clock / FADE_IN, 0.0, 1.0)

	var done := true
	for i in _row_nodes.size():
		var due := FADE_IN * 0.4 + float(i) * ROW_STAGGER
		var a := clampf((_clock - due) / 0.55, 0.0, 1.0)
		_row_nodes[i].modulate.a = a
		if a < 1.0:
			done = false

	if done and _root.modulate.a >= 1.0:
		_revealing = false


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible:
		return
	if event.is_action_pressed(&"ui_cancel_custom") \
			or event.is_action_pressed(&"ui_accept"):
		_on_back()
		get_viewport().set_input_as_handled()

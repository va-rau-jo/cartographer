extends CanvasLayer
## The in-gallery HUD: the approach prompt, the round's spend state, and the
## curator's text bubble.
##
## Reads GameState and asks RoundController for costs; it never changes the
## phase itself. Everything it shows is driven off EventBus, so it does not
## need to poll the round machine for changes.
##
## Typography carries the whole performance here, because the husband has no
## voice (plan §8.1) — hence the punctuation-aware reveal rather than a plain
## label swap.

## Seconds per character, and the extra pause each mark earns.
const CHAR_TIME := 0.030
const PAUSE_COMMA := 0.14
const PAUSE_STOP := 0.34
const PAUSE_ELLIPSIS := 0.75

## Large text is on by default: the plausible audience includes elderly
## players, and this is the cheapest accessibility decision in the project
## (plan §10.6).
const BODY_SIZE := 21
const PROMPT_SIZE := 22
const BUBBLE_SIZE := 24

var rounds: RoundController = null

var _prompt: Label = null
var _round_panel: PanelContainer = null
var _round_label: RichTextLabel = null
var _bubble_panel: PanelContainer = null
var _bubble: RichTextLabel = null
var _toast: Label = null

## Text being revealed a character at a time.
var _bubble_full := ""
var _bubble_prefix := ""
var _bubble_shown := 0
var _bubble_clock := 0.0
var _bubble_hold := 0.0
var _toast_time := 0.0
## Rises as she leans on him; slows his speech (plan §8.2).
var _fatigue := 0.0


func setup(controller: RoundController) -> void:
	rounds = controller


func _ready() -> void:
	layer = 8
	_build()

	EventBus.photo_approached.connect(_on_approached)
	EventBus.round_started.connect(_on_round_started)
	EventBus.round_finished.connect(_on_round_finished)
	EventBus.round_scored.connect(_on_scored)
	EventBus.curator_line_requested.connect(_on_curator_line)
	EventBus.hint_purchased.connect(_on_hint_purchased)
	EventBus.unblur_purchased.connect(_on_unblur_purchased)


func _build() -> void:
	# --- approach prompt, bottom centre ---
	_prompt = Label.new()
	_prompt.text = ""
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", PROMPT_SIZE)
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.92, 0.86))
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -120
	_prompt.offset_bottom = -78
	add_child(_prompt)

	# --- round state, bottom left ---
	_round_panel = _panel()
	_round_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_round_panel.offset_left = 34
	_round_panel.offset_top = -190
	_round_panel.offset_bottom = -34
	_round_panel.custom_minimum_size = Vector2(340, 0)
	_round_panel.visible = false
	add_child(_round_panel)

	_round_label = _rich(BODY_SIZE)
	_round_panel.add_child(_round_label)

	# --- his text bubble, bottom centre above the prompt ---
	_bubble_panel = _panel()
	_bubble_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_bubble_panel.offset_left = -430
	_bubble_panel.offset_right = 430
	_bubble_panel.offset_top = -330
	_bubble_panel.offset_bottom = -170
	_bubble_panel.visible = false
	add_child(_bubble_panel)

	_bubble = _rich(BUBBLE_SIZE)
	_bubble_panel.add_child(_bubble)

	# --- score toast, top centre ---
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_color_override("font_color", Color(0.98, 0.94, 0.84))
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("shadow_offset_y", 2)
	_toast.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 54
	_toast.offset_bottom = 104
	_toast.modulate.a = 0.0
	add_child(_toast)


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.04, 0.88)
	style.border_color = Color(0.35, 0.31, 0.26, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _process(delta: float) -> void:
	_tick_bubble(delta)
	_tick_toast(delta)

	if GameState.phase == GameState.Phase.GUESSING and rounds != null:
		_round_panel.visible = true
		_round_label.text = _compose_round()
	else:
		_round_panel.visible = false


# ------------------------------------------------------------ round panel

func _compose_round() -> String:
	var total := rounds.frames.size()
	var index := rounds.active_index()
	var spent := rounds.spent_fraction()
	var cfg := rounds.album.scoring if rounds.album != null \
		else AlbumSchema.ScoringConfig.new()
	var remaining := cfg.max_round_score() * (1.0 - spent)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Photograph %d of %d[/b]" % [index + 1, total])
	lines.append("This round is worth [b]%.0f[/b]" % remaining)

	if spent > 0.001:
		lines.append("[color=#c8a870]%.0f%% spent on help[/color]" % (spent * 100.0))

	lines.append("")
	if rounds.can_unblur():
		lines.append("[b]U[/b]  clear it a little   [color=gray]−%.0f%%[/color]"
			% (rounds.unblur_cost() * 100.0))
	else:
		lines.append("[color=#6a6560]U  as clear as it gets[/color]")

	if rounds.can_hint():
		lines.append("[b]H[/b]  ask him             [color=gray]−%.0f%%[/color]"
			% (rounds.next_hint_cost() * 100.0))
	else:
		lines.append("[color=#6a6560]H  he has told you all he can[/color]")

	return "\n".join(lines)


# --------------------------------------------------------------- bubble

## Punctuation-aware reveal. A comma waits, a full stop waits longer, an
## ellipsis waits much longer. This is what makes text feel spoken, and with no
## voice acting it is doing all the work.
func _tick_bubble(delta: float) -> void:
	if _bubble_full.is_empty():
		return

	if _bubble_shown >= _bubble_full.length():
		_bubble_hold -= delta
		if _bubble_hold <= 0.0:
			_bubble_panel.visible = false
			_bubble_full = ""
		return

	_bubble_clock -= delta
	while _bubble_clock <= 0.0 and _bubble_shown < _bubble_full.length():
		var ch := _bubble_full[_bubble_shown]
		_bubble_shown += 1
		# Fatigue slows him down as she leans on him harder.
		_bubble_clock += CHAR_TIME * (1.0 + _fatigue * 1.4)
		_bubble_clock += _pause_after(ch, _bubble_shown)

	_bubble.text = _bubble_prefix + _bubble_full.substr(0, _bubble_shown) + "[/color]"


func _pause_after(ch: String, at: int) -> float:
	if ch == ",":
		return PAUSE_COMMA
	if ch == ".":
		# An ellipsis is three stops; only pause long on the last one.
		var is_ellipsis := _bubble_full.substr(maxi(0, at - 3), 3) == "..."
		return PAUSE_ELLIPSIS if is_ellipsis else PAUSE_STOP
	if ch == "?" or ch == "!":
		return PAUSE_STOP
	if ch == ";" or ch == ":" or ch == "—":
		return PAUSE_COMMA * 1.6
	return 0.0


func _on_curator_line(text: String, mood: StringName) -> void:
	if text.strip_edges().is_empty():
		return

	var speaker := "Tom"
	if rounds != null and rounds.album != null \
			and not rounds.album.curator_voice_name.is_empty():
		speaker = rounds.album.curator_voice_name

	# He sounds more worn the deeper she goes into the hint ladder.
	var colour := "#e8e0d0"
	match mood:
		&"tired": colour = "#d8cdb8"
		&"failing": colour = "#c3b49c"

	# The speaker's name is a fixed prefix; only the speech animates.
	_bubble_prefix = "[color=#8d8478][i]%s[/i][/color]\n[color=%s]" % [speaker, colour]
	_bubble_full = text
	_bubble_shown = 0
	_bubble_clock = 0.0
	_bubble_hold = 3.2 + float(text.length()) * 0.035
	_bubble.text = _bubble_prefix + "[/color]"
	_bubble_panel.visible = true


# ---------------------------------------------------------------- events

func _on_approached(index: int) -> void:
	var played := GameState.is_played(index)
	_prompt.text = "" if played else "E   —   look at this photograph"


func _on_round_started(_index: int) -> void:
	_prompt.text = ""


func _on_round_finished(_index: int) -> void:
	_prompt.text = ""
	_fatigue = GameState.reliance()


func _on_hint_purchased(_index: int, tier: int, _cost: float) -> void:
	_fatigue = clampf(float(tier) / 3.0, 0.0, 1.0)


func _on_unblur_purchased(_index: int, _tier: int, _cost: float) -> void:
	pass


func _on_scored(_index: int, breakdown: Dictionary) -> void:
	var km: float = breakdown.get("distance_km", INF)
	var total: float = breakdown.get("total_score", 0.0)

	var where := "somewhere else entirely"
	match breakdown.get("error_band", &"far"):
		&"exact": where = "you had it"
		&"near": where = "close"
		&"region": where = "the right part of the world"
		&"continent": where = "the right continent"

	var distance := "—"
	if is_finite(km):
		distance = "%.0f km out" % km if km >= 1.0 else "spot on"

	_toast.text = "%s  ·  %s  ·  %.0f" % [where, distance, total]
	_toast.modulate.a = 1.0
	_toast_time = 3.6


func _tick_toast(delta: float) -> void:
	if _toast_time <= 0.0:
		return
	_toast_time -= delta
	if _toast_time < 0.9:
		_toast.modulate.a = clampf(_toast_time / 0.9, 0.0, 1.0)

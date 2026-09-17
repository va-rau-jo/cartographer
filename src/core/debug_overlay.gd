extends CanvasLayer
## Autoload: DebugOverlay. Toggle with F11.
##
## Builds itself in code so there is no scene to keep in sync. It shows the
## live score maths during a round, which plan §7.4 calls for — those constants
## can only be tuned by watching them move.

const PANEL_WIDTH := 460.0

var _visible_now := false
var _label: RichTextLabel = null
var _panel: PanelContainer = null


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_apply_visibility()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.82)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 13)
	_label.add_theme_font_size_override("mono_font_size", 13)
	_panel.add_child(_label)

	add_child(_panel)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_overlay"):
		_visible_now = not _visible_now
		_apply_visibility()


func _apply_visibility() -> void:
	if _panel != null:
		_panel.visible = _visible_now


func _process(_delta: float) -> void:
	if not _visible_now or _label == null:
		return
	_label.text = _compose()


func _compose() -> String:
	var lines: PackedStringArray = PackedStringArray()

	lines.append("[b]Chrono Cartographer[/b]  %d fps  %s"
		% [Engine.get_frames_per_second(), Platform.backend_name()])
	lines.append("phase: [color=aqua]%s[/color]   photo: %d"
		% [_phase_name(GameState.phase), GameState.current_photo_index])

	if AlbumService.has_album():
		var album := AlbumService.album()
		var hung := album.hung_photos()
		lines.append("album: %s  (%d photos)" % [album.title, hung.size()])
		lines.append("played %d/%d   score %.0f   reliance %.2f"
			% [GameState.photos_played(), hung.size(),
			   GameState.total_score(), GameState.reliance()])

		var idx := GameState.current_photo_index
		if idx >= 0 and idx < hung.size():
			var photo := hung[idx]
			var cfg := album.scoring
			var tier: int = GameState.unblur_tiers[idx]
			var hints: Array = GameState.hints_taken[idx]
			var spent := Scoring.spent_fraction(tier, hints, cfg)

			lines.append("")
			lines.append("[b]round[/b] %s" % photo.id)
			lines.append("  truth      %s  %s"
				% [photo.truth.place_label, photo.truth.date.label()])
			lines.append("  unblur     tier %d   hints %s" % [tier, str(hints)])
			lines.append("  spent      %.2f  (cap %.2f)" % [spent, cfg.max_spent_fraction])
			lines.append("  max round  %.0f  ->  %.0f after spend"
				% [cfg.max_round_score(), cfg.max_round_score() * (1.0 - spent)])

			var result: Variant = GameState.results[idx]
			if result != null:
				var r: Dictionary = result
				lines.append("  distance   %.1f km  ->  %.0f"
					% [r.get("distance_km", 0.0), r.get("distance_score", 0.0)])
				lines.append("  date       %d yr off  ->  %.0f"
					% [r.get("year_error", 0), r.get("date_score", 0.0)])
				lines.append("  [b]total     %.0f[/b]   band %s"
					% [r.get("total_score", 0.0), r.get("error_band", &"?")])
	else:
		lines.append("album: [color=gray]none loaded[/color]")

	var recent := CCLog.recent(6)
	if not recent.is_empty():
		lines.append("")
		lines.append("[b]log[/b]")
		for entry in recent:
			var colour := "gray"
			match int(entry["level"]):
				CCLog.Level.WARN: colour = "yellow"
				CCLog.Level.ERROR: colour = "red"
				CCLog.Level.INFO: colour = "white"
			lines.append("  [color=%s]%s[/color] %s" % [colour, entry["tag"], entry["msg"]])

	return "\n".join(lines)


func _phase_name(phase: int) -> String:
	var keys := GameState.Phase.keys()
	if phase >= 0 and phase < keys.size():
		return str(keys[phase])
	return "?"

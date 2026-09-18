extends Control
## "The two of you": who walks the hall, what they are called, and how they
## look — with whichever of them you are editing standing beside the swatches,
## turning.
##
## Two figures, two jobs, and the screen has to keep them straight without
## turning into a character creator:
##
##   * WHO YOU WALK AS decides who holds the map and who waits at the end of
##     the hall. It is one row at the top, because it changes the whole game.
##   * WHO YOU ARE EDITING is just which of them the swatches are dressing. It
##     is the row under it, and switching it changes nothing about the game.
##
## The preview is the real PixelFigure in a SubViewport with the gallery's kind
## of light on it, not a picture of one — so what is picked here is exactly what
## walks down the hall. It rebuilds on every swatch, which costs about a
## millisecond (around 760 triangles, generated in code).
##
## Saved to user://cast.json by CastProfile; the player controller, the gallery
## and the hospital room all read it when they build.

const HEADING := 30
const LABEL := 16

## Big enough to see the pixels, small enough to leave the swatches room.
const PREVIEW_SIZE := Vector2i(420, 560)
const TURN_SPEED := 0.55

var cast: CastProfile = null
## Which of the two the swatches are dressing. Starts as whoever the player
## walks as, because that is the one they came here to look at.
var editing: CastProfile.Role = CastProfile.Role.WIFE

var _figure: PixelFigure = null
var _camera: Camera3D = null
var _viewport: SubViewport = null
var _rows: VBoxContainer = null
var _status: Label = null
var _turning := true
var _angle := 0.0
var _swatch_rows: Array[HBoxContainer] = []

var _swatch_box: VBoxContainer = null
var _name_field: LineEdit = null
var _name_label: Label = null
var _play_buttons: Dictionary = {}     ## Role -> Button
var _edit_buttons: Dictionary = {}     ## Role -> Button
var _play_note: Label = null
var _hint: Label = null
var _title: Label = null


func _ready() -> void:
	cast = CastProfile.load_saved()
	editing = cast.player
	_build()
	_refresh_role_buttons()
	_rebuild_swatches()
	_rebuild_figure()


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
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	margin.add_child(columns)

	columns.add_child(_build_preview())
	columns.add_child(_build_controls())


func _build_preview() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)

	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(PREVIEW_SIZE)
	holder.add_child(frame)

	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(_viewport)

	# The hall's light, roughly: one warm key from the side, cool fill, and a
	# dark floor to stand on. Judging a palette under a different light than
	# the game's would be a waste of everyone's time.
	var world := Node3D.new()
	_viewport.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.082, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.44, 0.50)
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.72
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)

	# Two lights, both gentle. The first pass had one 6-energy spot a metre and
	# a half away, which blew her to white and threw a shadow slab across half
	# the preview — a palette cannot be judged through either.
	var key := SpotLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 2.4
	key.spot_range = 9.0
	key.spot_angle = 46.0
	key.spot_angle_attenuation = 0.8
	key.shadow_enabled = true
	key.shadow_bias = 0.06
	key.shadow_normal_bias = 3.0
	key.shadow_blur = 1.6
	key.position = Vector3(-1.9, 2.9, 2.4)
	key.look_at_from_position(key.position, Vector3(0, 0.85, 0), Vector3.UP)
	world.add_child(key)

	# Cool fill from the other side, so the shaded half is not a silhouette.
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.80, 0.86, 0.96)
	fill.light_energy = 0.75
	fill.omni_range = 5.0
	fill.shadow_enabled = false
	fill.position = Vector3(1.8, 1.5, 1.6)
	world.add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(2.6, 0.1, 2.6)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.20, 0.16, 0.13)
	floor_mat.roughness = 0.6
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.05, 0)
	world.add_child(floor_mesh)

	_camera = Camera3D.new()
	_camera.fov = 30.0
	# Far enough back that all of them fit with air above and below: they are
	# 1.62 m tall and were being cropped at the ankles.
	_camera.position = Vector3(0, 0.95, 3.5)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0.82, 0),
		Vector3.UP)
	_viewport.add_child(_camera)

	_hint = Label.new()
	_hint.text = "drag to turn her"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.50, 0.47, 0.43))
	holder.add_child(_hint)

	frame.gui_input.connect(_on_preview_input)
	return holder


func _build_controls() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.078, 0.070)
	style.border_color = Color(0.24, 0.22, 0.19)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	_title = Label.new()
	_title.text = "The two of you"
	_title.add_theme_font_size_override("font_size", HEADING)
	_title.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	_rows.add_child(_title)

	_rows.add_child(_blurb("One of them walks the hall with the map. The other"
		+ " waits at the far end of it, and lies in the bed at the start."))

	# 1. Who the player is. The one decision on this screen that changes the
	# game rather than the colours.
	_rows.add_child(_section("Who do you walk as?"))
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 10)
	_rows.add_child(play_row)
	for role in [CastProfile.Role.WIFE, CastProfile.Role.HUSBAND]:
		var button := _role_button(role, func() -> void: _set_player(role))
		_play_buttons[role] = button
		play_row.add_child(button)

	_play_note = _blurb("")
	_rows.add_child(_play_note)

	_rows.add_child(_separator())

	# 2. Which of them the swatches below are dressing. Changes nothing about
	# the game, which is why it is a separate row and says so.
	_rows.add_child(_section("Who are you dressing?"))
	var edit_row := HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 10)
	_rows.add_child(edit_row)
	for role in [CastProfile.Role.WIFE, CastProfile.Role.HUSBAND]:
		var button := _role_button(role, func() -> void: _set_editing(role))
		_edit_buttons[role] = button
		edit_row.add_child(button)

	_name_label = _section("Name")
	_rows.add_child(_name_label)
	_name_field = LineEdit.new()
	_name_field.max_length = FigureProfile.NAME_LIMIT
	_name_field.add_theme_font_size_override("font_size", LABEL)
	_name_field.text_changed.connect(_on_name_changed)
	_rows.add_child(_name_field)

	# The swatch rows are rebuilt when the figure changes, because the two
	# builds are offered different colours: a man's trousers and jumper come
	# from their own ranges, not from her dress swatches.
	_swatch_box = VBoxContainer.new()
	_swatch_box.add_theme_constant_override("separation", 10)
	_swatch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(_swatch_box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_rows.add_child(spacer)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", LABEL - 2)
	_status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	_rows.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_rows.add_child(buttons)
	buttons.add_child(_button("Save them", _on_save))
	buttons.add_child(_button("Start again", _on_reset))
	buttons.add_child(_button("Back to the menu", _on_back))

	return panel


func _blurb(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", LABEL)
	l.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52))
	return l


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", LABEL)
	l.add_theme_color_override("font_color", Color(0.78, 0.74, 0.67))
	return l


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	return sep


func _role_button(_role: CastProfile.Role, handler: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", LABEL)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b


# ------------------------------------------------------------------- state

func _current() -> FigureProfile:
	return cast.figure_for(editing)


func _set_player(role: CastProfile.Role) -> void:
	if cast.player == role:
		return
	cast.player = role
	# Dressing follows the choice: you almost always want to look at the one
	# you have just decided to be.
	editing = role
	_refresh_role_buttons()
	_rebuild_swatches()
	_rebuild_figure()
	_set_status("You will walk the hall as %s. %s waits at the end of it."
		% [cast.player_name(), cast.companion_name()])


func _set_editing(role: CastProfile.Role) -> void:
	if editing == role:
		return
	editing = role
	_refresh_role_buttons()
	_rebuild_swatches()
	_rebuild_figure()


## Both rows of buttons, the name field, and the two lines of prose that say
## what the state actually is.
func _refresh_role_buttons() -> void:
	for role in [CastProfile.Role.WIFE, CastProfile.Role.HUSBAND]:
		var who := cast.name_for(role)
		var side := "her" if role == CastProfile.Role.WIFE else "him"

		var play: Button = _play_buttons.get(role)
		if play != null:
			play.text = "%s  (%s)" % [who, side]
			# A tick rather than a colour: the swatch rows below already use
			# colour to mean "this is the one", and two meanings for one signal
			# on one screen is one too many.
			play.text = ("✓  " if cast.player == role else "    ") + play.text
			play.disabled = cast.player == role

		var edit: Button = _edit_buttons.get(role)
		if edit != null:
			edit.text = "%s  (%s)" % [who, side]
			edit.text = ("✓  " if editing == role else "    ") + edit.text
			edit.disabled = editing == role

	if _play_note != null:
		_play_note.text = "%s holds the map. %s is the one in the bed." \
			% [cast.player_name(), cast.companion_name()]

	if _name_label != null:
		_name_label.text = "What %s is called" % (
			"she" if editing == CastProfile.Role.WIFE else "he")
	if _name_field != null:
		_name_field.placeholder_text = CastProfile.DEFAULT_WIFE_NAME \
			if editing == CastProfile.Role.WIFE \
			else CastProfile.DEFAULT_HUSBAND_NAME
		if _name_field.text != _current().display_name:
			_name_field.text = _current().display_name

	if _hint != null:
		_hint.text = "drag to turn %s" % (
			"her" if editing == CastProfile.Role.WIFE else "him")

	if _title != null:
		_title.text = "The two of you"


func _on_name_changed(text: String) -> void:
	_current().display_name = text
	# Every label on this screen quotes the names, so they all move together.
	_refresh_role_buttons()


# ----------------------------------------------------------------- swatches

## Rebuilt rather than re-pointed, because which swatches exist depends on the
## build: trousers and jumpers have their own ranges.
func _rebuild_swatches() -> void:
	if _swatch_box == null:
		return
	for child in _swatch_box.get_children():
		_swatch_box.remove_child(child)
		child.queue_free()
	_swatch_rows.clear()

	var figure := _current()
	_add_swatch_row("Skin", FigureProfile.SKINS,
		func() -> Color: return _current().skin,
		func(c: Color) -> void: _current().skin = c)
	_add_swatch_row("Hair", FigureProfile.HAIRS,
		func() -> Color: return _current().hair,
		func(c: Color) -> void: _current().hair = c)
	_add_swatch_row(figure.dress_label(), figure.dress_options(),
		func() -> Color: return _current().dress,
		func(c: Color) -> void: _current().dress = c)
	_add_swatch_row(figure.wrap_label(), figure.wrap_options(),
		func() -> Color: return _current().wrap,
		func(c: Color) -> void: _current().wrap = c)
	_add_swatch_row("Shoes", FigureProfile.SHOES,
		func() -> Color: return _current().shoe,
		func(c: Color) -> void: _current().shoe = c)


func _add_swatch_row(row_name: String, options: Array, getter: Callable,
		setter: Callable) -> void:
	var label := Label.new()
	label.text = row_name
	label.add_theme_font_size_override("font_size", LABEL)
	label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))
	_swatch_box.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_swatch_box.add_child(row)
	_swatch_rows.append(row)

	for i in options.size():
		var colour: Color = options[i]
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(52, 52)
		swatch.tooltip_text = colour.to_html(false)
		swatch.focus_mode = Control.FOCUS_NONE

		var normal := StyleBoxFlat.new()
		normal.bg_color = colour
		normal.set_corner_radius_all(3)
		normal.border_color = Color(0.12, 0.11, 0.10)
		normal.set_border_width_all(2)
		swatch.add_theme_stylebox_override("normal", normal)

		var chosen := StyleBoxFlat.new()
		chosen.bg_color = colour
		chosen.set_corner_radius_all(3)
		chosen.border_color = Color(0.96, 0.92, 0.84)
		chosen.set_border_width_all(3)
		swatch.add_theme_stylebox_override("hover", chosen)
		swatch.set_meta("chosen_style", chosen)
		swatch.set_meta("normal_style", normal)
		swatch.set_meta("colour", colour)

		swatch.pressed.connect(func() -> void:
			setter.call(colour)
			_rebuild_figure()
			_mark_chosen())
		row.add_child(swatch)

	# Remembered so _mark_chosen can find the current one again.
	row.set_meta("getter", getter)


## Ring the swatch that is currently in use, in every row.
func _mark_chosen() -> void:
	for row in _swatch_rows:
		if not row.has_meta("getter"):
			continue
		var getter: Callable = row.get_meta("getter")
		var current: Color = getter.call()
		for child in row.get_children():
			var swatch := child as Button
			if swatch == null or not swatch.has_meta("colour"):
				continue
			var colour: Color = swatch.get_meta("colour")
			var style: StyleBox = swatch.get_meta(
				"chosen_style" if FigureProfile.same_colour(colour, current)
				else "normal_style")
			swatch.add_theme_stylebox_override("normal", style)


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", LABEL)
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- preview

## Rebuild rather than recolour: the figure's colours are vertex colours baked
## into a generated mesh, so changing one means generating it again. It is
## about a millisecond, which is why this can happen on every click.
func _rebuild_figure() -> void:
	if _viewport == null:
		return
	if _figure != null and is_instance_valid(_figure):
		_figure.get_parent().remove_child(_figure)
		_figure.queue_free()

	var figure := _current()
	_figure = PixelFigure.new()
	_viewport.get_child(0).add_child(_figure)
	_figure.build(figure.to_palette(), figure.form)
	_figure.rotation.y = _angle
	_apply_view()
	_mark_chosen()


## Keep them facing the camera as they turn, exactly as the game does — the
## drawn figure picks one of three views from where the camera is, so a preview
## that skipped this would show a plank.
func _apply_view() -> void:
	if _figure == null or _camera == null:
		return
	_figure.update_view_for_camera(_camera.global_position)


func _process(delta: float) -> void:
	if _figure == null:
		return
	if _turning:
		_angle = wrapf(_angle + delta * TURN_SPEED, -PI, PI)
		_figure.rotation.y = _angle
	_apply_view()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			# Dragging takes over; releasing hands them back to the turntable.
			_turning = not button.pressed
	elif event is InputEventMouseMotion and not _turning:
		var motion := event as InputEventMouseMotion
		_angle = wrapf(_angle - motion.relative.x * 0.01, -PI, PI)
		_figure.rotation.y = _angle
		_apply_view()


# ---------------------------------------------------------------- actions

func _on_save() -> void:
	if cast.save():
		Platform.sync_user_fs()
		_set_status("Saved. You walk as %s; %s is waiting."
			% [cast.player_name(), cast.companion_name()])
	else:
		_set_status("Could not save — they will look like this for now.")


func _on_reset() -> void:
	cast = CastProfile.create_default()
	editing = cast.player
	if _name_field != null:
		_name_field.text = _current().display_name
	_refresh_role_buttons()
	_rebuild_swatches()
	_rebuild_figure()
	_set_status("Back to the default: %s walks, %s waits."
		% [cast.player_name(), cast.companion_name()])


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel_custom"):
		_on_back()
		get_viewport().set_input_as_handled()

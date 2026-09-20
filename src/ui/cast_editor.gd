class_name CastEditor
extends HBoxContainer
## The two characters, edited: a turning preview on the left, and on the right
## the name, the build and five rows of swatches for whichever one is selected.
##
## This is a panel rather than a screen, because it is used in two places and
## must behave identically in both:
##
##   * the settings editor's General tab, where it edits the cast that will
##     travel inside the settings file;
##   * "Characters" on the menu, where it edits this machine's own default.
##
## Which character is selected is a view state, not data — switching it changes
## nothing. The one button here that DOES change the data is Swap, which
## exchanges the two, so whoever was waiting at the end of the hall now walks
## it. That is the only decision on this panel that changes the game.
##
## The preview is the real PixelFigure in a SubViewport under the hall's kind of
## light, not a picture of one, so what is picked here is exactly what walks
## down the hall. It rebuilds on every swatch, which costs about a millisecond.

signal changed()

const LABEL := 16
const PREVIEW_SIZE := Vector2i(360, 480)
const TURN_SPEED := 0.55

var cast: CastProfile = null
## Which character the swatches are dressing. View state only.
var editing: CastProfile.Role = CastProfile.Role.MAIN

var _figure: PixelFigure = null
var _camera: Camera3D = null
var _viewport: SubViewport = null
var _turning := true
var _angle := 0.0

var _swatch_rows: Array[HBoxContainer] = []
var _swatch_box: VBoxContainer = null
var _name_field: LineEdit = null
var _role_buttons: Dictionary = {}     ## Role -> Button
var _build_buttons: Dictionary = {}    ## PixelFigure.Build -> Button
var _hint: Label = null


## Give it a cast to edit. Called before it enters the tree, or after.
func setup(who: CastProfile) -> void:
	cast = who
	editing = CastProfile.Role.MAIN
	if _swatch_box != null:
		_refresh_all()


func _ready() -> void:
	add_theme_constant_override("separation", 28)
	if cast == null:
		cast = CastProfile.create_default()
	add_child(_build_preview())
	add_child(_build_controls())
	_refresh_all()


func _refresh_all() -> void:
	_refresh_buttons()
	_rebuild_swatches()
	_rebuild_figure()


# ------------------------------------------------------------------ preview

func _build_preview() -> Control:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 8)

	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.custom_minimum_size = Vector2(PREVIEW_SIZE)
	holder.add_child(frame)

	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(_viewport)

	# The hall's light, roughly: one warm key from the side, a cool fill, and a
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
	# a half away, which blew the figure to white and threw a shadow slab
	# across half the preview — a palette cannot be judged through either.
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
	# Far enough back that the whole figure fits with air above and below: it
	# is 1.62 m tall and was being cropped at the ankles.
	_camera.position = Vector3(0, 0.95, 3.5)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0.82, 0),
		Vector3.UP)
	_viewport.add_child(_camera)

	_hint = Label.new()
	_hint.text = "drag to turn"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.50, 0.47, 0.43))
	holder.add_child(_hint)

	frame.gui_input.connect(_on_preview_input)
	return holder


# ----------------------------------------------------------------- controls

## No ScrollContainer of its own: this panel is embedded in screens that
## already scroll, and two nested scrollbars in one tab is one too many. It
## asks for the height it needs instead — see the caller's custom_minimum_size.
func _build_controls() -> Control:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 1. Which of the two is being edited.
	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 8)
	rows.add_child(role_row)
	for role in [CastProfile.Role.MAIN, CastProfile.Role.SIDE]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", LABEL)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _select(role))
		_role_buttons[role] = button
		role_row.add_child(button)

	# 2. The name.
	rows.add_child(_section("Name"))
	_name_field = LineEdit.new()
	_name_field.max_length = FigureProfile.NAME_LIMIT
	_name_field.add_theme_font_size_override("font_size", LABEL)
	_name_field.text_changed.connect(_on_name_changed)
	rows.add_child(_name_field)

	# 3. The build.
	rows.add_child(_section("Build"))
	var build_row := HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8)
	rows.add_child(build_row)
	for kind in [PixelFigure.Build.TROUSERS, PixelFigure.Build.SKIRT]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", LABEL - 1)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: _set_build(kind))
		_build_buttons[kind] = button
		build_row.add_child(button)

	# 4. Five colours.
	_swatch_box = VBoxContainer.new()
	_swatch_box.add_theme_constant_override("separation", 8)
	_swatch_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(_swatch_box)

	# 5. And the one button that changes the game rather than the colours.
	rows.add_child(_separator())
	var swap := Button.new()
	swap.text = "Swap them"
	swap.custom_minimum_size = Vector2(0, 38)
	swap.add_theme_font_size_override("font_size", LABEL - 1)
	swap.pressed.connect(_on_swap)
	rows.add_child(swap)

	return rows


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", LABEL)
	l.add_theme_color_override("font_color", Color(0.78, 0.74, 0.67))
	return l


func _separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	return sep


# -------------------------------------------------------------------- state

func _current() -> FigureProfile:
	return cast.figure_for(editing)


func _select(role: CastProfile.Role) -> void:
	if editing == role:
		return
	editing = role
	_refresh_all()


func _set_build(kind: PixelFigure.Build) -> void:
	if _current().form == kind:
		return
	_current().set_build(kind)
	_refresh_buttons()
	_rebuild_swatches()
	_rebuild_figure()
	changed.emit()


func _on_swap() -> void:
	cast.swap()
	_refresh_all()
	changed.emit()


func _on_name_changed(text: String) -> void:
	_current().display_name = text
	_refresh_buttons()
	changed.emit()


func _refresh_buttons() -> void:
	for role in [CastProfile.Role.MAIN, CastProfile.Role.SIDE]:
		var button: Button = _role_buttons.get(role)
		if button == null:
			continue
		# A tick rather than a colour: the swatches below already use colour to
		# mean "this is the one", and two meanings for one signal on one panel
		# is one too many.
		button.text = "%s%s — %s" % [
			"✓  " if editing == role else "    ",
			CastProfile.label_for(role),
			cast.name_for(role)]
		button.disabled = editing == role

	for kind in _build_buttons.keys():
		var button: Button = _build_buttons[kind]
		var current: bool = _current().form == kind
		# The same tick the role buttons use. Without it the DIM button is the
		# selected one — disabled means "you are already on this" — which
		# reads exactly backwards.
		button.text = "%s%s" % ["✓  " if current else "    ",
			"Trousers" if kind == PixelFigure.Build.TROUSERS else "Skirt"]
		button.disabled = current

	if _name_field != null:
		_name_field.placeholder_text = CastProfile.DEFAULT_MAIN_NAME \
			if editing == CastProfile.Role.MAIN else CastProfile.DEFAULT_SIDE_NAME
		# Guarded, or setting it from here re-enters _on_name_changed.
		if _name_field.text != _current().display_name:
			_name_field.text = _current().display_name


# ----------------------------------------------------------------- swatches

## Rebuilt rather than re-pointed, because which swatches exist depends on the
## build: trousers and jumpers have their own colour ranges.
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
	_swatch_box.add_child(_section(row_name))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_swatch_box.add_child(row)
	_swatch_rows.append(row)

	for i in options.size():
		var colour: Color = options[i]
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(46, 46)
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
			_mark_chosen()
			changed.emit())
		row.add_child(swatch)

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


# ------------------------------------------------------------------- figure

## Rebuild rather than recolour: the colours are vertex colours baked into a
## generated mesh, so changing one means generating it again. About a
## millisecond, which is why this can happen on every click.
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


## Keep the figure facing the camera as it turns, exactly as the game does —
## the drawn figure picks one of three views from where the camera is, so a
## preview that skipped this would show a plank.
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
			# Dragging takes over; releasing hands it back to the turntable.
			_turning = not button.pressed
	elif event is InputEventMouseMotion and not _turning:
		var motion := event as InputEventMouseMotion
		_angle = wrapf(_angle - motion.relative.x * 0.01, -PI, PI)
		_figure.rotation.y = _angle
		_apply_view()

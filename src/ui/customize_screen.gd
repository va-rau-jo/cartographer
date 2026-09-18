extends Control
## "Choose how she looks": five rows of swatches and the figure standing beside
## them, turning.
##
## The preview is the real PixelFigure in a SubViewport with the gallery's kind
## of light on it, not a picture of one — so what she picks is exactly what
## walks down the hall. It rebuilds on every swatch, which costs about a
## millisecond (758 triangles, generated in code).
##
## Saved to user://profile.json by FigureProfile; the player controller reads
## it when the gallery builds.

const HEADING := 30
const LABEL := 16

## Big enough to see the pixels, small enough to leave the swatches room.
const PREVIEW_SIZE := Vector2i(420, 560)
const TURN_SPEED := 0.55

var profile: FigureProfile = null

var _figure: PixelFigure = null
var _camera: Camera3D = null
var _viewport: SubViewport = null
var _rows: VBoxContainer = null
var _status: Label = null
var _turning := true
var _angle := 0.0
var _swatch_rows: Array[HBoxContainer] = []


func _ready() -> void:
	profile = FigureProfile.load_saved()
	_build()
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
	# Far enough back that all of her fits with air above and below: she is
	# 1.62 m tall and was being cropped at the ankles.
	_camera.position = Vector3(0, 0.95, 3.5)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0.82, 0),
		Vector3.UP)
	_viewport.add_child(_camera)

	var hint := Label.new()
	hint.text = "drag to turn her"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.50, 0.47, 0.43))
	holder.add_child(hint)

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

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	panel.add_child(_rows)

	var title := Label.new()
	title.text = "Choose how she looks"
	title.add_theme_font_size_override("font_size", HEADING)
	title.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	_rows.add_child(title)

	var blurb := Label.new()
	blurb.text = "She is who the player walks the hall as, and she is on"
	blurb.text += " screen the whole time."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", LABEL)
	blurb.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52))
	_rows.add_child(blurb)

	_swatch_rows.clear()
	_add_swatch_row("Skin", FigureProfile.SKINS,
		func() -> Color: return profile.skin,
		func(c: Color) -> void: profile.skin = c)
	_add_swatch_row("Hair", FigureProfile.HAIRS,
		func() -> Color: return profile.hair,
		func(c: Color) -> void: profile.hair = c)
	_add_swatch_row("Dress", FigureProfile.DRESSES,
		func() -> Color: return profile.dress,
		func(c: Color) -> void: profile.dress = c)
	_add_swatch_row("Cardigan", FigureProfile.WRAPS,
		func() -> Color: return profile.wrap,
		func(c: Color) -> void: profile.wrap = c)
	_add_swatch_row("Shoes", FigureProfile.SHOES,
		func() -> Color: return profile.shoe,
		func(c: Color) -> void: profile.shoe = c)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_child(spacer)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", LABEL - 2)
	_status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	_rows.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	_rows.add_child(buttons)
	buttons.add_child(_button("Save her", _on_save))
	buttons.add_child(_button("Start again", _on_reset))
	buttons.add_child(_button("Back to the menu", _on_back))

	return panel


func _add_swatch_row(name: String, options: Array, getter: Callable,
		setter: Callable) -> void:
	var label := Label.new()
	label.text = name
	label.add_theme_font_size_override("font_size", LABEL)
	label.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))
	_rows.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows.add_child(row)
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

	_figure = PixelFigure.new()
	_viewport.get_child(0).add_child(_figure)
	_figure.build(profile.to_palette())
	_figure.rotation.y = _angle
	_apply_view()
	_set_status("")


## Keep her facing the camera as she turns, exactly as the game does — the
## drawn figure picks one of three views from where the camera is, so a
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
			# Dragging takes over; releasing hands her back to the turntable.
			_turning = not button.pressed
	elif event is InputEventMouseMotion and not _turning:
		var motion := event as InputEventMouseMotion
		_angle = wrapf(_angle - motion.relative.x * 0.01, -PI, PI)
		_figure.rotation.y = _angle
		_apply_view()


# ---------------------------------------------------------------- actions

func _on_save() -> void:
	if profile.save():
		Platform.sync_user_fs()
		_set_status("Saved. She will look like this in the hall.")
	else:
		_set_status("Could not save — she will look like this for now.")


func _on_reset() -> void:
	profile = FigureProfile.new()
	_rebuild_figure()
	_mark_chosen()
	_set_status("Back to the default.")


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel_custom"):
		_on_back()
		get_viewport().set_input_as_handled()

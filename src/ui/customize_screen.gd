extends Control
## "Characters" on the menu: this machine's own two characters.
##
## Almost all of this screen is CastEditor, which is the same panel the
## settings editor's General tab uses — so the two never drift apart. What is
## here on top of it is where the cast is saved: `user://cast.json`, which is
## the default a NEW settings file starts from.
##
## Worth being clear about, because it is the one confusing thing: a settings
## file carries its own two characters, and when one is loaded, its characters
## are the ones that play. This screen sets what a new file begins with, and
## who plays when a file names nobody.

const HEADING := 30
const LABEL := 16

var cast: CastProfile = null

var _editor: CastEditor = null
var _status: Label = null


func _ready() -> void:
	cast = CastProfile.load_saved()
	_build()


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

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "Characters"
	title.add_theme_font_size_override("font_size", HEADING)
	title.add_theme_color_override("font_color", Color(0.94, 0.90, 0.82))
	rows.add_child(title)

	var blurb := Label.new()
	blurb.text = "Two characters. The main one walks the hall with the map;"
	blurb.text += " the side one waits at the end of it. These are the two a"
	blurb.text += " new settings file starts with."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", LABEL)
	blurb.add_theme_color_override("font_color", Color(0.60, 0.57, 0.52))
	rows.add_child(blurb)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.078, 0.070)
	style.border_color = Color(0.24, 0.22, 0.19)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(panel)

	_editor = CastEditor.new()
	_editor.setup(cast)
	_editor.changed.connect(func() -> void: _set_status(""))
	panel.add_child(_editor)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", LABEL - 2)
	_status.add_theme_color_override("font_color", Color(0.62, 0.58, 0.52))
	rows.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	buttons.add_child(_button("Save", _on_save))
	buttons.add_child(_button("Start again", _on_reset))
	buttons.add_child(_button("Back to the menu", _on_back))


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", LABEL)
	b.pressed.connect(handler)
	return b


# ---------------------------------------------------------------- actions

func _on_save() -> void:
	if cast.save():
		Platform.sync_user_fs()
		_set_status("Saved. %s walks; %s waits."
			% [cast.main_name(), cast.side_name()])
	else:
		_set_status("Could not save — they will look like this for now.")


func _on_reset() -> void:
	cast = CastProfile.create_default()
	_editor.setup(cast)
	_set_status("Back to the default: %s walks, %s waits."
		% [cast.main_name(), cast.side_name()])


func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel_custom"):
		_on_back()
		get_viewport().set_input_as_handled()

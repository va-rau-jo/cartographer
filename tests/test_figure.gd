extends RefCounted
## The player's own figure: the palette she is built from, and where that is
## remembered between sessions.
##
## The brief asked for a customizable player model. For a drawn figure that
## comes down to five colours, and the assertions worth making are that a
## colour actually reaches the mesh, that the shading stays derived from it
## rather than fixed, and that a profile survives the round trip to disk —
## including when the file is missing, empty or rubbish, because a player who
## cannot get into the game is a worse outcome than a default-looking woman.

const TEST_PATH := "user://test_figure_profile.json"

var _holder: Node3D = null


func run() -> TestFramework:
	var t := TestFramework.new("figure")

	_holder = Node3D.new()
	_holder.name = "FigureTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	_test_palette(t)
	_test_presets(t)
	_test_round_trip(t)
	_test_broken_files(t)
	_test_reaches_the_mesh(t)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null
	return t


# ---------------------------------------------------------------- palette

func _test_palette(t: TestFramework) -> void:
	var profile := FigureProfile.new()
	profile.skin = Color(0.80, 0.60, 0.50)
	profile.hair = Color(0.30, 0.25, 0.20)
	profile.dress = Color(0.20, 0.40, 0.60)
	profile.wrap = Color(0.55, 0.50, 0.45)
	profile.shoe = Color(0.10, 0.10, 0.12)

	var palette := profile.to_palette()
	t.ok(palette.skin.is_equal_approx(profile.skin), "the skin reaches the palette")
	t.ok(palette.dress.is_equal_approx(profile.dress), "and the dress")
	t.ok(palette.wrap.is_equal_approx(profile.wrap), "and the cardigan")
	t.ok(FigureProfile.same_colour(palette.hair, profile.hair),
		"and the hair")

	# The shades are derived, not authored: moving one swatch has to move its
	# shading with it, or the figure comes out with mismatched form shading.
	var colours := palette.to_array()
	var skin_shade: Color = colours[2]
	t.lt(skin_shade.v, palette.skin.v, "the skin's shade is darker than the skin")
	t.gt(skin_shade.v, palette.skin.v * 0.5,
		"but not so dark it reads as a hole")

	var dress_shade: Color = colours[6]
	t.lt(dress_shade.v, palette.dress.v, "the dress shades from the dress")
	t.gt(dress_shade.b, dress_shade.r,
		"a blue dress still shades blue (r %.2f, b %.2f)"
			% [dress_shade.r, dress_shade.b])

	t.eq(colours.size(), 12, "a palette is twelve entries")
	t.ok((colours[0] as Color).a < 0.01, "the first of which is nothing")


func _test_presets(t: TestFramework) -> void:
	var slots := {
		"skins": FigureProfile.SKINS,
		"hairs": FigureProfile.HAIRS,
		"dresses": FigureProfile.DRESSES,
		"wraps": FigureProfile.WRAPS,
		"shoes": FigureProfile.SHOES,
	}
	for name in slots.keys():
		var options: Array = slots[name]
		t.gt(float(options.size()), 3.0, "%s offers a choice" % name)

		# Distinct enough to tell apart on a 52-pixel swatch.
		var duplicates := 0
		for i in options.size():
			for j in range(i + 1, options.size()):
				if FigureProfile.same_colour(options[i], options[j]):
					duplicates += 1
		t.eq(duplicates, 0, "%s has no repeats" % name)

		for colour in options:
			var c: Color = colour
			t.ok(c.a > 0.99, "every %s swatch is opaque" % name)

	# The defaults have to be among the swatches, or the screen opens with
	# nothing ringed and looks broken.
	var profile := FigureProfile.new()
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, profile.skin)), -1.0,
		"the default skin is one of the swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.HAIRS, profile.hair)), -1.0,
		"and the default hair")
	t.gt(float(FigureProfile.index_of(FigureProfile.DRESSES, profile.dress)), -1.0,
		"and the default dress")
	t.eq(FigureProfile.index_of(FigureProfile.SKINS, Color(0.01, 0.02, 0.03)), -1,
		"a colour that is not a swatch is not found")


# ------------------------------------------------------------- persistence

func _test_round_trip(t: TestFramework) -> void:
	var profile := FigureProfile.new()
	profile.skin = FigureProfile.SKINS[4]
	profile.hair = FigureProfile.HAIRS[0]
	profile.dress = FigureProfile.DRESSES[2]
	profile.wrap = FigureProfile.WRAPS[3]
	profile.shoe = FigureProfile.SHOES[1]

	t.ok(profile.save(TEST_PATH), "a figure saves")
	t.ok(FileAccess.file_exists(TEST_PATH), "and the file is there")

	# To eight bits per channel, which is what hex storage keeps and what the
	# mesh's vertex colours keep too — see FigureProfile.same_colour.
	var back := FigureProfile.load_saved(TEST_PATH)
	t.ok(FigureProfile.same_colour(back.skin, profile.skin), "the skin comes back")
	t.ok(FigureProfile.same_colour(back.hair, profile.hair), "and the hair")
	t.ok(FigureProfile.same_colour(back.dress, profile.dress), "and the dress")
	t.ok(FigureProfile.same_colour(back.wrap, profile.wrap), "and the cardigan")
	t.ok(FigureProfile.same_colour(back.shoe, profile.shoe), "and the shoes")

	# And a saved figure still recognises its own swatches, or the screen
	# opens with nothing ringed.
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, back.skin)), -1.0,
		"a saved skin is still found among the swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.DRESSES, back.dress)), -1.0,
		"and a saved dress")

	# It is a readable file on purpose: an author who wants a colour that is
	# not on the swatch row can type one in.
	var text := FileAccess.get_file_as_string(TEST_PATH)
	t.ok(text.contains("figure"), "the file is legible JSON")
	t.ok(text.contains("skin"), "with named fields")


func _test_broken_files(t: TestFramework) -> void:
	var default := FigureProfile.new()

	var missing := FigureProfile.load_saved("user://not_here_at_all.json")
	t.ok(FigureProfile.same_colour(missing.skin, default.skin),
		"a missing profile is the default figure, not an error")

	for rubbish in ["", "{ not json", "[]", '{"schema": 99, "figure": {}}']:
		var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
		f.store_string(rubbish)
		f.close()
		var loaded := FigureProfile.load_saved(TEST_PATH)
		t.ok(FigureProfile.same_colour(loaded.skin, default.skin),
			"a profile of %s falls back to the default"
				% ("nothing" if rubbish.is_empty() else rubbish.substr(0, 14)))

	# A partial profile keeps what it has and defaults the rest, rather than
	# refusing the whole file.
	var partial := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	partial.store_string('{"schema": 1, "figure": {"dress": "3366aa"}}')
	partial.close()
	var half := FigureProfile.load_saved(TEST_PATH)
	t.close(half.dress.b, 0.666, 0.05, "the one field given is used")
	t.ok(FigureProfile.same_colour(half.skin, default.skin),
		"and the missing ones are the defaults")

	# An unparseable colour must not become black.
	var bad_colour := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	bad_colour.store_string('{"schema": 1, "figure": {"hair": "not a colour"}}')
	bad_colour.close()
	var safe := FigureProfile.load_saved(TEST_PATH)
	t.ok(FigureProfile.same_colour(safe.hair, default.hair),
		"a nonsense colour falls back rather than going black")


# -------------------------------------------------------- reaching the mesh

## The whole point: a chosen colour has to end up in the geometry. The figure's
## colours are vertex colours baked into a generated mesh, so this is checked
## by building two figures and comparing their vertex data.
func _test_reaches_the_mesh(t: TestFramework) -> void:
	var plain := FigureProfile.new()
	var loud := FigureProfile.new()
	loud.dress = Color(0.90, 0.10, 0.80)

	var a := PixelFigure.new()
	_holder.add_child(a)
	a.build(plain.to_palette())

	var b := PixelFigure.new()
	_holder.add_child(b)
	b.build(loud.to_palette())

	t.eq(a.total_triangles(), b.total_triangles(),
		"changing a colour does not change the geometry")
	t.gt(float(a.total_triangles()), 0.0, "and there is geometry to change")

	t.ok(_has_colour(b, loud.dress), "the chosen dress colour is in the mesh")
	t.ok(not _has_colour(a, loud.dress),
		"and was not there before it was chosen")
	t.ok(_has_colour(a, plain.dress), "the default dress is in the default figure")

	# Rebuilding in place, which is what the customization screen does on every
	# swatch, must not leave two figures' worth of meshes behind.
	var before := a.total_triangles()
	a.apply_palette(loud.to_palette())
	t.eq(a.total_triangles(), before,
		"applying a palette rebuilds rather than accumulating")
	t.ok(_has_colour(a, loud.dress), "with the new colour")

	for figure in [a, b]:
		figure.get_parent().remove_child(figure)
		figure.free()


## True when any vertex of any view carries this colour.
func _has_colour(figure: PixelFigure, colour: Color) -> bool:
	for node in figure.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for c in colours:
				# Vertex colours are eight bits per channel in the mesh.
				if FigureProfile.same_colour(c, colour):
					return true
	return false

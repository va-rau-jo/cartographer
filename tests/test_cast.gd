extends RefCounted
## The two of them: who you play as, what they are called, and the second body.
##
## The rule this suite exists to protect: everything downstream asks the cast
## for "the player" and "the companion" and never for "her" and "him", so
## swapping who you play swaps who is in the bed at the start and who waits at
## the end of the hall — with one exception, the drawn embrace, which is a pose
## of a specific pair and asks for the wife and the husband by name.

const CAST_PATH := "user://test_cast.json"
const OLD_PATH := "user://test_old_profile.json"


func run() -> TestFramework:
	var t := TestFramework.new("cast")

	_test_defaults(t)
	_test_swap(t)
	_test_names(t)
	_test_round_trip(t)
	_test_broken_files(t)
	_test_adopting_an_old_profile(t)
	_test_swatch_lists(t)
	_test_two_bodies(t)
	_test_resting_head(t)

	_remove(CAST_PATH)
	_remove(OLD_PATH)
	return t


# ------------------------------------------------------------------ basics

func _test_defaults(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.eq(cast.player, CastProfile.Role.WIFE, "she is the one you play by default")
	t.eq(cast.wife.display_name, "Chelsea", "and she is Chelsea")
	t.eq(cast.husband.display_name, "Victor", "he is Victor")
	t.eq(cast.player_name(), "Chelsea", "so the player is Chelsea")
	t.eq(cast.companion_name(), "Victor", "and the one waiting is Victor")

	t.eq(cast.wife.form, PixelFigure.Form.WOMAN, "she is drawn as a woman")
	t.eq(cast.husband.form, PixelFigure.Form.MAN, "and he as a man")

	# Every default colour must be one of the offered swatches, or the
	# customization screen opens with nothing ringed.
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, cast.wife.skin)),
		-1.0, "her skin is one of the swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.TROUSERS,
		cast.husband.dress)), -1.0, "his trousers are one of his swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.JUMPERS,
		cast.husband.wrap)), -1.0, "and his jumper")


func _test_swap(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.ok(cast.player_figure() == cast.wife, "she holds the map")
	t.ok(cast.companion_figure() == cast.husband, "he waits")
	t.eq(cast.companion_role(), CastProfile.Role.HUSBAND, "he is the companion")

	cast.player = CastProfile.Role.HUSBAND
	t.ok(cast.player_figure() == cast.husband, "now he holds the map")
	t.ok(cast.companion_figure() == cast.wife, "and she is the one waiting")
	t.eq(cast.companion_role(), CastProfile.Role.WIFE, "she is the companion")
	t.eq(cast.player_name(), "Victor", "the player's name follows")
	t.eq(cast.companion_name(), "Chelsea", "and so does the other one's")

	# The one you play is never also the one in the bed.
	t.ok(cast.player_figure() != cast.companion_figure(),
		"the player is never also the one dying")
	t.eq(cast.other_than(cast.player), CastProfile.Role.WIFE,
		"and the roles stay opposite")


func _test_names(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	cast.wife.display_name = "  Margaret  "
	t.eq(cast.name_for(CastProfile.Role.WIFE), "Margaret",
		"a name is trimmed")

	# An empty name in a line of his dialogue reads as a bug, not as silence.
	cast.wife.display_name = ""
	t.eq(cast.name_for(CastProfile.Role.WIFE), "Chelsea",
		"an empty name falls back rather than showing nothing")
	cast.husband.display_name = "   "
	t.eq(cast.name_for(CastProfile.Role.HUSBAND), "Victor",
		"and so does a name of spaces")

	var long_name := "Bartholomew Fitzwilliam Montgomery the Third"
	var read := FigureProfile.from_figure_dict({"name": long_name})
	t.eq(read.display_name.length(), FigureProfile.NAME_LIMIT,
		"a very long name is cut to the limit (%d)" % read.display_name.length())


# -------------------------------------------------------------------- disk

func _test_round_trip(t: TestFramework) -> void:
	var cast := CastProfile.create_default()
	cast.player = CastProfile.Role.HUSBAND
	cast.wife.display_name = "Maggie"
	cast.wife.hair = FigureProfile.HAIRS[0]
	cast.wife.dress = FigureProfile.DRESSES[3]
	cast.husband.display_name = "Tom"
	cast.husband.skin = FigureProfile.SKINS[4]
	cast.husband.dress = FigureProfile.TROUSERS[2]
	cast.husband.wrap = FigureProfile.JUMPERS[1]

	t.ok(cast.save(CAST_PATH), "the cast saves")
	var back := CastProfile.load_saved(CAST_PATH)

	t.eq(back.player, CastProfile.Role.HUSBAND, "who you play comes back")
	t.eq(back.wife.display_name, "Maggie", "her name comes back")
	t.eq(back.husband.display_name, "Tom", "and his")
	# Hex on disk, 8-bit vertex colours in the mesh — see same_colour.
	t.ok(FigureProfile.same_colour(back.wife.hair, cast.wife.hair),
		"her hair comes back")
	t.ok(FigureProfile.same_colour(back.wife.dress, cast.wife.dress),
		"and her dress")
	t.ok(FigureProfile.same_colour(back.husband.skin, cast.husband.skin),
		"his skin comes back")
	t.ok(FigureProfile.same_colour(back.husband.dress, cast.husband.dress),
		"and his trousers")
	t.ok(FigureProfile.same_colour(back.husband.wrap, cast.husband.wrap),
		"and his jumper")
	t.eq(back.wife.form, PixelFigure.Form.WOMAN, "she is still a woman")
	t.eq(back.husband.form, PixelFigure.Form.MAN, "he is still a man")


func _test_broken_files(t: TestFramework) -> void:
	# Nothing there at all.
	_remove(CAST_PATH)
	_remove(OLD_PATH)
	var missing := CastProfile.load_saved(CAST_PATH)
	t.eq(missing.player_name(), "Chelsea",
		"a missing file is the default cast")

	# Not JSON.
	var f := FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()
	var broken := CastProfile.load_saved(CAST_PATH)
	t.eq(broken.player_name(), "Chelsea", "so is a file that is not JSON")

	# A schema we do not know: refuse rather than guess, the same rule the
	# album manifest follows.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 99, "player": "husband"}')
	f.close()
	var future := CastProfile.load_saved(CAST_PATH)
	t.eq(future.player, CastProfile.Role.WIFE,
		"a schema from the future is refused, not half-read")

	# Half a file: the fields that are there are used, the rest default.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 1, "wife": {"name": "Ann"}}')
	f.close()
	var partial := CastProfile.load_saved(CAST_PATH)
	t.eq(partial.wife.display_name, "Ann", "a partial file keeps what it has")
	t.eq(partial.husband.display_name, "Victor", "and defaults the rest")
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, partial.wife.skin)),
		-1.0, "with a whole person's colours")

	# A file that claims she is drawn as a man would put a skirt-less figure in
	# the bed the hospital room dresses as her.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 1, "wife": {"form": "man"},'
		+ ' "husband": {"form": "woman"}}')
	f.close()
	var forms := CastProfile.load_saved(CAST_PATH)
	t.eq(forms.wife.form, PixelFigure.Form.WOMAN, "her build is not swappable")
	t.eq(forms.husband.form, PixelFigure.Form.MAN, "nor his")

	_remove(CAST_PATH)


## Somebody who already made a figure in the build that only had one keeps it.
func _test_adopting_an_old_profile(t: TestFramework) -> void:
	var old := FigureProfile.wife_default()
	old.hair = FigureProfile.HAIRS[4]
	old.dress = FigureProfile.DRESSES[2]
	t.ok(old.save(OLD_PATH), "the old single-figure file saves")

	var cast := CastProfile._adopt_old_profile(OLD_PATH)
	t.ok(FigureProfile.same_colour(cast.wife.hair, old.hair),
		"her old hair colour is adopted")
	t.ok(FigureProfile.same_colour(cast.wife.dress, old.dress),
		"and her old dress")
	t.eq(cast.husband.display_name, "Victor", "he starts from the default")
	t.eq(cast.player, CastProfile.Role.WIFE, "and she is still the player")

	_remove(OLD_PATH)
	var nothing := CastProfile._adopt_old_profile(OLD_PATH)
	t.eq(nothing.player_name(), "Chelsea",
		"with no old file it is simply the default")


# ---------------------------------------------------------------- swatches

func _test_swatch_lists(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.ok(cast.wife.dress_options() == FigureProfile.DRESSES,
		"she is offered dresses")
	t.ok(cast.husband.dress_options() == FigureProfile.TROUSERS,
		"he is offered trousers")
	t.ok(cast.husband.wrap_options() == FigureProfile.JUMPERS,
		"and jumpers")
	t.eq(cast.wife.dress_label(), "Dress", "and the labels say which")
	t.eq(cast.husband.dress_label(), "Trousers", "for him too")
	t.eq(cast.husband.wrap_label(), "Jumper", "including the top half")

	# No duplicates within a list: two identical swatches look like a bug.
	for pair in [["trousers", FigureProfile.TROUSERS],
			["jumpers", FigureProfile.JUMPERS]]:
		var options: Array = pair[1]
		for i in options.size():
			for j in range(i + 1, options.size()):
				t.ok(not FigureProfile.same_colour(options[i], options[j]),
					"%s %d and %d differ" % [pair[0], i, j])


# ------------------------------------------------------------- the drawings

func _test_two_bodies(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	var her := PixelFigure.new()
	her.build(cast.wife.to_palette(), cast.wife.form)
	var him := PixelFigure.new()
	him.build(cast.husband.to_palette(), cast.husband.form)

	t.gt(float(her.total_triangles()), 0.0, "she is drawn")
	t.gt(float(him.total_triangles()), 0.0, "and so is he")
	t.ok(her.total_triangles() != him.total_triangles(),
		"and they are not the same drawing (%d vs %d triangles)"
			% [her.total_triangles(), him.total_triangles()])

	# The same height, because the hug at the ending is one drawn pose that
	# expects a pair whose proportions it already knows.
	t.eq(PixelFigure.SPRITE_HEIGHT, 56, "both are 56 pixels tall")

	# Trousers, which is the strongest read at this size: daylight up the
	# middle where her skirt is solid.
	var his_front: PackedByteArray = him._front_canvas_man()
	var her_front: PackedByteArray = her._front_canvas()
	var cx := int(PixelFigure.CENTRE)
	var gap_rows := 0
	for y in range(6, 20):
		if his_front[cx + PixelFigure.SPRITE_WIDTH * y] == PixelFigure.EMPTY:
			gap_rows += 1
	t.gt(float(gap_rows), 10.0,
		"his legs have daylight between them (%d rows)" % gap_rows)
	t.ok(her_front[cx + PixelFigure.SPRITE_WIDTH * 12] != PixelFigure.EMPTY,
		"where her skirt is solid")

	# No bun on the back of his head, and hair on the back of hers.
	var his_back: PackedByteArray = him._back_canvas_man()
	t.gt(float(_count(his_back, PixelFigure.HAIR)), 0.0,
		"his hair is drawn from behind")
	t.lt(float(_count(his_back, PixelFigure.HAIR_SHADE)),
		float(_count(her._back_canvas(), PixelFigure.HAIR_SHADE)),
		"with less of it than her bun")

	# Every view exists for both, or a figure turns into nothing when the
	# camera crosses behind it.
	for pair in [["her", her], ["him", him]]:
		var figure: PixelFigure = pair[1]
		for view in [PixelFigure.View.FRONT, PixelFigure.View.SIDE,
				PixelFigure.View.BACK]:
			figure.set_view(view, false)
			var visible := 0
			for mi in figure.find_children("*", "MeshInstance3D", true, false):
				if (mi as MeshInstance3D).visible:
					visible += 1
			t.eq(visible, 1, "%s has exactly one view showing at a time"
				% pair[0])

	# Re-dressing keeps the build: an earlier apply_palette took the colours
	# and silently rebuilt as the default body.
	him.apply_palette(cast.wife.to_palette())
	t.eq(him.form, PixelFigure.Form.MAN,
		"changing his colours does not change his build")

	her.free()
	him.free()


## The head on the pillow is whoever is dying, and her hair spreads on it.
func _test_resting_head(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	var his := RestingHead.new()
	his.build(cast.husband.to_palette(), cast.husband.form)
	var hers := RestingHead.new()
	hers.build(cast.wife.to_palette(), cast.wife.form)

	t.gt(float(his.filled_pixels()), 0.0, "his head is drawn")
	t.gt(float(hers.filled_pixels()), float(his.filled_pixels()),
		"hers takes more of the pillow (%d vs %d pixels)"
			% [hers.filled_pixels(), his.filled_pixels()])
	t.gt(float(hers.total_triangles()), 0.0, "and it becomes geometry")

	his.free()
	hers.free()


# ------------------------------------------------------------------ helpers

static func _count(canvas: PackedByteArray, value: int) -> int:
	var n := 0
	for v in canvas:
		if v == value:
			n += 1
	return n


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

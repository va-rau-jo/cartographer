extends RefCounted
## The two characters: main and side.
##
## The rule this suite exists to protect: everything downstream asks the cast
## for the MAIN or the SIDE character and never for a gender, so the two can be
## swapped, renamed or re-dressed without any scene knowing. The one exception
## is the drawn embrace, which is a fixed pose with a skirted figure on the
## left, and so asks by BUILD.

const CAST_PATH := "user://test_cast.json"
const OLD_PATH := "user://test_old_profile.json"


func run() -> TestFramework:
	var t := TestFramework.new("cast")

	_test_defaults(t)
	_test_swap(t)
	_test_names(t)
	_test_builds(t)
	_test_round_trip(t)
	_test_schema_one(t)
	_test_broken_files(t)
	_test_adopting_an_old_profile(t)
	_test_from_settings_file(t)
	_test_swatch_lists(t)
	_test_two_bodies(t)
	_test_resting_head(t)

	_remove(CAST_PATH)
	_remove(OLD_PATH)
	return t


# ------------------------------------------------------------------ basics

func _test_defaults(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.eq(cast.main.display_name, "Victor",
		"the main character is Victor by default")
	t.eq(cast.side.display_name, "Chelsea", "and the side one is Chelsea")
	t.eq(cast.main_name(), "Victor", "so the one who walks is Victor")
	t.eq(cast.side_name(), "Chelsea", "and the one waiting is Chelsea")

	t.eq(cast.main.form, PixelFigure.Build.TROUSERS,
		"the main character starts on the trousers build")
	t.eq(cast.side.form, PixelFigure.Build.SKIRT, "and the side one on the skirt")

	t.eq(CastProfile.label_for(CastProfile.Role.MAIN), "Main character",
		"the roles have plain labels")
	t.eq(CastProfile.label_for(CastProfile.Role.SIDE), "Side character",
		"both of them")

	# Every default colour must be one of the offered swatches, or the
	# characters screen opens with nothing ringed.
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, cast.main.skin)),
		-1.0, "the main character's skin is one of the swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.TROUSERS,
		cast.main.dress)), -1.0, "and their trousers")
	t.gt(float(FigureProfile.index_of(FigureProfile.JUMPERS,
		cast.main.wrap)), -1.0, "and their jumper")
	t.gt(float(FigureProfile.index_of(FigureProfile.DRESSES,
		cast.side.dress)), -1.0, "and the side character's dress")


func _test_swap(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.ok(cast.main_figure() == cast.main, "the main character holds the map")
	t.ok(cast.side_figure() == cast.side, "the side one waits")
	t.eq(cast.other_than(CastProfile.Role.MAIN), CastProfile.Role.SIDE,
		"and the roles are opposite")

	var was_main := cast.main
	var was_side := cast.side
	cast.swap()

	t.ok(cast.main == was_side, "swapping makes the side character the main one")
	t.ok(cast.side == was_main, "and the main one the side")
	t.eq(cast.main_name(), "Chelsea", "so Chelsea walks now")
	t.eq(cast.side_name(), "Victor", "and Victor waits")
	# Names and looks travel with them: the point is to change which of these
	# two people you are, not to rename either of them.
	t.eq(cast.main.form, PixelFigure.Build.SKIRT,
		"and each keeps their own build")

	cast.swap()
	t.eq(cast.main_name(), "Victor", "swapping twice puts them back")

	# The main character is never also the one in the bed.
	t.ok(cast.main_figure() != cast.side_figure(),
		"the one who walks is never the one dying")


func _test_names(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	cast.main.display_name = "  Margaret  "
	t.eq(cast.name_for(CastProfile.Role.MAIN), "Margaret", "a name is trimmed")

	# An empty name in a line of dialogue reads as a bug, not as silence.
	cast.main.display_name = ""
	t.eq(cast.name_for(CastProfile.Role.MAIN), "Victor",
		"an empty name falls back rather than showing nothing")
	cast.side.display_name = "   "
	t.eq(cast.name_for(CastProfile.Role.SIDE), "Chelsea",
		"and so does a name of spaces")

	var long_name := "Bartholomew Fitzwilliam Montgomery the Third"
	var read := FigureProfile.from_figure_dict({"name": long_name})
	t.eq(read.display_name.length(), FigureProfile.NAME_LIMIT,
		"a very long name is cut to the limit (%d)" % read.display_name.length())


## The build is a look, not a role: either character can be either, and moving
## between them keeps the figure inside the swatches it is offered.
func _test_builds(t: TestFramework) -> void:
	var cast := CastProfile.create_default()
	var main := cast.main

	main.set_build(PixelFigure.Build.SKIRT)
	t.eq(main.form, PixelFigure.Build.SKIRT, "the main character can wear a skirt")
	t.eq(main.dress_label(), "Dress", "and the label follows")
	t.gt(float(FigureProfile.index_of(FigureProfile.DRESSES, main.dress)), -1.0,
		"with a colour that is one of the dress swatches")
	t.gt(float(FigureProfile.index_of(FigureProfile.WRAPS, main.wrap)), -1.0,
		"and a cardigan colour that is one of those")

	main.set_build(PixelFigure.Build.TROUSERS)
	t.eq(main.dress_label(), "Trousers", "and back again")
	t.gt(float(FigureProfile.index_of(FigureProfile.TROUSERS, main.dress)), -1.0,
		"with a trousers colour")
	t.eq(main.build_label(), "Trousers", "which is what the toggle says")

	main.set_build(PixelFigure.Build.TROUSERS)
	t.eq(main.form, PixelFigure.Build.TROUSERS,
		"setting the build it already has changes nothing")

	# Both on the same build is allowed, and the embrace still has a left and
	# a right.
	cast.side.set_build(PixelFigure.Build.TROUSERS)
	t.ok(cast.skirt_figure() != null, "with both in trousers there is still a left")
	t.ok(cast.trousers_figure() == cast.main,
		"and the main character takes the taller right-hand slot")


# -------------------------------------------------------------------- disk

func _test_round_trip(t: TestFramework) -> void:
	var cast := CastProfile.create_default()
	cast.main.display_name = "Tom"
	cast.main.skin = FigureProfile.SKINS[4]
	cast.main.dress = FigureProfile.TROUSERS[2]
	cast.main.wrap = FigureProfile.JUMPERS[1]
	cast.side.display_name = "Maggie"
	cast.side.hair = FigureProfile.HAIRS[0]
	cast.side.dress = FigureProfile.DRESSES[3]

	t.ok(cast.save(CAST_PATH), "the cast saves")
	var back := CastProfile.load_saved(CAST_PATH)

	t.eq(back.main.display_name, "Tom", "the main character's name comes back")
	t.eq(back.side.display_name, "Maggie", "and the side one's")
	# Hex on disk, 8-bit vertex colours in the mesh — see same_colour.
	t.ok(FigureProfile.same_colour(back.main.skin, cast.main.skin),
		"their skin comes back")
	t.ok(FigureProfile.same_colour(back.main.dress, cast.main.dress),
		"and their trousers")
	t.ok(FigureProfile.same_colour(back.main.wrap, cast.main.wrap),
		"and their jumper")
	t.ok(FigureProfile.same_colour(back.side.hair, cast.side.hair),
		"the side character's hair comes back")
	t.ok(FigureProfile.same_colour(back.side.dress, cast.side.dress),
		"and their dress")
	t.eq(back.main.form, PixelFigure.Build.TROUSERS, "builds come back too")
	t.eq(back.side.form, PixelFigure.Build.SKIRT, "both of them")

	# A build the author chose survives, which it must: it is a look now, and
	# an earlier version of this file pinned it by role on every load.
	cast.main.set_build(PixelFigure.Build.SKIRT)
	cast.save(CAST_PATH)
	t.eq(CastProfile.load_saved(CAST_PATH).main.form, PixelFigure.Build.SKIRT,
		"a main character in a skirt stays in a skirt")


## The file the first version of the cast wrote: a wife, a husband, and which
## of the two you walked as. That last field is exactly what main/side means,
## so it migrates without asking anybody anything.
func _test_schema_one(t: TestFramework) -> void:
	var as_wife := CastProfile.from_dict({
		"schema": 1,
		"player": "wife",
		"wife": {"name": "Maggie", "form": "woman", "hair": "ffffff"},
		"husband": {"name": "Tom", "form": "man"},
	})
	t.eq(as_wife.main_name(), "Maggie",
		"whoever the old file said you played becomes the main character")
	t.eq(as_wife.side_name(), "Tom", "and the other one the side character")
	t.eq(as_wife.main.form, PixelFigure.Build.SKIRT,
		"with the build they were drawn as")
	t.ok(FigureProfile.same_colour(as_wife.main.hair, Color.WHITE),
		"and the colours they were given")

	var as_husband := CastProfile.from_dict({
		"schema": 1,
		"player": "husband",
		"wife": {"name": "Maggie"},
		"husband": {"name": "Tom"},
	})
	t.eq(as_husband.main_name(), "Tom", "playing as the husband makes him main")
	t.eq(as_husband.side_name(), "Maggie", "and her the side character")
	t.eq(as_husband.main.form, PixelFigure.Build.TROUSERS,
		"still on the build he had")


func _test_broken_files(t: TestFramework) -> void:
	_remove(CAST_PATH)
	_remove(OLD_PATH)
	var missing := CastProfile.load_saved(CAST_PATH)
	t.eq(missing.main_name(), "Victor", "a missing file is the default cast")

	var f := FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string("{ not json at all")
	f.close()
	t.eq(CastProfile.load_saved(CAST_PATH).main_name(), "Victor",
		"so is a file that is not JSON")

	# A schema we do not know: refuse rather than guess, the same rule the
	# manifest follows.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 99, "main": {"name": "Nobody"}}')
	f.close()
	t.eq(CastProfile.load_saved(CAST_PATH).main_name(), "Victor",
		"a schema from the future is refused, not half-read")

	# Half a file: what is there is used, the rest defaults.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 2, "main": {"name": "Ann"}}')
	f.close()
	var partial := CastProfile.load_saved(CAST_PATH)
	t.eq(partial.main.display_name, "Ann", "a partial file keeps what it has")
	t.eq(partial.side.display_name, "Chelsea", "and defaults the rest")
	t.gt(float(FigureProfile.index_of(FigureProfile.SKINS, partial.main.skin)),
		-1.0, "with a whole person's colours")

	# Nulls where objects belong, which any hand edit can produce.
	f = FileAccess.open(CAST_PATH, FileAccess.WRITE)
	f.store_string('{"schema": 2, "main": null, "side": null}')
	f.close()
	var nulls := CastProfile.load_saved(CAST_PATH)
	t.eq(nulls.main_name(), "Victor", "nulls fall back rather than throwing")
	t.eq(nulls.side_name(), "Chelsea", "on both of them")

	_remove(CAST_PATH)


## Somebody who already made a figure in the build that only had one keeps it,
## as the main character.
func _test_adopting_an_old_profile(t: TestFramework) -> void:
	var old := FigureProfile.skirt_default()
	old.hair = FigureProfile.HAIRS[4]
	old.dress = FigureProfile.DRESSES[2]
	t.ok(old.save(OLD_PATH), "the old single-figure file saves")

	var cast := CastProfile._adopt_old_profile(OLD_PATH)
	t.ok(FigureProfile.same_colour(cast.main.hair, old.hair),
		"their old hair colour is adopted")
	t.ok(FigureProfile.same_colour(cast.main.dress, old.dress),
		"and their old dress")
	t.eq(cast.main.form, PixelFigure.Build.SKIRT, "and their build")
	t.eq(cast.side.display_name, "Chelsea",
		"while the side character starts from the default")

	_remove(OLD_PATH)
	t.eq(CastProfile._adopt_old_profile(OLD_PATH).main_name(), "Victor",
		"with no old file it is simply the default")


## The characters travel INSIDE a settings file, so the person it was made for
## meets the author's two and not whatever their own machine has saved.
func _test_from_settings_file(t: TestFramework) -> void:
	var album := AlbumSchema.Album.create_empty("For Maggie")
	t.ok(not album.has_cast(), "a fresh album names nobody")

	var mine := CastProfile.create_default()
	mine.main.display_name = "Author"
	mine.side.display_name = "Recipient"
	album.cast = mine.to_dict()
	t.ok(album.has_cast(), "and one with a cast says so")

	var read := CastProfile.for_album(album)
	t.eq(read.main_name(), "Author", "the file's own characters are used")
	t.eq(read.side_name(), "Recipient", "both of them")

	# Through the manifest and back, which is the path the real file takes.
	var again := AlbumSchema.Album.from_dict(album.to_dict())
	t.ok(again.has_cast(), "the cast survives the manifest")
	t.eq(CastProfile.for_album(again).main_name(), "Author",
		"with its names intact")

	# No cast in the file: this machine's own, whatever that is.
	var bare := AlbumSchema.Album.create_empty("Bare")
	t.ok(CastProfile.for_album(bare) != null,
		"a file with no cast falls back to this machine's")
	t.ok(CastProfile.for_album(null) != null, "and so does no file at all")


# ---------------------------------------------------------------- swatches

func _test_swatch_lists(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	t.ok(cast.side.dress_options() == FigureProfile.DRESSES,
		"the skirt build is offered dresses")
	t.ok(cast.main.dress_options() == FigureProfile.TROUSERS,
		"the trousers build is offered trousers")
	t.ok(cast.main.wrap_options() == FigureProfile.JUMPERS, "and jumpers")
	t.eq(cast.side.dress_label(), "Dress", "and the labels say which")
	t.eq(cast.main.wrap_label(), "Jumper", "including the top half")

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

	var skirt := PixelFigure.new()
	skirt.build(cast.side.to_palette(), cast.side.form)
	var trousers := PixelFigure.new()
	trousers.build(cast.main.to_palette(), cast.main.form)

	t.gt(float(skirt.total_triangles()), 0.0, "the skirt build is drawn")
	t.gt(float(trousers.total_triangles()), 0.0, "and the trousers build")
	t.ok(skirt.total_triangles() != trousers.total_triangles(),
		"and they are not the same drawing (%d vs %d triangles)"
			% [skirt.total_triangles(), trousers.total_triangles()])

	# The same height, because the hug at the ending is one drawn pose that
	# expects a pair whose proportions it already knows.
	t.eq(PixelFigure.SPRITE_HEIGHT, 56, "both are 56 pixels tall")

	# Trousers, which is the strongest read at this size: daylight up the
	# middle where the skirt is solid.
	var trousers_front: PackedByteArray = trousers._front_canvas_trousers()
	var skirt_front: PackedByteArray = skirt._front_canvas()
	var cx := int(PixelFigure.CENTRE)
	var gap_rows := 0
	for y in range(6, 20):
		if trousers_front[cx + PixelFigure.SPRITE_WIDTH * y] == PixelFigure.EMPTY:
			gap_rows += 1
	t.gt(float(gap_rows), 10.0,
		"the legs have daylight between them (%d rows)" % gap_rows)
	t.ok(skirt_front[cx + PixelFigure.SPRITE_WIDTH * 12] != PixelFigure.EMPTY,
		"where the skirt is solid")

	# No holes: _round_rect used to clear its top corners unconditionally, and
	# _extrude fills the whole depth, so a shape drawn over another punched a
	# window through the figure.
	for pair in [["skirt", skirt_front], ["trousers", trousers_front],
			["skirt back", skirt._back_canvas()],
			["trousers back", trousers._back_canvas_trousers()]]:
		t.eq(_holes(pair[1]), 0, "%s has no holes through it" % pair[0])

	# Every view exists for both, or a figure turns into nothing when the
	# camera crosses behind it.
	for pair in [["skirt", skirt], ["trousers", trousers]]:
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
	trousers.apply_palette(cast.side.to_palette())
	t.eq(trousers.form, PixelFigure.Build.TROUSERS,
		"changing the colours does not change the build")

	skirt.free()
	trousers.free()


## The head on the pillow is whoever is dying, and long hair spreads on it.
func _test_resting_head(t: TestFramework) -> void:
	var cast := CastProfile.create_default()

	var cropped := RestingHead.new()
	cropped.build(cast.main.to_palette(), cast.main.form)
	var long := RestingHead.new()
	long.build(cast.side.to_palette(), cast.side.form)

	t.gt(float(cropped.filled_pixels()), 0.0, "the cropped head is drawn")
	t.gt(float(long.filled_pixels()), float(cropped.filled_pixels()),
		"and the long-haired one takes more of the pillow (%d vs %d pixels)"
			% [long.filled_pixels(), cropped.filled_pixels()])
	t.gt(float(long.total_triangles()), 0.0, "and it becomes geometry")

	cropped.free()
	long.free()


# ------------------------------------------------------------------ helpers

## An EMPTY pixel with all four neighbours filled: a window through the figure.
static func _holes(canvas: PackedByteArray) -> int:
	var w := PixelFigure.SPRITE_WIDTH
	var h := PixelFigure.SPRITE_HEIGHT
	var n := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if canvas[x + w * y] != PixelFigure.EMPTY:
				continue
			if canvas[x - 1 + w * y] != PixelFigure.EMPTY \
					and canvas[x + 1 + w * y] != PixelFigure.EMPTY \
					and canvas[x + w * (y - 1)] != PixelFigure.EMPTY \
					and canvas[x + w * (y + 1)] != PixelFigure.EMPTY:
				n += 1
	return n


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

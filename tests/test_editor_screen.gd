extends RefCounted
## The editor's own screen, built for real in a live tree.
##
## test_editor covers EditorSession, which does no IO and no layout. This one
## covers the parts that ARE the screen, because that is where the bug was: the
## date fields existed, were wired up correctly and wrote the right values, and
## were still impossible to use, because the row they sat in was six hundred
## pixels wide inside a three-hundred-pixel column whose horizontal scrolling
## is switched off. A photograph that arrived without a date could not be given
## one.
##
## So the assertions here are about reach as much as behaviour: nothing in the
## detail column may need more width than the column will ever have.

## The narrowest the detail column gets: three columns and their margins inside
## a 1024-wide window. Anything in it that needs more than this is unreachable
## rather than merely cramped, and there is no horizontal scrollbar to save it.
const DETAIL_BUDGET := 320.0

var _holder: Node = null


func run() -> TestFramework:
	var t := TestFramework.new("editor screen")

	_holder = Node.new()
	_holder.name = "EditorScreenTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	var screen := _open()

	_test_tabs(t, screen)
	_test_characters(t, screen)
	_test_dial_starts_sensible(t, screen)
	_test_date_fields_fit(t, screen)
	_test_setting_a_missing_date(t, screen)
	_test_copying_a_year(t, screen)
	_test_filling_undated(t, screen)
	_test_date_note(t, screen)
	_test_no_hand_holding(t, screen)
	_test_defaults(t, screen)
	_test_answering_a_default(t, screen)
	_test_saving_is_never_blocked(t, screen)

	screen.get_parent().remove_child(screen)
	screen.free()
	_holder.get_parent().remove_child(_holder)
	_holder.free()
	_holder = null
	return t


# -------------------------------------------------------------- fixtures

func _jpeg(seed_value: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.04
	var img := noise.get_image(240, 180)
	img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.9)


func _open() -> Control:
	# _ready builds the whole screen, so adding it to a live tree is the whole
	# setup. (Outside a live tree _ready never fires — see test_host.)
	var screen: Control = load("res://src/editor/editor_screen.gd").new()
	_holder.add_child(screen)
	return screen


## Three photographs on the wall with no date on any of them. add_photo() now
## dates an undated photograph today, so this blanks the date afterwards and
## clears the flag with it — the state the author leaves behind by emptying the
## year box, and the state the older tests below were written against.
func _hang_three(screen: Control) -> void:
	while screen.session.slot_count() > 0:
		screen.session.remove_slot(0)
	for i in 3:
		screen.session.add_photo("IMG_%04d.jpg" % (i + 1), _jpeg(400 + i))
		var slot: EditorSession.Slot = screen.session.slot_at(i)
		slot.photo.truth.date.year = 0
		slot.photo.truth.date.month = 0
		slot.photo.truth.date.day = 0
		slot.date_defaulted = false
	screen._select(0)


# ------------------------------------------------------------------ the dial

func _test_dial_starts_sensible(t: TestFramework, screen: Control) -> void:
	var album: AlbumSchema.Album = screen.session.album
	t.eq(album.guess_year_min, AlbumSchema.DIAL_DEFAULT_MIN,
		"a new album's dial starts at 1980")
	t.eq(album.guess_year_max, AlbumSchema.current_year(),
		"and ends this year")
	t.eq(int(screen._guess_from.value), AlbumSchema.DIAL_DEFAULT_MIN,
		"and the box on screen says so")
	t.eq(int(screen._guess_to.value), AlbumSchema.current_year(),
		"both boxes")

	# Neither box will accept a year that has not happened, or one before
	# photography. The old pair went to 2100.
	t.eq(int(screen._guess_from.max_value), AlbumSchema.current_year(),
		"the dial cannot be set into the future")
	t.eq(int(screen._guess_to.max_value), AlbumSchema.current_year(),
		"at either end")
	t.eq(int(screen._year.max_value), AlbumSchema.current_year(),
		"nor can a photograph be dated into the future")

	t.ok(screen._dial_note.text.contains(str(AlbumSchema.DIAL_DEFAULT_MIN)),
		"and the note under them says what she will turn (%s)"
			% screen._dial_note.text)


# ------------------------------------------------------------- reachability

func _test_date_fields_fit(t: TestFramework, screen: Control) -> void:
	for field in [screen._year, screen._month, screen._day]:
		var box: SpinBox = field
		t.ok(box != null, "the date box exists")
		t.ok(box.is_inside_tree(), "and is in the screen")

	# The row they sit in, whatever it is, must fit the column.
	var row: Control = screen._year.get_parent()
	var needed := row.get_combined_minimum_size().x
	t.lt(needed, DETAIL_BUDGET,
		"the date row fits the detail column (%d px of %d)"
			% [needed, DETAIL_BUDGET])

	# And so must everything else in that column, or the same bug simply moves
	# to another field. This is the assertion that would have caught it.
	var worst := 0.0
	var worst_name := ""
	for child in screen._detail.get_children():
		var control := child as Control
		if control == null:
			continue
		var width := control.get_combined_minimum_size().x
		if width > worst:
			worst = width
			worst_name = control.get_class()
	t.lt(worst, DETAIL_BUDGET,
		"nothing in the detail column is wider than it (%s at %d px)"
			% [worst_name, worst])

	# The precision menu was moved out of the date row to make that fit; it is
	# still there and still offers all four.
	t.eq(screen._precision.item_count, 4, "all four precisions are offered")


# ------------------------------------------------------- setting a date

func _test_setting_a_missing_date(t: TestFramework, screen: Control) -> void:
	_hang_three(screen)
	var photo: AlbumSchema.Photo = screen.session.slot_at(0).photo
	t.ok(not photo.truth.date.is_set(),
		"this one arrived without a date, like a scan")

	# Exactly what typing in the boxes does.
	screen._year.value = 1974
	t.eq(photo.truth.date.year, 1974, "typing a year writes it to the photograph")
	screen._month.value = 7
	t.eq(photo.truth.date.month, 7, "and a month")
	screen._day.value = 18
	t.eq(photo.truth.date.day, 18, "and a day")
	t.ok(photo.truth.date.is_set(), "so it has a date now")
	t.eq(photo.truth.date.label(), "18 July 1974", "which reads correctly")

	# A year on its own is a complete answer: month and day may stay at zero.
	screen._month.value = 0
	screen._day.value = 0
	t.ok(photo.truth.date.is_set(), "a year on its own still counts as a date")
	t.eq(photo.truth.date.label(), "1974", "and reads as just the year")

	# And the wall list picks it up, which is where the author looks.
	t.ok(screen._wall_list.get_item_text(0).contains("1974"),
		"the wall shows the date it was given (%s)"
			% screen._wall_list.get_item_text(0))


func _test_copying_a_year(t: TestFramework, screen: Control) -> void:
	_hang_three(screen)
	screen._select(0)
	screen._year.value = 1961

	screen._select(1)
	t.ok(not screen.session.slot_at(1).photo.truth.date.is_set(),
		"the next one along has no date")
	screen._on_copy_year()
	t.eq(screen.session.slot_at(1).photo.truth.date.year, 1961,
		"and takes its year from the one above it")
	t.eq(int(screen._year.value), 1961, "which shows in the box")

	# Nothing above the first one to copy from, and it says so rather than
	# silently doing nothing.
	screen._select(0)
	screen._on_copy_year()
	t.ok(screen._status.text.contains("nothing above"),
		"the first photograph has nothing to copy from (%s)"
			% screen._status.text)


func _test_filling_undated(t: TestFramework, screen: Control) -> void:
	_hang_three(screen)
	screen._select(1)
	screen._year.value = 2003          # this one is dated; it must be left alone

	screen._select(0)
	screen._year.value = 1985
	screen._on_fill_years()

	t.eq(screen.session.slot_at(0).photo.truth.date.year, 1985,
		"the one in hand keeps its year")
	t.eq(screen.session.slot_at(1).photo.truth.date.year, 2003,
		"one that already had a date is not overwritten")
	t.eq(screen.session.slot_at(2).photo.truth.date.year, 1985,
		"and the undated one is filled in")
	t.ok(screen._status.text.contains("left alone"),
		"and it says what it did not touch (%s)" % screen._status.text)

	# Twice over changes nothing, and says nothing was left to do.
	screen._on_fill_years()
	t.ok(screen._status.text.contains("already"),
		"a second run reports there was nothing to do (%s)"
			% screen._status.text)

	# A zero year is a refusal, not a way to erase ten dates.
	screen._year.value = 0
	screen._on_fill_years()
	t.eq(screen.session.slot_at(2).photo.truth.date.year, 1985,
		"filling with no year in the box changes nothing")
	t.ok(screen._status.text.contains("year in the box"),
		"and asks for one (%s)" % screen._status.text)


func _test_date_note(t: TestFramework, screen: Control) -> void:
	_hang_three(screen)
	screen._select(0)
	t.ok(screen._date_note.text.contains("no date"),
		"an undated photograph says so (%s)" % screen._date_note.text)
	t.ok(screen._date_note.text.contains("year on"),
		"and says a year alone is enough")

	screen._year.value = 1992
	screen._read_photo_fields()
	t.ok(screen._date_note.text.contains("1992"),
		"a dated one shows its date (%s)" % screen._date_note.text)

	# A date out of Google's export gets a warning, because for a scanned
	# print it is the day it was scanned, not the day it was taken.
	screen.session.slot_at(0).from_sidecar = true
	screen._read_photo_fields()
	t.ok(screen._date_note.text.contains("scanned"),
		"a date from Google's export is flagged (%s)" % screen._date_note.text)

# ---------------------------------------------------------------- the tabs

## Three steps, in order, and each one leads to the next.
func _test_tabs(t: TestFramework, screen: Control) -> void:
	var tabs: TabContainer = screen._tabs
	t.ok(tabs != null, "the screen is a set of tabs")
	t.eq(tabs.get_tab_count(), 3, "three of them")
	t.ok(tabs.get_tab_title(0).contains("General"), "General is first (%s)"
		% tabs.get_tab_title(0))
	t.ok(tabs.get_tab_title(1).contains("Photograph"),
		"then the photographs (%s)" % tabs.get_tab_title(1))
	t.ok(tabs.get_tab_title(2).contains("Save"), "then saving (%s)"
		% tabs.get_tab_title(2))
	t.eq(tabs.current_tab, 0, "and it opens on the first")

	# The characters are on the General tab, not on a screen of their own.
	t.ok(screen._cast_editor != null, "the characters are edited here")
	t.ok(screen._cast_editor.is_inside_tree(), "and are on screen")
	var general := tabs.get_child(0)
	t.ok(general.is_ancestor_of(screen._cast_editor),
		"on the General tab specifically")
	t.ok(general.is_ancestor_of(screen._title),
		"along with the title")
	t.ok(general.is_ancestor_of(screen._guess_from),
		"and the calendar range")

	# The photographs are on the second, and nothing about them is on the
	# first: that was the whole complaint.
	var photos := tabs.get_child(1)
	t.ok(photos.is_ancestor_of(screen._detail),
		"the photograph's own fields are on the Photographs tab")
	t.ok(photos.is_ancestor_of(screen._wall_list), "with the wall")
	t.ok(photos.is_ancestor_of(screen._source_list), "and the source folder")
	t.ok(not general.is_ancestor_of(screen._detail),
		"and not on the General tab")

	# Saving is the third, with what is left to do beside the button.
	var review := tabs.get_child(2)
	t.ok(review.is_ancestor_of(screen._export_button),
		"the save button is on the Save tab")
	t.ok(review.is_ancestor_of(screen._problem_text),
		"next to what is still missing")


## The characters live in the file, so what the author sets here is what the
## person it is made for meets — not whatever their own machine has saved.
func _test_characters(t: TestFramework, screen: Control) -> void:
	var editor: CastEditor = screen._cast_editor
	t.ok(editor.cast != null, "there are two characters to edit")
	t.eq(editor.cast.main_name(), "Victor", "Victor is the main one by default")
	t.eq(editor.cast.side_name(), "Chelsea", "and Chelsea the side one")

	# Editing them writes them into the file being built.
	editor.cast.main.display_name = "Tom"
	editor._on_name_changed("Tom")
	t.ok(screen.session.album.has_cast(),
		"a change puts the characters into the settings")
	t.eq(CastProfile.for_album(screen.session.album).main_name(), "Tom",
		"with the name that was typed")

	# And the names the lines are written with follow them, rather than being
	# typed a second time in two fields of their own.
	t.eq(screen.session.album.curator_player_name, "Tom",
		"the main character names themselves")
	t.eq(screen.session.album.curator_voice_name, "Chelsea",
		"and so does the side one")

	# Swapping is the one control here that changes the game.
	editor._on_swap()
	t.eq(CastProfile.for_album(screen.session.album).main_name(), "Chelsea",
		"swapping puts the other one in front")
	t.eq(screen.session.album.curator_player_name, "Chelsea",
		"and the lines follow")
	editor._on_swap()
	t.eq(editor.cast.main_name(), "Tom", "and back again")

	# A build is a look: either character can have either.
	editor._select(CastProfile.Role.MAIN)
	editor._set_build(PixelFigure.Build.SKIRT)
	t.eq(editor.cast.main.form, PixelFigure.Build.SKIRT,
		"the main character can be put in a skirt")
	t.eq(CastProfile.for_album(screen.session.album).main.form,
		PixelFigure.Build.SKIRT, "and it is written to the file")
	editor._set_build(PixelFigure.Build.TROUSERS)


## Collect every Label under a node, so a test can ask what the screen says
## rather than what it is made of.
func _all_label_text(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		var label := child as Label
		if label != null:
			out += label.text + "\n"
		out += _all_label_text(child)
	return out


## The editor accumulated a sentence of explanation under almost every box —
## "Shown when the settings are loaded", "Zero means unknown", and so on. They
## made a long screen longer and said things the box itself already said. Gone,
## and pinned here so they do not grow back one at a time. The notes that stay
## are the ones that change with the file: the dial's actual span, and the line
## that appears only on a photograph that arrived with no date.
func _test_no_hand_holding(t: TestFramework, screen: Control) -> void:
	var said := _all_label_text(screen)
	for gone in ["Shown when the settings are loaded",
			"as she would say", "Zero means unknown", "Zero at either end",
			"In the order they are walked past", "Nothing is copied out of",
			"Nothing saves until", "never shown in the game"]:
		t.ok(not said.contains(gone), "no longer explains itself: '%s'" % gone)

	var general: Node = screen._tabs.get_child(0)
	var general_text := _all_label_text(general)
	t.ok(general_text.contains("Set guessing range"),
		"the dial is headed 'Set guessing range'")
	t.ok(not general_text.contains("Calendar range"),
		"and not 'Calendar range'")


# ------------------------------------------------------- dates and places

## A photograph with neither a date nor a location of its own arrives
## answerable: dated today, pinned at Seattle, and saying so in three places.
## The defaults exist so a folder of scans is playable immediately; the saying
## so exists because a default left in place is a wrong answer the player is
## scored against.
func _test_defaults(t: TestFramework, screen: Control) -> void:
	while screen.session.slot_count() > 0:
		screen.session.remove_slot(0)
	screen.session.add_photo("scan_01.jpg", _jpeg(900))
	screen._select(0)

	var slot: EditorSession.Slot = screen.session.slot_at(0)
	var truth := slot.photo.truth
	var today := Time.get_date_dict_from_system(true)

	t.ok(truth.date.is_set(), "an undated photograph is dated on the way in")
	t.eq(truth.date.year, int(today["year"]), "with this year")
	t.eq(truth.date.month, int(today["month"]), "this month")
	t.eq(truth.date.day, int(today["day"]), "and today")
	t.ok(slot.date_defaulted, "and it is flagged as a default, not a fact")

	t.ok(truth.has_location(), "and it is somewhere")
	t.close(truth.lat, EditorSession.DEFAULT_LAT, 0.001, "Seattle's latitude")
	t.close(truth.lon, EditorSession.DEFAULT_LON, 0.001, "and longitude")
	t.eq(truth.place_label, EditorSession.DEFAULT_PLACE_LABEL, "named as such")
	t.eq(truth.region, "Washington", "with the state on it")
	t.ok(slot.place_defaulted, "flagged as a default too")

	# Said in the detail panel...
	t.ok(screen._date_note.text.contains("today"),
		"the date note says the date is today's (%s)" % screen._date_note.text)
	t.ok(screen._place_note.text.contains(EditorSession.DEFAULT_PLACE_LABEL),
		"the place note names the default (%s)" % screen._place_note.text)
	# ...on the wall, which is the list the author scans before saving...
	t.ok(screen._wall_list.get_item_text(0).contains("(default)"),
		"the wall row marks it (%s)" % screen._wall_list.get_item_text(0))
	# ...and on the Save tab, which is the last thing they read.
	t.ok(screen._defaults_line().contains("default"),
		"and the Save tab names it (%s)" % screen._defaults_line())
	t.ok(screen._problem_text.text.contains("default"),
		"in the list the tab actually shows")


## Answering the question takes the flag off — and only the one answered.
func _test_answering_a_default(t: TestFramework, screen: Control) -> void:
	var slot: EditorSession.Slot = screen.session.slot_at(0)

	screen._year.value = 1974
	t.ok(not slot.date_defaulted, "typing a year answers the date")
	t.ok(slot.place_defaulted, "and says nothing about the place")
	t.ok(not screen._date_note.text.contains("today"),
		"the note stops talking about today (%s)" % screen._date_note.text)

	screen._on_map_pin(48.8566, 2.3522)
	t.ok(not slot.place_defaulted, "moving the pin answers the place")
	t.eq(screen._place_note.text, "", "and the note has nothing left to say")
	t.eq(screen._defaults_line(), "",
		"with both answered, the Save tab drops the line")

	# The year buttons treat a default as the blank it really is, and leave a
	# year alone rather than dressing it as a day in September.
	screen.session.add_photo("scan_02.jpg", _jpeg(901))
	var second: EditorSession.Slot = screen.session.slot_at(1)
	t.ok(second.date_defaulted, "the new one starts on the default")
	screen._select(1)
	screen._on_copy_year()
	t.eq(second.photo.truth.date.year, 1974, "the year comes down from above")
	t.eq(second.photo.truth.date.month, 0, "the month does not")
	t.eq(second.photo.truth.date.day, 0, "nor the day")
	t.eq(second.photo.truth.date_precision, AlbumSchema.DatePrecision.YEAR,
		"and it is scored to the year, which is all that is known")
	t.ok(not second.date_defaulted, "and it is no longer a default")

	# A write that goes nowhere near the screen also takes the flag off, so a
	# photograph the author answered is never reported as defaulted. The flag
	# by itself only knew about edits made through these controls.
	screen.session.add_photo("scan_03.jpg", _jpeg(902))
	var third: EditorSession.Slot = screen.session.slot_at(2)
	t.ok(third.date_is_default(), "the third one starts on the default date")
	t.ok(third.place_is_default(), "and the default place")
	third.photo.truth.date.year = 1999
	third.photo.truth.lat = 51.5
	third.photo.truth.lon = -0.12
	t.ok(not third.date_is_default(),
		"writing the date directly answers it too")
	t.ok(not third.place_is_default(), "and the coordinates")

	# What is left is the one the year button answered but nobody has pinned:
	# the second photograph, still sitting in Seattle. Half an answer is still
	# reported, because half an answer is still scored.
	var left: PackedInt32Array = screen.session.defaulted_positions()
	t.eq(left.size(), 1, "one photograph is still on a default")
	t.eq(left[0], 2, "the second, whose place nobody has moved")


## Saving is the author's call. The Save tab says what is unfinished; it does
## not hold the file hostage. Only an empty wall has nothing to write.
func _test_saving_is_never_blocked(t: TestFramework, screen: Control) -> void:
	t.ok(not screen.session.can_export(),
		"two photographs is not a finished album")
	screen._refresh()
	t.ok(not screen._export_button.disabled,
		"but the Save button is live anyway")
	t.ok(screen._problem_text.text.contains("either way"),
		"and the tab says so (%s)" % screen._problem_text.text.left(80))

	while screen.session.slot_count() > 0:
		screen.session.remove_slot(0)
	screen._select(-1)
	screen._refresh()
	t.ok(screen._export_button.disabled, "an empty wall has nothing to save")
	screen._on_export()
	t.ok(screen._status.text.contains("Nothing to save"),
		"and says that rather than nothing (%s)" % screen._status.text)

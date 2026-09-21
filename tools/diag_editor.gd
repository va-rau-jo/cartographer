extends Node
## Photographs the settings editor with a part-filled file in it — every tab,
## because each one is now a screen of its own.
##
##   xvfb-run -a godot --path . --script tools/run_diag_editor.gd
##
## The editor is the densest screen in the game — three columns and about forty
## controls — and a layout that reads fine as a node tree can still come out
## with the detail panel two pixels wide. This puts real photographs in it and
## takes a picture.

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(1600, 900)

const PLACES := [
	[43.7696, 11.2558, "Florence, Italy"],
	[54.4858, -0.6206, "Whitby, England"],
	[64.1466, -21.9426, "Reykjavik, Iceland"],
	[35.0116, 135.7681, "Kyoto, Japan"],
]


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var window := get_window()
	window.size = SHOT_SIZE

	# The SCENE, not the script: the .tscn carries the full-rect anchors, and
	# instantiating the script alone gives a Control with no size — which is
	# how this tool first "found" a squashed three-column layout that was
	# nothing of the kind.
	var scene := load("res://scenes/editor/editor.tscn") as PackedScene
	if scene == null:
		print("scenes/editor/editor.tscn did not load")
		get_tree().quit(3)
		return

	var screen: Control = scene.instantiate()
	window.add_child(screen)
	await get_tree().process_frame

	# Four photographs, the way the editor would have them after four adds,
	# plus a folder listing so the left column has something in it.
	var offered: Array = []
	for i in 12:
		var file := Platform.PickedFile.new()
		file.name = "IMG_%04d.jpg" % (i + 1)
		file.size = 2_100_000 + i * 13_000
		offered.append(file)
	screen.session.set_sources(offered)

	var noise := FastNoiseLite.new()
	for i in PLACES.size():
		noise.seed = 400 + i
		noise.frequency = 0.03
		var img := noise.get_image(320, 240)
		img.convert(Image.FORMAT_RGB8)
		var error: String = screen.session.add_photo(
			"IMG_%04d.jpg" % (i + 1), img.save_jpg_to_buffer(0.9))
		if not error.is_empty():
			print("add failed: %s" % error)
			continue
		var photo: AlbumSchema.Photo = screen.session.slot_at(i).photo
		photo.truth.lat = PLACES[i][0]
		photo.truth.lon = PLACES[i][1]
		photo.truth.place_label = PLACES[i][2]
		photo.truth.date.year = 1961 + i * 6
		photo.truth.date.month = 6
		photo.content.title = "Photograph %d" % (i + 1)
		photo.content.description = "What happened that week, in her words."
		photo.curator.hints = PackedStringArray([
			"Warm stone, and you complained all week.",
			"Somewhere in Europe, that summer.",
			"It was %s." % PLACES[i][2],
		])

	screen.session.album.title = "For Maggie"
	screen.session.album.closing_line = "There you are."
	screen._read_album_fields()
	screen._select(1)

	# 1. General, which is where an author starts: the title, the note, the two
	# characters and the calendar range.
	screen._tabs.current_tab = 0
	for _i in 6:
		await get_tree().process_frame
	_save(window, "40_editor_general")

	# The characters are half of that tab, so scroll down to them.
	var general_scroll := screen._tabs.get_child(0) as ScrollContainer
	if general_scroll != null:
		general_scroll.scroll_vertical = int(
			screen._cast_editor.position.y - 40.0)
		for _i in 4:
			await get_tree().process_frame
		_save(window, "41_editor_characters")

	# 2. The photographs.
	screen._tabs.current_tab = 1
	for _i in 4:
		await get_tree().process_frame
	_save(window, "42_editor_photos")

	# 3. Saving, and what is left to do before it.
	screen._tabs.current_tab = 2
	for _i in 4:
		await get_tree().process_frame
	_save(window, "44_editor_save")

	screen._tabs.current_tab = 1
	for _i in 2:
		await get_tree().process_frame

	# Scrolled down to the date fields, which is where the interesting bug was:
	# they were wired correctly and unreachable, because the row they sat in was
	# wider than the column and there is no horizontal scrollbar. A picture is
	# the only way to be sure they are on screen.
	var scroll := screen._detail.get_parent() as ScrollContainer
	if scroll != null:
		# Put the "When" block at the top of the visible area.
		scroll.scroll_vertical = int(maxf(0.0,
			screen._year.get_parent().position.y - 120.0))
		for _i in 4:
			await get_tree().process_frame
		_save(window, "43_editor_dates")

	# A photograph exactly as it arrives out of a folder of scans: no date, no
	# location, so both are sitting on the defaults this editor filled in. The
	# two notes and the wall row all have to say so, because a default left
	# alone is what the player gets scored against.
	screen.session.add_photo("scan_05.jpg", _plain_jpeg(905))
	screen._select(screen.session.slot_count() - 1)
	if scroll != null:
		scroll.scroll_vertical = int(maxf(0.0,
			screen._lat.get_parent().position.y - 120.0))
	for _i in 4:
		await get_tree().process_frame
	_save(window, "46_editor_defaults")
	print("")
	print("place note     %s" % screen._place_note.text)
	print("default date   %s" % screen._date_note.text)
	print("wall row       %s" % screen._wall_list.get_item_text(
		screen.session.slot_count() - 1))
	print("defaults line  %s" % screen._defaults_line())
	print("save button    %s" % ("live" if not screen._export_button.disabled
		else "blocked"))
	screen.session.remove_slot(screen.session.slot_count() - 1)
	screen._select(1)
	for _i in 2:
		await get_tree().process_frame

	# And an undated photograph, which is what a scan arrives as: the note
	# above the boxes has to say so.
	screen.session.slot_at(2).photo.truth.date.year = 0
	screen.session.slot_at(2).photo.truth.date.month = 0
	screen._select(2)
	if scroll != null:
		scroll.scroll_vertical = int(maxf(0.0,
			screen._year.get_parent().position.y - 120.0))
	for _i in 4:
		await get_tree().process_frame
	_save(window, "45_editor_undated")
	print("")
	print("tabs           %d" % screen._tabs.get_tab_count())
	print("main / side    %s / %s" % [screen._cast_editor.cast.main_name(),
		screen._cast_editor.cast.side_name()])
	print("summary        %s" % screen._summary.text)
	print("date note      %s" % screen._date_note.text)
	print("date row min   %d px" % screen._year.get_parent()
		.get_combined_minimum_size().x)
	print("detail width   %d px" % screen._detail.size.x)
	print("slots          %d of %d" % [screen.session.slot_count(),
		EditorSession.MAX_PHOTOS])
	print("sources        %d" % screen.session.source_count())
	print("assets held    %d KB" % (screen.session.total_asset_bytes() / 1024))
	print("exportable     %s" % ("yes" if screen.session.can_export() else "no"))
	print("problems       %d" % screen.session.problems(true).size())
	get_tree().quit(0)


## A plain noise JPEG, for a photograph that is only there to arrive.
func _plain_jpeg(seed_value: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.03
	var img := noise.get_image(320, 240)
	img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.9)


func _save(window: Window, name: String) -> void:
	var img := window.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  %-16s %s" % [name, "ok" if img.save_png(path) == OK else "FAILED"])

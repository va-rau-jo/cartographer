extends RefCounted
## The album preview screen — the page you land on after loading an album —
## and the thumbnails the editor now shows.
##
## The assertion that matters most here is a design one: this screen is the
## first thing the person the gift is FOR will see, so it must not show her the
## ten photographs. It shows the tier-0 fog she will meet in the hall, and only
## reveals them when somebody ticks the box that says it gives the game away.

const PLACES := [
	[43.7696, 11.2558, "Florence, Italy"],
	[54.4858, -0.6206, "Whitby, England"],
	[64.1466, -21.9426, "Reykjavik, Iceland"],
]

var _holder: Node = null


func run() -> TestFramework:
	var t := TestFramework.new("preview")

	_holder = Node.new()
	_holder.name = "PreviewTestHolder"
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)

	var bytes := _album_bytes()
	_test_edit_handoff(t)
	_test_thumbnails(t, bytes)
	_test_preview_screen(t, bytes)
	_test_empty_preview(t)

	AlbumService.unload()
	if _holder != null and is_instance_valid(_holder):
		_holder.get_parent().remove_child(_holder)
		_holder.free()
		_holder = null
	return t


# -------------------------------------------------------------- fixtures

func _jpeg(seed_value: int) -> PackedByteArray:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.05
	var img := noise.get_image(320, 240)
	img.convert(Image.FORMAT_RGB8)
	return img.save_jpg_to_buffer(0.9)


## A real three-photograph album, packed the way the editor packs one.
func _album_bytes() -> PackedByteArray:
	var session := EditorSession.new()
	session.album.title = "For Maggie"
	session.album.author_note = "Sixty years, ten of them."
	session.album.curator_voice_name = "Tom"

	for i in PLACES.size():
		session.add_photo("IMG_%04d.jpg" % (i + 1), _jpeg(600 + i))
		var photo := session.slot_at(i).photo
		photo.truth.lat = PLACES[i][0]
		photo.truth.lon = PLACES[i][1]
		photo.truth.place_label = PLACES[i][2]
		photo.truth.date.year = 1961 + i * 10
		photo.content.private_note = "PRIVATE"

	return session.export_bytes()


# -------------------------------------------------------------- the handoff

## "Edit this album" survives a scene change through one flag, and is consumed
## so that opening the editor from the menu afterwards starts empty.
func _test_edit_handoff(t: TestFramework) -> void:
	GameState.edit_loaded_album = false
	t.ok(not GameState.take_edit_request(), "nothing is requested by default")

	GameState.edit_loaded_album = true
	t.ok(GameState.take_edit_request(), "a request is picked up")
	t.ok(not GameState.take_edit_request(),
		"and only once — the editor does not inherit it next time")
	t.ok(not GameState.edit_loaded_album, "the flag is cleared")


# ------------------------------------------------------------- thumbnails

func _test_thumbnails(t: TestFramework, bytes: PackedByteArray) -> void:
	# From the editor's own slots, which is what its lists and preview use.
	var session := EditorSession.new()
	session.add_photo("IMG_0001.jpg", _jpeg(700))
	var slot := session.slot_at(0)

	var thumb := slot.thumbnail()
	t.ok(thumb != null, "a slot can produce its thumbnail")
	if thumb != null:
		t.gt(float(thumb.get_width()), 16.0,
			"which is a real image (%d px)" % thumb.get_width())
		t.lt(float(thumb.get_width()), 512.0, "and a small one")
		t.ok(slot.thumbnail() == thumb, "decoded once and kept")

	# And from a loaded album, which is what the preview screen uses.
	t.ok(AlbumService.load_album_bytes(bytes), "the fixture album loads")
	var hung: Array = AlbumService.album().hung_photos()
	var from_album: ImageTexture = AlbumService.thumb_texture(hung[0].id)
	t.ok(from_album != null, "a loaded album can produce a thumbnail")
	t.ok(AlbumService.thumb_texture(hung[0].id) == from_album,
		"and caches it too")
	t.ok(AlbumService.thumb_texture("no_such_photo") == null,
		"a photograph that is not there has no thumbnail")

	# A tier that would not decode must never be served by a SHARPER one.
	#
	# The decode used to append only its successes, and tier_texture indexes
	# the result BY TIER — so one corrupt tier 1 shifted the whole ladder down
	# and handed her tier 2's clearer image at tier 1's price. Now the slot
	# holds a null and the lookup walks DOWN to the nearest blurrier tier that
	# did decode.
	var ladder: Array = AlbumService._tier_textures[hung[0].id]
	t.eq(ladder.size(), AlbumSchema.BLUR_TIER_COUNT,
		"there is one slot per tier, decoded or not")
	var tier0 := AlbumService.tier_texture(hung[0].id, 0)
	var tier2 := AlbumService.tier_texture(hung[0].id, 2)
	ladder[1] = null
	t.ok(AlbumService.tier_texture(hung[0].id, 1) == tier0,
		"a tier that failed to decode falls back to the blurrier one")
	t.ok(AlbumService.tier_texture(hung[0].id, 1) != tier2,
		"and never to a sharper one")
	t.ok(AlbumService.tier_texture(hung[0].id, 2) == tier2,
		"while the tiers that did decode are unaffected")
	# Put it back, because the screen below draws from this.
	AlbumService.unload()
	AlbumService.load_album_bytes(bytes)
	hung = AlbumService.album().hung_photos()
	from_album = AlbumService.thumb_texture(hung[0].id)

	# The fog is a different, much smaller image than the thumbnail — that
	# difference is the whole point of the preview screen's default.
	var fog := AlbumService.tier_texture(hung[0].id, 0)
	t.ok(fog != null, "tier 0 exists")
	if fog != null and from_album != null:
		t.lt(float(fog.get_width()), float(from_album.get_width()),
			"and the fog is smaller than the thumbnail (%d vs %d)"
				% [fog.get_width(), from_album.get_width()])


# ---------------------------------------------------------- the screen

func _test_preview_screen(t: TestFramework, bytes: PackedByteArray) -> void:
	AlbumService.load_album_bytes(bytes)

	var screen: Control = load("res://src/ui/album_preview_screen.gd").new()
	_holder.add_child(screen)

	t.ok(screen.album != null, "the screen finds the loaded album")
	t.eq(screen._grid.get_child_count(), PLACES.size(),
		"one tile per photograph")
	t.eq(screen._tiles.size(), PLACES.size(), "and one image per tile")
	t.ok(not screen._play.disabled, "and Begin is available")

	t.ok(screen._title_label.text.contains("For Maggie"),
		"the album's title is shown (got %s)" % screen._title_label.text)
	t.ok(screen._note_label.text.contains("Sixty years"),
		"and the author's note")

	var facts: String = screen._facts_label.text
	t.ok(facts.contains("3 photograph"), "the count is shown (%s)" % facts)
	t.ok(facts.contains("1961"), "and the years they span")
	t.ok(facts.contains("Tom"), "and who he is")

	# THE IMPORTANT ONE: fog by default, not the photographs.
	var hung := AlbumService.album().hung_photos()
	var fog := AlbumService.tier_texture(hung[0].id, 0)
	var thumb := AlbumService.thumb_texture(hung[0].id)
	t.ok(screen._tiles[0].texture == fog,
		"the tiles show the fog she will meet, not the photograph")
	t.ok(screen._tiles[0].texture != thumb, "which is not the thumbnail")
	t.ok(not screen._revealed, "and nothing is revealed to begin with")

	# Nor do the captions give the answers away.
	for caption in screen._captions:
		var text: String = caption.text
		for place in PLACES:
			t.ok(not text.contains(String(place[2])),
				"a caption does not name a place (%s)" % text)

	# Ticking the box reveals both, and says so.
	screen._on_reveal_toggled(true)
	t.ok(screen._tiles[0].texture == thumb,
		"revealing shows the photographs")
	t.ok(screen._captions[0].text.contains(String(PLACES[0][2])),
		"and where they were (%s)" % screen._captions[0].text)
	t.ok(screen._captions[0].text.contains("1961"), "and when")
	t.ok(not screen._status.text.is_empty(),
		"with a warning that the answers are on screen")

	# And untickng puts it all back.
	screen._on_reveal_toggled(false)
	t.ok(screen._tiles[0].texture == fog, "unticking hides them again")
	t.ok(not screen._captions[0].text.contains(String(PLACES[0][2])),
		"including the places")

	# The author's private notes must not appear anywhere on this screen,
	# revealed or not.
	screen._on_reveal_toggled(true)
	t.ok(not _all_text(screen).contains("PRIVATE"),
		"private notes stay out of the preview")

	screen.get_parent().remove_child(screen)
	screen.free()


## With nothing loaded the screen still has to make sense.
func _test_empty_preview(t: TestFramework) -> void:
	AlbumService.unload()

	var screen: Control = load("res://src/ui/album_preview_screen.gd").new()
	_holder.add_child(screen)

	t.ok(screen.album == null, "no album, and it knows")
	t.eq(screen._grid.get_child_count(), 0, "no tiles")
	t.ok(screen._play.disabled, "and Begin is refused")
	t.ok(screen._title_label.text.contains("No album"),
		"with a line saying so (got %s)" % screen._title_label.text)

	screen.get_parent().remove_child(screen)
	screen.free()


func _all_text(node: Node) -> String:
	var out: PackedStringArray = PackedStringArray()
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		out.append(_all_text(child))
	return " ".join(out)

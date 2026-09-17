extends SceneTree
## Generates a valid, playable ten-photo .ccalbum from generated imagery, so
## every later milestone has real data to work against before the editor
## exists.
##
##   godot --headless --path . --script tools/make_test_album.gd
##
## Writes to user://test_album.ccalbum and prints the absolute path. Ten real
## places with real coordinates, so distance scoring produces believable
## numbers rather than everything being a few metres apart.

const OUT_PATH := "user://test_album.ccalbum"

const PLACES := [
	{"label": "Florence, Italy", "cc": "IT", "lat": 43.7696, "lon": 11.2558,
	 "year": 1978, "month": 6, "precision": "month",
	 "title": "The bridge with the shops on it",
	 "desc": "Our honeymoon. You complained about the heat for a solid week and bought a straw hat I hated.",
	 "hints": ["Warm stone everywhere, and you would not stop complaining about the heat.",
			   "Somewhere in Italy, that first summer.",
			   "The bridge with the little shops built right onto it, love."],
	 "reveal": "June of '78. You wore the green dress and we ate too much."},

	{"label": "Whitby, England", "cc": "GB", "lat": 54.4858, "lon": -0.6206,
	 "year": 1965, "month": 8, "precision": "month",
	 "title": "Cold water, colder wind",
	 "desc": "The seaside trip with your sister. It rained all afternoon and we ate chips under the awning.",
	 "hints": ["Wind off the water, and chips wrapped in paper.",
			   "The Yorkshire coast, the year after we married.",
			   "Whitby. Your sister came with us."],
	 "reveal": "August, 1965. The rain came in sideways and you laughed at me."},

	{"label": "Reykjavik, Iceland", "cc": "IS", "lat": 64.1466, "lon": -21.9426,
	 "year": 1994, "month": 3, "precision": "month",
	 "title": "The night the sky moved",
	 "desc": "Your sixtieth. We stood outside in the cold for two hours waiting for the lights.",
	 "hints": ["So cold my fingers went white, and the sky would not hold still.",
			   "The far north, on your sixtieth.",
			   "Reykjavik, and the lights over the water."],
	 "reveal": "March of '94. Two hours in the cold and you said it was worth every minute."},

	{"label": "Kyoto, Japan", "cc": "JP", "lat": 35.0116, "lon": 135.7681,
	 "year": 2001, "month": 4, "precision": "month",
	 "title": "Everything was pink",
	 "desc": "The trip we saved four years for. You cried at the temple and would not say why.",
	 "hints": ["Petals in the gutters, and a quiet we were not used to.",
			   "The far side of the world, the spring after we retired.",
			   "Kyoto, in blossom season."],
	 "reveal": "April, 2001. You cried at the temple and never did tell me why."},

	{"label": "Lisbon, Portugal", "cc": "PT", "lat": 38.7223, "lon": -9.1393,
	 "year": 1987, "month": 9, "precision": "month",
	 "title": "The yellow tram",
	 "desc": "We got hopelessly lost and you insisted it was on purpose.",
	 "hints": ["Tiles on every wall, and a hill in every direction.",
			   "The Atlantic coast of Europe, in the late eighties.",
			   "Lisbon, and that yellow tram we rode four times."],
	 "reveal": "September of '87. Lost for three hours and you called it exploring."},

	{"label": "Banff, Canada", "cc": "CA", "lat": 51.1784, "lon": -115.5708,
	 "year": 1972, "month": 7, "precision": "month",
	 "title": "Water the wrong colour",
	 "desc": "The drive with the borrowed car. We slept in it one night because the lodge was full.",
	 "hints": ["Water too blue to be real, and mountains on all sides.",
			   "The Canadian Rockies, early seventies.",
			   "Banff. We slept in the borrowed car."],
	 "reveal": "July, 1972. You said the lake had been painted."},

	{"label": "Marrakesh, Morocco", "cc": "MA", "lat": 31.6295, "lon": -7.9811,
	 "year": 1983, "month": 11, "precision": "month",
	 "title": "Too much at once",
	 "desc": "The market overwhelmed you and we sat on a step for twenty minutes until it passed.",
	 "hints": ["Noise and spice and far too much happening at once.",
			   "North Africa, in the early eighties.",
			   "Marrakesh, and that square at dusk."],
	 "reveal": "November of '83. We sat on a step until the noise stopped being frightening."},

	{"label": "Edinburgh, Scotland", "cc": "GB", "lat": 55.9533, "lon": -3.1883,
	 "year": 1961, "month": 0, "precision": "year",
	 "title": "Before all of it",
	 "desc": "The first photograph anyone took of us together. Neither of us knew yet.",
	 "hints": ["Grey stone, and both of us far too young.",
			   "Scotland, at the very beginning.",
			   "Edinburgh. The first picture of the two of us."],
	 "reveal": "1961. Neither of us had any idea."},

	{"label": "Santorini, Greece", "cc": "GR", "lat": 36.3932, "lon": 25.4615,
	 "year": 1999, "month": 6, "precision": "month",
	 "title": "White and blue and nothing else",
	 "desc": "The anniversary trip. You read four books in five days and I let you.",
	 "hints": ["White walls, and a blue that hurt to look at.",
			   "The Greek islands, at the end of the nineties.",
			   "Santorini, for our anniversary."],
	 "reveal": "June, 1999. Four books in five days and not one word of apology."},

	{"label": "Ambleside, England", "cc": "GB", "lat": 54.4300, "lon": -2.9615,
	 "year": 2019, "month": 5, "precision": "month",
	 "title": "The last long walk",
	 "desc": "We did not know it would be the last one. It was a very good day.",
	 "hints": ["Wet grass, and you walking slower than you used to.",
			   "The Lake District, only a few years ago.",
			   "Ambleside. Our last long walk."],
	 "reveal": "May of 2019. We did not know. It was a very good day."},
]


func _initialize() -> void:
	var album := AlbumSchema.Album.create_empty("Margaret & Tom")
	album.author_note = "A test album, generated by tools/make_test_album.gd."
	album.curator_voice_name = "Tom"
	album.curator_player_name = "Maggie"
	album.curator_style = "warm, a little wry, drifts mid-sentence when tired"
	album.cover_photo_id = "p_001"

	var assets := {}
	var order: PackedStringArray = PackedStringArray()
	var t0 := Time.get_ticks_msec()

	for i in PLACES.size():
		var place: Dictionary = PLACES[i]
		var pid := "p_%03d" % (i + 1)

		# Alternate portrait and landscape so the frame's variable mat (plan
		# §4.3) is exercised from the very first test data.
		var landscape := i % 3 != 2
		var w := 2400 if landscape else 1600
		var h := 1600 if landscape else 2400

		var source := _placeholder(w, h, i).save_png_to_buffer()
		var proc := ImagePipeline.process(source, "%s.png" % pid, pid)
		if not proc.ok:
			print("FAILED on %s: %s" % [pid, proc.error])
			quit(1)
			return

		var photo := AlbumSchema.Photo.new()
		photo.id = pid
		photo.aspect = proc.aspect
		var paths := AlbumSchema.Photo.default_paths(pid)
		photo.full_path = paths["full"]
		photo.blur_paths = PackedStringArray(paths["blurTiers"])
		photo.thumb_path = paths["thumb"]

		photo.truth.lat = place["lat"]
		photo.truth.lon = place["lon"]
		photo.truth.place_label = place["label"]
		photo.truth.country_code = place["cc"]
		photo.truth.location_precision_km = 8.0
		photo.truth.date.year = place["year"]
		photo.truth.date.month = place["month"]
		photo.truth.date_precision = AlbumSchema.precision_from_string(place["precision"])

		photo.content.title = place["title"]
		photo.content.description = place["desc"]
		photo.content.people = PackedStringArray(["Margaret", "Tom"])

		photo.curator.hints = PackedStringArray(place["hints"])
		photo.curator.reveal_monologue = place["reveal"]
		photo.curator.idle_barks = PackedStringArray(["You always liked this one."])
		photo.curator.bake_model = "hand-written"
		photo.curator.approved_by_author = true

		album.photos.append(photo)
		order.append(pid)
		assets.merge(proc.assets)

		print("  %s  %-22s %4dx%-4d  %d assets"
			% [pid, place["label"], w, h, proc.assets.size()])

	album.hang_order = order

	# Export validation is the strict pass: exactly ten photos, every line
	# approved. If this album cannot pass it, neither could a real one.
	var problems := AlbumValidator.validate(album, true)
	if AlbumValidator.has_errors(problems):
		print("\nvalidation failed:\n%s" % AlbumValidator.format_all(problems))
		quit(1)
		return

	var bytes := AlbumIO.pack(album, assets)
	if bytes.is_empty():
		print("packing failed")
		quit(1)
		return

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		print("cannot write %s" % OUT_PATH)
		quit(1)
		return
	f.store_buffer(bytes)
	f.close()

	# Prove it loads back before claiming success.
	var reloaded := AlbumIO.load_from_bytes(bytes)
	var round_trips := reloaded.is_ok()
	var photo_count := reloaded.album.hung_photos().size() if reloaded.album != null else 0
	reloaded.close()

	print("")
	print("wrote %s" % ProjectSettings.globalize_path(OUT_PATH))
	print("  %d photos, %.2f MB, %d ms"
		% [album.photos.size(), bytes.size() / 1048576.0, Time.get_ticks_msec() - t0])
	print("  reloads cleanly: %s (%d photos)" % [str(round_trips), photo_count])
	print("")

	quit(0 if round_trips else 1)


## Stand-in imagery until real photographs are loaded through the editor.
## Fractal noise, tinted per photo so the ten are visually distinguishable, and
## generated natively because a GDScript pixel loop at this size takes minutes.
func _placeholder(w: int, h: int, index: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = 1000 + index * 37
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 6
	noise.frequency = 0.0035

	var img := noise.get_image(w, h)
	img.convert(Image.FORMAT_RGBA8)

	# A wash of colour so the ten are visually distinguishable. The overlay
	# must carry alpha: blend_rect with an opaque RGB overlay replaces the
	# image outright, which flattens the noise to a solid colour and makes the
	# resulting album absurdly small.
	var tint := Color.from_hsv(fmod(float(index) * 0.13, 1.0), 0.5, 1.0, 0.35)
	var overlay := Image.create(w, h, false, Image.FORMAT_RGBA8)
	overlay.fill(tint)
	img.blend_rect(overlay, Rect2i(0, 0, w, h), Vector2i.ZERO)

	img.convert(Image.FORMAT_RGB8)
	return img

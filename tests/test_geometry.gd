extends RefCounted
## Hallway geometry and voxel meshing. Both are pure builders that never touch
## the scene tree, which is what makes them testable headless.

static func run() -> TestFramework:
	var t := TestFramework.new("geometry")

	_test_hallway(t)
	_test_voxel_grid(t)
	_test_greedy_meshing(t)
	_test_figure_proportions(t)
	_test_frame_mat(t)

	return t


# -------------------------------------------------------------- hallway

static func _test_hallway(t: TestFramework) -> void:
	var h := HallwayBuilder.build()

	t.ok(h.mesh != null, "hallway produces a mesh")
	t.eq(h.mesh.get_surface_count(), 4,
		"one surface per material: floor, wall, trim, ceiling")

	# Five bays, two photographs each — one per wall — makes the ten an album
	# holds.
	t.eq(HallwayBuilder.frame_count(), AlbumSchema.PHOTOS_PER_ALBUM,
		"five bays times two walls is exactly an album")
	t.eq(h.frame_anchors.size(), AlbumSchema.PHOTOS_PER_ALBUM,
		"ten frame anchors")
	t.eq(h.window_anchors.size(), HallwayBuilder.CLERESTORY_COUNT * 2,
		"clerestory openings on both sides")

	var half_w := HallwayBuilder.HALL_WIDTH * 0.5

	# Hang order is bay 0 right, bay 0 left, bay 1 right, ... so she meets the
	# photographs in pairs as she walks rather than all down one wall.
	for i in h.frame_anchors.size():
		var origin: Vector3 = h.frame_anchors[i].origin
		var facing: Vector3 = h.frame_anchors[i].basis.z.normalized()
		var bay := i / HallwayBuilder.FRAMES_PER_BAY
		var on_right := i % HallwayBuilder.FRAMES_PER_BAY == 0

		t.close(origin.z, HallwayBuilder.bay_z(bay), 0.001,
			"frame %d is in bay %d" % [i, bay])
		t.close(origin.y, HallwayBuilder.FRAME_ANCHOR_HEIGHT, 0.001,
			"frame %d is at picture height" % i)

		if on_right:
			t.close(origin.x, half_w - 0.02, 0.001, "frame %d is on the right wall" % i)
			t.close(facing.x, -1.0, 0.001, "frame %d faces into the hall (-X)" % i)
		else:
			t.close(origin.x, -half_w + 0.02, 0.001, "frame %d is on the left wall" % i)
			t.close(facing.x, 1.0, 0.001, "frame %d faces into the hall (+X)" % i)

	# The two frames of a bay must face each other across the hall.
	for bay in HallwayBuilder.BAY_COUNT:
		var right: Transform3D = h.frame_anchors[bay * 2]
		var left: Transform3D = h.frame_anchors[bay * 2 + 1]
		t.close(right.origin.z, left.origin.z, 0.001,
			"bay %d hangs its pair at the same depth" % bay)
		t.close(right.basis.z.dot(left.basis.z), -1.0, 0.001,
			"bay %d pair faces each other" % bay)

	# Bays evenly spaced, and wide enough apart for a two-metre picture.
	for bay in HallwayBuilder.BAY_COUNT - 1:
		var a := HallwayBuilder.bay_z(bay)
		var b := HallwayBuilder.bay_z(bay + 1)
		t.close(absf(b - a), HallwayBuilder.BAY_SPACING, 0.001,
			"bays %d and %d are one spacing apart" % [bay, bay + 1])
	t.gt(HallwayBuilder.BAY_SPACING,
		PhotoFrame.OPENING_WIDTH + PhotoFrame.MOULDING_WIDTH * 2.0 + 0.6,
		"bays are wider than a framed picture plus breathing room")

	# The hall must be wide enough that two facing pictures are not in each
	# other's faces, and tall enough to carry them under a clerestory.
	t.gt(HallwayBuilder.HALL_WIDTH, 8.0, "the hall is genuinely wide")
	t.gt(HallwayBuilder.HALL_HEIGHT, HallwayBuilder.CLERESTORY_HEAD,
		"the ceiling clears the clerestory head")

	# Clerestory windows must sit ABOVE the pictures: that is the whole reason
	# they moved upstairs when the second wall filled with photographs.
	var picture_top := HallwayBuilder.FRAME_ANCHOR_HEIGHT \
		+ PhotoFrame.OPENING_HEIGHT * 0.5 + PhotoFrame.MOULDING_WIDTH
	t.gt(HallwayBuilder.CLERESTORY_SILL, picture_top,
		"the clerestory sill clears the top of a framed picture")

	# Openings on both walls, facing into the hall.
	for i in h.window_anchors.size():
		var origin: Vector3 = h.window_anchors[i].origin
		var facing: Vector3 = h.window_anchors[i].basis.z.normalized()
		t.close(absf(origin.x), half_w, 0.001, "window %d sits on a side wall" % i)
		t.close(facing.x, -signf(origin.x), 0.001,
			"window %d faces into the hall" % i)
		t.gt(origin.y, picture_top, "window %d is above the pictures" % i)
		t.lt(origin.y, HallwayBuilder.HALL_HEIGHT, "window %d is below the ceiling" % i)

	# Half the openings on each side.
	var left_count := 0
	for anchor in h.window_anchors:
		if anchor.origin.x < 0.0:
			left_count += 1
	t.eq(left_count, HallwayBuilder.CLERESTORY_COUNT,
		"the clerestory is symmetric across the hall")

	# The hall must be long enough to hold every bay plus run-out.
	t.gt(h.hall_length, absf(HallwayBuilder.bay_z(HallwayBuilder.BAY_COUNT - 1)),
		"hall is longer than the last bay")
	t.lt(h.hall_length, 40.0, "hall is not absurdly long")

	# Collision: floor, ceiling, two side walls, two end walls.
	t.eq(h.colliders.size(), 6, "six collision boxes enclose the hall")
	for box in h.colliders:
		var size: Vector3 = box["size"]
		t.ok(size.x > 0.0 and size.y > 0.0 and size.z > 0.0,
			"collider has positive size")

	# Start and end positions must be inside the hall and on the floor.
	t.close(h.player_start.origin.y, 0.0, 0.001, "player starts on the floor")
	t.ok(h.player_start.origin.z > h.companion_end.origin.z,
		"she starts at the near end and he waits at the far end")
	t.ok(absf(h.companion_end.origin.x) < half_w,
		"the companion waits inside the hall")
	t.gt(h.companion_end.origin.z, -h.hall_length,
		"the companion is not inside the end wall")

	# Geometry budget: this is the whole shell, and it ships as code.
	var tris := 0
	for s in h.mesh.get_surface_count():
		tris += h.mesh.surface_get_array_len(s) / 3
	t.gt(float(tris), 200.0, "shell has real geometry, not an empty mesh")
	t.lt(float(tris), 8000.0, "shell stays cheap (%d tris)" % tris)


# ------------------------------------------------------------ voxel grid

static func _test_voxel_grid(t: TestFramework) -> void:
	var g := VoxelGrid.new(4, 5, 6)
	t.eq(g.width, 4, "grid width")
	t.eq(g.height, 5, "grid height")
	t.eq(g.depth, 6, "grid depth")
	t.eq(g.cells.size(), 4 * 5 * 6, "grid allocates every cell")
	t.eq(g.filled_count(), 0, "a new grid is empty")

	g.set_cell(1, 2, 3, 7)
	t.eq(g.get_cell(1, 2, 3), 7, "set then get round-trips")
	t.eq(g.filled_count(), 1, "one filled cell")

	# Out-of-bounds must be inert, not a crash: the ellipsoid filler walks past
	# the edges by design.
	g.set_cell(-1, 0, 0, 9)
	g.set_cell(99, 0, 0, 9)
	t.eq(g.get_cell(-1, 0, 0), 0, "out-of-bounds reads as empty")
	t.eq(g.get_cell(99, 99, 99), 0, "far out-of-bounds reads as empty")
	t.eq(g.filled_count(), 1, "out-of-bounds writes are dropped")

	# Box fill, including clipping.
	var b := VoxelGrid.new(4, 4, 4)
	b.fill_box(1, 1, 1, 2, 2, 2, 3)
	t.eq(b.filled_count(), 8, "a 2x2x2 box fills eight cells")
	b.fill_box(-5, -5, -5, 99, 99, 99, 4)
	t.eq(b.filled_count(), 64, "an oversized box clips to the grid")

	# Reversed corners must still work.
	var rev := VoxelGrid.new(4, 4, 4)
	rev.fill_box(2, 2, 2, 1, 1, 1, 5)
	t.eq(rev.filled_count(), 8, "a box given in reverse order still fills")

	# Ellipsoid: symmetric, and inside the grid.
	var e := VoxelGrid.new(8, 8, 8)
	e.fill_ellipsoid(Vector3(4, 4, 4), Vector3(3, 3, 3), 1)
	t.gt(float(e.filled_count()), 60.0, "ellipsoid fills a substantial volume")
	t.lt(float(e.filled_count()), 512.0, "ellipsoid does not fill the whole grid")
	for axis in 3:
		var a := Vector3i(4, 4, 4)
		var lo := a
		var hi := a
		lo[axis] = 0
		hi[axis] = 7
		t.eq(e.get_cell(lo.x, lo.y, lo.z), e.get_cell(hi.x, hi.y, hi.z),
			"ellipsoid is symmetric on axis %d" % axis)

	# Recolour, used by the customization palette swaps.
	var r := VoxelGrid.new(3, 3, 3)
	r.fill_box(0, 0, 0, 2, 2, 2, 2)
	r.recolor(2, 5)
	t.eq(r.get_cell(1, 1, 1), 5, "recolour replaces the index")
	t.eq(r.filled_count(), 27, "recolour does not remove cells")

	# Bounds of the filled region.
	var bb := VoxelGrid.new(10, 10, 10)
	bb.fill_box(2, 3, 4, 5, 6, 7, 1)
	var bounds := bb.filled_bounds()
	t.eq(bounds.position, Vector3(2, 3, 4), "filled bounds origin")
	t.eq(bounds.size, Vector3(4, 4, 4), "filled bounds size")
	t.eq(VoxelGrid.new(4, 4, 4).filled_bounds().size, Vector3.ZERO,
		"an empty grid has zero bounds")


# --------------------------------------------------------- greedy meshing

static func _test_greedy_meshing(t: TestFramework) -> void:
	var palette := [Color.TRANSPARENT, Color.RED, Color.GREEN]

	# A single voxel is a cube: six faces, one quad each.
	var one := VoxelGrid.new(1, 1, 1)
	one.set_cell(0, 0, 0, 1)
	t.eq(VoxelMesher.count_quads(one), 6, "a single voxel emits six quads")

	# THE POINT OF THE ALGORITHM: a solid 4x4x4 block of one colour has 64
	# voxels and 384 faces naively, but only six visible rectangles. If this
	# assertion ever fails, greedy merging has stopped merging.
	var block := VoxelGrid.new(4, 4, 4)
	block.fill_box(0, 0, 0, 3, 3, 3, 1)
	t.eq(VoxelMesher.count_quads(block), 6,
		"a solid single-colour block merges to six quads, not 384")

	# Interior faces must be culled: a 3x3x3 solid has one hidden centre voxel
	# contributing nothing.
	var solid := VoxelGrid.new(3, 3, 3)
	solid.fill_box(0, 0, 0, 2, 2, 2, 1)
	t.eq(VoxelMesher.count_quads(solid), 6, "interior faces are culled")

	# Two colours cannot merge across the colour boundary, so the faces
	# perpendicular to the split stay whole but the split faces double.
	var split := VoxelGrid.new(4, 4, 4)
	split.fill_box(0, 0, 0, 3, 3, 3, 1)
	split.fill_box(0, 0, 0, 1, 3, 3, 2)
	t.gt(float(VoxelMesher.count_quads(split)), 6.0,
		"a two-colour block needs more than six quads")
	t.lt(float(VoxelMesher.count_quads(split)), 384.0,
		"a two-colour block still merges substantially")

	# An empty grid must produce an empty mesh rather than a broken one.
	var empty := VoxelGrid.new(4, 4, 4)
	t.eq(VoxelMesher.count_quads(empty), 0, "an empty grid emits no quads")
	t.eq(VoxelMesher.build(empty, palette, 0.05).get_surface_count(), 0,
		"an empty grid builds an empty mesh")

	# A real mesh: correct triangle count, and non-degenerate.
	var mesh := VoxelMesher.build(block, palette, 0.05)
	t.eq(mesh.get_surface_count(), 1, "meshing produces one surface")
	t.eq(mesh.surface_get_array_len(0) / 3, 12,
		"six merged quads are twelve triangles")

	# Scale and offset must be honoured, since limb pivots depend on them.
	var scaled := VoxelMesher.build(block, palette, 0.1)
	var aabb := scaled.get_aabb()
	t.close(aabb.size.x, 0.4, 0.001, "voxel size scales the mesh (4 * 0.1)")

	var offset := VoxelMesher.build(block, palette, 0.1, Vector3(-2, 0, -2))
	var off_aabb := offset.get_aabb()
	t.close(off_aabb.position.x, -0.2, 0.001, "origin offset shifts the mesh")
	t.close(off_aabb.position.y, 0.0, 0.001, "origin offset leaves Y alone")

	# A hollow shell: faces on the inside as well as the outside.
	var shell := VoxelGrid.new(5, 5, 5)
	shell.fill_box(0, 0, 0, 4, 4, 4, 1)
	shell.fill_box(1, 1, 1, 3, 3, 3, 0)
	t.gt(float(VoxelMesher.count_quads(shell)), 6.0,
		"a hollow shell has interior faces to emit")


# --------------------------------------------------- figure proportions

static func _test_figure_proportions(t: TestFramework) -> void:
	# The character is a drawn sprite extruded to a few centimetres, not a
	# voxel model. The earlier figure was not too blocky, it was too COARSE:
	# nine voxels across a torso. These assertions pin the resolution that
	# fixed it.
	t.gt(PixelFigure.SPRITE_HEIGHT, 40,
		"the sprite is tall enough to be pixel art rather than Minecraft")
	t.gt(PixelFigure.SPRITE_WIDTH, 24, "the sprite has width to draw into")
	t.close(PixelFigure.FIGURE_HEIGHT,
		float(PixelFigure.SPRITE_HEIGHT) * PixelFigure.PIXEL, 0.0001,
		"figure height is derived from the sprite, not set separately")

	# An elderly woman, not a hero.
	t.gt(PixelFigure.FIGURE_HEIGHT, 1.45, "figure is at least 1.45 m tall")
	t.lt(PixelFigure.FIGURE_HEIGHT, 1.80, "figure is under 1.80 m tall")

	# Thickness has to be real enough to catch light and cast a silhouette,
	# but nowhere near a modelled body.
	var depth := float(PixelFigure.THICKNESS) * PixelFigure.PIXEL
	t.gt(depth, 0.04, "the figure has enough thickness to read as solid")
	t.lt(depth, 0.20, "the figure is still a drawing, not a model")

	# She must fit through the door and under the ceiling with room to spare.
	t.lt(PixelFigure.FIGURE_HEIGHT, HallwayBuilder.DOOR_HEIGHT,
		"figure fits through the doorway")
	t.lt(PixelFigure.FIGURE_HEIGHT, HallwayBuilder.HALL_HEIGHT,
		"figure fits under the ceiling")

	# The pictures are hung for someone her height to look at.
	var eye_height := PixelFigure.FIGURE_HEIGHT * 0.92
	t.lt(absf(eye_height - HallwayBuilder.FRAME_ANCHOR_HEIGHT), 0.75,
		"pictures hang within comfortable reach of her eyeline")

	# Three drawn views cover four facings, because the profile is mirrored.
	t.eq(PixelFigure.View.size(), 3, "front, side and back views")

	# Every palette entry must resolve, including the derived shades: a missing
	# index would silently render as grey.
	var colours := PixelFigure.Palette.new().to_array()
	t.eq(colours.size(), 12, "palette covers every index the canvases use")
	for i in range(1, colours.size()):
		var c: Color = colours[i]
		t.ok(c.a > 0.99, "palette index %d is opaque" % i)

	# Shades must actually be darker than their base, or the form shading
	# inverts under scene light.
	var pal := PixelFigure.Palette.new()
	var arr := pal.to_array()
	for base in PixelFigure.SHADE_OF.keys():
		var b: Color = arr[base]
		var sh: Color = arr[PixelFigure.SHADE_OF[base]]
		t.lt(sh.get_luminance(), b.get_luminance(),
			"shade of index %d is darker than its base" % base)

	# The husband reads as a different person, not a recolour of nothing.
	var her := PixelFigure.Palette.new().to_array()
	var him := PixelFigure.Palette.husband().to_array()
	var differences := 0
	for i in her.size():
		if not (her[i] as Color).is_equal_approx(him[i]):
			differences += 1
	t.gt(float(differences), 2.0, "the two figures differ in several tones")


# ------------------------------------------------------------ frame mat

static func _test_frame_mat(t: TestFramework) -> void:
	# The opening is landscape, which is what makes a portrait photo need wide
	# side margins rather than being stretched (plan §4.3).
	var opening := PhotoFrame.opening_aspect()
	t.gt(opening, 1.0, "the frame opening is landscape")

	# Museum scale: about two metres across, so a photograph is a work rather
	# than a snapshot on a wall.
	t.gt(PhotoFrame.OPENING_WIDTH, 1.8, "the opening is grand, not domestic")
	t.gt(PhotoFrame.OPENING_HEIGHT, 1.5, "the opening is tall enough to match")
	t.close(opening, PhotoFrame.OPENING_WIDTH / PhotoFrame.OPENING_HEIGHT, 0.0001,
		"opening aspect matches its dimensions")

	# The blur ladder must have one entry per baked tier, and must decrease:
	# later tiers are sharper.
	t.eq(PhotoFrame.TIER_BLUR.size(), AlbumSchema.BLUR_TIER_COUNT,
		"one blur value per baked tier")
	for i in PhotoFrame.TIER_BLUR.size() - 1:
		t.gt(float(PhotoFrame.TIER_BLUR[i]), float(PhotoFrame.TIER_BLUR[i + 1]),
			"tier %d blurs more than tier %d" % [i, i + 1])
	t.close(PhotoFrame.REVEALED_BLUR, 0.0, 0.0001,
		"a revealed photograph has no blur at all")

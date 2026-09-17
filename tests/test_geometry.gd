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

	# One frame anchor per photograph, and the album is exactly ten.
	t.eq(h.frame_anchors.size(), AlbumSchema.PHOTOS_PER_ALBUM,
		"ten frame anchors, matching an album")
	t.eq(h.window_anchors.size(), HallwayBuilder.BAY_COUNT,
		"one window per bay")

	# Anchors must be on the right wall, at picture height, evenly spaced.
	var half_w := HallwayBuilder.HALL_WIDTH * 0.5
	for i in h.frame_anchors.size():
		var origin: Vector3 = h.frame_anchors[i].origin
		t.close(origin.x, half_w - 0.02, 0.001, "frame %d sits on the right wall" % i)
		t.close(origin.y, HallwayBuilder.FRAME_ANCHOR_HEIGHT, 0.001,
			"frame %d is at picture height" % i)
		t.close(origin.z, HallwayBuilder.bay_z(i), 0.001, "frame %d is in bay %d" % [i, i])

	for i in h.frame_anchors.size() - 1:
		var a: Vector3 = h.frame_anchors[i].origin
		var b: Vector3 = h.frame_anchors[i + 1].origin
		t.close(absf(b.z - a.z), HallwayBuilder.BAY_SPACING, 0.001,
			"frames %d and %d are one bay apart" % [i, i + 1])

	# A frame anchor's local +Z must point INTO the hall, because a QuadMesh
	# faces +Z and the picture has to face the player.
	for i in h.frame_anchors.size():
		var facing: Vector3 = h.frame_anchors[i].basis.z.normalized()
		t.close(facing.x, -1.0, 0.001, "frame %d faces into the hall (-X)" % i)

	# A window anchor's local +Z must point the other way, into the hall from
	# the left wall. Getting this backwards fired the window lights through the
	# wall and left the corridor unlit.
	for i in h.window_anchors.size():
		var origin: Vector3 = h.window_anchors[i].origin
		var facing: Vector3 = h.window_anchors[i].basis.z.normalized()
		t.close(origin.x, -half_w, 0.001, "window %d sits on the left wall" % i)
		t.close(facing.x, 1.0, 0.001, "window %d faces into the hall (+X)" % i)

	# Windows offset half a bay from the frames, so light lands between the
	# pictures rather than straight onto them.
	for i in h.window_anchors.size():
		var win_z: float = h.window_anchors[i].origin.z
		var frame_z := HallwayBuilder.bay_z(i)
		t.close(absf(win_z - frame_z), HallwayBuilder.BAY_SPACING * 0.5, 0.001,
			"window %d is half a bay off frame %d" % [i, i])

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
	# The joint offsets are derived from the grid sizes precisely so they
	# cannot drift apart. An earlier version had the hips below the leg length,
	# which sank the feet through the floor and buried the head in the chest.
	t.close(VoxelFigure.LEG_LENGTH,
		float(VoxelFigure.THIGH_VOXELS + VoxelFigure.SHIN_VOXELS) * VoxelFigure.VOXEL,
		0.0001, "leg length is derived from the leg grids")
	t.close(VoxelFigure.TORSO_HEIGHT,
		float(VoxelFigure.TORSO_VOXELS) * VoxelFigure.VOXEL, 0.0001,
		"torso height is derived from the torso grid")

	# An elderly woman, not a hero: somewhere between 1.5 and 1.8 m.
	t.gt(VoxelFigure.FIGURE_HEIGHT, 1.45, "figure is at least 1.45 m tall")
	t.lt(VoxelFigure.FIGURE_HEIGHT, 1.80, "figure is under 1.80 m tall")

	# She must fit through the door and under the ceiling with room to spare.
	t.lt(VoxelFigure.FIGURE_HEIGHT, HallwayBuilder.DOOR_HEIGHT,
		"figure fits through the doorway")
	t.lt(VoxelFigure.FIGURE_HEIGHT, HallwayBuilder.HALL_HEIGHT,
		"figure fits under the ceiling")

	# Arms must hang clear of the torso, or their faces z-fight with the chest.
	t.gt(VoxelFigure.SHOULDER_X, VoxelFigure.TORSO_HALF_WIDTH,
		"shoulders sit outside the torso half-width")

	# Her eyeline should be near the pictures, which is what makes the hang
	# height right.
	var eye_height := VoxelFigure.FIGURE_HEIGHT * 0.94
	t.lt(absf(eye_height - HallwayBuilder.FRAME_ANCHOR_HEIGHT), 0.45,
		"pictures hang within half a metre of her eyeline")


# ------------------------------------------------------------ frame mat

static func _test_frame_mat(t: TestFramework) -> void:
	# The opening is landscape, which is what makes a portrait photo need wide
	# side margins rather than being stretched (plan §4.3).
	var opening := PhotoFrame.opening_aspect()
	t.gt(opening, 1.0, "the frame opening is landscape")
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

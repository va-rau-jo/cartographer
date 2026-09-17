class_name HallwayBuilder
extends RefCounted
## Procedurally builds the gallery hallway.
##
## Everything here is prismatic — boxes, extrusions, a lathe profile for the
## cornice — which is exactly what makes a hallway the right first space: tall
## walls, a repeating bay rhythm, pilasters, a coffered ceiling. All of it is
## code, so it costs nothing in the download budget (plan §1.4) and one changed
## number updates every bay.
##
## The layout the geometry serves:
##
##   photographs down the RIGHT wall (+X), one per bay
##   tall windows down the LEFT wall (-X), offset half a bay so the light
##     falls between the frames rather than straight onto them
##   the far end (-Z) left dark, which is where he waits
##
## build() returns geometry plus the anchor transforms the gallery scene needs;
## it never touches the scene tree, so it is testable headless.

const BAY_COUNT := 10
const BAY_SPACING := 2.4

const HALL_WIDTH := 4.6
const HALL_HEIGHT := 5.0
const WALL_THICKNESS := 0.4

## First bay centre, and therefore where she starts looking.
const FIRST_BAY_Z := -2.2

const SKIRTING_HEIGHT := 0.22
const SKIRTING_DEPTH := 0.05

const PILASTER_WIDTH := 0.34
const PILASTER_DEPTH := 0.13

const CORNICE_HEIGHT := 0.40
const CORNICE_DEPTH := 0.26
const CORNICE_STEPS := 4        ## stepped profile; reads as moulding under raking light

const WINDOW_WIDTH := 1.60
const WINDOW_SILL := 1.05
const WINDOW_HEAD := 3.70

const CEILING_BEAM_DEPTH := 0.22
const CEILING_BEAM_WIDTH := 0.30

const FRAME_ANCHOR_HEIGHT := 1.72   ## centre of the picture, near standing eye level
const DOOR_WIDTH := 1.6
const DOOR_HEIGHT := 2.9

enum Surface { FLOOR, WALL, TRIM, CEILING }

## Left and right wall multipliers. Typed, because an untyped array literal
## makes the products below uninferrable under this project's strict
## warnings-as-errors setting.
const SIDES: Array[float] = [-1.0, 1.0]


class Result extends RefCounted:
	var mesh: ArrayMesh = null
	## One per photograph, in hang order. Facing -X, into the hall.
	var frame_anchors: Array[Transform3D] = []
	## One per window, facing +X. Light shafts are spawned from these.
	var window_anchors: Array[Transform3D] = []
	## Axis-aligned collision boxes: [{size: Vector3, origin: Vector3}].
	var colliders: Array[Dictionary] = []
	var player_start: Transform3D = Transform3D.IDENTITY
	var companion_end: Transform3D = Transform3D.IDENTITY
	var hall_length: float = 0.0


static func bay_z(index: int) -> float:
	return FIRST_BAY_Z - float(index) * BAY_SPACING


static func hall_length() -> float:
	# A bay of run-out past the last frame so the far end is not cramped.
	return absf(bay_z(BAY_COUNT - 1)) + BAY_SPACING * 1.6


static func build() -> Result:
	var r := Result.new()
	r.hall_length = hall_length()

	var half_w := HALL_WIDTH * 0.5
	var z_near := 1.2                      # a little hall behind the player
	var z_far := -r.hall_length

	var floor_st := SurfaceTool.new()
	var wall_st := SurfaceTool.new()
	var trim_st := SurfaceTool.new()
	var ceil_st := SurfaceTool.new()
	for st in [floor_st, wall_st, trim_st, ceil_st]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- floor and ceiling ---
	_quad_y(floor_st, Vector3(-half_w, 0.0, z_far), Vector3(half_w, 0.0, z_near), true, 1.0)
	_quad_y(ceil_st, Vector3(-half_w, HALL_HEIGHT, z_far),
		Vector3(half_w, HALL_HEIGHT, z_near), false, 1.0)

	# --- right wall: solid, carries the photographs ---
	_box(wall_st, Vector3(half_w, 0.0, z_far),
		Vector3(half_w + WALL_THICKNESS, HALL_HEIGHT, z_near), 0.5)

	# --- left wall: built in pieces so the windows are real openings ---
	_build_window_wall(wall_st, -half_w, z_near, z_far, r)

	# --- end walls. The near one has a doorway she arrives through. ---
	_build_near_wall(wall_st, half_w, z_near)
	_box(wall_st, Vector3(-half_w, 0.0, z_far - WALL_THICKNESS),
		Vector3(half_w, HALL_HEIGHT, z_far), 0.5)

	# --- trim: skirting, pilasters, cornice, ceiling beams ---
	_build_skirting(trim_st, half_w, z_near, z_far)
	_build_pilasters(trim_st, half_w)
	_build_cornice(trim_st, half_w, z_near, z_far)
	_build_ceiling_beams(ceil_st, half_w)

	# --- frame anchors, one per bay on the right wall ---
	for i in BAY_COUNT:
		var pos := Vector3(half_w - 0.02, FRAME_ANCHOR_HEIGHT, bay_z(i))
		# Facing -X, into the hall. Basis looking along -X with +Y up.
		var basis := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))
		r.frame_anchors.append(Transform3D(basis, pos))

	# --- collision: simple boxes, not a trimesh. A character controller wants
	# flat planes, and the mouldings would only snag it. ---
	var mid_z := (z_near + z_far) * 0.5
	var len_z := z_near - z_far
	r.colliders = [
		{"size": Vector3(HALL_WIDTH + 2.0, 0.4, len_z), "origin": Vector3(0, -0.2, mid_z)},
		{"size": Vector3(HALL_WIDTH + 2.0, 0.4, len_z),
		 "origin": Vector3(0, HALL_HEIGHT + 0.2, mid_z)},
		{"size": Vector3(WALL_THICKNESS, HALL_HEIGHT, len_z),
		 "origin": Vector3(half_w + WALL_THICKNESS * 0.5, HALL_HEIGHT * 0.5, mid_z)},
		{"size": Vector3(WALL_THICKNESS, HALL_HEIGHT, len_z),
		 "origin": Vector3(-half_w - WALL_THICKNESS * 0.5, HALL_HEIGHT * 0.5, mid_z)},
		{"size": Vector3(HALL_WIDTH + 2.0, HALL_HEIGHT, WALL_THICKNESS),
		 "origin": Vector3(0, HALL_HEIGHT * 0.5, z_far - WALL_THICKNESS * 0.5)},
		{"size": Vector3(HALL_WIDTH + 2.0, HALL_HEIGHT, WALL_THICKNESS),
		 "origin": Vector3(0, HALL_HEIGHT * 0.5, z_near + WALL_THICKNESS * 0.5)},
	]

	r.player_start = Transform3D(Basis(), Vector3(0.0, 0.0, z_near - 1.4))
	# He waits in the dark at the far end, a little off-centre.
	r.companion_end = Transform3D(Basis(), Vector3(-0.7, 0.0, z_far + 2.0))

	# --- assemble, one surface per material ---
	var mesh := ArrayMesh.new()
	for entry in [
		{"st": floor_st, "name": "floor"},
		{"st": wall_st, "name": "wall"},
		{"st": trim_st, "name": "trim"},
		{"st": ceil_st, "name": "ceiling"},
	]:
		var st: SurfaceTool = entry["st"]
		st.generate_normals()
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, String(entry["name"]))

	r.mesh = mesh
	return r


# --------------------------------------------------------------- wall pieces

static func _build_window_wall(st: SurfaceTool, x: float, z_near: float,
		z_far: float, r: Result) -> void:
	var outer := x - WALL_THICKNESS
	var half_win := WINDOW_WIDTH * 0.5

	# Windows sit half a bay offset from the frames, so the light lands between
	# the pictures rather than blowing them out.
	var centres: Array[float] = []
	for i in BAY_COUNT:
		centres.append(bay_z(i) - BAY_SPACING * 0.5)

	# Wall below the sill and above the head run the whole length.
	_box(st, Vector3(outer, 0.0, z_far), Vector3(x, WINDOW_SILL, z_near), 0.5)
	_box(st, Vector3(outer, WINDOW_HEAD, z_far), Vector3(x, HALL_HEIGHT, z_near), 0.5)

	# Piers between the openings.
	var edges: Array[float] = [z_near]
	for c in centres:
		edges.append(c + half_win)
		edges.append(c - half_win)
	edges.append(z_far)

	var i := 0
	while i + 1 < edges.size():
		var a: float = edges[i]
		var b: float = edges[i + 1]
		if i % 2 == 0 and a - b > 0.001:
			_box(st, Vector3(outer, WINDOW_SILL, b),
				Vector3(x, WINDOW_HEAD, a), 0.5)
		i += 1

	# Reveals and a bright pane, so a window reads as a window in grey-box.
	for c in centres:
		var mid_y := (WINDOW_SILL + WINDOW_HEAD) * 0.5
		var basis := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
		r.window_anchors.append(Transform3D(basis, Vector3(x, mid_y, c)))


static func _build_near_wall(st: SurfaceTool, half_w: float, z_near: float) -> void:
	var z0 := z_near
	var z1 := z_near + WALL_THICKNESS
	var half_door := DOOR_WIDTH * 0.5

	_box(st, Vector3(-half_w - WALL_THICKNESS, 0.0, z0),
		Vector3(-half_door, HALL_HEIGHT, z1), 0.5)
	_box(st, Vector3(half_door, 0.0, z0),
		Vector3(half_w + WALL_THICKNESS, HALL_HEIGHT, z1), 0.5)
	_box(st, Vector3(-half_door, DOOR_HEIGHT, z0),
		Vector3(half_door, HALL_HEIGHT, z1), 0.5)


# --------------------------------------------------------------------- trim

static func _build_skirting(st: SurfaceTool, half_w: float, z_near: float,
		z_far: float) -> void:
	for side in SIDES:
		var inner := side * (half_w - SKIRTING_DEPTH)
		var outer := side * half_w
		_box(st, Vector3(minf(inner, outer), 0.0, z_far),
			Vector3(maxf(inner, outer), SKIRTING_HEIGHT, z_near), 1.0)


static func _build_pilasters(st: SurfaceTool, half_w: float) -> void:
	var half_p := PILASTER_WIDTH * 0.5
	for i in BAY_COUNT + 1:
		# Between the bays, so each photograph sits in its own panel.
		var z := bay_z(i) + BAY_SPACING * 0.5
		for side in SIDES:
			var inner := side * (half_w - PILASTER_DEPTH)
			var outer := side * half_w
			_box(st, Vector3(minf(inner, outer), SKIRTING_HEIGHT, z - half_p),
				Vector3(maxf(inner, outer), HALL_HEIGHT - CORNICE_HEIGHT, z + half_p), 1.0)


## A stepped profile rather than a true lathe: four receding steps read as
## moulding once raking window light hits them, and cost a handful of boxes.
static func _build_cornice(st: SurfaceTool, half_w: float, z_near: float,
		z_far: float) -> void:
	var step_h := CORNICE_HEIGHT / float(CORNICE_STEPS)
	for s in CORNICE_STEPS:
		var t := float(s) / float(CORNICE_STEPS)
		var depth := CORNICE_DEPTH * (1.0 - t)
		var y0 := HALL_HEIGHT - CORNICE_HEIGHT + float(s) * step_h
		var y1 := y0 + step_h
		for side in SIDES:
			var inner := side * (half_w - depth)
			var outer := side * half_w
			_box(st, Vector3(minf(inner, outer), y0, z_far),
				Vector3(maxf(inner, outer), y1, z_near), 1.0)


static func _build_ceiling_beams(st: SurfaceTool, half_w: float) -> void:
	var half_b := CEILING_BEAM_WIDTH * 0.5
	for i in BAY_COUNT + 1:
		var z := bay_z(i) + BAY_SPACING * 0.5
		_box(st, Vector3(-half_w, HALL_HEIGHT - CEILING_BEAM_DEPTH, z - half_b),
			Vector3(half_w, HALL_HEIGHT, z + half_b), 1.0)


# ---------------------------------------------------------------- primitives

## Axis-aligned box. `uv_scale` is metres per UV unit, so trim sheets tile at a
## consistent real-world size across every surface.
static func _box(st: SurfaceTool, a: Vector3, b: Vector3, uv_scale: float) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	if lo.is_equal_approx(hi):
		return

	# -X, +X
	_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), uv_scale)
	_quad(st, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), uv_scale)
	# -Z, +Z
	_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), uv_scale)
	_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), uv_scale)
	# -Y, +Y
	_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), uv_scale)
	_quad(st, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z),
		Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), uv_scale)


## Horizontal quad spanning two opposite corners. `up` picks the facing.
static func _quad_y(st: SurfaceTool, a: Vector3, b: Vector3, up: bool,
		uv_scale: float) -> void:
	var y := a.y
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var z0 := minf(a.z, b.z)
	var z1 := maxf(a.z, b.z)
	if up:
		_quad(st, Vector3(x0, y, z0), Vector3(x1, y, z0),
			Vector3(x1, y, z1), Vector3(x0, y, z1), uv_scale)
	else:
		_quad(st, Vector3(x0, y, z1), Vector3(x1, y, z1),
			Vector3(x1, y, z0), Vector3(x0, y, z0), uv_scale)


## Counter-clockwise quad as two triangles, UVs projected on the dominant axis
## so tiling stays uniform without authoring UVs per face.
static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3,
		p3: Vector3, uv_scale: float) -> void:
	var n := (p1 - p0).cross(p3 - p0)
	if n.length_squared() < 0.0000001:
		return
	n = n.normalized()

	var pts := [p0, p1, p2, p3]
	var uvs: Array[Vector2] = []
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	for p in pts:
		var v: Vector3 = p
		if ax >= ay and ax >= az:
			uvs.append(Vector2(v.z, -v.y) / uv_scale)
		elif ay >= az:
			uvs.append(Vector2(v.x, v.z) / uv_scale)
		else:
			uvs.append(Vector2(v.x, -v.y) / uv_scale)

	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			st.set_normal(n)
			st.set_uv(uvs[k])
			st.add_vertex(pts[k])

class_name VoxelMesher
extends RefCounted
## Greedy meshing: turns a VoxelGrid into the fewest quads that render it.
##
## The naive approach emits six quads per filled voxel, so a modest figure
## becomes tens of thousands of triangles of which almost all are interior
## faces nobody can see. Greedy meshing keeps only faces exposed to empty
## space, then merges coplanar neighbours of the same colour into the largest
## rectangles it can. A 16x32x16 figure drops from roughly 25k triangles to a
## few hundred.
##
## That matters here for two reasons beyond tidiness: the download budget is
## 100 MB for the whole game (plan §1.4), and the WebGL 2 Compatibility
## renderer has no spare draw-call headroom to waste on invisible geometry.
##
## Colours are baked into vertex colours, so a whole figure is one material and
## one draw call regardless of how many palette entries it uses.

## Face directions, each with the axis it advances along and its normal.
const DIRECTIONS := [
	{"axis": 0, "sign": 1},   # +X
	{"axis": 0, "sign": -1},  # -X
	{"axis": 1, "sign": 1},   # +Y
	{"axis": 1, "sign": -1},  # -Y
	{"axis": 2, "sign": 1},   # +Z
	{"axis": 2, "sign": -1},  # -Z
]


## `palette` maps index -> Color; index 0 is unused. `voxel_size` is metres per
## voxel. `origin_offset` shifts the mesh in voxel units before scaling, which
## is how a limb gets its pivot at the shoulder rather than at its corner.
static func build(grid: VoxelGrid, palette: Array, voxel_size: float = 0.05,
		origin_offset: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var emitted := 0
	for dir in DIRECTIONS:
		emitted += _mesh_direction(st, grid, palette, int(dir["axis"]),
			int(dir["sign"]), voxel_size, origin_offset)

	if emitted == 0:
		return ArrayMesh.new()

	st.generate_normals()
	return st.commit()


## Quad count for a grid, without building a mesh. Used by tests to assert the
## merging actually merged.
static func count_quads(grid: VoxelGrid) -> int:
	var total := 0
	for dir in DIRECTIONS:
		total += _mesh_direction(null, grid, [], int(dir["axis"]),
			int(dir["sign"]), 1.0, Vector3.ZERO)
	return total


# --- internals ---

static func _mesh_direction(st: SurfaceTool, grid: VoxelGrid, palette: Array,
		axis: int, sign: int, voxel_size: float,
		origin_offset: Vector3) -> int:
	# u and v are the two axes of the slice plane; `axis` is the slice normal.
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3

	var dims := [grid.width, grid.height, grid.depth]
	var slice_count: int = dims[axis]
	var u_size: int = dims[u]
	var v_size: int = dims[v]

	var normal := Vector3.ZERO
	normal[axis] = float(sign)

	var quads := 0

	for slice in slice_count:
		# Mask of exposed faces in this slice, by palette index.
		var mask := PackedInt32Array()
		mask.resize(u_size * v_size)
		mask.fill(0)

		var any := false
		for vi in v_size:
			for ui in u_size:
				var here := _at(grid, axis, slice, u, ui, v, vi)
				if here == 0:
					continue
				# A face is exposed only if the neighbour in this direction is
				# empty (or outside the grid).
				var neighbour := _at(grid, axis, slice + sign, u, ui, v, vi)
				if neighbour != 0:
					continue
				mask[ui + u_size * vi] = here
				any = true

		if not any:
			continue

		# Greedy rectangle merge over the mask.
		for vi in v_size:
			var ui := 0
			while ui < u_size:
				var value := mask[ui + u_size * vi]
				if value == 0:
					ui += 1
					continue

				# Grow along u while the colour matches.
				var w := 1
				while ui + w < u_size and mask[ui + w + u_size * vi] == value:
					w += 1

				# Grow along v while the whole row of width w matches.
				var h := 1
				var can_grow := true
				while vi + h < v_size and can_grow:
					for k in w:
						if mask[ui + k + u_size * (vi + h)] != value:
							can_grow = false
							break
					if can_grow:
						h += 1

				# Consume the rectangle so it is not emitted again.
				for dv in h:
					for du in w:
						mask[ui + du + u_size * (vi + dv)] = 0

				quads += 1
				if st != null:
					_emit_quad(st, palette, axis, slice, sign, u, ui, w, v, vi, h,
						normal, voxel_size, origin_offset, value)

				ui += w

	return quads


static func _at(grid: VoxelGrid, axis: int, a: int, u: int, ui: int,
		v: int, vi: int) -> int:
	var c := [0, 0, 0]
	c[axis] = a
	c[u] = ui
	c[v] = vi
	return grid.get_cell(c[0], c[1], c[2])


static func _emit_quad(st: SurfaceTool, palette: Array, axis: int, slice: int,
		sign: int, u: int, ui: int, w: int, v: int, vi: int, h: int,
		normal: Vector3, voxel_size: float, origin_offset: Vector3,
		value: int) -> void:

	# The quad sits on the far face of the voxel when advancing positively.
	var plane := float(slice) + (1.0 if sign > 0 else 0.0)

	var corners: Array[Vector3] = []
	for corner in [[0, 0], [w, 0], [w, h], [0, h]]:
		var p := Vector3.ZERO
		p[axis] = plane
		p[u] = float(ui + corner[0])
		p[v] = float(vi + corner[1])
		corners.append((p + origin_offset) * voxel_size)

	# Winding: for a positive-facing quad the u-then-v order is already
	# counter-clockwise seen from outside; for a negative face it must reverse,
	# and the u/v axis parity flips it once more.
	var flip := sign < 0
	if (axis == 1) != flip:
		corners.reverse()

	var colour := Color(0.8, 0.8, 0.8)
	if value >= 0 and value < palette.size():
		colour = palette[value]

	for tri in [[0, 1, 2], [0, 2, 3]]:
		for k in tri:
			st.set_normal(normal)
			st.set_color(colour)
			st.add_vertex(corners[k])


## Material for meshes produced here: vertex colours as albedo, no texture.
static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.78
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	# Voxel figures in a lit room need to sit IN the light, not float on it:
	# they must receive shadow and cast it, or they read as pasted on
	# (plan §11.1).
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat

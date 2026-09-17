class_name VoxelGrid
extends RefCounted
## A 3D grid of palette indices, with primitives for filling it.
##
## Characters are authored as volumes rather than as modelled meshes: a voxel
## figure *is* a grid of coloured cubes, so it can be built in code and needs
## no external tool. Ellipsoids rasterised into a coarse grid give exactly the
## stair-stepped curves the style wants, from a few lines instead of a sculpt.
##
## 0 means empty. Indices 1..255 refer to a palette held by the caller.

var width: int = 0
var height: int = 0
var depth: int = 0
var cells: PackedByteArray = PackedByteArray()


func _init(w: int = 1, h: int = 1, d: int = 1) -> void:
	width = maxi(1, w)
	height = maxi(1, h)
	depth = maxi(1, d)
	cells.resize(width * height * depth)
	cells.fill(0)


func index(x: int, y: int, z: int) -> int:
	return x + width * (y + height * z)


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height and z >= 0 and z < depth


func get_cell(x: int, y: int, z: int) -> int:
	if not in_bounds(x, y, z):
		return 0
	return cells[index(x, y, z)]


func set_cell(x: int, y: int, z: int, value: int) -> void:
	if in_bounds(x, y, z):
		cells[index(x, y, z)] = value


func filled_count() -> int:
	var n := 0
	for c in cells:
		if c != 0:
			n += 1
	return n


## Inclusive box fill, clipped to the grid.
func fill_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, value: int) -> void:
	var ax := mini(x0, x1)
	var bx := maxi(x0, x1)
	var ay := mini(y0, y1)
	var by := maxi(y0, y1)
	var az := mini(z0, z1)
	var bz := maxi(z0, z1)
	for z in range(maxi(az, 0), mini(bz, depth - 1) + 1):
		for y in range(maxi(ay, 0), mini(by, height - 1) + 1):
			for x in range(maxi(ax, 0), mini(bx, width - 1) + 1):
				cells[index(x, y, z)] = value


## Ellipsoid centred on `centre` (in voxel units) with the given radii.
func fill_ellipsoid(centre: Vector3, radii: Vector3, value: int) -> void:
	var r := Vector3(maxf(radii.x, 0.001), maxf(radii.y, 0.001), maxf(radii.z, 0.001))
	var lo := (centre - r).floor()
	var hi := (centre + r).ceil()

	for z in range(maxi(int(lo.z), 0), mini(int(hi.z), depth - 1) + 1):
		for y in range(maxi(int(lo.y), 0), mini(int(hi.y), height - 1) + 1):
			for x in range(maxi(int(lo.x), 0), mini(int(hi.x), width - 1) + 1):
				# Sample at voxel centres, so the silhouette is symmetric.
				var d := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) - centre) / r
				if d.length_squared() <= 1.0:
					cells[index(x, y, z)] = value


## Replace one palette index with another wherever it appears. Used for the
## customization palette swaps.
func recolor(from_value: int, to_value: int) -> void:
	for i in cells.size():
		if cells[i] == from_value:
			cells[i] = to_value


## Bounding box of the filled cells, or a zero-size box when empty.
func filled_bounds() -> AABB:
	var lo := Vector3i(width, height, depth)
	var hi := Vector3i(-1, -1, -1)
	for z in depth:
		for y in height:
			for x in width:
				if cells[index(x, y, z)] != 0:
					lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
					hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))
	if hi.x < lo.x:
		return AABB()
	return AABB(Vector3(lo), Vector3(hi - lo) + Vector3.ONE)

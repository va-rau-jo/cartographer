class_name VoxelFigure
extends Node3D
## A voxel character, built from code and assembled as a parts hierarchy.
##
## The hierarchy IS the rig and IS the customization slot system: each limb is
## its own node with its pivot at the joint, so animation keys node transforms
## and a slot swap adds or removes a child. No skeleton, no weights, no
## external tool (plan §11.1).
##
## Proportions here are deliberately not heroic — she is in her eighties, so
## the figure is short, slightly stooped, and narrow at the shoulder.

const VOXEL := 0.045   ## metres per voxel

## Derived so the joint offsets cannot drift out of step with the grids.
const THIGH_VOXELS := 7
const SHIN_VOXELS := 7
const TORSO_VOXELS := 14
const LEG_LENGTH := float(THIGH_VOXELS + SHIN_VOXELS) * VOXEL
const TORSO_HEIGHT := float(TORSO_VOXELS) * VOXEL

## Total standing height, for sanity-checking against the architecture.
const FIGURE_HEIGHT := LEG_LENGTH + TORSO_HEIGHT + 9.0 * VOXEL

## Torso is 9 voxels wide; arms hang clear of it rather than inside it.
const TORSO_HALF_WIDTH := 4.5 * VOXEL
const SHOULDER_X := TORSO_HALF_WIDTH + 1.0 * VOXEL
const HIP_X := 2.0 * VOXEL

## Palette indices. Kept as constants so recolouring is legible.
const EMPTY := 0
const SKIN := 1
const HAIR := 2
const GARMENT := 3
const GARMENT_DARK := 4
const SHOE := 5
const DETAIL := 6


class Palette extends RefCounted:
	var skin := Color(0.84, 0.69, 0.60)
	var hair := Color(0.88, 0.87, 0.85)
	var garment := Color(0.46, 0.51, 0.58)
	var garment_dark := Color(0.34, 0.37, 0.44)
	var shoe := Color(0.18, 0.15, 0.14)
	var detail := Color(0.12, 0.11, 0.10)

	func to_array() -> Array:
		# Index 0 is empty and never sampled, but must occupy the slot.
		return [Color.TRANSPARENT, skin, hair, garment, garment_dark, shoe, detail]

	static func husband() -> Palette:
		var p := Palette.new()
		p.skin = Color(0.80, 0.66, 0.57)
		p.hair = Color(0.78, 0.78, 0.76)
		p.garment = Color(0.44, 0.38, 0.30)
		p.garment_dark = Color(0.30, 0.26, 0.21)
		return p


var palette := Palette.new()

## Joint nodes, for animation and for the hug (plan §12).
var hips: Node3D = null
var torso: Node3D = null
var head: Node3D = null
var arm_l: Node3D = null
var arm_r: Node3D = null
var forearm_l: Node3D = null
var forearm_r: Node3D = null
var leg_l: Node3D = null
var leg_r: Node3D = null
var shin_l: Node3D = null
var shin_r: Node3D = null

var _material: StandardMaterial3D = null


func build(p: Palette = null) -> void:
	if p != null:
		palette = p
	_material = VoxelMesher.make_material()

	var colours := palette.to_array()

	# --- hips: root of everything that moves ---
	# Height must equal the leg chain, or the feet sink through the floor.
	# thigh (7 voxels) + shin (7 voxels) = 14 * VOXEL.
	hips = _joint(self, "Hips", Vector3(0, LEG_LENGTH, 0))

	# --- torso, with a slight forward stoop ---
	torso = _joint(hips, "Torso", Vector3(0, 0, 0))
	torso.rotation_degrees = Vector3(6, 0, 0)
	_attach(torso, _torso_grid(), colours, Vector3(-4.5, 0, -2.5))

	# --- head ---
	# Sits ON the torso, not inside it. At 0.30 the skull was buried to the
	# jaw and the figure read as a pile of boxes.
	head = _joint(torso, "Head", Vector3(0, TORSO_HEIGHT - 0.03, 0.005))
	_attach(head, _head_grid(), colours, Vector3(-4.0, 0, -4.0))

	# --- arms. Pivots at the shoulders, hanging slightly out from the body. ---
	for side in [-1, 1]:
		var label := "L" if side < 0 else "R"
		# Just OUTSIDE the torso. The torso is 9 voxels wide, so its half-width
		# is 0.2025 m; at 0.115 the arms sat inside the body and their faces
		# z-fought with the chest, which read as stripes down the front.
		var shoulder := _joint(torso, "Arm_%s" % label,
			Vector3(SHOULDER_X * float(side), TORSO_HEIGHT - 0.14, 0))
		shoulder.rotation_degrees = Vector3(4, 0, -7.0 * float(side))
		_attach(shoulder, _upper_arm_grid(), colours, Vector3(-1.5, -6.0, -1.5))

		var elbow := _joint(shoulder, "Forearm_%s" % label, Vector3(0, -0.27, 0))
		elbow.rotation_degrees = Vector3(-12, 0, 0)
		_attach(elbow, _forearm_grid(), colours, Vector3(-1.5, -6.0, -1.5))

		if side < 0:
			arm_l = shoulder
			forearm_l = elbow
		else:
			arm_r = shoulder
			forearm_r = elbow

	# --- legs ---
	for side in [-1, 1]:
		var label := "L" if side < 0 else "R"
		var hip := _joint(hips, "Leg_%s" % label, Vector3(HIP_X * float(side), 0, 0))
		_attach(hip, _thigh_grid(), colours, Vector3(-2.0, -7.0, -2.0))

		var knee := _joint(hip, "Shin_%s" % label, Vector3(0, -0.315, 0))
		_attach(knee, _shin_grid(), colours, Vector3(-2.0, -7.0, -2.0))

		if side < 0:
			leg_l = hip
			shin_l = knee
		else:
			leg_r = hip
			shin_r = knee


## Swap the palette without rebuilding geometry — the customization screen
## changes colours far more often than shapes.
func apply_palette(p: Palette) -> void:
	palette = p
	# Vertex colours are baked, so a live swap means rebuilding the meshes.
	# At this size that is a few milliseconds, and it keeps one code path.
	for child in get_children():
		child.queue_free()
	build(p)


func total_triangles() -> int:
	var n := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh != null:
			for s in m.mesh.get_surface_count():
				n += m.mesh.surface_get_array_len(s) / 3
	return n


# --- grids ---

func _torso_grid() -> VoxelGrid:
	var g := VoxelGrid.new(9, 14, 5)
	# Body, tapering: narrower at the waist than the chest.
	g.fill_box(1, 0, 1, 7, 4, 3, GARMENT)          # waist
	g.fill_box(0, 5, 0, 8, 12, 4, GARMENT)         # chest and shoulders
	g.fill_box(3, 12, 1, 5, 13, 3, SKIN)           # neck
	# A shawl across the shoulders, in the darker garment tone.
	g.fill_box(0, 9, 0, 8, 12, 4, GARMENT_DARK)
	g.fill_box(3, 12, 1, 5, 13, 3, SKIN)
	# Buttons down the front.
	for y in [6, 8, 10]:
		g.set_cell(4, y, 4, DETAIL)
	return g


func _head_grid() -> VoxelGrid:
	var g := VoxelGrid.new(8, 9, 8)
	g.fill_ellipsoid(Vector3(4, 4.3, 4), Vector3(3.7, 4.3, 3.7), SKIN)

	# Hair as a cap and a back panel, masked to where skin already is, so it
	# follows the skull instead of ballooning past it. Three overlapping
	# ellipsoids read as a jumble at eight voxels across.
	for z in 8:
		for y in 9:
			for x in 8:
				if g.get_cell(x, y, z) != SKIN:
					continue
				var crown := y >= 6
				var back := z <= 2
				var sides := (x == 0 or x == 7) and y >= 4
				if crown or back or sides:
					g.set_cell(x, y, z, HAIR)

	# Eyes, one voxel each, on the front face.
	g.set_cell(2, 4, 7, DETAIL)
	g.set_cell(5, 4, 7, DETAIL)
	return g


func _upper_arm_grid() -> VoxelGrid:
	var g := VoxelGrid.new(3, 6, 3)
	g.fill_box(0, 0, 0, 2, 5, 2, GARMENT_DARK)
	return g


func _forearm_grid() -> VoxelGrid:
	var g := VoxelGrid.new(3, 6, 3)
	g.fill_box(0, 2, 0, 2, 5, 2, GARMENT_DARK)
	g.fill_box(0, 0, 0, 2, 1, 2, SKIN)   # hand
	return g


func _thigh_grid() -> VoxelGrid:
	var g := VoxelGrid.new(4, 7, 4)
	g.fill_box(0, 0, 0, 3, 6, 3, GARMENT_DARK)
	return g


func _shin_grid() -> VoxelGrid:
	var g := VoxelGrid.new(4, 7, 6)
	g.fill_box(0, 2, 1, 3, 6, 4, GARMENT_DARK)
	g.fill_box(0, 0, 0, 3, 1, 5, SHOE)   # foot, extending forward
	return g


# --- assembly helpers ---

func _joint(parent: Node3D, node_name: String, offset: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = offset
	parent.add_child(n)
	return n


func _attach(parent: Node3D, grid: VoxelGrid, colours: Array,
		origin_offset: Vector3) -> void:
	var mesh := VoxelMesher.build(grid, colours, VOXEL, origin_offset)
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "%s_Mesh" % parent.name
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)

class_name RestingHead
extends Node3D
## The dying one's head on the pillow, seen from above: a small drawn sprite,
## extruded and laid flat. Either of them can be the one in the bed (see
## CastProfile), so the drawing takes a build: a man's hair stops at the
## hairline, a woman's spreads onto the pillow around her.
##
## Only the head is modelled. The rest of him is the shape under the blanket,
## which is both cheaper and truer to what you see from a doorway — and it
## sidesteps the fact that PixelFigure has no lying-down pose.
##
## This started life as a local function inside the hospital scene using
## lambdas to plot pixels, and drew nothing at all: GDScript lambdas capture
## locals BY VALUE, and a PackedByteArray is a value type, so every `canvas[i] =
## v` inside the lambda wrote to a copy that was thrown away. The render showed
## a bed with no one in it. Hence a real class with real methods.

## Across the bed by WIDTH, along it by HEIGHT — a head seen from above is
## longer than it is wide, and the first version had those the other way round,
## which put a small square face on a large pillow.
const WIDTH := 15
const HEIGHT := 19
const THICKNESS := 3

## Roughly half the standing figures' pixel size: at their scale an
## eighteen-pixel head came out half a metre across.
const PIXEL := PixelFigure.PIXEL * 0.52

const EMPTY := 0
const SKIN := 1
const SKIN_SHADE := 2
const HAIR := 3
const HAIR_SHADE := 4
const EYE := 5

var _canvas: PackedByteArray = PackedByteArray()
var _mesh: MeshInstance3D = null
var form: PixelFigure.Build = PixelFigure.Build.TROUSERS


## `palette` supplies the skin and hair; everything else is derived. `new_form`
## of -1 keeps whichever build this head already is.
func build(palette: PixelFigure.Palette = null, new_form: int = -1) -> void:
	var p := palette if palette != null else PixelFigure.Palette.for_trousers()
	if new_form >= 0:
		form = new_form as PixelFigure.Build

	var colours: Array = [
		Color.TRANSPARENT,
		p.skin, _shade(p.skin),
		p.hair, _shade(p.hair),
		Color(0.14, 0.12, 0.12),
	]

	_canvas = _draw()

	var grid := VoxelGrid.new(WIDTH, HEIGHT, THICKNESS)
	for y in HEIGHT:
		for x in WIDTH:
			var v := _canvas[x + WIDTH * y]
			if v == EMPTY:
				continue
			for z in THICKNESS:
				grid.set_cell(x, y, z, v)

	var mesh := VoxelMesher.build(grid, colours, PIXEL, Vector3(
		-float(WIDTH) * 0.5, -float(HEIGHT) * 0.5, -float(THICKNESS) * 0.5))
	if mesh.get_surface_count() == 0:
		CCLog.warn("hospital", "resting head produced no geometry")
		return

	_mesh = MeshInstance3D.new()
	_mesh.name = "Drawing"
	_mesh.mesh = mesh
	_mesh.material_override = VoxelMesher.make_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Laid flat, crown toward -Z: the canvas's "up" becomes the length of the
	# bed, so he is looking at the ceiling rather than standing on the pillow.
	_mesh.rotation_degrees = Vector3(-90, 0, 0)
	add_child(_mesh)


func filled_pixels() -> int:
	var n := 0
	for v in _canvas:
		if v != EMPTY:
			n += 1
	return n


func total_triangles() -> int:
	if _mesh == null or _mesh.mesh == null:
		return 0
	var n := 0
	for s in _mesh.mesh.get_surface_count():
		n += _mesh.mesh.surface_get_array_len(s) / 3
	return n


func size_metres() -> Vector2:
	return Vector2(float(WIDTH) * PIXEL, float(HEIGHT) * PIXEL)


# ---------------------------------------------------------------- drawing

## Seen from above, lying on his back. Hair frames the face; the eyes are
## closed; the near side of the face falls into shade.
func _draw() -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(WIDTH * HEIGHT)
	c.fill(EMPTY)

	# Hair spread on the pillow, for her: a row wider on each side and further
	# down toward the shoulders. On a pillow seen from above that spread is the
	# whole difference between the two of them.
	if form == PixelFigure.Build.SKIRT:
		_rect(c, 1, 3, 13, 18, HAIR)
		_rect(c, 0, 6, 14, 15, HAIR_SHADE)

	# Hair all round, face inside it. The crown (high y) is the end nearest the
	# headboard; the chin is at the low end.
	_rect(c, 2, 2, 12, 17, HAIR)
	_rect(c, 3, 3, 11, 14, SKIN)
	_rect(c, 4, 15, 10, 17, HAIR_SHADE)
	# Corners off, so the head is a head and not a domino.
	_px(c, 2, 2, EMPTY)
	_px(c, 12, 2, EMPTY)
	_px(c, 2, 17, EMPTY)
	_px(c, 12, 17, EMPTY)

	# Closed eyes, a nose shadow, and the line of a mouth.
	_rect(c, 4, 10, 5, 10, EYE)
	_rect(c, 9, 10, 10, 10, EYE)
	_rect(c, 7, 8, 7, 9, SKIN_SHADE)
	_rect(c, 6, 6, 8, 6, SKIN_SHADE)

	# The side away from the window is in shadow.
	for y in HEIGHT:
		for x in range(8, WIDTH):
			var v := _sample(c, x, y)
			if v == SKIN:
				_px(c, x, y, SKIN_SHADE)
			elif v == HAIR:
				_px(c, x, y, HAIR_SHADE)

	return c


func _px(c: PackedByteArray, x: int, y: int, v: int) -> void:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return
	c[x + WIDTH * y] = v


func _sample(c: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or x >= WIDTH or y < 0 or y >= HEIGHT:
		return EMPTY
	return c[x + WIDTH * y]


func _rect(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int,
		v: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			_px(c, x, y, v)


func _shade(colour: Color) -> Color:
	return Color(colour.r * 0.74, colour.g * 0.76, colour.b * 0.84)

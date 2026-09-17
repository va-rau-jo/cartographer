class_name EmbraceFigure
extends Node3D
## The two of them holding each other: one drawing, not two posed figures.
##
## PixelFigure's trade-off (see its header) is that an extruded drawing has no
## joints, so the hug cannot be animated out of the walking sprites — an arm
## that does not exist cannot be raised. The cheap answer is the one pixel
## artists use: draw the pose. This is a single 56 x 56 canvas holding both of
## them, extruded and billboarded exactly like PixelFigure, so it lights,
## shadows and turns to camera the same way and nothing else in the scene has to
## know it is a special case.
##
## Both palettes live in one colour table: hers at indices 1..11 and his at
## 12..22, which is why the drawing code takes a `Tones` rather than reading
## module constants.
##
## It is deliberately NOT a PixelFigure subclass. Almost nothing is shared —
## no three views, no walk cycle, no view selection — and inheriting would have
## meant overriding more than it reused.

const PIXEL := PixelFigure.PIXEL
const CANVAS_WIDTH := 56
const CANVAS_HEIGHT := 56
const THICKNESS := 3

## Shared indices, outside either palette.
const EMPTY := 0
const EDGE := 23

## Index of the first entry of each person's block.
const HER_BASE := 1
const HIS_BASE := 12

## Offsets within a person's block, in the order Palette.to_array() writes them.
const OFF_SKIN := 0
const OFF_SKIN_SHADE := 1
const OFF_HAIR := 2
const OFF_HAIR_SHADE := 3
const OFF_DRESS := 4
const OFF_DRESS_SHADE := 5
const OFF_WRAP := 6
const OFF_WRAP_SHADE := 7
const OFF_SHOE := 8
const OFF_EDGE := 9
const OFF_EYE := 10


## One person's palette indices into the combined colour table.
class Tones extends RefCounted:
	var skin := 0
	var skin_shade := 0
	var hair := 0
	var hair_shade := 0
	var cloth := 0        ## skirt / trousers
	var cloth_shade := 0
	var wrap := 0         ## cardigan
	var wrap_shade := 0
	var shoe := 0
	var eye := 0

	static func at(base: int) -> Tones:
		var t := Tones.new()
		t.skin = base + OFF_SKIN
		t.skin_shade = base + OFF_SKIN_SHADE
		t.hair = base + OFF_HAIR
		t.hair_shade = base + OFF_HAIR_SHADE
		t.cloth = base + OFF_DRESS
		t.cloth_shade = base + OFF_DRESS_SHADE
		t.wrap = base + OFF_WRAP
		t.wrap_shade = base + OFF_WRAP_SHADE
		t.shoe = base + OFF_SHOE
		t.eye = base + OFF_EYE
		return t

	## Base index -> shaded index, for the light-from-the-left pass.
	func shade_map() -> Dictionary:
		return {
			skin: skin_shade,
			hair: hair_shade,
			cloth: cloth_shade,
			wrap: wrap_shade,
		}


## Where each of them stands on the canvas. They overlap in the middle; that
## overlap is the whole point of the drawing.
const HER_X := 20
const HIS_X := 36

var _body: Node3D = null
var _mesh: MeshInstance3D = null
var _canvas: PackedByteArray = PackedByteArray()


func build(her: PixelFigure.Palette = null, his: PixelFigure.Palette = null) -> void:
	var her_palette := her if her != null else PixelFigure.Palette.new()
	var his_palette := his if his != null else PixelFigure.Palette.husband()

	var colours: Array = [Color.TRANSPARENT]
	# to_array() writes [transparent, skin, skin_shade, ... , edge, eye]; drop
	# its leading transparent and append the eleven real tones.
	var her_tones: Array = her_palette.to_array()
	var his_tones: Array = his_palette.to_array()
	for i in range(1, her_tones.size()):
		colours.append(her_tones[i])
	for i in range(1, his_tones.size()):
		colours.append(his_tones[i])
	# The contact edge, darker than either of them.
	colours.append(Color(0.10, 0.085, 0.08))

	_canvas = _draw()

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var grid := _extrude(_canvas)
	var offset := Vector3(
		-float(CANVAS_WIDTH) * 0.5,
		0.0,
		-float(THICKNESS) * 0.5)
	var mesh := VoxelMesher.build(grid, colours, PIXEL, offset)
	if mesh.get_surface_count() == 0:
		CCLog.warn("embrace", "drawing produced no geometry")
		return

	_mesh = MeshInstance3D.new()
	_mesh.name = "Drawing"
	_mesh.mesh = mesh
	_mesh.material_override = VoxelMesher.make_material()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_body.add_child(_mesh)


## Turn the drawing to camera, as PixelFigure does. Without this the pair
## foreshortens to a plank the moment the ending camera moves.
func face_camera(camera_global_position: Vector3) -> void:
	if _body == null:
		return
	var to_cam := camera_global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	to_cam = to_cam.normalized()
	_body.global_rotation.y = atan2(to_cam.x, to_cam.z)


## A breath, so the pose is not a statue. Very small on purpose.
func breathe(time: float) -> void:
	if _body == null:
		return
	_body.position.y = sin(time * 1.15) * 0.008
	_body.rotation.z = deg_to_rad(sin(time * 0.6) * 0.5)


func total_triangles() -> int:
	if _mesh == null or _mesh.mesh == null:
		return 0
	var n := 0
	for s in _mesh.mesh.get_surface_count():
		n += _mesh.mesh.surface_get_array_len(s) / 3
	return n


func filled_pixels() -> int:
	var n := 0
	for v in _canvas:
		if v != EMPTY:
			n += 1
	return n


# ---------------------------------------------------------------- drawing

func _extrude(canvas: PackedByteArray) -> VoxelGrid:
	var g := VoxelGrid.new(CANVAS_WIDTH, CANVAS_HEIGHT, THICKNESS)
	for y in CANVAS_HEIGHT:
		for x in CANVAS_WIDTH:
			var v := canvas[x + CANVAS_WIDTH * y]
			if v == EMPTY:
				continue
			for z in THICKNESS:
				g.set_cell(x, y, z, v)
	return g


## The pose, drawn back to front: him first (he is the far figure), then her in
## front of him, then the arms that cross over both.
func _draw() -> PackedByteArray:
	var c := _new_canvas()
	var her := Tones.at(HER_BASE)
	var his := Tones.at(HIS_BASE)

	# Layer order is the pose. His arms go on before she does, so her body
	# covers them the way a real embrace hides them; only the hand that comes
	# round her far side shows. Hers go on last, over his shoulders.
	#
	# Drawing every arm on top — the first attempt — put two diagonal bands
	# across her chest that read as a sash rather than as arms around a back.
	_draw_him(c, his)
	_draw_his_arms(c, his)
	_draw_her(c, her)
	_draw_his_hands(c, his)
	_draw_her_arms(c, her)

	# Light from the left, per person, so each one's own tones shade correctly.
	_shade_right(c, 26, her.shade_map())
	_shade_right(c, 26, his.shade_map())
	_ground_contact(c, [her.shoe, his.shoe])
	return c


## He is taller, stands a little behind, and his head tilts down toward her.
func _draw_him(c: PackedByteArray, t: Tones) -> void:
	var cx := HIS_X

	# Feet, turned in toward her.
	_rect(c, cx - 5, 0, cx + 3, 2, t.shoe)

	# Trousers, then torso, then the cardigan over it.
	_taper(c, 3, 27, 6.5, 5.5, float(cx), t.cloth)
	_taper(c, 27, 44, 6.0, 7.5, float(cx), t.cloth)
	_taper(c, 29, 44, 6.5, 7.5, float(cx), t.wrap)

	# Neck and head, leaning toward her.
	_rect(c, cx - 3, 43, cx - 1, 46, t.skin)
	_draw_head(c, cx - 2, 45, t, true, -1)


## She is in front and a little shorter, her head against his shoulder.
func _draw_her(c: PackedByteArray, t: Tones) -> void:
	var cx := HER_X

	_rect(c, cx - 3, 0, cx + 5, 2, t.shoe)

	# The long skirt, flaring to the hem.
	_taper(c, 3, 26, 8.0, 6.0, float(cx), t.cloth)
	_taper(c, 26, 41, 5.5, 7.0, float(cx), t.cloth)
	_taper(c, 28, 41, 6.0, 7.0, float(cx), t.wrap)

	# Neck and head, tipped toward him.
	_rect(c, cx + 1, 40, cx + 3, 43, t.skin)
	_draw_her_head(c, cx + 2, 42, t)


## Her head, seen from the front but tipped: the eyes are closed, which is the
## single detail that makes this read as an embrace rather than two people
## standing very close.
func _draw_her_head(c: PackedByteArray, cx: int, base_y: int, t: Tones) -> void:
	_round_rect(c, cx - 4, base_y, cx + 4, base_y + 10, t.skin)
	_round_rect(c, cx - 5, base_y + 7, cx + 5, base_y + 11, t.hair)
	_rect(c, cx - 5, base_y + 4, cx - 4, base_y + 8, t.hair)
	_rect(c, cx + 4, base_y + 4, cx + 5, base_y + 8, t.hair)
	# The bun, at the back of the crown.
	_round_rect(c, cx - 6, base_y + 6, cx - 3, base_y + 10, t.hair_shade)
	_draw_closed_eyes(c, cx, base_y, t)
	_rect(c, cx - 1, base_y + 2, cx + 1, base_y + 2, t.skin_shade)


## His head. `lean` tips the hair and face toward her by a pixel or two.
func _draw_head(c: PackedByteArray, cx: int, base_y: int, t: Tones,
		eyes_closed: bool, lean: int) -> void:
	_round_rect(c, cx - 4, base_y, cx + 4, base_y + 10, t.skin)
	_round_rect(c, cx - 5 + lean, base_y + 7, cx + 5 + lean, base_y + 11, t.hair)
	_rect(c, cx - 5, base_y + 4, cx - 4, base_y + 8, t.hair)
	_rect(c, cx + 4, base_y + 4, cx + 5, base_y + 8, t.hair)

	if eyes_closed:
		_draw_closed_eyes(c, cx, base_y, t)
	else:
		_px(c, cx - 2, base_y + 5, t.eye)
		_px(c, cx + 2, base_y + 5, t.eye)
	_rect(c, cx - 1, base_y + 2, cx + 1, base_y + 2, t.skin_shade)


## Eyes closed, on a nine-pixel-wide head.
##
## The first version drew each eye as a two-pixel bar, which at the size the
## player actually sees rendered as a black blindfold across both their faces.
## One pixel of eye with a shaded lid beneath it is the standard pixel-art
## solution, and it reads as closed rather than as missing.
func _draw_closed_eyes(c: PackedByteArray, cx: int, base_y: int,
		t: Tones) -> void:
	_px(c, cx - 2, base_y + 5, t.eye)
	_px(c, cx + 2, base_y + 5, t.eye)
	_px(c, cx - 2, base_y + 4, t.skin_shade)
	_px(c, cx + 2, base_y + 4, t.skin_shade)


## His arms, which go around her and are therefore mostly hidden: only the
## stretch between his shoulder and her silhouette is ever seen.
func _draw_his_arms(c: PackedByteArray, t: Tones) -> void:
	# Upper arm, from his shoulder down toward her back.
	_slope(c, HIS_X - 6, 39, HER_X + 2, 34, 3, t.wrap)
	# Lower arm, around her waist.
	_slope(c, HIS_X - 5, 33, HER_X + 1, 29, 3, t.wrap_shade)


## The hands of his that come round her far side. Drawn after her, because a
## hand you cannot see is not holding anyone.
func _draw_his_hands(c: PackedByteArray, t: Tones) -> void:
	# On her far shoulder blade.
	_rect(c, HER_X - 9, 33, HER_X - 7, 35, t.wrap)
	_rect(c, HER_X - 10, 32, HER_X - 8, 34, t.skin)
	# And at her far side, lower.
	_rect(c, HER_X - 9, 28, HER_X - 7, 30, t.wrap_shade)
	_rect(c, HER_X - 10, 27, HER_X - 8, 29, t.skin_shade)


## Her arms, up over his shoulders — the part of the pose that is meant to be
## seen, so it goes on top of everything.
func _draw_her_arms(c: PackedByteArray, t: Tones) -> void:
	# Up around his neck, hand on his far shoulder.
	_slope(c, HER_X + 5, 37, HIS_X + 1, 43, 3, t.wrap)
	_rect(c, HIS_X + 1, 43, HIS_X + 4, 45, t.skin)
	# The other arm across his back, lower.
	_slope(c, HER_X + 6, 31, HIS_X + 2, 35, 2, t.wrap_shade)
	_rect(c, HIS_X + 2, 34, HIS_X + 4, 36, t.skin_shade)


# ------------------------------------------------------------- primitives

func _new_canvas() -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(CANVAS_WIDTH * CANVAS_HEIGHT)
	c.fill(EMPTY)
	return c


func _px(c: PackedByteArray, x: int, y: int, v: int) -> void:
	if x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT:
		return
	c[x + CANVAS_WIDTH * y] = v


func _sample(c: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or x >= CANVAS_WIDTH or y < 0 or y >= CANVAS_HEIGHT:
		return EMPTY
	return c[x + CANVAS_WIDTH * y]


func _rect(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int, v: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			_px(c, x, y, v)


func _taper(c: PackedByteArray, y0: int, y1: int, half_at_y0: float,
		half_at_y1: float, centre: float, v: int) -> void:
	for y in range(y0, y1 + 1):
		var t := float(y - y0) / maxf(float(y1 - y0), 1.0)
		var half := lerpf(half_at_y0, half_at_y1, t)
		_rect(c, int(round(centre - half)), y, int(round(centre + half - 1)), y, v)


## A thick line from (x0,y0) to (x1,y1) — an arm. Drawn by walking x and
## rounding y, which is enough for a limb of this length and keeps the pixels
## exact.
func _slope(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int,
		thickness: int, v: int) -> void:
	var steps := maxi(absi(x1 - x0), absi(y1 - y0))
	if steps == 0:
		_rect(c, x0, y0, x0, y0 + thickness - 1, v)
		return
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := int(round(lerpf(float(x0), float(x1), t)))
		var y := int(round(lerpf(float(y0), float(y1), t)))
		_rect(c, x, y, x, y + thickness - 1, v)


func _round_rect(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int,
		v: int) -> void:
	_rect(c, x0, y0, x1, y1, v)
	_px(c, x0, y0, _sample(c, x0, y0 - 1))
	_px(c, x1, y0, _sample(c, x1, y0 - 1))
	_px(c, x0, y1, EMPTY)
	_px(c, x1, y1, EMPTY)


func _shade_right(c: PackedByteArray, from_x: int, shade_of: Dictionary) -> void:
	for y in CANVAS_HEIGHT:
		for x in range(from_x, CANVAS_WIDTH):
			var v := _sample(c, x, y)
			if shade_of.has(v):
				_px(c, x, y, shade_of[v])


func _ground_contact(c: PackedByteArray, skip: Array) -> void:
	for x in CANVAS_WIDTH:
		var v := _sample(c, x, 0)
		if v != EMPTY and not skip.has(v):
			_px(c, x, 0, EDGE)

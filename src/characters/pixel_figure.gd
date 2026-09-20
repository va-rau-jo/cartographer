class_name PixelFigure
extends Node3D
## A pixel-art character: a 2D sprite extruded to a few centimetres of
## thickness, standing in a lit 3D room.
##
## This replaces the earlier voxel figure. The problem with that one was never
## that it was blocky — it was that it was COARSE: nine voxels across a torso
## is not pixel art, it is Minecraft. A hand-drawn pixel character is thirty to
## sixty pixels tall with a dozen distinct shades, and reads as a person.
## Here the sprite is 34 x 56 and carries base, shade and edge tones per
## material, which is roughly twenty-five times the detail of the old figure at
## a fraction of its awkwardness.
##
## Why extrude rather than use a transparent billboard:
##
##   * No transparency. Alpha-scissored sprites in the Compatibility renderer
##     need careful shadow and sort handling; solid geometry needs none.
##   * A real cast shadow with the character's exact silhouette, which is what
##     stops a 2D figure looking pasted onto a 3D room.
##   * The pixels stay exact. Colours are vertex colours on merged rectangles,
##     so there is no texture filtering to soften them.
##
## Three views are drawn — front, side, back. Two things then happen every
## frame, and both are needed:
##
##   1. WHICH drawing shows is chosen from where the camera is relative to the
##      figure's own facing, so walking away shows her back and crossing the
##      hall shows her profile.
##   2. The drawing is then turned to face the camera about Y.
##
## Step 2 is not optional. A flat drawing with a fixed facing foreshortens into
## a plank the moment the camera is oblique, and with a third-person camera the
## player can look from anywhere. Turning the sprite to camera is what every
## game that mixes drawn characters with 3D rooms does, and it costs only that
## the cast shadow swings a little as the camera orbits.
##
## The side view is mirrored for the other direction, so four facings come from
## three drawings.
##
## Trade-off worth knowing: because the sprite is drawn rather than modelled,
## the walk is a bob and a lean rather than articulated limbs, and the hug at
## the ending will need its own drawn pose instead of two posed rigs. That is a
## change from plan §12, and a cheaper one.

const PIXEL := 0.029           ## metres per pixel; 56 px ≈ 1.62 m
const SPRITE_WIDTH := 34
const SPRITE_HEIGHT := 56
const THICKNESS := 3           ## pixels; ≈ 8.7 cm of real depth

const FIGURE_HEIGHT := float(SPRITE_HEIGHT) * PIXEL

enum View { FRONT, SIDE, BACK }

## Which body is drawn. Two builds, from the same primitives and the same
## five-colour palette: a skirt and a bun, or trousers and a short crop. Named
## for the clothes rather than for a person, because either character can be
## either build (see CastProfile).
##
## They are the same height — the hug at the ending is one drawn pose and it
## expects a pair it already knows the proportions of.
enum Build { SKIRT, TROUSERS }

## Palette indices.
const EMPTY := 0
const SKIN := 1
const SKIN_SHADE := 2
const HAIR := 3
const HAIR_SHADE := 4
const DRESS := 5
const DRESS_SHADE := 6
const WRAP := 7                ## cardigan / shawl
const WRAP_SHADE := 8
const SHOE := 9
const EDGE := 10               ## inner contact edge, not a cartoon outline
const EYE := 11

## Base index -> shaded index, for the single shading pass.
const SHADE_OF := {
	SKIN: SKIN_SHADE,
	HAIR: HAIR_SHADE,
	DRESS: DRESS_SHADE,
	WRAP: WRAP_SHADE,
}


class Palette extends RefCounted:
	var skin := Color(0.91, 0.76, 0.66)
	var hair := Color(0.80, 0.78, 0.75)
	var dress := Color(0.62, 0.42, 0.46)
	var wrap := Color(0.33, 0.38, 0.48)
	var shoe := Color(0.22, 0.18, 0.17)
	var eye := Color(0.16, 0.13, 0.13)

	## Shades are derived rather than authored, so a customization slider only
	## has to move one colour and the form shading follows it.
	func to_array() -> Array:
		return [
			Color.TRANSPARENT,
			skin, _shade(skin),
			hair, _shade(hair),
			dress, _shade(dress),
			wrap, _shade(wrap),
			shoe,
			_edge(),
			eye,
		]

	func _shade(c: Color) -> Color:
		# Darker and slightly cooler, the way pixel artists shade.
		return Color(c.r * 0.74, c.g * 0.76, c.b * 0.84)

	func _edge() -> Color:
		return Color(dress.r * 0.32, dress.g * 0.30, dress.b * 0.36)

	## The muted colours the trousers build starts in. Kept in step with
	## FigureProfile.trousers_default, so a figure built straight from this
	## looks like one built from the saved default.
	static func for_trousers() -> Palette:
		var p := Palette.new()
		p.skin = Color(0.91, 0.76, 0.66)
		p.hair = Color(0.80, 0.78, 0.75)
		p.dress = Color(0.42, 0.40, 0.36)     # trousers
		p.wrap = Color(0.55, 0.45, 0.33)      # jumper
		p.shoe = Color(0.22, 0.18, 0.17)
		return p


var palette := Palette.new()
## Which of the two bodies is drawn.
var form: Build = Build.SKIRT
## Turn to the viewport's camera every frame without being driven by anything.
##
## The player's figure is driven by the controller and the embrace by the
## ending, but a figure that is simply STOOD somewhere — the one waiting at the
## end of the hall, the one beside the bed — had nothing calling
## update_view_for_camera at all. The header above says that turn is not
## optional, and they proved it: the one in the hospital rendered as a sliver
## about seventy degrees off the lens, and the one down the hall was rotated
## 180° to face back up it, which showed the BACK of the slab — the front
## drawing mirrored, with the light-from-the-left shading on the wrong side.
var auto_face_camera := false
## Where the figure is looking, in its own local space. Movement sets this.
var view: View = View.FRONT

var _views: Dictionary = {}     ## View -> MeshInstance3D
var _side_mirrored := false
var _material: StandardMaterial3D = null
var _bob_phase := 0.0
var _body: Node3D = null


## `new_form` of -1 means "keep whichever body this figure is already drawn as",
## so existing callers that only care about colours are unaffected.
func build(p: Palette = null, new_form: int = -1) -> void:
	if p != null:
		palette = p
	if new_form >= 0:
		form = new_form as Build

	_material = VoxelMesher.make_material()
	var colours := palette.to_array()

	# A single body node carries the bob and lean, so the sprite meshes
	# themselves never need transforming.
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_views.clear()
	# No per-view yaw: every drawing faces the body node's +Z, and the body is
	# turned to camera each frame instead.
	_add_view(View.FRONT, _front_canvas(), colours)
	_add_view(View.SIDE, _side_canvas(), colours)
	_add_view(View.BACK, _back_canvas(), colours)

	set_view(View.FRONT, false)


## Pick the view from where the camera is, so she always reads as a person
## rather than a card turned edge-on.
func update_view_for_camera(camera_global_position: Vector3) -> void:
	var to_cam := camera_global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	to_cam = to_cam.normalized()

	# A Node3D's forward is -Z, and the controller aims that along the
	# direction of travel.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	# Signed angle from her facing to the camera: 0 means the camera is looking
	# her in the face.
	var angle := rad_to_deg(atan2(forward.cross(to_cam).y, forward.dot(to_cam)))

	if absf(angle) <= 45.0:
		set_view(View.FRONT, false)
	elif absf(angle) >= 135.0:
		set_view(View.BACK, false)
	else:
		set_view(View.SIDE, angle > 0.0)

	# Turn the drawing to camera. The sprite's front is its local +Z.
	if _body != null:
		_body.global_rotation.y = atan2(to_cam.x, to_cam.z)


func set_view(new_view: View, mirrored: bool) -> void:
	view = new_view
	_side_mirrored = mirrored
	for key in _views.keys():
		var mi: MeshInstance3D = _views[key]
		mi.visible = key == new_view

	if new_view == View.SIDE and _views.has(View.SIDE):
		var mi: MeshInstance3D = _views[View.SIDE]
		# One drawn profile serves both directions: mirror it rather than
		# drawing a fourth sprite.
		mi.scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)


func _process(_delta: float) -> void:
	if not auto_face_camera:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		update_view_for_camera(cam.global_position)


## Walk animation: a bob and a slight lean, not articulated limbs. An extruded
## drawing has no joints, so this is what the style buys and costs.
func animate_walk(delta: float, speed: float) -> void:
	if _body == null:
		return
	if speed > 0.05:
		_bob_phase += delta * speed * 7.0
		var bob := absf(sin(_bob_phase)) * 0.022
		var lean := sin(_bob_phase * 0.5) * 1.6
		_body.position.y = bob
		_body.rotation.z = deg_to_rad(lean)
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, delta * 8.0)
		_body.rotation.z = lerpf(_body.rotation.z, 0.0, delta * 8.0)


## Rebuild in the new colours. The old meshes are REMOVED from the tree as
## well as freed: queue_free alone is deferred to the end of the frame, so the
## new figure and the old one were both in the scene — and both drawn — until
## then, which a triangle count caught before an eye would have.
func apply_palette(p: Palette, new_form: int = -1) -> void:
	palette = p
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_views.clear()
	_body = null
	build(p, new_form)


func total_triangles() -> int:
	var n := 0
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh != null:
			for s in m.mesh.get_surface_count():
				n += m.mesh.surface_get_array_len(s) / 3
	return n


# --------------------------------------------------------------- assembly

func _add_view(v: View, canvas: PackedByteArray, colours: Array) -> void:
	var grid := _extrude(canvas)
	# Centre horizontally and in depth; feet at y = 0.
	var offset := Vector3(
		-float(SPRITE_WIDTH) * 0.5,
		0.0,
		-float(THICKNESS) * 0.5)
	var mesh := VoxelMesher.build(grid, colours, PIXEL, offset)
	if mesh.get_surface_count() == 0:
		return

	var mi := MeshInstance3D.new()
	mi.name = "View_%d" % v
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_body.add_child(mi)
	_views[v] = mi


## A 2D canvas becomes a solid slab: every opaque pixel is filled through the
## depth, so the greedy mesher produces front and back faces plus side walls
## that follow the silhouette exactly.
func _extrude(canvas: PackedByteArray) -> VoxelGrid:
	var g := VoxelGrid.new(SPRITE_WIDTH, SPRITE_HEIGHT, THICKNESS)
	for y in SPRITE_HEIGHT:
		for x in SPRITE_WIDTH:
			var v := canvas[x + SPRITE_WIDTH * y]
			if v == EMPTY:
				continue
			for z in THICKNESS:
				g.set_cell(x, y, z, v)
	return g


# ------------------------------------------------------------------ canvas

func _new_canvas() -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(SPRITE_WIDTH * SPRITE_HEIGHT)
	c.fill(EMPTY)
	return c


func _px(c: PackedByteArray, x: int, y: int, v: int) -> void:
	if x < 0 or x >= SPRITE_WIDTH or y < 0 or y >= SPRITE_HEIGHT:
		return
	c[x + SPRITE_WIDTH * y] = v


func _sample(c: PackedByteArray, x: int, y: int) -> int:
	if x < 0 or x >= SPRITE_WIDTH or y < 0 or y >= SPRITE_HEIGHT:
		return EMPTY
	return c[x + SPRITE_WIDTH * y]


func _rect(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int, v: int) -> void:
	for y in range(mini(y0, y1), maxi(y0, y1) + 1):
		for x in range(mini(x0, x1), maxi(x0, x1) + 1):
			_px(c, x, y, v)


## A tapered column, for a skirt that flares toward the hem.
func _taper(c: PackedByteArray, y0: int, y1: int, half_at_y0: float,
		half_at_y1: float, centre: float, v: int) -> void:
	for y in range(y0, y1 + 1):
		var t := float(y - y0) / maxf(float(y1 - y0), 1.0)
		var half := lerpf(half_at_y0, half_at_y1, t)
		_rect(c, int(round(centre - half)), y, int(round(centre + half - 1)), y, v)


## Shading pass: everything right of `from_x` takes its darker tone, giving a
## consistent light-from-the-left read. Scene lighting multiplies on top.
func _shade_right(c: PackedByteArray, from_x: int) -> void:
	for y in SPRITE_HEIGHT:
		for x in range(from_x, SPRITE_WIDTH):
			var v := _sample(c, x, y)
			if SHADE_OF.has(v):
				_px(c, x, y, SHADE_OF[v])


## Darken only the row where the figure meets the floor.
##
## An earlier version darkened every pixel whose right or lower neighbour was
## empty. On a round head that produced a thick jagged ring which read as
## spikes, and it fought the scene lighting rather than helping it. Pixel art
## gets its definition from deliberate shading, not from an automatic outline.
func _ground_contact(c: PackedByteArray) -> void:
	for x in SPRITE_WIDTH:
		# Only the bottom row, and never over the shoes: darkening two rows
		# turned her feet into a solid black bar.
		var v := _sample(c, x, 0)
		if v != EMPTY and v != SHOE:
			_px(c, x, 0, EDGE)


## Rectangle with its four corner pixels rounded off — the standard pixel-art
## way to round a small shape without antialiasing it.
##
## Each corner takes whatever is just beyond it rather than being cleared: on
## the silhouette that is nothing, which rounds the corner, and inside other
## geometry it is that geometry, which leaves it alone. The top two corners
## used to be set to EMPTY unconditionally, and since `_extrude` fills the
## whole depth, a shape drawn over existing geometry — her bun over her hair,
## every time — punched two 2.9 cm holes clean through the back of her head
## that the room showed through from behind. Which is the normal walking view.
func _round_rect(c: PackedByteArray, x0: int, y0: int, x1: int, y1: int,
		v: int) -> void:
	_rect(c, x0, y0, x1, y1, v)
	_px(c, x0, y0, _sample(c, x0, y0 - 1))
	_px(c, x1, y0, _sample(c, x1, y0 - 1))
	_px(c, x0, y1, _sample(c, x0, y1 + 1))
	_px(c, x1, y1, _sample(c, x1, y1 + 1))


# ------------------------------------------------------------------- views

const CENTRE := 17.0


## Head, drawn as explicit shapes rather than by masking an ellipse. At nine
## pixels across, a rounded rectangle reads as a head and an ellipse reads as a
## blob with ragged edges.
func _draw_head(c: PackedByteArray, cx: int, front: bool, profile: bool) -> void:
	_round_rect(c, cx - 4, 44, cx + 4, 54, SKIN)

	# Hair cap over the crown, and side locks. In profile the forward lock is
	# omitted: drawn on both sides it hung a block of hair in front of her face.
	_round_rect(c, cx - 5, 51, cx + 5, 55, HAIR)
	_rect(c, cx - 5, 48, cx - 4, 52, HAIR)
	if not profile:
		_rect(c, cx + 4, 48, cx + 5, 52, HAIR)

	if not front:
		# From behind, hair covers everything.
		for y in range(44, 56):
			for x in range(cx - 5, cx + 6):
				if _sample(c, x, y) == SKIN:
					_px(c, x, y, HAIR)
		# The bun, proud of the back of the head.
		_round_rect(c, cx - 2, 48, cx + 2, 52, HAIR_SHADE)
		return

	if profile:
		# In profile the far half of the head is hair, and the bun sits behind.
		for y in range(44, 56):
			for x in range(cx - 5, cx):
				if _sample(c, x, y) == SKIN:
					_px(c, x, y, HAIR)
		_round_rect(c, cx - 7, 47, cx - 4, 52, HAIR)
		_px(c, cx + 3, 49, EYE)
		_rect(c, cx + 3, 46, cx + 4, 46, SKIN_SHADE)
		return

	# Face: two eyes and the suggestion of a mouth.
	_px(c, cx - 2, 49, EYE)
	_px(c, cx + 2, 49, EYE)
	_rect(c, cx - 1, 46, cx + 1, 46, SKIN_SHADE)


func _front_canvas() -> PackedByteArray:
	if form == Build.TROUSERS:
		return _front_canvas_trousers()
	var c := _new_canvas()
	var cx := int(CENTRE)

	# Shoes, slightly apart.
	_rect(c, cx - 5, 0, cx - 1, 2, SHOE)
	_rect(c, cx + 1, 0, cx + 5, 2, SHOE)

	# A long skirt to the ankle, flaring toward the hem.
	_taper(c, 3, 27, 8.5, 6.0, CENTRE, DRESS)

	# Torso, then the cardigan over it, with the dress showing at the collar.
	_taper(c, 27, 43, 6.0, 7.5, CENTRE, DRESS)
	_taper(c, 30, 43, 6.5, 7.5, CENTRE, WRAP)
	_rect(c, cx - 1, 39, cx + 1, 43, DRESS)

	# Sleeves outside the body, with hands below them.
	_rect(c, cx - 9, 29, cx - 7, 41, WRAP)
	_rect(c, cx + 7, 29, cx + 9, 41, WRAP)
	_rect(c, cx - 9, 26, cx - 7, 29, SKIN)
	_rect(c, cx + 7, 26, cx + 9, 29, SKIN)

	# Neck, then head.
	_rect(c, cx - 1, 42, cx + 1, 45, SKIN)
	_draw_head(c, cx, true, false)

	_shade_right(c, cx + 2)
	_ground_contact(c)
	return c


func _side_canvas() -> PackedByteArray:
	if form == Build.TROUSERS:
		return _side_canvas_trousers()
	var c := _new_canvas()
	var cx := int(CENTRE)

	# In profile one foot shows, pointing forward (+x).
	_rect(c, cx - 3, 0, cx + 5, 2, SHOE)

	# Skirt in profile. Deep, not narrow: an earlier version was eight pixels
	# against the front view's nineteen, which read as a plank rather than a
	# person seen side-on.
	_taper(c, 3, 27, 7.0, 5.5, CENTRE + 0.5, DRESS)
	# The hem hangs a little at the back.
	_rect(c, cx - 8, 3, cx - 6, 15, DRESS_SHADE)

	# Torso with a stoop: the upper body leans forward as it rises.
	for y in range(27, 44):
		var lean := float(y - 27) / 17.0 * 2.0
		_rect(c, int(round(CENTRE - 5.5 + lean)), y,
			int(round(CENTRE + 5.0 + lean)), y, DRESS)
	for y in range(30, 44):
		var lean := float(y - 30) / 14.0 * 2.0
		_rect(c, int(round(CENTRE - 6.0 + lean)), y,
			int(round(CENTRE + 4.5 + lean)), y, WRAP)

	# The near arm, swung slightly forward, and its hand.
	_rect(c, cx + 2, 29, cx + 4, 41, WRAP_SHADE)
	_rect(c, cx + 2, 26, cx + 4, 29, SKIN_SHADE)

	# Neck and head, carried forward by the stoop.
	_rect(c, cx + 1, 42, cx + 3, 45, SKIN)
	_draw_head(c, cx + 2, true, true)

	_shade_right(c, cx + 4)
	_ground_contact(c)
	return c


func _back_canvas() -> PackedByteArray:
	if form == Build.TROUSERS:
		return _back_canvas_trousers()
	var c := _new_canvas()
	var cx := int(CENTRE)

	_rect(c, cx - 5, 0, cx - 1, 2, SHOE)
	_rect(c, cx + 1, 0, cx + 5, 2, SHOE)

	_taper(c, 3, 27, 8.5, 6.0, CENTRE, DRESS)
	_taper(c, 27, 43, 6.0, 7.5, CENTRE, DRESS)
	_taper(c, 30, 43, 6.5, 7.5, CENTRE, WRAP)

	_rect(c, cx - 9, 29, cx - 7, 41, WRAP)
	_rect(c, cx + 7, 29, cx + 9, 41, WRAP)
	_rect(c, cx - 9, 26, cx - 7, 29, SKIN)
	_rect(c, cx + 7, 26, cx + 9, 29, SKIN)

	_rect(c, cx - 1, 42, cx + 1, 45, SKIN)
	_draw_head(c, cx, false, false)

	_shade_right(c, cx + 2)
	_ground_contact(c)
	return c


# ------------------------------------------------------ the trousers build

## The same figure with three changes, which between them are the whole
## difference between the two builds at this size: trousers with a gap between
## the legs instead of a skirt, a squarer and slightly wider torso, and a short
## crop instead of a bun.
##
## The palette slots do not change — `dress` is the trousers and `wrap` is the
## jumper — so one set of swatches dresses either build, and the shading pass
## is shared.
func _draw_head_crop(c: PackedByteArray, cx: int, front: bool,
		profile: bool) -> void:
	# A squarer jaw. Her head is a rounded rectangle; his keeps the two corners
	# at the chin (y = 44 is the chin, y = 55 the crown).
	_rect(c, cx - 4, 44, cx + 4, 54, SKIN)

	# A short crop: a cap over the crown and a row down each side to the
	# temples, ending above the ears. It has to be four rows deep and joined to
	# the sides — at three rows and two loose pixels it read as a cap resting on
	# his head rather than as hair, which a flat render of the canvas showed at
	# once and the 3D one did not.
	_round_rect(c, cx - 5, 52, cx + 5, 55, HAIR)
	_rect(c, cx - 5, 50, cx - 5, 52, HAIR)
	_rect(c, cx + 5, 50, cx + 5, 52, HAIR)
	# Receding at the temples, which is most of what makes him his age.
	_px(c, cx - 4, 51, HAIR_SHADE)
	_px(c, cx + 4, 51, HAIR_SHADE)

	# Ears, which show on him because the hair stops above them.
	_px(c, cx - 5, 48, SKIN)
	_px(c, cx + 5, 48, SKIN)

	if not front:
		# The whole head, chin included. Stopping at y = 48 left his jaw
		# showing as bare skin from behind.
		for y in range(44, 56):
			for x in range(cx - 6, cx + 7):
				if _sample(c, x, y) == SKIN:
					_px(c, x, y, HAIR)
		# The back of a short haircut: a shaded nape rather than a bun.
		_rect(c, cx - 3, 47, cx + 3, 49, HAIR_SHADE)
		return

	if profile:
		for y in range(44, 56):
			for x in range(cx - 5, cx):
				if _sample(c, x, y) == SKIN:
					_px(c, x, y, HAIR)
		# The back of the head, which the cap alone does not cover in profile.
		_rect(c, cx - 6, 48, cx - 4, 53, HAIR)
		_px(c, cx + 3, 49, EYE)
		# A nose, one pixel proud of the face, then the brow and the mouth. At
		# this size that single pixel is most of what says "a man, in profile".
		_px(c, cx + 5, 47, SKIN)
		_rect(c, cx + 2, 50, cx + 4, 50, HAIR_SHADE)
		_rect(c, cx + 2, 45, cx + 4, 45, SKIN_SHADE)
		return

	_px(c, cx - 2, 49, EYE)
	_px(c, cx + 2, 49, EYE)
	# Heavy brows, directly over the eyes: the one feature that separates his
	# face from hers head-on.
	_rect(c, cx - 3, 50, cx - 1, 50, HAIR_SHADE)
	_rect(c, cx + 1, 50, cx + 3, 50, HAIR_SHADE)
	_rect(c, cx - 1, 45, cx + 1, 45, SKIN_SHADE)


## Trousers: two legs with daylight between them, which is the single strongest
## read at this size — her skirt is one solid taper to the hem.
func _draw_trousers(c: PackedByteArray, cx: int) -> void:
	_rect(c, cx - 6, 3, cx - 2, 26, DRESS)
	_rect(c, cx + 2, 3, cx + 6, 26, DRESS)
	# Seat and waist, where the legs join.
	_rect(c, cx - 6, 24, cx + 6, 29, DRESS)


func _front_canvas_trousers() -> PackedByteArray:
	var c := _new_canvas()
	var cx := int(CENTRE)

	# Bigger flatter shoes, set wider than hers.
	_rect(c, cx - 7, 0, cx - 2, 2, SHOE)
	_rect(c, cx + 2, 0, cx + 7, 2, SHOE)

	_draw_trousers(c, cx)

	# Torso: straight sided and a little broader than hers, in the jumper, with
	# the collar of a shirt open at the neck.
	_taper(c, 29, 43, 7.0, 7.5, CENTRE, WRAP)
	_rect(c, cx - 2, 41, cx + 2, 43, SKIN_SHADE)

	# Sleeves outside the body, hands below them. His shoulders are a pixel
	# wider each side.
	_rect(c, cx - 10, 29, cx - 7, 41, WRAP)
	_rect(c, cx + 7, 29, cx + 10, 41, WRAP)
	_rect(c, cx - 10, 25, cx - 7, 29, SKIN)
	_rect(c, cx + 7, 25, cx + 10, 29, SKIN)

	# A thicker neck, then the head.
	_rect(c, cx - 2, 42, cx + 2, 45, SKIN)
	_draw_head_crop(c, cx, true, false)

	_shade_right(c, cx + 2)
	_ground_contact(c)
	return c


func _side_canvas_trousers() -> PackedByteArray:
	var c := _new_canvas()
	var cx := int(CENTRE)

	# One foot, pointing forward (+x).
	_rect(c, cx - 4, 0, cx + 6, 2, SHOE)

	# The near leg, with the far one a shade behind it.
	_taper(c, 3, 27, 4.0, 3.5, CENTRE - 1.5, DRESS_SHADE)
	_taper(c, 3, 27, 4.0, 3.5, CENTRE + 1.0, DRESS)
	_rect(c, cx - 5, 24, cx + 4, 29, DRESS)

	# Torso with a slight stoop — less than hers; he is lying down most of the
	# time she is walking, and upright is how she remembers him.
	for y in range(29, 44):
		var lean := float(y - 29) / 15.0 * 1.5
		_rect(c, int(round(CENTRE - 5.0 + lean)), y,
			int(round(CENTRE + 5.0 + lean)), y, WRAP)

	# The near arm, hanging, and its hand.
	_rect(c, cx + 2, 29, cx + 5, 41, WRAP_SHADE)
	_rect(c, cx + 2, 25, cx + 5, 29, SKIN_SHADE)

	_rect(c, cx + 1, 42, cx + 3, 45, SKIN)
	_draw_head_crop(c, cx + 2, true, true)

	_shade_right(c, cx + 4)
	_ground_contact(c)
	return c


func _back_canvas_trousers() -> PackedByteArray:
	var c := _new_canvas()
	var cx := int(CENTRE)

	_rect(c, cx - 7, 0, cx - 2, 2, SHOE)
	_rect(c, cx + 2, 0, cx + 7, 2, SHOE)

	_draw_trousers(c, cx)

	_taper(c, 29, 43, 7.0, 7.5, CENTRE, WRAP)

	_rect(c, cx - 10, 29, cx - 7, 41, WRAP)
	_rect(c, cx + 7, 29, cx + 10, 41, WRAP)
	_rect(c, cx - 10, 25, cx - 7, 29, SKIN)
	_rect(c, cx + 7, 25, cx + 10, 29, SKIN)

	_rect(c, cx - 2, 42, cx + 2, 45, SKIN)
	_draw_head_crop(c, cx, false, false)

	_shade_right(c, cx + 2)
	_ground_contact(c)
	return c

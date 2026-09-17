class_name PhotoFrame
extends Node3D
## One hung photograph: moulding, mount board, image, and its accent light.
##
## Every frame is the SAME physical size. The photograph's aspect is absorbed
## by the mount board in the shader (plan §4.3), so ten frames holding a mix of
## portrait and landscape still read as one set.
##
## The accent light does double duty: it makes the wall look lit by intent
## rather than ambience, and it draws the eye to the next photograph, which is
## the only wayfinding a corridor needs.

## Museum scale: roughly two metres across, so a photograph reads as a work
## rather than a snapshot. The mount board absorbs each photo's aspect, so
## every frame is still physically identical (plan §4.3).
const OPENING_WIDTH := 2.12
const OPENING_HEIGHT := 1.74
const MOULDING_WIDTH := 0.14
const MOULDING_DEPTH := 0.11
const BOARD_DEPTH := 0.035

## Blur strength per tier, in texels. Tier textures get smaller as the tier
## drops, so a constant texel radius already means a much heavier world-space
## blur at tier 0 — these values only shape the curve on top of that.
const TIER_BLUR := [3.4, 2.8, 2.2, 1.6]
const REVEALED_BLUR := 0.0

## Depth of the volume in front of the picture that counts as "at this
## photograph". Generous, because a two-metre picture is looked at from a
## couple of metres back.
const INTERACTION_DEPTH := 2.9
const INTERACTION_WIDTH := 2.6
const INTERACTION_HEIGHT := 2.6

var photo: AlbumSchema.Photo = null
var tier: int = 0
var revealed: bool = false
## Entered by the player; the round controller watches this to know she has
## arrived at a picture.
var interaction_area: Area3D = null

var _material: ShaderMaterial = null
var _accent: SpotLight3D = null
var _surface: MeshInstance3D = null


static func opening_aspect() -> float:
	return OPENING_WIDTH / OPENING_HEIGHT


## Build the frame for a photo. `tex` is the tier-0 texture to start with.
func setup(p: AlbumSchema.Photo, tex: Texture2D) -> void:
	photo = p
	name = "Frame_%s" % p.id

	_build_moulding()
	_build_surface(tex)
	_build_accent()
	_build_interaction()

	set_tier(0)


func set_tier(new_tier: int) -> void:
	tier = clampi(new_tier, 0, TIER_BLUR.size() - 1)
	if _material != null and not revealed:
		_material.set_shader_parameter("blur_strength", TIER_BLUR[tier])


func set_texture(tex: Texture2D) -> void:
	if _material != null and tex != null:
		_material.set_shader_parameter("photo_tex", tex)


## Swap in the full-resolution image and drop the blur entirely.
func reveal(full_tex: Texture2D) -> void:
	revealed = true
	if _material == null:
		return
	if full_tex != null:
		_material.set_shader_parameter("photo_tex", full_tex)
	_material.set_shader_parameter("blur_strength", REVEALED_BLUR)
	if _accent != null:
		# Lift the light a touch on reveal: the room notices.
		_accent.light_energy = 3.4


func accent_light() -> SpotLight3D:
	return _accent


# --- construction ---

func _build_surface(tex: Texture2D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(OPENING_WIDTH, OPENING_HEIGHT)

	_material = ShaderMaterial.new()
	_material.shader = load("res://src/photo/photo_frame.gdshader")
	_material.set_shader_parameter("photo_aspect",
		photo.aspect if photo != null and photo.aspect > 0.0 else 1.5)
	_material.set_shader_parameter("opening_aspect", opening_aspect())
	if tex != null:
		_material.set_shader_parameter("photo_tex", tex)

	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.mesh = quad
	_surface.material_override = _material
	# The quad faces +Z by default; the frame node itself is oriented by the
	# wall anchor, so the surface only needs to sit proud of the board.
	_surface.position = Vector3(0, 0, BOARD_DEPTH)
	add_child(_surface)


func _build_moulding() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.105, 0.085)
	mat.roughness = 0.45
	mat.metallic = 0.12
	mat.metallic_specular = 0.4

	var hw := OPENING_WIDTH * 0.5
	var hh := OPENING_HEIGHT * 0.5
	var m := MOULDING_WIDTH
	var d := MOULDING_DEPTH

	# Four rails plus a backing board.
	var pieces := [
		{"size": Vector3(OPENING_WIDTH + m * 2.0, m, d),
		 "pos": Vector3(0, hh + m * 0.5, d * 0.5)},
		{"size": Vector3(OPENING_WIDTH + m * 2.0, m, d),
		 "pos": Vector3(0, -hh - m * 0.5, d * 0.5)},
		{"size": Vector3(m, OPENING_HEIGHT, d),
		 "pos": Vector3(hw + m * 0.5, 0, d * 0.5)},
		{"size": Vector3(m, OPENING_HEIGHT, d),
		 "pos": Vector3(-hw - m * 0.5, 0, d * 0.5)},
		{"size": Vector3(OPENING_WIDTH, OPENING_HEIGHT, BOARD_DEPTH),
		 "pos": Vector3(0, 0, BOARD_DEPTH * 0.5)},
	]

	for piece in pieces:
		var box := BoxMesh.new()
		box.size = piece["size"]
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.position = piece["pos"]
		mi.material_override = mat
		add_child(mi)


func _build_interaction() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "Interaction"
	# Only the player is on layer 1; nothing else should trip this.
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 1
	interaction_area.monitorable = false

	var shape := BoxShape3D.new()
	shape.size = Vector3(INTERACTION_WIDTH, INTERACTION_HEIGHT, INTERACTION_DEPTH)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# Centred in front of the picture and dropped toward standing height, so
	# the volume is where a person is rather than where the frame is.
	cs.position = Vector3(0, -0.45, INTERACTION_DEPTH * 0.5)
	interaction_area.add_child(cs)
	add_child(interaction_area)


func _build_accent() -> void:
	_accent = SpotLight3D.new()
	_accent.name = "Accent"
	# Above and in front, angled down at the picture — a gallery wall-washer.
	_accent.position = Vector3(0, OPENING_HEIGHT * 0.5 + 0.95, 1.35)
	_accent.rotation_degrees = Vector3(-38, 0, 0)
	_accent.light_color = Color(1.0, 0.93, 0.82)
	_accent.light_energy = 0.9
	_accent.spot_range = 6.5
	_accent.spot_angle = 38.0
	_accent.spot_angle_attenuation = 1.2
	# No shadow map. An accent light washes a flat wall from close range, so it
	# has nothing meaningful to shadow — and ten shadow-casting spots in one
	# corridor is real cost the WebGL 2 renderer has no headroom for. The
	# window lights carry the shadows that define the space.
	_accent.shadow_enabled = false
	add_child(_accent)

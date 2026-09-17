class_name LightShaft
extends MeshInstance3D
## A fake volumetric light shaft from a window.
##
## The Compatibility renderer has no volumetric fog, so the shafts that make a
## dusty gallery read as dusty have to be geometry: a slab reaching from the
## window opening across the hall, additive, fading at its edges, along its
## travel, and against the depth buffer. At the raking angles a corridor gives
## you this is close to the real thing (plan §6.3) for one transparent box.
##
## Orientation matters more than it looks. The window anchors are built with
## local +Z pointing into the hall, so the slab must extend along its own local
## Z. An earlier version built it along local X and rotated the node, which put
## a five-metre slab running lengthwise DOWN the corridor and displaced two and
## a half metres from its window — from the near end you looked straight
## through all ten of them and the hall filled with white.
##
## The fades are therefore computed from model-space position rather than UV:
## a BoxMesh's UVs differ per face, so there is no single UV axis that means
## "distance travelled from the window".

const SHADER := """
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 shaft_color : source_color = vec3(1.0, 0.94, 0.80);
uniform float intensity : hint_range(0.0, 1.0) = 0.10;

// Slab dimensions in model space: x = along the hall, y = vertical,
// z = distance travelled from the window.
uniform float half_width = 0.8;
uniform float half_height = 1.3;
uniform float span = 5.0;

uniform float edge_softness : hint_range(0.01, 1.0) = 0.55;
uniform float travel_fade : hint_range(0.0, 1.0) = 0.8;
uniform float depth_fade : hint_range(0.1, 20.0) = 1.8;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Soft in the two cross-section axes so the slab has no hard silhouette.
	float fx = 1.0 - smoothstep(1.0 - edge_softness, 1.0,
		abs(v_local.x) / max(half_width, 0.001));
	float fy = 1.0 - smoothstep(1.0 - edge_softness, 1.0,
		abs(v_local.y) / max(half_height, 0.001));

	// Dimmer the further the beam has come from the window.
	float travelled = clamp(v_local.z / max(span, 0.001), 0.0, 1.0);
	float ft = mix(1.0, 1.0 - travelled, travel_fade);

	// Fade where the slab meets solid geometry, so it does not draw a visible
	// seam across the floor or a picture frame.
	float scene_depth = texture(depth_texture, SCREEN_UV).x;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	view.xyz /= view.w;
	float behind = -view.z + VERTEX.z;
	float occl = clamp(behind / depth_fade, 0.0, 1.0);

	ALBEDO = shaft_color;
	ALPHA = fx * fy * ft * occl * intensity;
}
"""

var _material: ShaderMaterial = null


## `window_size` is the opening (width along the hall, height). `span` is how
## far the beam reaches across the hall. The slab extends along local +Z, which
## the window anchor points into the hall.
func setup(window_size: Vector2, span: float, energy: float = 0.10) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(window_size.x, window_size.y, span)
	mesh = box
	position = Vector3(0, 0, span * 0.5)

	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("intensity", energy)
	_material.set_shader_parameter("half_width", window_size.x * 0.5)
	_material.set_shader_parameter("half_height", window_size.y * 0.5)
	_material.set_shader_parameter("span", span)
	material_override = _material

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = -0.5


func set_energy(energy: float) -> void:
	if _material != null:
		_material.set_shader_parameter("intensity", energy)

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// One material draws both the mount board and the photograph, with the window
// cut from the photo's own aspect ratio at runtime.
//
// This is what lets ten hand-placed frames of IDENTICAL physical size hold a
// mix of portrait, landscape and square photographs without stretching any of
// them — the mat takes up the difference, exactly as a real gallery does
// (plan §4.3). A portrait gets wide side margins, a landscape gets deep top
// and bottom margins, and the frames all still read as one set.
//
// The blur is also here. Tier textures are tiny by design (tier 0 is 64 px),
// so a few taps at display time turn bilinear upscale facets into real haze.
// Note what this shader never does: blur the FULL-RESOLUTION image. At guess
// time that texture is not even loaded, which is the whole point of the
// resolution-based ladder.

uniform sampler2D photo_tex : source_color, filter_linear_mipmap;

// width / height of the photograph.
uniform float photo_aspect = 1.5;
// width / height of the frame opening this material is stretched across.
uniform float opening_aspect = 1.222;

// Fraction of the opening the photo may occupy before the mat takes over.
uniform float max_fill : hint_range(0.5, 1.0) = 0.92;
// Floor on the short dimension, so a panorama does not become a letterbox
// slit inside an otherwise square frame.
uniform float min_fill : hint_range(0.1, 1.0) = 0.34;

// 0 = untouched, rising with the blur tier. Scaled by texel size, so a 64 px
// tier blurs far more in world space than a 512 px one for the same value.
uniform float blur_strength : hint_range(0.0, 8.0) = 3.0;

// Mid-tone, not near-white: a bright board under an accent light plus the
// window wash clipped to featureless white and took the photograph with it.
uniform vec3 mat_color : source_color = vec3(0.56, 0.53, 0.47);
uniform vec3 photo_tint : source_color = vec3(0.80, 0.79, 0.76);
// Depth cue where the mount board meets the photograph.
uniform float bevel_width : hint_range(0.0, 0.05) = 0.012;
uniform float bevel_strength : hint_range(0.0, 1.0) = 0.55;

uniform float roughness_mat : hint_range(0.0, 1.0) = 0.92;
uniform float roughness_photo : hint_range(0.0, 1.0) = 0.42;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

// The photo window in the opening's UV space, as (min, max).
void window_rect(out vec2 lo, out vec2 hi) {
	// Ratio of the photo's shape to the opening's shape. Above 1 the photo is
	// relatively wider, so width binds; below 1, height binds.
	float ratio = photo_aspect / opening_aspect;

	vec2 fill;
	if (ratio >= 1.0) {
		fill = vec2(max_fill, max_fill / ratio);
	} else {
		fill = vec2(max_fill * ratio, max_fill);
	}

	fill = clamp(fill, vec2(min_fill), vec2(max_fill));

	vec2 margin = (vec2(1.0) - fill) * 0.5;
	lo = margin;
	hi = vec2(1.0) - margin;
}

void fragment() {
	vec2 lo;
	vec2 hi;
	window_rect(lo, hi);

	vec2 inside = step(lo, v_uv) * step(v_uv, hi);
	float in_window = inside.x * inside.y;

	// Photo UVs, remapped so the image fills the window exactly.
	vec2 puv = (v_uv - lo) / max(hi - lo, vec2(0.0001));

	// Nine-tap separable-ish gaussian in texel space.
	vec2 texel = 1.0 / vec2(textureSize(photo_tex, 0));
	vec2 step_uv = texel * blur_strength;

	vec3 photo = texture(photo_tex, puv).rgb * 0.2270270270;
	photo += texture(photo_tex, puv + vec2(step_uv.x, 0.0)).rgb * 0.1945945946;
	photo += texture(photo_tex, puv - vec2(step_uv.x, 0.0)).rgb * 0.1945945946;
	photo += texture(photo_tex, puv + vec2(0.0, step_uv.y)).rgb * 0.1945945946;
	photo += texture(photo_tex, puv - vec2(0.0, step_uv.y)).rgb * 0.1945945946;
	photo += texture(photo_tex, puv + step_uv * 0.7071).rgb * 0.0603603604;
	photo += texture(photo_tex, puv - step_uv * 0.7071).rgb * 0.0603603604;
	photo += texture(photo_tex, puv + vec2(step_uv.x, -step_uv.y) * 0.7071).rgb * 0.0603603604;
	photo += texture(photo_tex, puv + vec2(-step_uv.x, step_uv.y) * 0.7071).rgb * 0.0603603604;
	photo /= 1.0475;
	photo *= photo_tint;

	// A darkened lip just inside the window edge: the mount board has
	// thickness, and without this the photo looks printed onto the mat.
	vec2 edge = min(v_uv - lo, hi - v_uv);
	float d = min(edge.x, edge.y);
	float bevel = 1.0 - bevel_strength * (1.0 - smoothstep(0.0, bevel_width, d));

	ALBEDO = mix(mat_color, photo * bevel, in_window);
	ROUGHNESS = mix(roughness_mat, roughness_photo, in_window);
	SPECULAR = mix(0.18, 0.5, in_window);
}

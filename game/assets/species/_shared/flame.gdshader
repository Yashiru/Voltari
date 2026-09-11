shader_type spatial;
render_mode blend_add, cull_back, unshaded, depth_draw_never, shadows_disabled;

// Reproduces the in-game tail-flame effect.
//
// Neither source texture holds colour — both are channel-packed masks, which is
// why a plain glTF export gives a dead blob. Measured from the assets:
//
//   FireCoreCombo (64x128)   R = core silhouette   G = hot sparks
//     top/bottom seam 2.4 -> tiles vertically, and the mesh UVs run to
//     v = 1.83, so this layer is built to scroll in V.
//
//   FireStenCombo (128x128)  R = flicker   G = second flicker   B = vertical ramp
//     left/right seam 3.1 -> tiles horizontally, so this layer scrolls in U:
//     the outer flame swirls around its axis.
//
// The two surfaces are therefore driven differently — LAYER_CORE for the inner
// body, LAYER_STEN for the outer shell. Colour comes from uniforms; the in-game
// constants are not recoverable from the FBX, so these are tuned by eye.

const int LAYER_CORE = 0;
const int LAYER_STEN = 1;

uniform int layer : hint_range(0, 1) = 0;

uniform sampler2D core_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D sten_tex : repeat_enable, filter_linear_mipmap;

uniform vec3 colour_low : source_color = vec3(0.90, 0.13, 0.01);
uniform vec3 colour_mid : source_color = vec3(1.00, 0.52, 0.05);
uniform vec3 colour_hot : source_color = vec3(1.00, 0.95, 0.70);

uniform float core_scroll = 0.55;   // V, upward
uniform float sten_scroll = 0.20;   // U, around the axis
uniform float intensity = 1.9;
uniform float cutoff : hint_range(0.0, 1.0) = 0.06;
uniform float softness : hint_range(0.01, 0.8) = 0.34;
uniform float opacity : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float t = TIME;
	float mask;
	float hot;

	if (layer == LAYER_CORE) {
		vec4 c = texture(core_tex, vec2(UV.x, UV.y - t * core_scroll));
		// A touch of the flicker layer keeps the core edge from looking cut out.
		float edge = texture(sten_tex, vec2(UV.x + t * sten_scroll * 0.5, UV.y)).r;
		mask = c.r * (0.72 + 0.28 * edge);
		hot = max(c.g, c.r * 0.55);
	} else {
		vec4 s1 = texture(sten_tex, vec2(UV.x + t * sten_scroll, UV.y));
		vec4 s2 = texture(sten_tex, vec2(UV.x - t * sten_scroll * 0.71 + 0.41, UV.y));
		float flicker = max(s1.r, s2.g);
		mask = flicker * mix(0.35, 1.0, s1.b);
		hot = s1.r * s2.g;
	}

	mask = clamp(mask, 0.0, 1.0);
	float heat = clamp(hot * 0.85 + mask * 0.55, 0.0, 1.0);

	vec3 col = mix(colour_low, colour_mid, smoothstep(0.02, 0.45, heat));
	col = mix(col, colour_hot, smoothstep(0.5, 0.95, heat));

	ALBEDO = col;
	EMISSION = col * intensity;
	ALPHA = clamp(smoothstep(cutoff, cutoff + softness, mask) * opacity, 0.0, 1.0);
}

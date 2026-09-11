shader_type spatial;

// Printed-comic surface for the creatures — a second look, sitting beside
// `toon.gdshader` rather than replacing it. Pick one with the `style` property
// on the species root, or `style=bd` on the viewer's command line.
//
// Where the toon shader models a painted figure — soft bands, a tinted
// highlight, a rim — this one models a *drawn* one. Three things carry it, and
// none of them is a light:
//
//   1. two tones      - lit and shadow, one hard edge, no gradient between them
//   2. screentone     - the shadow is not darker paint, it is printed dots, in
//                       screen space, on a 45 degree grid like a real halftone
//   3. ink            - the silhouette line comes from the outline pass as
//                       before, and the interior lines are drawn here from the
//                       curvature of the surface
//
// There is no highlight at all. A gloss blob is a painting device; ink and
// screentone are a printing one, and mixing them reads as neither.
//
// **This pass is `unshaded` and lights itself** from `light_direction`. That is
// the price of the screentone: the dots have to be laid out in screen space
// against the same shading value that chooses the tone, and Godot's `light()`
// stage runs once per light with no screen coordinates to hand. Lighting the
// surface here instead makes the result identical under every scene, which is
// what a printed page wants — and it means a coloured or moving scene light
// will not touch these creatures. That is a real limitation, not an oversight.

render_mode blend_mix, cull_back, unshaded, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Cell offset for the face sheets. Zero on every other surface, which is why the
// body and the eyes can share one shader.
uniform vec2 uv_offset = vec2(0.0, 0.0);

group_uniforms paint;
uniform float saturation : hint_range(0.5, 3.0) = 1.6;
uniform float lift : hint_range(0.0, 0.5) = 0.10;
// Print has a limited number of inks. Snapping the artwork to a few levels per
// channel is what turns a rendered gradient into flat fill; below 2 it is off.
uniform float flat_levels : hint_range(0.0, 16.0) = 6.0;

group_uniforms lighting;
// Where the key light comes from, in world space. Normalised in the shader, so
// any length will do.
uniform vec3 light_direction = vec3(-0.4, 0.8, 0.55);
// How far round the form the lit tone reaches. 0.5 puts the edge on the
// geometric terminator; higher pulls it towards the light and leaves more
// shadow, which reads as stronger drawing.
uniform float terminator : hint_range(0.0, 1.0) = 0.46;
// Kept small on purpose. This edge is the drawing — softening it is the one
// change that turns the whole look back into a render.
uniform float terminator_softness : hint_range(0.001, 0.2) = 0.018;
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.68, 0.86, 1.0);
uniform float shadow_depth : hint_range(0.0, 1.0) = 0.26;

group_uniforms screentone;
uniform float dots_amount : hint_range(0.0, 1.0) = 0.45;
// Side of one dot cell, in pixels. Screen space, not UV: a halftone belongs to
// the paper, so it must not scale with the model or slide with the surface.
uniform float dots_size : hint_range(2.0, 32.0) = 11.0;
uniform float dots_angle : hint_range(0.0, 90.0) = 45.0;
// Largest a dot grows, as a share of its cell. At 1.0 the deepest shadow fills
// solid and the tone is lost.
uniform float dots_max : hint_range(0.1, 1.2) = 0.60;
uniform float dots_softness : hint_range(0.0, 0.5) = 0.12;

group_uniforms ink;
uniform vec4 ink_colour : source_color = vec4(0.09, 0.08, 0.13, 1.0);
// Interior lines, drawn where the surface bends. The silhouette is the outline
// pass's job; this is what puts a line round a jaw or a joint.
uniform float crease_ink : hint_range(0.0, 1.0) = 0.70;
uniform float crease_bias : hint_range(0.0, 0.5) = 0.025;
uniform float crease_width : hint_range(0.001, 0.3) = 0.045;

varying vec3 world_normal;

// Push a colour away from its own luminance. Keeps the hue, lifts the paint.
vec3 enrich(vec3 colour) {
	float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	vec3 richer = mix(vec3(luma), colour, saturation);
	return clamp(richer + lift * richer, vec3(0.0), vec3(1.0));
}

// Snap each channel to a fixed number of levels — the ink count of a press.
vec3 flatten(vec3 colour) {
	if (flat_levels < 2.0) {
		return colour;
	}
	return floor(colour * flat_levels + 0.5) / flat_levels;
}

// A halftone cell's coverage at this pixel, for a dot of radius `radius`.
// Returns 1 inside the dot, 0 outside, with a soft rim so it does not crawl.
float halftone(vec2 pixel, float radius) {
	float angle = radians(dots_angle);
	mat2 turn = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	vec2 cell = fract(turn * (pixel / max(dots_size, 1.0))) - 0.5;
	// Doubled so `distance` runs 0 at the centre to 1 at the cell edge, which
	// makes `radius` read directly as a share of the cell.
	float distance = length(cell) * 2.0;
	float soft = max(dots_softness, 0.001);
	return smoothstep(radius + soft, radius - soft, distance);
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 paper = flatten(enrich(texture(albedo_tex, fract(UV + uv_offset)).rgb));

	// Lit or shadow, and nothing in between.
	float facing = dot(normalize(world_normal), normalize(light_direction)) * 0.5 + 0.5;
	float lit = smoothstep(terminator - terminator_softness,
			terminator + terminator_softness, facing);

	vec3 shade = paper * mix(vec3(1.0), shadow_tint.rgb, shadow_depth);
	vec3 colour = mix(shade, paper, lit);

	// The dots grow with how far past the terminator the surface has turned, not
	// with the stepped tone — that is what gives a screentone its ramp instead of
	// a flat field of identical dots.
	float depth = clamp((terminator - facing) / max(terminator, 0.001), 0.0, 1.0);
	float dots = halftone(SCREEN_UV * VIEWPORT_SIZE, depth * dots_max);
	colour = mix(colour, ink_colour.rgb, dots * dots_amount * (1.0 - lit));

	// How fast the normal turns across one pixel: high on a fold, near zero on a
	// flat panel. The toon shader tints with this; here it is a line.
	float bend = length(fwidth(NORMAL));
	float line = smoothstep(crease_bias, crease_bias + crease_width, bend);
	colour = mix(colour, ink_colour.rgb, line * crease_ink);

	ALBEDO = colour;
}

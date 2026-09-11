shader_type spatial;

// Cartoon / chibi surface for the creatures. One shader for the body and for
// the eye decal, because they meet on the cheek and any difference in finish
// shows as a seam there.
//
// The problem it exists to solve: these models are large areas of one flat
// colour, so smooth lambert lighting leaves them reading as silhouettes with no
// interior form. Four things put the shape back, in rough order of how much
// they contribute:
//
//   1. banded diffuse   - a hard terminator states where the form turns
//   2. crease shading   - darkens where the surface bends, from the rate of
//                         change of the normal, so folds and joins read even on
//                         a single colour with no baked occlusion available
//   3. rim light        - lifts the silhouette off the background
//   4. ground shading   - a gentle vertical gradient, so undersides sit down
//
// The colour is pushed towards its own hue rather than simply brightened:
// saturation lifts the paint, and the shadow is tinted cool instead of grey so
// the lit side reads warmer by contrast. Flat multiplication by grey is what
// makes stylised models look muddy.

render_mode blend_mix, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Cell offset for the eye atlas. Zero on every other surface, which is why the
// body and the eyes can share one shader.
uniform vec2 uv_offset = vec2(0.0, 0.0);

group_uniforms colour;
uniform float saturation : hint_range(0.5, 2.5) = 1.35;
uniform float lift : hint_range(0.0, 0.5) = 0.06;

group_uniforms lighting;
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float band_softness : hint_range(0.001, 0.3) = 0.035;
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.47, 0.68, 1.0);
uniform float wrap : hint_range(0.0, 1.0) = 0.35;

group_uniforms form;
uniform float crease_strength : hint_range(0.0, 3.0) = 1.15;
uniform float crease_bias : hint_range(0.0, 0.5) = 0.02;
uniform vec4 crease_tint : source_color = vec4(0.30, 0.36, 0.52, 1.0);
uniform float ground_shade : hint_range(0.0, 1.0) = 0.22;

group_uniforms highlight;
uniform float spec_sharpness : hint_range(1.0, 128.0) = 28.0;
uniform float spec_edge : hint_range(0.0, 1.0) = 0.42;
uniform float spec_strength : hint_range(0.0, 2.0) = 0.35;
// Edge width as a fraction of the threshold rather than an absolute number, so
// the blob keeps the same crispness whether it lands on a broad belly or a
// tight limb. A fixed width reads hard on one and mushy on the other.
uniform float spec_softness : hint_range(0.0, 0.5) = 0.08;
// How much the highlight gives way on an already-bright surface. A fixed white
// blob blows out a dark wing and turns into a pale stain on a yellow body;
// scaling it by the room left above the surface's own brightness keeps it
// reading the same on both. This is the control that matters most.
uniform float spec_adapt : hint_range(0.0, 1.0) = 0.65;
// Pulls the highlight towards the creature's own colour, so it belongs to the
// paint instead of sitting on top of it as a foreign white patch.
uniform float spec_tint : hint_range(0.0, 1.0) = 0.35;
// Concentrates the highlight towards grazing angles, so it follows the form
// rather than parking as a dot in the middle of a flat panel.
uniform float spec_fresnel : hint_range(0.0, 1.0) = 0.40;
uniform float rim_width : hint_range(0.0, 1.0) = 0.42;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec4 rim_colour : source_color = vec4(1.0, 0.97, 0.88, 1.0);

varying vec3 world_normal;

// Push a colour away from its own luminance. Keeps the hue, lifts the paint.
vec3 enrich(vec3 colour) {
	float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	vec3 richer = mix(vec3(luma), colour, saturation);
	return clamp(richer + lift * richer, vec3(0.0), vec3(1.0));
}

// Quantise into steps with a controllable edge, rather than the hard floor()
// that aliases badly on a curved surface.
float step_bands(float value, float count, float softness) {
	float scaled = value * count;
	float lower = floor(scaled);
	float edge = smoothstep(0.5 - softness, 0.5 + softness, scaled - lower);
	return clamp((lower + edge) / count, 0.0, 1.0);
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 colour = enrich(texture(albedo_tex, fract(UV + uv_offset)).rgb);

	// How fast the normal turns across one pixel. High on a fold, near zero on
	// a flat panel — a curvature signal that needs no baked map, which matters
	// because none of these models ship one.
	float bend = length(fwidth(NORMAL));
	float crease = clamp((bend - crease_bias) * crease_strength, 0.0, 1.0);
	colour = mix(colour, colour * crease_tint.rgb, crease);

	// Undersides sit down, tops catch the sky. Subtle on purpose: enough to
	// give a chibi body weight, not enough to read as a second light.
	float sky = world_normal.y * 0.5 + 0.5;
	colour *= mix(1.0 - ground_shade, 1.0, sky);

	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;

	float rim = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	EMISSION = rim_colour.rgb * smoothstep(1.0 - rim_width, 1.0, rim) * rim_strength;
}

void light() {
	// Wrapped so the unlit side keeps its colour instead of going black, then
	// banded so the terminator is a statement rather than a gradient.
	float raw = dot(normalize(NORMAL), normalize(LIGHT));
	float wrapped = (raw + wrap) / (1.0 + wrap);
	float level = step_bands(clamp(wrapped, 0.0, 1.0), bands, band_softness);

	vec3 shaded = mix(shadow_tint.rgb, vec3(1.0), level);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * shaded;

	vec3 half_vector = normalize(VIEW + LIGHT);
	float gloss = pow(clamp(dot(normalize(NORMAL), half_vector), 0.0, 1.0),
			spec_sharpness);
	float edge = max(spec_edge * spec_softness, 0.001);
	float blob = smoothstep(spec_edge - edge, spec_edge + edge, gloss);

	// Grazing angles keep more of the highlight, so it hugs the silhouette.
	float grazing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	blob *= mix(1.0, grazing, spec_fresnel);

	float luma = dot(ALBEDO, vec3(0.2126, 0.7152, 0.0722));
	float room = mix(1.0, 1.0 - luma, spec_adapt);
	// Lifted towards white before tinting, or a dark surface would drag its own
	// highlight down to nothing and the adaptation would be counted twice.
	vec3 hue = mix(vec3(1.0), clamp(ALBEDO + vec3(0.35), 0.0, 1.0), spec_tint);

	SPECULAR_LIGHT += blob * spec_strength * room * hue * LIGHT_COLOR * ATTENUATION;
}

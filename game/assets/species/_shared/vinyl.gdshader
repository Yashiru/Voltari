shader_type spatial;

// Matte soft-toy surface — the control, not the contender.
//
// This is the look a monster-collecting game usually ships: a vinyl figure under
// a soft key, no bands, no gloss, and colour doing the work that contrast does
// elsewhere. Animal Crossing and Sword/Shield both live here. It exists so the
// printed look has something honest to be compared against: if `comic` does not
// beat this clearly on the same creature in the same pose, the printed direction
// is a detour and not a decision.
//
// Three things and no more:
//
//   1. a wrapped terminator, soft on purpose — the opposite of `comic`, where the
//      hard edge *is* the drawing. Here the form turns rather than steps.
//   2. warm towards the light, cool away from it. On a flat painted atlas this is
//      what reads as volume; multiplying by grey is what reads as dirt.
//   3. nothing specular at all. A vinyl figure is matte, and the moment a
//      highlight appears the creature reads as plastic rather than as a toy.
//
// Unlike `comic` this pass is lit normally, so scene lights reach it. That is
// half the point of having it: it tells you what you give up by lighting the
// printed look inside its own shader.

render_mode blend_mix, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Cell offset for the face sheets. Zero on every other surface.
uniform vec2 uv_offset = vec2(0.0, 0.0);

group_uniforms paint;
uniform float saturation : hint_range(0.5, 2.5) = 1.35;
uniform float lift : hint_range(0.0, 0.5) = 0.04;

group_uniforms surface;
// How far past the geometric terminator the light carries. High on purpose: a
// soft toy has no sharp shadow line on it, and this is the single control that
// separates this look from every other one in the set.
uniform float wrap : hint_range(0.0, 1.0) = 0.55;
uniform vec4 shadow_hue : source_color = vec4(0.54, 0.60, 0.80, 1.0);
uniform float shadow_hue_mix : hint_range(0.0, 1.0) = 0.28;
uniform vec4 light_hue : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float light_hue_mix : hint_range(0.0, 1.0) = 0.10;

group_uniforms volume;
// Sky above, ground below. Welcome here, where everything is smooth anyway.
uniform float ground_shade : hint_range(0.0, 0.6) = 0.08;

varying vec3 world_normal;

vec3 enrich(vec3 colour) {
	float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	vec3 richer = mix(vec3(luma), colour, saturation);
	return clamp(richer + lift * richer, vec3(0.0), vec3(1.0));
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 colour = enrich(texture(albedo_tex, fract(UV + uv_offset)).rgb);

	float sky = normalize(world_normal).y * 0.5 + 0.5;
	colour *= mix(1.0 - ground_shade, 1.0, sky);

	ALBEDO = colour;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	// Wrapped, and left as a gradient. No banding: the whole point of this look
	// is that the terminator is not a statement.
	float raw = dot(normalize(NORMAL), normalize(LIGHT));
	float level = clamp((raw + wrap) / (1.0 + wrap), 0.0, 1.0);

	vec3 cool = mix(vec3(1.0), shadow_hue.rgb, shadow_hue_mix);
	vec3 warm = mix(vec3(1.0), light_hue.rgb, light_hue_mix);
	vec3 tint = mix(cool, warm, level);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tint * level;
	// SPECULAR_LIGHT deliberately untouched.
}

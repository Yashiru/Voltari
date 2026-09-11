shader_type spatial;

// Flat fill lit by the creature's own element.
//
// The other looks decorate. This one carries information: the rim and the shadow
// both take their hue from the creature's type, so a fire creature is edged in
// orange and shadowed warm, a water one in cyan and shadowed cold. At the size of
// a party thumbnail, where the silhouette is four hundred pixels of one colour
// and the face is unreadable, that edge is the only thing still telling you what
// you are looking at.
//
// The type is pushed in as `accent` by the runtime script, from the palette it
// keeps. The seventeen names are the project's own — `content/type-chart.yaml`,
// Gen 4 without Fairy, decision 0003 — so nothing here invents a vocabulary.
//
// **The link is not wired to real species yet, and cannot be.** These are
// species creatures with dex numbers for names; the project's `content/`
// holds three species species. Setting the type is a property on the
// creature for now. Reading it from the species is a change to Voltari rather
// than to the species, and belongs in its own decision.
//
// Two tones, not a gradient, because the point is a shape that reads at a
// glance. Two rather than `comic`'s three: this look is meant to be legible
// small, and a core shadow at thumbnail size is one tone too many.

render_mode blend_mix, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Cell offset for the face sheets. Zero on every other surface.
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Raised to 1 on the eye and mouth surfaces by the runtime script. The rim is
// what the face must not wear: an orange edge round a pupil reads as an error.
uniform float face_flat : hint_range(0.0, 1.0) = 0.0;

// The creature's element, as a colour. Neutral grey when it has none.
uniform vec4 accent : source_color = vec4(0.72, 0.75, 0.82, 1.0);

group_uniforms paint;
uniform float saturation : hint_range(0.5, 2.5) = 1.30;
uniform float lift : hint_range(0.0, 0.5) = 0.05;

group_uniforms surface;
uniform float wrap : hint_range(0.0, 1.0) = 0.22;
// Where the single step falls, on the wrapped light term.
uniform float terminator : hint_range(0.0, 1.0) = 0.46;
uniform float terminator_softness : hint_range(0.001, 0.3) = 0.03;
uniform float shadow_depth : hint_range(0.0, 1.0) = 0.34;
// How bright the lit tone is allowed to get.
uniform float lit_level : hint_range(0.4, 1.0) = 0.86;
// How far the shadow leans towards the element rather than simply darkening.
uniform float shadow_accent : hint_range(0.0, 1.0) = 0.45;

group_uniforms rim;
// The band along the silhouette, in the element's colour. This is the read.
// Kept under 1 on purpose. A rim bright enough to bloom reads as "selected" in
// most games, which is a word this shader must not accidentally say.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform float rim_width : hint_range(0.0, 1.0) = 0.30;

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
	ALBEDO = enrich(texture(albedo_tex, fract(UV + uv_offset)).rgb);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;

	float facing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float band = smoothstep(1.0 - rim_width, 1.0, facing);
	EMISSION = accent.rgb * band * rim_strength * (1.0 - face_flat);
}

void light() {
	float raw = dot(normalize(NORMAL), normalize(LIGHT));
	float level = clamp((raw + wrap) / (1.0 + wrap), 0.0, 1.0);
	float lit = smoothstep(terminator - terminator_softness,
			terminator + terminator_softness, level);

	// The shadow is the element's colour, darkened — not grey. That is what makes
	// the two tones read as one creature rather than as a creature and a stain.
	vec3 shade = mix(vec3(1.0 - shadow_depth),
			accent.rgb * (1.0 - shadow_depth * 0.6), shadow_accent);
	// Neither tone reaches full light. A two-tone step near the middle leaves
	// most of the body on the lit side, and at 1.0 that is white on anything
	// pale — the three-tone looks get away with it, this one cannot.
	vec3 tint = mix(shade, vec3(lit_level), lit);

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * tint;
	// The rim is emission, so it survives being in shadow — which is the whole
	// reason it reads at thumbnail size. Nothing specular here either.
}

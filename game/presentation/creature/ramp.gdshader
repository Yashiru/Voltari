shader_type spatial;

// Cel shading whose curve is an image, not an expression.
//
// Every other look in this set decides its own steps: `comic` computes a
// terminator and a core, `toon` quantises into bands. Here the shading is a
// single lookup into `shading_ramp.png` — a strip 256 pixels wide read from dark
// on the left to lit on the right. Where the steps fall, how wide each one is,
// what hue the shadow takes: all of it lives in the image.
//
// That is the point. It moves the decision out of the shader and into a file an
// artist opens in any paint program, and it makes a per-creature ramp a matter of
// shipping a second strip rather than writing a second shader. Arc System Works
// build Guilty Gear this way, and it is why their characters can each be lit
// wrong on purpose.
//
// The ramp is bound by the runtime script from `_shared/shading_ramp.png`. With
// none present the sampler reads white — `hint_default_white` — and the creature
// comes out plainly lit rather than black, which is the failure you can see past.

render_mode blend_mix, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

// Cell offset for the face sheets. Zero on every other surface.
uniform vec2 uv_offset = vec2(0.0, 0.0);

// The shading curve. Left edge is fully shaded, right edge fully lit.
uniform sampler2D shading_ramp : source_color, hint_default_white,
		filter_linear, repeat_disable;

group_uniforms paint;
uniform float saturation : hint_range(0.5, 2.5) = 1.25;
uniform float lift : hint_range(0.0, 0.5) = 0.05;

group_uniforms surface;
// How far round the form the light carries before the ramp is sampled. Kept
// modest: pushing it high flattens the ramp's own steps into the middle of the
// strip, where the artist has the least control.
uniform float wrap : hint_range(0.0, 1.0) = 0.30;
// Where the ramp is read across its height, for a strip that holds more than one
// curve stacked. 0.5 is the middle of a single-row ramp.
uniform float ramp_row : hint_range(0.0, 1.0) = 0.5;

group_uniforms volume;
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
	float raw = dot(normalize(NORMAL), normalize(LIGHT));
	float level = clamp((raw + wrap) / (1.0 + wrap), 0.0, 1.0);
	// Clamped off both edges: sampling exactly at 0 or 1 with a linear filter
	// bleeds the strip's border texel, which shows as a hairline of the wrong
	// colour right where the shadow is deepest.
	vec3 curve = texture(shading_ramp, vec2(clamp(level, 0.002, 0.998), ramp_row)).rgb;

	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * curve;
	// SPECULAR_LIGHT deliberately untouched: the ramp carries the whole response.
}

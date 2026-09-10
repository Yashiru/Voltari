shader_type spatial;

// Grass that opens around whoever is walking through it.
//
// A vertex shader and nothing else: no memory, no trail, no per-blade state.
// Each vertex asks how close the walker is and leans away, weighted by how far
// up the blade it sits — so the roots stay planted and only the tops move.
//
// The softness does not live here. This is a pure function of where the walker
// is, and grass springs back the instant that point moves. What makes the
// recovery gentle is that the point handed in **lags behind the player**
// (`grass_field.gd`), so the bend trails and settles rather than snapping.
//
// It replaces the imported material rather than adding a pass, so it also has to
// draw the grass: these models carry a flat colour and no texture at all, which
// is why reproducing them is three lines.

render_mode cull_back, diffuse_burley;

// Where the walker is, in world space, and how much notice to take of them.
// Strength is separate so that the effect can be faded out entirely — during a
// battle, in a cutscene — without moving the point somewhere untrue.
uniform vec3 walker_position = vec3(0.0);
uniform float walker_strength : hint_range(0.0, 1.0) = 1.0;

// How far the parting reaches, in metres. About half a cell: further and grass
// bends before anybody is near it.
uniform float reach : hint_range(0.05, 4.0) = 1.05;

// How far the tips move at the centre of it.
uniform float push : hint_range(0.0, 2.0) = 0.5;

// How much a bent blade also sinks. Without it the tips slide sideways and the
// blade appears to stretch instead of bending.
uniform float droop : hint_range(0.0, 1.0) = 0.35;

// How tall a blade is taken to be. Vertices above this lean the full amount.
uniform float blade_height : hint_range(0.05, 6.0) = 1.6;

uniform vec4 albedo : source_color = vec4(0.35, 0.7, 0.35, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool has_texture = false;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 away = world - walker_position;
	away.y = 0.0;

	float distance_out = length(away);
	// Squared falloff, so the middle of the parting is flat and the edge is a
	// curve rather than a cone.
	float nearness = 1.0 - smoothstep(0.0, reach, distance_out);
	nearness *= nearness;

	float up_the_blade = clamp(VERTEX.y / max(blade_height, 0.001), 0.0, 1.0);
	float lean = nearness * up_the_blade * walker_strength;

	// A walker standing exactly on a vertex has no direction to push it in.
	// Leaving it alone is the only answer that is not a guess.
	vec3 sideways = distance_out > 0.0001 ? away / distance_out : vec3(0.0);

	vec3 offset = sideways * push * lean - vec3(0.0, push * droop * lean, 0.0);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(offset, 0.0)).xyz;
}

void fragment() {
	vec4 colour = albedo;
	if (has_texture) {
		colour *= texture(albedo_texture, UV);
	}
	ALBEDO = colour.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}

shader_type spatial;

// Grass that moves a little, and jostles when somebody walks through it.
//
// **It never deforms a tuft.** Every blade of a cell leans the same way by the
// same amount, so the shape of the tuft is the shape the artist made — what
// changes is which way it is leaning. An earlier version pushed blades apart
// radially and it read as damage rather than as somebody passing.
//
// Two things move it, and both are small:
//
// 1. **Wind.** A slow sway with a gust travelling across the field, and a small
//    shiver on each tuft at its own phase. Deliberately weak: grass that waves
//    is grass the eye watches instead of the game.
// 2. **A jostle.** Stepping into a cell sets that cell swinging once, and it
//    settles. One shot, no memory, no trail — the cell is either ringing or it
//    is not.
//
// The world says which cell and how long ago (`grass_field.gd`). This holds no
// state at all.

render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms jostle;

// The two cells that may be ringing: the one being stood in, and the one just
// left. Two, because a cell is crossed in about half a second and a jostle lasts
// about as long — with one slot, leaving a cell would cut it off mid-swing.
uniform vec3 jostle_a = vec3(0.0);
uniform float jostle_a_age = 999.0;
uniform vec3 jostle_b = vec3(0.0);
uniform float jostle_b_age = 999.0;

// How close a cell's own origin has to be to count as the one that was entered.
// A little over half a cell, so the cell stepped into rings and its neighbours
// do not.
uniform float jostle_reach : hint_range(0.05, 3.0) = 0.62;

// How long one swing lasts, how fast it swings, and how far.
uniform float jostle_seconds : hint_range(0.05, 3.0) = 0.7;
uniform float jostle_hz : hint_range(0.5, 12.0) = 4.5;
uniform float jostle_strength : hint_range(0.0, 1.0) = 0.3;

// Fades the jostle out without pretending nobody is there. A battle hides the
// world, and grass swinging around somebody who is not on screen is worse than
// grass standing still.
uniform float walker_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms wind;

// The direction gusts travel, and how long one wave is.
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float gust_wavelength : hint_range(0.5, 20.0) = 6.5;
uniform float gust_speed : hint_range(0.0, 8.0) = 0.9;

// How far the wind leans a blade at its tip, as a fraction of the blade's
// length. **Small on purpose**: 0.34 was the first attempt and the field read as
// a storm.
uniform float gust_strength : hint_range(0.0, 0.5) = 0.075;

// The slow swell, so gusts arrive and pass rather than running at one strength.
uniform float swell_hz : hint_range(0.0, 1.0) = 0.09;
uniform float swell_depth : hint_range(0.0, 1.0) = 0.6;

// The shiver on each tuft, at its own phase.
uniform float flutter_hz : hint_range(0.0, 8.0) = 1.7;
uniform float flutter_strength : hint_range(0.0, 0.2) = 0.022;

// How much stiffness varies from tuft to tuft. Zero makes every tuft equally
// springy, which is one of the two tells of instanced grass.
uniform float stiffness_spread : hint_range(0.0, 1.0) = 0.4;

group_uniforms blade;

// The mesh's own extent, written per item by the tile library builder. Guessing
// one number for every model would put the hinge in the wrong place on all but
// one of them — the grass in the placeholder pack runs from 0.55 m to 3.4 m.
uniform float blade_height : hint_range(0.05, 8.0) = 2.0;
uniform float blade_base = 0.0;

// How far up the blade is anchored. Below this nothing moves, so grass stays
// planted in the ground rather than sliding over it.
uniform float root_hold : hint_range(0.0, 0.6) = 0.15;

// How far each cell is turned. The other tell of instanced grass — a `GridMap`
// draws the same mesh at every cell and the eye finds the repetition quickly.
//
// **Off by default**, because turning a tile changes a map that is already
// painted, and that is a decision for whoever painted it rather than a side
// effect of a shader.
uniform float scatter_yaw : hint_range(0.0, 3.15) = 0.0;

group_uniforms colour;

uniform vec4 albedo : source_color = vec4(0.35, 0.62, 0.32, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool has_texture = false;

// How much darker the base is than the tip. The cheapest thing that makes grass
// sit *in* the ground rather than on top of it.
uniform float root_shade : hint_range(0.0, 1.0) = 0.35;

// Tuft-to-tuft variation in brightness, and the drift towards a warmer tip.
uniform float shade_spread : hint_range(0.0, 0.5) = 0.08;
uniform vec4 tip_tint : source_color = vec4(0.78, 0.82, 0.42, 1.0);
uniform float tip_tint_amount : hint_range(0.0, 1.0) = 0.15;

// How much light passes through a blade lit from behind.
uniform float translucency : hint_range(0.0, 1.0) = 0.3;

varying float blade_fraction;
varying float blade_shade;


// A cheap, stable hash. Stable is the word that matters: it is taken from the
// cell's own origin, so a tuft keeps its phase and its shade while it moves
// rather than shimmering through them.
float hash21(vec2 p) {
	vec2 q = fract(p * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}


// Turns a point about the vertical axis.
vec2 turned(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}


// One swing of a cell that was stepped into, from nothing through a swing and
// back to nothing.
//
// Signed, so it goes both ways, and squared on the way out so it settles rather
// than stopping. A cell that is not the one entered, or one whose swing is over,
// returns nothing and costs two comparisons.
float jostle_of(vec3 cell, vec3 entered, float age, float radius) {
	if (age < 0.0 || age > jostle_seconds) {
		return 0.0;
	}
	if (distance(cell.xz, entered.xz) > radius) {
		return 0.0;
	}
	float left = 1.0 - age / jostle_seconds;
	return sin(age * jostle_hz * TAU) * left * left;
}


void vertex() {
	// Where this cell is, and everything it takes from being that cell: its
	// phase, its stiffness, its shade, and how far it is turned.
	vec3 cell = MODEL_MATRIX[3].xyz;
	float seed = hash21(cell.xz);
	blade_shade = seed;

	float yaw = (seed * 2.0 - 1.0) * scatter_yaw;
	vec3 shaped = VERTEX;
	shaped.xz = turned(VERTEX.xz, yaw);

	float up_the_blade = clamp(
		(shaped.y - blade_base) / max(blade_height, 0.001), 0.0, 1.0
	);
	blade_fraction = up_the_blade;

	// Anchored at the bottom, and easing rather than ramping: a linear weight
	// hinges the tuft at a point, a curved one bends it along its length.
	float leverage = smoothstep(root_hold, 1.0, up_the_blade);
	leverage *= leverage;

	// Stiff tufts take less of everything. Spread rather than scaled, so the
	// average stays where it was tuned.
	float give = mix(1.0 - stiffness_spread * 0.5, 1.0 + stiffness_spread * 0.5, seed);

	// --- wind ---------------------------------------------------------------
	vec2 blowing = normalize(wind_direction + vec2(0.0001, 0.0));
	float along = dot(cell.xz, blowing);

	float wave = sin(along * (TAU / max(gust_wavelength, 0.001)) - TIME * gust_speed);
	float swell = mix(
		1.0 - swell_depth, 1.0, 0.5 + 0.5 * sin(TIME * swell_hz * TAU + seed * 1.7)
	);
	// Half a wave of bias, so a gust pushes downwind and eases rather than
	// swinging the tuft evenly both ways.
	float gust = (wave * 0.5 + 0.5) * swell * gust_strength;
	float flutter = sin(
		TIME * flutter_hz * TAU * mix(0.85, 1.15, seed) + seed * TAU
	) * flutter_strength;

	vec2 lean = blowing * (gust + flutter) * give;

	// --- the jostle ---------------------------------------------------------
	//
	// Its own direction per cell, not the walker's. A cell brushed as somebody
	// passes swings the way its own stems happen to give, and taking the
	// walker's heading would make a field of tufts all swing in step.
	float swing = jostle_of(cell, jostle_a, jostle_a_age, jostle_reach)
		+ jostle_of(cell, jostle_b, jostle_b_age, jostle_reach);
	vec2 shaken = turned(blowing, seed * TAU) * swing * jostle_strength * walker_strength;

	// --- moving it ----------------------------------------------------------
	//
	// One direction and one amount for the whole tuft, so it leans as one piece.
	// Nothing here changes the shape the artist made.
	vec2 push = (lean + shaken) * leverage * give;
	shaped.x += push.x * (shaped.y - blade_base);
	shaped.z += push.y * (shaped.y - blade_base);

	VERTEX = shaped;

	// The normal turns with the lean. A leaning tuft lit by an upright normal
	// reads as flat the moment the sun is anywhere but overhead.
	vec3 spun = NORMAL;
	spun.xz = turned(NORMAL.xz, yaw);
	NORMAL = normalize(spun - vec3(push.x, 0.0, push.y) * leverage * 0.5);
}


void fragment() {
	vec4 colour = albedo;
	if (has_texture) {
		colour *= texture(albedo_texture, UV);
	}

	// Darker in the thatch, warmer at the tip, and a little lighter or darker
	// per tuft. Three lines, and between them most of the difference between a
	// green mass and a field.
	colour.rgb *= mix(1.0 - root_shade, 1.0, blade_fraction);
	colour.rgb = mix(
		colour.rgb, tip_tint.rgb, tip_tint_amount * blade_fraction * blade_fraction
	);
	colour.rgb *= mix(1.0 - shade_spread, 1.0 + shade_spread, blade_shade);

	ALBEDO = colour.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(translucency * mix(0.35, 1.0, blade_fraction));
}

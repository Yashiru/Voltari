shader_type spatial;

// Grass that lives, and opens around whoever walks through it.
//
// Every vertex asks the same three questions — where is the wind, where is the
// walker, and where was the walker a moment ago — and leans accordingly. There
// is no per-blade state anywhere, no trail texture and no second pass.
//
// Four things separate this from a shader that merely moves grass:
//
// 1. **The blade rotates about its root.** Adding an offset to the tip stretches
//    the blade; a bend that keeps its length is a rigid rotation of the stalk,
//    and the difference is visible the moment the wind is strong enough to
//    notice.
// 2. **The normal turns with it.** Bent geometry lit by an unbent normal reads
//    as flat cardboard the instant the sun moves.
// 3. **Nothing is in phase.** Every blade takes its phase, its stiffness and its
//    shade from a hash of where its root is in the world, so the field never
//    breathes as one animal — which is the single tell of instanced grass.
// 4. **The walker leaves a wake.** Two lagged centres arrive from the world; the
//    gap between them is grass the walker has just left. It is still down, and
//    it rings as it comes back up.
//
// The world holds the lag (`grass_field.gd`). This holds no memory at all.

render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms walker;

// Where the walker is, and where they were a moment ago. Both arrive from the
// world already smoothed; the gap between them is the wake.
uniform vec3 walker_position = vec3(0.0);
uniform vec3 walker_wake = vec3(0.0);

// Which way they are going, and how fast against a walk. The heading is what
// makes grass splay away along the path instead of opening in a perfect circle,
// which is the difference between somebody walking and a force field.
uniform vec3 walker_heading = vec3(0.0, 0.0, 1.0);
uniform float walker_speed : hint_range(0.0, 1.0) = 0.0;

// Fades the whole effect out without moving the walker somewhere untrue.
uniform float walker_strength : hint_range(0.0, 1.0) = 1.0;

// How far the parting reaches, in metres, and how hard it presses.
uniform float reach : hint_range(0.05, 4.0) = 1.25;
uniform float trample : hint_range(0.0, 3.0) = 2.1;

// How much of the reach is pressed flat before the falloff begins. A footprint
// with no core is a cone, and a cone reads as a spotlight rather than as
// somebody standing there.
uniform float footprint_core : hint_range(0.0, 0.9) = 0.38;

// How much the push follows the walker rather than pointing straight away from
// them. All radial is a circle; all heading is a bulldozer.
uniform float splay : hint_range(0.0, 1.0) = 0.45;

// How far the wake stays down behind the walker, and how hard it springs.
uniform float wake_hold : hint_range(0.0, 1.0) = 0.85;
uniform float wake_ring : hint_range(0.0, 1.0) = 0.35;
uniform float wake_hz : hint_range(0.5, 8.0) = 3.4;

group_uniforms wind;

// The direction gusts travel, and how long one wave is. A wavelength near a few
// metres is what makes a gust read as crossing the field rather than as the
// whole field pulsing.
uniform vec2 wind_direction = vec2(0.82, 0.57);
uniform float gust_wavelength : hint_range(0.5, 20.0) = 5.5;
uniform float gust_speed : hint_range(0.0, 8.0) = 1.35;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.34;

// The slow swell that makes gusts arrive and pass instead of running forever at
// one strength.
uniform float swell_hz : hint_range(0.0, 1.0) = 0.11;
uniform float swell_depth : hint_range(0.0, 1.0) = 0.55;

// The small shiver on each blade, at its own phase.
uniform float flutter_hz : hint_range(0.0, 8.0) = 2.6;
uniform float flutter_strength : hint_range(0.0, 0.5) = 0.085;

// How much stiffness varies from blade to blade. Zero makes every blade equally
// springy, which is the second tell of instanced grass.
uniform float stiffness_spread : hint_range(0.0, 1.0) = 0.45;

// How much of the wind a pressed blade gives up.
//
// Grass under a foot is not also waving in the breeze. Adding the two is the
// mistake that makes a footprint look like a coincidence rather than a weight.
uniform float wind_yield : hint_range(0.0, 1.0) = 0.8;

group_uniforms scatter;

// How far each cell is turned, and how much its size varies.
//
// **This is what stops a grid of identical tiles reading as a grid.** A GridMap
// draws the same mesh at every cell, and the eye finds the repetition in about a
// second. Turning and resizing each one costs a hash and removes the single
// loudest tell that grass was instanced.
uniform float scatter_yaw : hint_range(0.0, 3.15) = 1.1;
uniform float scatter_size : hint_range(0.0, 0.6) = 0.22;

group_uniforms blade;

// The mesh's own extent, written per item by the tile library builder. Guessing
// one number for every model would put the hinge in the wrong place on all but
// one of them.
uniform float blade_height : hint_range(0.05, 8.0) = 2.0;
uniform float blade_base = 0.0;

// How far up the blade is anchored. Below this nothing moves at all, so the
// grass stays planted in the ground rather than sliding over it.
uniform float root_hold : hint_range(0.0, 0.6) = 0.12;

group_uniforms colour;

uniform vec4 albedo : source_color = vec4(0.35, 0.62, 0.32, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool has_texture = false;

// How much darker the base is than the tip. The cheapest thing that makes grass
// sit *in* the ground instead of on top of it.
uniform float root_shade : hint_range(0.0, 1.0) = 0.42;

// Blade-to-blade variation in brightness, and the drift towards a warmer tip.
uniform float shade_spread : hint_range(0.0, 0.5) = 0.11;
uniform vec4 tip_tint : source_color = vec4(0.78, 0.82, 0.42, 1.0);
uniform float tip_tint_amount : hint_range(0.0, 1.0) = 0.22;

// How much light passes through a blade lit from behind.
uniform float translucency : hint_range(0.0, 1.0) = 0.35;

// How much darker a pressed blade is. Grass in a depression is grass in its own
// shadow, and this is what makes a footprint read as a hollow rather than as a
// patch that happens to be leaning.
uniform float press_shade : hint_range(0.0, 1.0) = 0.3;

varying float blade_fraction;
varying float blade_shade;
varying float blade_pressed;


// A cheap, stable hash. Stable is the word that matters: it is taken from the
// blade's rest position, so a blade keeps its phase and its shade while it moves
// rather than shimmering through them.
float hash21(vec2 p) {
	vec2 q = fract(p * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}


// Rotates `v` by the rotation that takes unit `from` to unit `to`.
//
// Rodrigues, and worth the instructions: this is what turns the normal by
// exactly the amount the geometry turned. Nudging the normal towards the bend
// is the usual shortcut and it drifts wrong precisely when the bend is large,
// which is when anybody is looking.
vec3 rotate_between(vec3 from, vec3 to, vec3 v) {
	vec3 axis = cross(from, to);
	float sine = length(axis);
	float cosine = dot(from, to);
	if (sine < 0.0001) {
		// Parallel, or exactly opposed. Neither is a rotation worth building,
		// and an opposed pair cannot happen: a blade never bends past flat.
		return v;
	}
	axis /= sine;
	return v * cosine + cross(axis, v) * sine + axis * dot(axis, v) * (1.0 - cosine);
}


// How much a point is inside a walker's footprint, from nothing to one.
//
// A flat core and a soft shoulder rather than a curve from the middle outwards:
// somebody standing in grass flattens what is under them and bends what is
// around it, and a falloff that starts at the centre flattens nothing at all.
float footprint(vec3 world, vec3 centre, float radius) {
	float away = length(world.xz - centre.xz);
	return 1.0 - smoothstep(radius * footprint_core, radius, away);
}


// Turns a point about the vertical axis.
vec2 turned(vec2 p, float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}


void vertex() {
	// Every cell turned and sized a little differently. Done before anything
	// else, so the blade that bends is the blade that is drawn.
	float cell_seed = hash21(MODEL_MATRIX[3].xz);
	float yaw = (cell_seed * 2.0 - 1.0) * scatter_yaw;
	float grow = mix(1.0 - scatter_size, 1.0 + scatter_size, fract(cell_seed * 7.31));

	vec3 shaped = vec3(turned(VERTEX.xz, yaw), 0.0).xzy;
	shaped.y = VERTEX.y;
	shaped *= grow;
	shaped.y += blade_base * (1.0 - grow);

	// The blade's own root, and the stalk standing on it. Everything below is a
	// rotation of that stalk.
	vec3 root_local = vec3(shaped.x, blade_base, shaped.z);
	vec3 world_root = (MODEL_MATRIX * vec4(root_local, 1.0)).xyz;
	vec3 world_tip = (MODEL_MATRIX * vec4(shaped, 1.0)).xyz;

	vec3 stalk = world_tip - world_root;
	float stalk_length = length(stalk);

	float up_the_blade = clamp(
		(shaped.y - blade_base) / max(blade_height * grow, 0.001), 0.0, 1.0
	);
	blade_fraction = up_the_blade;

	// Anchored at the bottom, and easing rather than ramping: a linear weight
	// hinges the blade at a point, a cubic one bends it along its length.
	float leverage = smoothstep(root_hold, 1.0, up_the_blade);
	leverage *= leverage;

	float seed = hash21(floor(world_root.xz * 11.0));
	blade_shade = seed;

	// Stiff blades take less of everything. Spread rather than scaled, so the
	// average stays where it was tuned.
	float give = mix(1.0 - stiffness_spread * 0.5, 1.0 + stiffness_spread * 0.5, seed);

	// --- wind ---------------------------------------------------------------
	vec2 blowing = normalize(wind_direction + vec2(0.0001, 0.0));
	float along = dot(world_root.xz, blowing);

	// Gusts travelling across the field, swelling and passing.
	float wave = sin(along * (TAU / max(gust_wavelength, 0.001)) - TIME * gust_speed);
	float swell = mix(
		1.0 - swell_depth,
		1.0,
		0.5 + 0.5 * sin(TIME * swell_hz * TAU + seed * 1.7)
	);
	// Half a wave of bias, so a gust pushes downwind and eases rather than
	// swinging the blade evenly both ways.
	float gust = (wave * 0.5 + 0.5) * swell * gust_strength;

	// The blade's own shiver, at its own phase and its own rate.
	float flutter = sin(
		TIME * flutter_hz * TAU * mix(0.85, 1.15, seed) + seed * TAU
	) * flutter_strength;

	vec2 wind_push = blowing * (gust + flutter) * give;

	// --- the walker ---------------------------------------------------------
	float under_foot = footprint(world_tip, walker_position, reach);
	float behind = footprint(world_tip, walker_wake, reach);

	// Grass the trailing centre still covers but the leading one has left. It is
	// down, and it is on its way up.
	float wake = clamp(behind - under_foot, 0.0, 1.0);
	float pressed = max(under_foot, behind * wake_hold);

	vec2 outward = world_tip.xz - walker_position.xz;
	float spread_out = length(outward);
	// A walker standing exactly on a blade has no direction to push it. Leaning
	// on the heading instead is the only answer that is not a guess.
	vec2 radial = spread_out > 0.0001 ? outward / spread_out : walker_heading.xz;
	vec2 pushing = normalize(mix(radial, walker_heading.xz, splay * walker_speed) + vec2(0.0001, 0.0));

	// A pressed blade gives up most of the wind. Two forces added would make a
	// footprint look like a coincidence rather than a weight.
	wind_push *= 1.0 - clamp(pressed * wind_yield, 0.0, 1.0);
	blade_pressed = pressed * walker_strength;

	vec2 walk_push = pushing * pressed * trample * walker_strength;

	// The spring. Released blades swing past upright and settle, and the swing
	// fades as the trailing centre catches up — so nothing rings forever and
	// nothing needs to remember when it was stepped on.
	float ring = sin(TIME * wake_hz * TAU + seed * TAU) * wake * wake_ring * walker_strength;
	walk_push += radial * ring * give;

	// --- bending ------------------------------------------------------------
	vec3 push = vec3(wind_push.x + walk_push.x, 0.0, wind_push.y + walk_push.y) * leverage;

	vec3 spun_normal = vec3(turned(NORMAL.xz, yaw), 0.0).xzy;
	spun_normal.y = NORMAL.y;

	if (stalk_length > 0.0001) {
		vec3 was = stalk / stalk_length;
		vec3 bent = normalize(stalk + push * stalk_length);
		// The stalk keeps its length: a rigid rotation, not a stretch.
		vec3 moved = world_root + bent * stalk_length;

		mat4 back = inverse(MODEL_MATRIX);
		VERTEX = (back * vec4(moved, 1.0)).xyz;

		vec3 world_normal = normalize((MODEL_MATRIX * vec4(spun_normal, 0.0)).xyz);
		NORMAL = normalize((back * vec4(rotate_between(was, bent, world_normal), 0.0)).xyz);
	} else {
		VERTEX = shaped;
		NORMAL = normalize(spun_normal);
	}
}


void fragment() {
	vec4 colour = albedo;
	if (has_texture) {
		colour *= texture(albedo_texture, UV);
	}

	// Darker in the thatch, warmer at the tip, and a little lighter or darker
	// per blade. Three lines, and between them they are most of the difference
	// between a green mass and a field.
	colour.rgb *= mix(1.0 - root_shade, 1.0, blade_fraction);
	colour.rgb = mix(
		colour.rgb, tip_tint.rgb, tip_tint_amount * blade_fraction * blade_fraction
	);
	colour.rgb *= mix(1.0 - shade_spread, 1.0 + shade_spread, blade_shade);
	colour.rgb *= 1.0 - press_shade * blade_pressed;

	ALBEDO = colour.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	// Light through a blade, and more of it towards the thin tip.
	BACKLIGHT = vec3(translucency * mix(0.35, 1.0, blade_fraction));
}

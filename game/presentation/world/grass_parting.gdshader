shader_type spatial;

// Grass moved by one wind.
//
// **Everything here is global.** There is no per-tuft phase, no per-tuft
// stiffness, no per-cell rotation and no per-cell size. A field of grass in wind
// does not shiver at a hundred different rates: it is one moving air mass, and
// two blades a metre apart are doing very nearly the same thing.
//
// An earlier version varied all four per cell and it read as elastic and random
// — every tuft twitching to its own clock. What replaced it is two travelling
// waves and nothing else:
//
// - a **long** one, twelve metres and slow, which is the gust crossing the field
// - a **shorter** one at a different speed, so the sum never repeats and the
//   field never looks like a single sine
//
// Both are functions of world position and time alone. A blade's phase comes
// from where it stands, so neighbours are in step and distant grass is not —
// which is what makes a gust *travel* rather than the field pulse.
//
// On top of that, one local thing: stepping into a cell sets that cell swinging
// once. It never changes the shape of a tuft — every blade of a cell leans the
// same way by the same amount.

render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms wind;

// Which way the wind blows. One direction for the whole world.
uniform vec2 wind_direction = vec2(0.82, 0.57);

// How far the tip leans, as a fraction of the blade's length, at full gust.
uniform float wind_strength : hint_range(0.0, 0.6) = 0.16;

// The long wave: the gust itself. Metres between crests, and how fast the crest
// travels in metres a second.
//
// **Long and slow on purpose.** A short wavelength makes neighbouring tufts
// disagree, which is the difference between wind and static.
uniform float gust_length : hint_range(1.0, 40.0) = 13.0;
uniform float gust_speed : hint_range(0.0, 6.0) = 1.6;

// The second wave, which only exists so the sum is not a sine. Shorter, faster,
// and a fraction of the amplitude.
uniform float ripple_length : hint_range(0.5, 20.0) = 4.5;
uniform float ripple_speed : hint_range(0.0, 6.0) = 0.9;
uniform float ripple_amount : hint_range(0.0, 1.0) = 0.3;

// The slow breath under both, so the wind rises and falls over several seconds
// instead of running at one strength for ever. Global: the whole field lulls
// together, because that is what a lull is.
uniform float breath_seconds : hint_range(1.0, 60.0) = 11.0;
uniform float breath_depth : hint_range(0.0, 1.0) = 0.45;

// How much of the lean is a steady press downwind rather than a swing either
// way. Wind pushes; it does not rock.
uniform float wind_bias : hint_range(0.0, 1.0) = 0.6;

group_uniforms jostle;

// The two cells that may be ringing: the one being stood in, and the one just
// left. Two, because a cell is crossed in about half a second and a swing lasts
// about as long — with one slot, leaving a cell would cut it off mid-swing.
uniform vec3 jostle_a = vec3(0.0);
uniform float jostle_a_age = 999.0;
uniform vec3 jostle_b = vec3(0.0);
uniform float jostle_b_age = 999.0;

// How close a cell's own origin has to be to count as the one entered. Set from
// the map's cell width by `grass_field.gd`, not guessed here.
uniform float jostle_reach : hint_range(0.05, 3.0) = 0.62;

// How long one swing lasts, how fast it swings, and how far.
uniform float jostle_seconds : hint_range(0.05, 3.0) = 0.7;
uniform float jostle_hz : hint_range(0.5, 12.0) = 3.2;
uniform float jostle_strength : hint_range(0.0, 1.0) = 0.22;

// Fades the jostle out without pretending nobody is there. A battle hides the
// world, and grass swinging around somebody off screen is worse than grass
// standing still.
uniform float walker_strength : hint_range(0.0, 1.0) = 1.0;

group_uniforms blade;

// The mesh's own extent, written per item by the tile library builder. Guessing
// one number for every model would put the hinge in the wrong place on all but
// one of them — the grass in the placeholder pack runs from 0.55 m to 3.4 m.
uniform float blade_height : hint_range(0.05, 8.0) = 2.0;
uniform float blade_base = 0.0;

// How far up the blade is anchored. Below this nothing moves, so grass stays
// planted in the ground rather than sliding over it.
uniform float root_hold : hint_range(0.0, 0.6) = 0.18;

group_uniforms colour;

uniform vec4 albedo : source_color = vec4(0.35, 0.62, 0.32, 1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform bool has_texture = false;

// How much darker the base is than the tip. The cheapest thing that makes grass
// sit *in* the ground rather than on top of it, and the only shading variation
// here — it follows the blade rather than a random number.
uniform float root_shade : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tip_tint : source_color = vec4(0.78, 0.82, 0.42, 1.0);
uniform float tip_tint_amount : hint_range(0.0, 1.0) = 0.15;

// How much light passes through a blade lit from behind.
uniform float translucency : hint_range(0.0, 1.0) = 0.3;

varying float blade_fraction;


// One swing of a cell that was stepped into, from nothing through a swing and
// back to nothing.
//
// Signed, so it goes both ways, and squared on the way out so it settles rather
// than stopping. A cell that is not the one entered, or one whose swing is over,
// returns nothing and costs two comparisons.
float jostle_of(vec3 cell, vec3 entered, float age) {
	if (age < 0.0 || age > jostle_seconds) {
		return 0.0;
	}
	if (distance(cell.xz, entered.xz) > jostle_reach) {
		return 0.0;
	}
	float left = 1.0 - age / jostle_seconds;
	return sin(age * jostle_hz * TAU) * left * left;
}


void vertex() {
	vec3 cell = MODEL_MATRIX[3].xyz;

	float up_the_blade = clamp(
		(VERTEX.y - blade_base) / max(blade_height, 0.001), 0.0, 1.0
	);
	blade_fraction = up_the_blade;

	// Anchored at the bottom and easing upwards: a linear weight hinges the tuft
	// at a point, a curved one bends it along its length. This is the whole of
	// what makes the motion look supple rather than tilted.
	float leverage = smoothstep(root_hold, 1.0, up_the_blade);
	leverage *= leverage;

	// --- one wind -----------------------------------------------------------
	vec2 blowing = normalize(wind_direction + vec2(0.0001, 0.0));
	float along = dot(cell.xz, blowing);

	// Both waves are functions of where the tuft stands and of time. Neighbours
	// are therefore in step and distant grass is not, which is what makes a gust
	// cross the field instead of the field pulsing.
	float gust = sin(along * (TAU / max(gust_length, 0.001)) - TIME * gust_speed);
	float ripple = sin(along * (TAU / max(ripple_length, 0.001)) - TIME * ripple_speed);
	float wave = mix(gust, ripple, ripple_amount);

	// Wind pushes downwind and eases; it does not rock evenly about upright.
	float pressed = mix(wave, wave * 0.5 + 0.5, wind_bias);

	float breath = mix(
		1.0 - breath_depth, 1.0,
		0.5 + 0.5 * sin(TIME * TAU / max(breath_seconds, 0.001))
	);

	vec2 lean = blowing * pressed * breath * wind_strength;

	// --- one footfall -------------------------------------------------------
	//
	// Across the wind rather than along it, so a step reads as something other
	// than a gust arriving.
	float swing = jostle_of(cell, jostle_a, jostle_a_age)
		+ jostle_of(cell, jostle_b, jostle_b_age);
	vec2 shaken = vec2(-blowing.y, blowing.x) * swing * jostle_strength * walker_strength;

	// --- moving it ----------------------------------------------------------
	//
	// One direction and one amount for every blade of the tuft, so it leans as
	// one piece. Nothing here changes the shape the artist made.
	vec2 push = (lean + shaken) * leverage;
	float up = VERTEX.y - blade_base;

	VERTEX.x += push.x * up;
	VERTEX.z += push.y * up;

	// The normal turns with the lean. A leaning tuft lit by an upright normal
	// reads as flat the moment the sun is anywhere but overhead.
	NORMAL = normalize(NORMAL - vec3(push.x, 0.0, push.y) * 0.5);
}


void fragment() {
	vec4 colour = albedo;
	if (has_texture) {
		colour *= texture(albedo_texture, UV);
	}

	// Darker in the thatch, warmer at the tip. Both follow the blade rather than
	// a random number, so two tufts side by side are the same colour.
	colour.rgb *= mix(1.0 - root_shade, 1.0, blade_fraction);
	colour.rgb = mix(
		colour.rgb, tip_tint.rgb, tip_tint_amount * blade_fraction * blade_fraction
	);

	ALBEDO = colour.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(translucency * mix(0.35, 1.0, blade_fraction));
}

// One wind, for everything that bends in it.
//
// This was the top of `grass_parting.gdshader` and it moved the day a second
// thing needed it. Decision 0062 deliberately kept the wind out of the shared
// look, and gave a reason: only the grass moved. That reason stopped being true
// when the lawn arrived, and the alternative — the same two waves written out in
// two files — is how a field ends up with its tufts leaning one way and the turf
// under them leaning another, with nobody able to see why.
//
// It stays out of `comic_look.gdshaderinc` all the same. That file is what a
// surface *looks* like, and ninety per cent of the world does not move. A shader
// includes this one only if it bends.
//
// ## The shape of it, which has three decisions behind it
//
// **Everything here is global.** No per-tuft phase, no per-tuft stiffness, no
// per-cell anything. A field of grass in wind does not shiver at a hundred
// different rates: it is one moving air mass, and two blades a metre apart are
// doing very nearly the same thing (decision 0061).
//
// The lean at a point is two travelling waves summed:
//
// - a **long** one, thirteen metres and slow, which is the gust crossing the field
// - a **shorter** one at a different speed, so the sum never repeats and the field
//   never looks like a single sine
//
// Both are functions of world position and time alone. A blade's phase comes from
// where it stands, so neighbours are in step and distant grass is not — which is
// what makes a gust *travel* rather than the field pulse.

group_uniforms wind;

// Which way the wind blows. One direction for the whole world.
uniform vec2 wind_direction = vec2(0.82, 0.57);

// How far a tip leans, as a fraction of its own length, at full gust.
uniform float wind_strength : hint_range(0.0, 0.6) = 0.22;

// The long wave: the gust itself. Metres between crests, and how fast a crest
// travels in metres a second.
//
// **Long and slow on purpose.** A short wavelength makes neighbouring tufts
// disagree, which is the difference between wind and static.
uniform float gust_length : hint_range(1.0, 40.0) = 13.0;
uniform float gust_speed : hint_range(0.0, 6.0) = 2.5;

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


// Which way the air is pushing at a point on the ground, and how hard.
//
// Takes where it is being asked about rather than reading a built-in, because the
// two callers mean different things by it: a tuft asks once for its own cell so
// the whole clump leans as one piece, and the lawn asks per blade so the gust
// crosses it continuously. Passing it in is what lets one function serve both.
vec2 wind_lean(vec2 here, float now) {
	vec2 blowing = normalize(wind_direction + vec2(0.0001, 0.0));
	float along = dot(here, blowing);

	float gust = sin(along * (TAU / max(gust_length, 0.001)) - now * gust_speed);
	float ripple = sin(along * (TAU / max(ripple_length, 0.001)) - now * ripple_speed);
	float wave = mix(gust, ripple, ripple_amount);

	// Wind pushes downwind and eases; it does not rock evenly about upright.
	float pressed = mix(wave, wave * 0.5 + 0.5, wind_bias);

	float breath = mix(
		1.0 - breath_depth, 1.0,
		0.5 + 0.5 * sin(now * TAU / max(breath_seconds, 0.001))
	);

	return blowing * pressed * breath * wind_strength;
}

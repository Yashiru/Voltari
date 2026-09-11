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
//
// ## What this file is, and is not
//
// It is the **movement**. The look — the terminator, the two screens, the shadow
// tint — comes from `comic_look.gdshaderinc`, which every surface in the game
// shares. That split is deliberate: grass moves and almost nothing else does, so
// the wind has no business in a file the tiles and the creatures also read.
//
// What grass keeps of its own colour is only what follows the blade: darker in
// the thatch, warmer at the tip. Those are properties of the plant, and the
// shared look has no idea a blade has a bottom and a top.
//
// `cull_disabled` is why this cannot simply *be* the shared shader: a blade is a
// card and has to draw from both sides, and `render_mode` is per shader, not per
// material. Everything else the world wears is a closed mesh that culls.

render_mode cull_disabled, unshaded, shadows_disabled;

#include "res://game/presentation/creature/comic_look.gdshaderinc"
#include "res://game/presentation/world/wind.gdshaderinc"

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

// The blade's extent is `model_base` and `model_height`, from the shared look —
// one quantity under one name. The wind needs it to know where a blade is hinged
// and how far up its tip is; the contact shadow needs the same numbers to know
// where a model meets the ground. Written per item by the tile library builder.

// How far up the blade is anchored. Below this nothing moves, so grass stays
// planted in the ground rather than sliding over it.
uniform float root_hold : hint_range(0.0, 0.6) = 0.18;

group_uniforms colour;

// `albedo` and `albedo_tex` are the shared look's, not this file's — one surface
// colour convention for the whole game, set by whoever dresses the material.
//
// What is left here is the only colour that belongs to a *plant*: darker in the
// thatch, warmer at the tip. Both follow the blade rather than a random number,
// so two tufts side by side are the same colour.
uniform float root_shade : hint_range(0.0, 1.0) = 0.35;
uniform vec4 tip_tint : source_color = vec4(0.78, 0.82, 0.42, 1.0);
uniform float tip_tint_amount : hint_range(0.0, 1.0) = 0.15;


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

	float up_the_blade = comic_up(VERTEX.y);

	// Anchored at the bottom and easing upwards: a linear weight hinges the tuft
	// at a point, a curved one bends it along its length. This is the whole of
	// what makes the motion look supple rather than tilted.
	float leverage = smoothstep(root_hold, 1.0, up_the_blade);
	leverage *= leverage;

	// --- one wind -----------------------------------------------------------
	//
	// Asked for the *cell*, not for this vertex: every blade of a tuft leans the
	// same way by the same amount, so the clump moves as one piece rather than
	// unfurling. The lawn asks the same function per blade — see `wind.gdshaderinc`.
	vec2 lean = wind_lean(cell.xz, TIME);
	vec2 blowing = normalize(wind_direction + vec2(0.0001, 0.0));

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
	float up = VERTEX.y - model_base;

	VERTEX.x += push.x * up;
	VERTEX.z += push.y * up;

	// The normal turns with the lean. A leaning tuft shaded by an upright normal
	// reads as flat the moment the key is anywhere but overhead.
	NORMAL = normalize(NORMAL - vec3(push.x, 0.0, push.y) * 0.5);

	// Last, and that order is the point: the shared look is handed the blade as
	// the wind left it. Handing it the upright one would shade a leaning tuft as
	// though it were standing, which is the usual way animated foliage ends up
	// looking painted on.
	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	// The same fraction the wind was weighted by, handed to the look so the
	// thatch, the tip tint and the contact band all measure from one place.
	model_up = up_the_blade;
}


void fragment() {
	vec3 paint = comic_paint(UV);

	// The plant's own colour, before the print. Applied after `comic_paint` has
	// saturated the fill rather than before, which costs an exact commutation
	// nobody can see and saves splitting the shared function in two.
	paint *= mix(1.0 - root_shade, 1.0, model_up);
	paint = mix(
		paint, tip_tint.rgb, tip_tint_amount * model_up * model_up
	);

	ALBEDO = comic_shade(paint, SCREEN_UV * VIEWPORT_SIZE, INV_VIEW_MATRIX);
}

// Where a lawn stops, worked out the same way by everything that has to agree.
//
// Two shaders draw one boundary. `turf_scatter.gdshader` decides whether a blade
// exists at all; `turf_mat.gdshader` decides how far the darkened ground reaches.
// **They must land on the same line to within a blade's width**, or the dark
// ground shows past the grass as a halo and the whole patch reads as a decal. The
// only way to promise that is for both to call the same functions on the same
// numbers, which is what this file is.
//
// ## Why the contour is not a contour
//
// Both boundaries are computed as distances — how far this point is from the
// nearest obstacle, and how far it is from the nearest ground nobody sowed. A
// distance is displaced by *adding to it*, so one noise subtracted from both makes
// the grass edge wander without any of the machinery that draws it knowing that it
// has. A boundary drawn from a perfect distance field is a perfect curve, and a
// perfect curve is the tell: real grass stops raggedly.
//
// The wander is a *bite*, in metres, and it is signed: positive eats into the
// grass, negative lets it reach further out. Metres and not texels or cells,
// because it has to mean the same thing to a field stored as a share of the
// clearance and to a distance stored in cell widths.
//
// ## Why its noise is its own
//
// `comic_look.gdshaderinc` already carries `noise31`, and this file cannot use it:
// a particle shader has no fragment stage, cannot declare a `varying`, and so
// cannot include the shared look at all. Copying `noise31` here would then collide
// with the real one in `turf_mat.gdshader`, which includes both. So the turf
// carries a two-dimensional noise under its own name — the ground is flat and the
// third dimension was never used anyway.

group_uniforms room;

// How much room there is on the ground, everywhere under the patch, as a share of
// the clearance: 0 inside something, 1 well clear of everything.
//
// **A distance to the shape of a thing, not to a circle around it.** A radius put
// a round bare ring around a square platform; what an author means by "keep half a
// metre away" is half a metre from its *edge*. Built by `turf_patch.gd` from the
// obstacles' own base triangles, stamped into one grid and measured once — so
// where two things overlap, the room is the room left by both, and a blade is
// never near either. A radius could not do that: the nearest centre wins and the
// second object is not consulted at all.
//
// Sampled smoothly, so the ring reads as a curve rather than as the texels it is.
uniform sampler2D room_field : filter_linear, repeat_disable, hint_default_white;
uniform vec2 field_origin;
uniform vec2 field_size;

// How far grass keeps away from anything standing on it, in metres. **The edge of
// the grass is exactly here**: at the clearance the lawn is full height, and
// inside it there is none.
uniform float clearance : hint_range(0.0, 3.0) = 0.35;

// The longest distance the field can express, in metres. It is stored as a share
// of this, so one texel means the same thing at any clearance, and it reaches past
// the clearance far enough for the ground under the grass to fade out inside it.
uniform float field_reach = 1.0;

group_uniforms edge;

// How far the boundary wanders from where the distance says it is, in metres.
//
// Small on purpose. This is a ragged edge, not a different shape: past a few
// centimetres the bare ring around a post stops reading as a ring and the patch
// border starts reading as damage.
uniform float edge_jitter : hint_range(0.0, 0.5) = 0.08;

// Metres across one wobble. A blade is a few centimetres wide, so anything under
// about a tenth of a metre is a boundary that wanders once per blade — which reads
// as a frayed line rather than as an irregular one.
uniform float edge_jitter_size : hint_range(0.05, 4.0) = 0.55;


// Two dimensions of value noise on the ground. See the header for why it is not
// `noise31`.
float turf_hash(vec2 at) {
	vec3 spread = fract(vec3(at.x, at.y, at.x) * vec3(0.1031, 0.1030, 0.0973));
	spread += dot(spread, spread.yzx + 33.33);
	return fract((spread.x + spread.y) * spread.z);
}


float turf_noise(vec2 at) {
	vec2 cell = floor(at);
	vec2 part = fract(at);
	part = part * part * (3.0 - 2.0 * part);
	return mix(
		mix(turf_hash(cell), turf_hash(cell + vec2(1.0, 0.0)), part.x),
		mix(turf_hash(cell + vec2(0.0, 1.0)), turf_hash(cell + vec2(1.0, 1.0)), part.x),
		part.y
	);
}


// How much grass is eaten away here, in metres, positive inward.
//
// **World space, and the same world space the grain is in.** A patch is a thing
// somebody selected, so a noise keyed on the patch would restart at every seam
// between two of them and draw the seam. Keyed on the world, two patches sown
// separately share one wander and the join disappears.
//
// Two octaves, the second small: one octave is a sine wave with a wobble and reads
// as scalloping, which is its own kind of perfect.
float turf_bite(vec2 world_xz) {
	if (edge_jitter <= 0.0) {
		return 0.0;
	}
	vec2 at = world_xz / max(edge_jitter_size, 0.02);
	float wobble = turf_noise(at);
	wobble = mix(wobble, turf_noise(at * 2.37 + vec2(11.3, 7.9)), 0.4);
	return (wobble - 0.5) * 2.0 * edge_jitter;
}


// How far inside the grass this point is, in metres, counting from the bare ring
// around whatever is standing on the ground. Negative is inside the ring.
//
// `on_ground` is the point in the grid's own space, which is the space the field
// was built in; `bite` is what `turf_bite` said at the same point.
//
// **A distance, not a share, and that is what stops the blades tapering.** The
// field used to be read as a 0-to-1 room and multiplied into a blade's size, so
// the lawn thinned out over the whole clearance and the ring was a fade rather
// than an edge. Grass does not get shorter as it approaches a rock. Handing back
// a distance lets the blades cut on its sign and the ground fade over a width of
// its own — one boundary, and each side of it drawn the way it should be.
//
// **The bite is faded out as the ground runs out**, and that is not a nicety. A
// wander that reached all the way in would push grass *inside* the thing it is
// keeping away from wherever the noise happened to be negative — a blade growing
// through a fence post, from a feature meant to make the edge prettier. Scaling
// the bite by the room already there means the boundary can move freely out in
// the open and cannot move at all against the object itself.
float turf_room(vec2 on_ground, float bite) {
	float gap = texture(
		room_field, (on_ground - field_origin) / max(field_size, vec2(0.0001))
	).r * field_reach;
	gap -= bite * smoothstep(0.0, abs(bite) + 1e-4, gap);
	return gap - clearance;
}


// How far inside the sown area this point is, after the wander, in metres.
//
// Negative is outside. The same quantity `turf_room` returns, measured against the
// other boundary — so whatever reads them can simply take the smaller.
//
// One line, and a function anyway: the sign convention is the thing two shaders
// have to agree on, and a convention written twice is a convention that gets
// flipped once.
float turf_edge(float from_bare, float bite) {
	return from_bare - bite;
}

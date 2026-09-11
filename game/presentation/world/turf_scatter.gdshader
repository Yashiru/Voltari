shader_type particles;

// Where every blade of the turf stands, and which way the wind has it.
//
// **Turf is not grass**, in this project's vocabulary. `grass_parting.gdshader`
// draws the tall tufts that are painted as map items, one model per clump. This
// is the short lawn on the ground underneath them — a few centimetres, never
// painted, never an item, and it has no idea the tufts exist.
//
// ## Why a particle shader places it
//
// Godot 4 has no geometry shader, so nothing can make blades out of a surface.
// What it does have is `GPUParticles3D`, whose process stage runs once per
// instance on the GPU — and an instance is a blade. Each one works out where it
// stands from its own `INDEX` and nothing else: a square grid over the patch,
// jittered off its cell, given a height and a facing from a hash of its own
// coordinates.
//
// **Nothing is stored.** No scatter data, no point cloud, no build step, no file
// per asset. Moving a patch or changing its density is one number, and a blade's
// position is recomputed from scratch every frame at no cost, because that is
// what the process stage is already doing.
//
// ## What it costs, measured
//
// A blade is 5 triangles. The project's low tier allows 150,000 triangles for a
// whole frame (`tools/budget/tiers.json`), so 30,000 blades is the entire budget
// for one ten-metre square. Density is therefore the dial this feature lives or
// dies on, and it is exposed rather than chosen here.
//
// ## No varyings, no shared look
//
// A particle shader has no fragment stage and cannot declare a `varying`, so
// `comic_look.gdshaderinc` cannot be included here — it would not compile. The
// wind can and is: a blade of turf and a tuft of grass a metre away must lean the
// same way, and that is only guaranteed by both reading `wind_lean`.

render_mode disable_force, disable_velocity, keep_data;

#include "res://game/presentation/world/wind.gdshaderinc"

group_uniforms patch;

// Every sown cell's own origin, one texel per cell, written by `turf_patch.gd`.
//
// A texture and not an array, because a patch may carry hundreds of cells and an
// array's ceiling would have to be written into this file. Unfiltered and
// unrepeated: what is read back has to be exactly what was written, and a cell
// index past the end is a mistake, not a wrap.
uniform sampler2D cell_spots : filter_nearest, repeat_disable, hint_default_black;
uniform float cell_count = 1.0;

// How many blades stand in one cell, and how wide a cell is. Together these are
// the whole of the layout: a blade finds its cell by dividing its index, and its
// place within the cell by the remainder.
uniform float per_cell = 300.0;
uniform float cell_width = 1.0;
uniform float cell_depth = 1.0;

// How far a blade may wander off its spot, as a share of the gap between spots.
// At zero the sub-grid is visible as rows the moment the camera looks along one.
uniform float blade_scatter : hint_range(0.0, 1.0) = 0.85;

group_uniforms blade;

// How tall the tallest blade is, in metres. Five to ten centimetres is what this
// is for — a card that short is the one case where instancing beats every other
// technique, because the blade is nearly all silhouette and no interior.
uniform float blade_height : hint_range(0.01, 0.4) = 0.09;

// How much shorter the shortest blades are, as a share of the tallest. A lawn
// with one height reads as a mown carpet, which is to say as plastic.
uniform float height_spread : hint_range(0.0, 1.0) = 0.45;

// How wide a blade is at its root, as a share of its own height. Proportional
// rather than absolute so a short blade is not a wide stub.
uniform float blade_width : hint_range(0.02, 1.0) = 0.16;

// How far a blade bows over of its own accord, as a share of its height. The
// blade mesh carries the shape of the bow in its local z, running 0 at the root
// to 1 at the tip; this is only how far that shape reaches.
//
// Geometry, not wind: it is there when the air is still, and it is what separates
// a field of grass from a field of spikes.
uniform float blade_bend : hint_range(0.0, 1.2) = 0.45;

// How far the wind lays a blade over, on top of what `wind_lean` already says.
// The turf is shorter and stiffer than a tuft, so it takes less of the same wind.
uniform float blade_give : hint_range(0.0, 2.0) = 0.55;


// Two numbers from a pair of integers, stable across frames. A blade must find
// the same height and the same facing every time or the lawn boils.
vec2 blade_hash(vec2 cell) {
	vec3 spread = fract(vec3(cell.xyx) * vec3(0.1031, 0.1030, 0.0973));
	spread += dot(spread, spread.yzx + 33.33);
	return fract((spread.xx + spread.yz) * spread.zy);
}


void start() {
	// Nothing. A blade is not born and does not die: `process` writes its whole
	// state from its index every frame, so there is no initial condition to set.
}


void process() {
	// Which cell this blade belongs to, and which blade of that cell it is. The
	// division is the whole reason a patch can be any shape the author selected:
	// blades are laid out per cell, so a cell nobody chose simply has none.
	float slot = min(floor(float(INDEX) / max(per_cell, 1.0)), max(cell_count - 1.0, 0.0));
	float within = float(INDEX) - slot * max(per_cell, 1.0);

	vec3 middle = texture(cell_spots, vec2((slot + 0.5) / max(cell_count, 1.0), 0.5)).rgb;

	// A square sub-grid inside the cell, then pushed off it. The grid is what
	// makes the coverage even; the scatter is what stops it reading as a grid.
	float side = max(ceil(sqrt(max(per_cell, 1.0))), 1.0);
	float col = mod(within, side);
	float row = floor(within / side);

	vec2 mine = blade_hash(vec2(col, row) + slot * 7.0);
	vec2 more = blade_hash(vec2(row, col) + slot * 13.0 + 17.0);

	vec2 step_by = vec2(cell_width, cell_depth) / side;
	vec2 spot = (vec2(col, row) + 0.5) * step_by - vec2(cell_width, cell_depth) * 0.5;
	spot += (mine - 0.5) * step_by * blade_scatter;

	vec3 here = middle + vec3(spot.x, 0.0, spot.y);

	// Where this blade stands **in the world**, which is what the wind must be
	// asked about. Read from the patch's own transform rather than from the
	// blade's local position: two patches side by side would otherwise each
	// compute the wind from their own centre, and the gust would restart at every
	// seam instead of crossing the map.
	vec3 out_there = (EMISSION_TRANSFORM * vec4(here, 1.0)).xyz;

	float tall = blade_height * mix(1.0 - height_spread, 1.0, more.x);
	float wide = tall * blade_width;

	// Every blade faces its own way. Without this the lawn has a grain, and the
	// grain turns with the camera.
	float yaw = more.y * TAU;
	float turn = cos(yaw);
	float across = sin(yaw);

	// The same wind the tall grass reads, asked for at this blade's own feet, so
	// a gust crosses the turf and the tufts standing in it as one thing.
	vec2 push = wind_lean(out_there.xz, TIME) * blade_give;

	// The lean is a shear of the up axis rather than a rotation: a blade bends
	// from its root and keeps its feet planted, which a rotation would not.
	// The third column is the bow, not a depth: a blade is a card with none, and
	// its local z carries how far along the bend each vertex sits. Scaling that
	// column by the blade's own height is what makes a tall blade bow further
	// than a short one by the same share.
	mat4 standing = mat4(
		vec4(vec3(turn, 0.0, -across) * wide, 0.0),
		vec4(vec3(push.x, 1.0, push.y) * tall, 0.0),
		vec4(vec3(across, 0.0, turn) * (tall * blade_bend), 0.0),
		vec4(here, 1.0)
	);

	// Through the patch's own transform, because the particles are world-space:
	// that is what lets the wind above be a world question and a patch still be
	// something you can pick up and move.
	TRANSFORM = EMISSION_TRANSFORM * standing;

	// What the blade's own shader is told about it: a number of its own for
	// colour variation, and how tall it came out.
	CUSTOM = vec4(mine.x, more.x, 0.0, 0.0);
}

shader_type spatial;

// A sown leaf, printed like everything else and moved by the one wind.
//
// The third shader in the world, and it exists for the reason the other two do:
// `render_mode` is per shader, and what a surface *does* is per shader. A crate
// is still; grass is a card that draws from both sides and bends as a clump; a
// leaf is a small stiff blade that flutters where it stands.
//
// It carries no look and no wind of its own. Both are included — the same
// `comic_look.gdshaderinc` every surface in the game wears, and the same
// `wind.gdshaderinc` the grass and the turf are moved by. A leaf that had its own
// copy of either would be a leaf that drifts out of step with the field it stands
// in, which is the whole thing those two files exist to prevent.
//
// `cull_disabled`, and `VltFoliage` winds each leaf **once** (decision 0078).
//
// It was the other way round — wound twice and culled — on the reading that
// turning culling off would draw every leaf four times. It does not: culling
// off rasterises each triangle once and accepts either facing, while winding
// twice submits two and discards one. Same image, twice the geometry, on the
// hottest surface in the game.
//
// Nothing is lost by showing both faces: both carried the support's normal
// already, so a leaf shades the same whichever side is turned towards you.

render_mode blend_mix, cull_disabled, specular_disabled, ambient_light_disabled;

#include "res://game/presentation/creature/comic_look.gdshaderinc"
#include "res://game/presentation/world/wind.gdshaderinc"

group_uniforms leaf;

// How far a leaf's tip swings, as a multiple of what the wind asks for.
//
// The wind speaks in fractions of a blade's length, so the swing is scaled by the
// leaf's own length — a small leaf stirs, a large one sweeps, and one number suits
// both. At zero a leaf is as still as the model it grew on.
//
// **Ten, and not one, because a leaf is small.** The wind's own scale was set on
// grass, where a blade is most of a metre and a fraction of it reads across a
// field. A leaf is a few centimetres, so the same fraction is sub-pixel. Measured
// over four tenths of a second on one palm: at 3 the canopy moves 64 pixels, at 8
// it moves 239, at 18 it moves 947, at 40 it moves 3,701. Ten is a stir. It is
// the first number to reach for, and it is exposed for exactly that reason.
uniform float leaf_sway : hint_range(0.0, 60.0) = 10.0;

// How much of the leaf is held rather than free. Below this nothing moves, so a
// leaf pivots at its stem instead of sliding off the branch.
uniform float stem_hold : hint_range(0.0, 0.6) = 0.15;

// How much darker the darkest leaf is than the branch it grew on.
//
// Which tone a leaf drew is baked per leaf by the generator, snapped to a few
// flat levels — see `VltFoliage.Settings.tone_spread`. Darkening only: a leaf
// brighter than the lit side of its own branch reads as a hole.
uniform float tone_spread : hint_range(0.0, 1.0) = 0.30;


varying float leaf_tone;


void vertex() {
	// Baked per vertex by the generator: how far up its own leaf this point sits,
	// and how long the leaf is. Neither survives the merge into one patch mesh,
	// which is why they are carried rather than derived.
	float along = COLOR.r;
	float length_of_leaf = COLOR.g;
	// Carried rather than read again later: `COLOR` belongs to this stage, and the
	// tone is wanted in `light()`.
	leaf_tone = COLOR.b;

	// Asked per vertex, not per instance. A patch is one mesh covering many cells,
	// so an instance origin would give the whole patch a single phase and the gust
	// would stop travelling — `wind_lean` takes the point precisely so its two
	// callers can differ on this.
	vec3 here = comic_point(VERTEX, MODEL_MATRIX);
	vec2 lean = wind_lean(here.xz, TIME);

	// Anchored at the stem and easing to the tip, squared so the leaf bends along
	// its length rather than hinging at a point.
	float leverage = smoothstep(stem_hold, 1.0, along);
	leverage *= leverage;

	vec2 push = lean * leverage * length_of_leaf * leaf_sway;
	VERTEX.x += push.x;
	VERTEX.z += push.y;

	// Last, and in that order: the look is handed the leaf as the wind left it.
	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	model_up = comic_up(VERTEX.y);
	look_uv = UV;
}

void fragment() {
	// White, deliberately: the look writes the finished colour in `light()`.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	comic_fragment(NORMAL, VIEW_MATRIX);
}


void light() {
	// The leaf's own tone, before the print rather than over it — the same order
	// the grain uses, so the saturation treats it as a colour of its own instead
	// of as a film laid on top.
	float tone = mix(1.0 - tone_spread, 1.0, leaf_tone);
	comic_shade(comic_paint() * tone, NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION,
			LIGHT_IS_DIRECTIONAL, FRAGCOORD.xy, DIFFUSE_LIGHT);
}

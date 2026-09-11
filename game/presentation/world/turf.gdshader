shader_type spatial;

// One blade of the short lawn, drawn in the same printed look as everything else.
//
// Where it stands and how the wind has it is `turf_scatter.gdshader`'s business;
// this file only says what a blade looks like once it is there. The split is the
// one `GPUParticles3D` imposes — a process shader places instances, a spatial
// shader draws them — and it happens to be the right one anyway.
//
// `cull_disabled` because a blade is a card with no thickness and is seen from
// both sides. That is also why **its normals point straight up in the model**
// rather than out of its face: a card lit by its own face normal flips shading
// as it turns, and at a hundred blades a square metre that reads as flicker.
// Pointing them up makes a blade shade like the ground it grows from, which is
// what a stylised lawn wants and what removes the two-sided problem entirely.

render_mode cull_disabled, unshaded, shadows_disabled;

#include "res://game/presentation/creature/comic_look.gdshaderinc"

group_uniforms blade;

// How much darker the base of a blade is than its tip. The whole of the depth in
// a lawn: without it a field of blades is one flat green area, because every
// blade is the same colour and they overlap.
uniform float root_shade : hint_range(0.0, 1.0) = 0.18;

// The colour the tip leans towards, and how far. Warmer and lighter than the
// fill, which is what makes a lawn read as catching light it is not actually
// being given.
uniform vec4 tip_tint : source_color = vec4(0.72, 0.86, 0.36, 1.0);

// How much of the way to the tip colour a blade goes at its very top. Driven to
// one by `turf_patch.gd`, which exposes both ends as colours: the gradient is the
// look, not a tint over it. Squared on the way in, so the root keeps its own
// colour for most of the blade and the change gathers where the light would.
uniform float tip_tint_amount : hint_range(0.0, 1.0) = 1.0;

// How much a blade's colour varies from its neighbour's, from the number the
// scatter gave it. Small: a lawn is one plant, not a meadow of species.
uniform float blade_variation : hint_range(0.0, 0.6) = 0.18;

// How far a blade's shading normal leans away from straight up, towards the way
// it faces.
//
// **This is what makes the grass read as printed rather than as smooth.** The
// shared look picks its tone from the angle between the normal and the key; with
// one normal for every blade the whole field lands on the same side of the
// terminator and the two-tone step never fires. Leaning each blade by its own
// facing gives the field the break, and it is stable per blade — so it is a
// texture of light and dark, not a flicker.
//
// Not the blade's true face normal, which would flip as it turns and shimmer at
// three hundred a square metre. A lean towards it, which reads as the same thing
// and cannot flip.
uniform float blade_facing : hint_range(0.0, 1.0) = 0.55;

// How far up its own blade this fragment is, 0 at the root and 1 at the tip.
varying float up_the_blade;

// This blade's own number, from `CUSTOM.x` in the scatter.
varying float blade_roll;


void vertex() {
	up_the_blade = UV.y;
	blade_roll = INSTANCE_CUSTOM.x;

	// Built here rather than taken from the mesh: every instance shares one blade,
	// so a normal off the mesh is the same for all of them. `INSTANCE_CUSTOM.zw`
	// is this blade's own facing, from the scatter.
	world_normal = normalize(vec3(
		INSTANCE_CUSTOM.z * blade_facing, 1.0, INSTANCE_CUSTOM.w * blade_facing
	));
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	model_up = up_the_blade;
}


void fragment() {
	// **The blade's own colour first, the ground's grain last.** The order is the
	// whole of it: `tip_tint_amount` is driven to one, so the mix at the tip
	// *replaces* the colour rather than tinting it — and a grain applied before
	// that is erased by it. Seen from above a lawn is nearly all tips, so the
	// variation vanished exactly where it would have been looked at.
	vec3 own = mix(
		albedo.rgb, tip_tint.rgb, tip_tint_amount * up_the_blade * up_the_blade
	);

	// Darker in the thatch. Follows the blade rather than a random number, so two
	// blades side by side agree about where the light is.
	own *= mix(1.0 - root_shade, 1.0, up_the_blade);

	// Then the per-blade number, and only as a darkening. Letting it brighten as
	// well would put pale blades among green ones, which reads as dead grass.
	own *= 1.0 - blade_variation * blade_roll;

	// And last the ground's own variation, read at this blade's feet. A blade
	// standing in a darker patch of ground is darker by the same amount as the
	// ground it came out of — they line up exactly rather than resembling each
	// other, because both read one function at one world position.
	vec3 paint = posterise(enrich(own)) * comic_grain(world_here) * comic_contact();

	ALBEDO = comic_shade(paint, SCREEN_UV * VIEWPORT_SIZE, INV_VIEW_MATRIX);
}

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

// How far up its own blade this fragment is, 0 at the root and 1 at the tip.
varying float up_the_blade;

// This blade's own number, from `CUSTOM.x` in the scatter.
varying float blade_roll;


void vertex() {
	up_the_blade = UV.y;
	blade_roll = INSTANCE_CUSTOM.x;

	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	model_up = up_the_blade;
}


void fragment() {
	vec3 paint = comic_paint(UV);

	// Darker in the thatch, warmer at the tip. Both follow the blade rather than
	// a random number, so two blades side by side agree about where the light is.
	paint *= mix(1.0 - root_shade, 1.0, up_the_blade);
	paint = mix(
		paint, tip_tint.rgb, tip_tint_amount * up_the_blade * up_the_blade
	);

	// Only then the per-blade number, and only as a darkening. Letting it brighten
	// as well would put pale blades among green ones, which reads as dead grass.
	paint *= 1.0 - blade_variation * blade_roll;

	ALBEDO = comic_shade(paint, SCREEN_UV * VIEWPORT_SIZE, INV_VIEW_MATRIX);
}

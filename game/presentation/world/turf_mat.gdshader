shader_type spatial;

// The dark ground under a patch of turf, fading out at its edge.
//
// A lawn standing on a bright tile shows the tile between its blades, and the
// blades then read as a green fringe laid on something else. The mat is one flat
// quad per sown cell, in the colour of the blade roots, so what shows between
// them is the ground those roots came out of.
//
// **The edge is the whole reason this is not the blade shader.** A mat that stops
// dead draws a rectangle on the map, and a rectangle is the one thing a patch of
// grass must not look like. Each corner carries how many of the four cells around
// it were sown, and that becomes the alpha — so the mat is solid inside the sown
// area and dissolves over its last cell, following whatever shape was selected.
//
// `depth_draw_never` because it is a transparent film lying on an opaque surface:
// writing depth would make the blades standing in it sort against their own
// ground. Nothing is drawn under it that it needs to hide.

render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

#include "res://game/presentation/creature/comic_look.gdshaderinc"

group_uniforms mat;

// How much darker the mat is than the colour it is given. A touch, because the
// blade roots standing in it are that colour exactly and the ground between them
// should read as further away rather than as a different material.
uniform float mat_shade : hint_range(0.0, 1.0) = 0.18;

// How much of the fade to keep. At zero the mat is solid to its edge, which is
// the rectangle this exists to avoid; at one it dissolves over its whole last
// cell.
uniform float edge_fade : hint_range(0.0, 1.0) = 1.0;

// How covered this corner is, 0 where one cell of four was sown and 1 where all
// four were. Written per vertex by `turf_patch.gd`.
varying float covered;


void vertex() {
	covered = COLOR.r;

	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	model_up = 0.0;
}


void fragment() {
	// Through `comic_paint`, so the mat picks up the same world-space grain the
	// ground under it has — the two are read at the same world position, so the
	// patches line up exactly rather than merely resembling each other.
	vec3 paint = comic_paint(UV) * (1.0 - mat_shade);

	ALBEDO = comic_shade(paint, SCREEN_UV * VIEWPORT_SIZE, INV_VIEW_MATRIX);
	ALPHA = mix(1.0, covered, edge_fade);
}

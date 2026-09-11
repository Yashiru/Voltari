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
// grass must not look like. Each corner carries how far inside the sown area it
// is, in metres, and the alpha is that distance over the fade width — so the mat
// is solid inside the sown area and dissolves over its last stretch, following
// whatever shape was selected and wandering off it the way `turf_edge` says.
//
// `depth_draw_never` because it is a transparent film lying on an opaque surface:
// writing depth would make the blades standing in it sort against their own
// ground. Nothing is drawn under it that it needs to hide.

render_mode blend_mix, cull_disabled, unshaded, shadows_disabled, depth_draw_never;

#include "res://game/presentation/creature/comic_look.gdshaderinc"
#include "res://game/presentation/world/turf_edge.gdshaderinc"

group_uniforms mat;

// How much darker the mat is than the colour it is given. A touch, because the
// blade roots standing in it are that colour exactly and the ground between them
// should read as further away rather than as a different material.
uniform float mat_shade : hint_range(0.0, 1.0) = 0.18;

// How far the mat takes to fade out at the edge of the sown area, in metres. At
// zero it is solid to its edge, which is the rectangle this exists to avoid.
//
// **The mat's alone.** Both boundaries are shared with the blades — the same
// distances, the same wander — but how wide the ground takes to give its own
// colour back is a property of the ground, and thinning the grass to match made
// the last metre read as half-mown.
uniform float edge_width : hint_range(0.0, 3.0) = 0.5;

// How far inside the sown area this corner is, in metres, before the wander.
// Written per vertex by `turf_patch.gd` — and it is the same number the blades
// standing here read out of the spots texture.
varying float from_bare;

// Where this fragment sits on the ground, in the grid's own space — which is this
// node's, because a patch is put exactly where its grid is.
varying vec2 on_ground;


void vertex() {
	// The second UV set and not the vertex colour, which is where this used to
	// live: a colour is quantised to eight bits and clamped to one on its way into
	// the mesh, so a distance in metres could neither exceed a metre nor be finer
	// than four millimetres. The blades read theirs from a float texture, and the
	// two have to be the same number.
	from_bare = UV2.x;
	on_ground = VERTEX.xz;

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

	// Two boundaries, and the tighter one wins: the edge of the sown area, and the
	// bare ring around everything standing on it. Both come back as the same
	// quantity — how far inside the grass this fragment is, in metres — so the
	// smaller of them is the distance to whichever edge is nearer, and one fade
	// over one width serves both. One wander displaces both, read once here and
	// handed to each, so the line the grass stops on and the line the ground gives
	// up on are the same line.
	//
	// **The fade runs inside the grass, never past it.** The ground is dark
	// because there is grass on it; a millimetre beyond the last blade there is no
	// reason for it to be anything but the tile.
	float bite = turf_bite(world_here.xz);
	float inside = min(turf_room(on_ground, bite), turf_edge(from_bare, bite));
	ALPHA = clamp(inside / max(edge_width, 0.0001), 0.0, 1.0);
}

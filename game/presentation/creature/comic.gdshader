shader_type spatial;

// The comic-book surface, worn by everything in the game that does not move of
// its own accord: the creatures, the world's tiles and props, the character.
//
// It began as a creature look, third in a set beside `toon.gdshader` and
// `bd.gdshader` — nothing is replaced, pick one with the `style` property on the
// placeholder root or `style=comic` on the viewer. It stopped being only that
// when the world was asked to match, and what changed to allow it is small: the
// look itself moved into `comic_look.gdshaderinc`, and a flat `albedo` colour
// joined the texture so a model that carries its colour in its material and
// nothing else can be drawn too.
//
// **Everything this file used to explain now lives in the include.** The brief,
// the five things that carry the form, why there is no interior ink, and why the
// pass lights itself — read it there. What is left here is the render mode and
// eight lines of wiring, and that is the point: a second shader that drew the
// same look would be a second look within a month.
//
// Grass is the one exception, and it has a shader of its own for exactly one
// reason: `render_mode` is per shader, not per material. A blade is a card and has
// to draw from both sides. It includes the same look.
//
// `blend_mix` is for the face sheets, which are copied opaque but are sampled with
// filtering at their edges.

render_mode blend_mix, cull_back, unshaded, shadows_disabled;

#include "comic_look.gdshaderinc"

void vertex() {
	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
}

void fragment() {
	ALBEDO = comic_shade(comic_paint(UV), SCREEN_UV * VIEWPORT_SIZE, INV_VIEW_MATRIX);
}

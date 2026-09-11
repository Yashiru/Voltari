shader_type spatial;

// The comic-book surface, worn by everything in the game that does not move of
// its own accord: the creatures, the world's tiles and props, the character.
//
// **Everything it does lives in `comic_look.gdshaderinc`** — the brief, the two
// shadow steps, the two screens, the terminator stroke, and why the surface
// declares itself white. Read it there. What is left here is the render mode and
// three lines of wiring, and that is the point: a second shader that drew the
// same look would be a second look within a month.
//
// Grass is the one exception, and it has a shader of its own for exactly one
// reason: `render_mode` is per shader, not per material, and a blade is a card
// that has to draw from both sides. It includes the same look.
//
// `blend_mix` is for the face sheets, which are copied opaque but are sampled
// with filtering at their edges. `ambient_light_disabled` because the look writes
// the whole surface itself — an ambient term would lay a flat wash over the
// tones. `specular_disabled` because gloss is the one thing this look must not
// have.

render_mode blend_mix, cull_back, specular_disabled, ambient_light_disabled;

#include "comic_look.gdshaderinc"

void vertex() {
	world_normal = comic_normal(NORMAL, MODEL_MATRIX);
	world_here = comic_point(VERTEX, MODEL_MATRIX);
	round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
	model_up = comic_up(VERTEX.y);
	look_uv = UV;
}

void fragment() {
	// White, deliberately. The renderer multiplies `DIFFUSE_LIGHT` by this.
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	comic_fragment(NORMAL, VIEW_MATRIX);
}

void light() {
	comic_shade(comic_paint(), NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION,
			LIGHT_IS_DIRECTIONAL, FRAGCOORD.xy, DIFFUSE_LIGHT);
}

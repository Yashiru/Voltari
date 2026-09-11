// The printed look, once, for every surface in the game.
//
// One terminator, one pair of screens, one shadow tint, one place to change them.
// The world wears it — tiles, props, grass, the character — and so do the
// creatures. A look computed in two files is a look that drifts.
//
// **The wind is deliberately not here.** Grass moves and almost nothing else
// does, so the wind stays in `grass_parting.gdshader` where its three decisions
// already live (0059 to 0061). This file is what a surface *looks* like; how a
// surface *moves* is the shader's own business.
//
// ## It is lit, and that is recent
//
// It used to be `unshaded` and to light itself from a direction uniform, on the
// belief that Godot's `light()` stage had no screen coordinates and so could not
// place a screentone. **That belief was wrong** — `FRAGCOORD` and `SCREEN_UV` are
// both in scope there — and it cost the game every cast shadow it might have had.
// Decision 0064 reopened it.
//
// Being lit is what buys the cast shadow, and the cast shadow is most of what
// makes a drawn world sit together: a tree that throws a shape across the ground
// is standing on it. `ATTENUATION` carries the shadow term, so the same maths that
// draws a dark side draws a thrown one, in the same tones, under the same screen.
//
// ## ALBEDO is white, and that is not a mistake
//
// **Measured on this project's renderer:** Forward Mobile multiplies whatever
// `light()` leaves in `DIFFUSE_LIGHT` by `ALBEDO` afterwards. An albedo of pure
// red under a pure white light comes out pure red.
//
// A multiply can only ever darken a channel, and this look needs a shadow that
// *cools and saturates* — a yellow body's shadow leans violet, which no multiply
// can reach. So the surface declares itself white, the paint is recomputed inside
// `light()` from the varyings, and what is written to `DIFFUSE_LIGHT` is the final
// colour. Multiplying it by white changes nothing, and the look keeps the exact
// control it had when it was unshaded.
//
// The cost is that the paint is computed once per light rather than once per
// pixel. With one sun that is the same work as before.
//
// ## One sun, and lamps add to it
//
// The directional light writes the printed surface. Everything else — a lantern,
// a window, a fire — **adds** a warm pool on top and never re-shades anything.
// That is both correct for the medium, where a page has one key and local glows,
// and the only way accumulation stays sane: two lights each writing a base would
// count the shadow tone twice.
//
// It follows that **a scene needs exactly one `DirectionalLight3D`**, and that a
// scene with none renders black. `Daylight` is the rig that supplies it.
//
// ## Why it lives at this address
//
// `comic.gdshader` exists in two copies: the tracked one, and a copy written into
// the gitignored species quarantine by the asset pipeline (decision 0027),
// which a standalone flat viewer also uses. A relative include resolves in all
// three places only if the file sits beside the shader that includes it — so it
// sits here, and the world shaders reach it by absolute path. The address says
// `creature`; the contents are the whole game's.
//
// ## What a shader has to do to use it
//
//   shader_type spatial;
//   render_mode blend_mix, cull_back, specular_disabled, ambient_light_disabled;
//   #include "res://game/presentation/creature/comic_look.gdshaderinc"
//
//   void vertex() {
//       world_normal = comic_normal(NORMAL, MODEL_MATRIX);
//       world_here = comic_point(VERTEX, MODEL_MATRIX);
//       round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
//       model_up = comic_up(VERTEX.y);
//       look_uv = UV;
//   }
//   void fragment() { comic_fragment(NORMAL, VIEW_MATRIX); }
//   void light()    { comic_shade(comic_paint(), NORMAL, LIGHT, VIEW, LIGHT_COLOR,
//                             ATTENUATION, LIGHT_IS_DIRECTIONAL, FRAGCOORD.xy,
//                             DIFFUSE_LIGHT); }
//
// Built-ins are passed in rather than read here: a built-in belongs to the stage
// it is declared in, and an include has no stage of its own.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable,
		hint_default_white;

// The flat colour under the texture, multiplied into it.
//
// For everything that has no texture at all, which is most of the world: these
// models carry their colour in their materials and nothing else. White by
// default, so a surface that does have a texture is unaffected by its presence.
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Cell offset for the face sheets. Zero on every other surface, which is why the
// body and the eyes can share one shader.
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Raised to 1 on the eye and mouth surfaces by the runtime script. Their artwork
// is already a drawing — laying tone over it fills the whites of the eyes with
// dots and ages the face by twenty years.
uniform float face_flat : hint_range(0.0, 1.0) = 0.0;

// Godot hands `LIGHT_COLOR` already multiplied by pi.
//
// The engine's own lighting path divides it out again inside the Lambert term,
// which carries a 1/pi. A shader that writes its own `light()` never reaches that
// term, so it has to do the division itself — and one that forgets renders every
// surface **3.14 times too bright**.
//
// That was measured, not deduced: a colour chart through the look at saturation
// 1.0, where `enrich` is the identity and the output must equal the input, came
// back brighter by a ratio of 3.09 to 3.17 on every channel of every swatch.
//
// It is worth knowing what it looked like, because it did not look like an
// exposure fault. Most channels clipped at one, and **a colour with a clipped
// channel is a pure hue** — so the world read as over-saturated, and the
// saturation control appeared to do nothing, because there was no headroom left
// for it to push into.
const float OVER_PI = 0.3183098861837907;

group_uniforms look;

// Which of the looks this surface wears.
//
// **One shader, six looks, and that is not a preference.** The world reaches the
// screen through five shaders which differ only by `render_mode` — a blade of
// grass draws from both sides, a crate does not — and `render_mode` is per shader,
// not per material. A look per shader would therefore be thirty files, each a
// copy of the same maths, and they would drift within a month. A branch on a
// uniform is coherent across a draw call and costs nothing measurable.
//
// The looks below `comic` began as separate creature shaders. They are ported
// here unchanged in what they do, and two things changed in how they do it: each
// takes the sun's shadow through `shadowed`, so every one of them now has cast
// shadows; and each returns a finished colour rather than writing `ALBEDO` and a
// tint separately, because the surface declares itself white.
//
// They share `saturation` and `lift` with `comic` rather than keeping their own.
// Each had its own default and the paint is one question, not six — a look is how
// a surface is *shaded*, and a surface that changed colour as well would make the
// two impossible to judge apart.
uniform int look_mode : hint_enum("comic", "toon", "bd", "vinyl", "ramp", "typelit") = 0;

group_uniforms paint;
// One at the default, which is the identity: the paint comes out as the model's
// own colour and nothing pushes it.
//
// It was 1.34, then 1.08, and both were guesses made against a pipeline that was
// rendering 3.14 times too bright — see `OVER_PI`. With channels clipping there
// was no way to judge a saturation, so the number kept coming down to fight a
// symptom. It is a real control again, and the sensible default for a control
// that pushes a colour is not to push it.
uniform float saturation : hint_range(0.5, 3.0) = 1.0;
// A little brightness back after the saturation. Zero now that the look is lit:
// it existed to rescue a desaturated original under a pass that never fully lit
// anything, and under a real sun it only pushes channels into the ceiling.
uniform float lift : hint_range(0.0, 0.5) = 0.0;

// How dark the brightest ink is, against the paper it is printed on.
//
// **The reason the lit side stopped burning.** The look writes a fully lit surface
// as the paint at full strength, and on a page nothing is ever as bright as the
// paper — a fill printed at the paper's own value is exactly what "over-exposed"
// looks like. Pulling the whole paint down keeps the ratio between lit and shadow
// and puts the surface back underneath the page.
// 0.92 and not 0.84: the lower number was half of a compensation for the missing
// 1/pi and is not needed now. What is left is the real reason — a printed fill
// sits just under the paper it is on.
uniform float ink : hint_range(0.3, 1.0) = 0.92;
// Snap each channel to this many levels — the ink count of a press. Off below 2,
// and off by default: these atlases are already flat, and quantising faithful
// artwork is a way to lose it, not to stylise it.
uniform float flat_levels : hint_range(0.0, 24.0) = 0.0;

group_uniforms lighting;
// Where the lit tone gives way, on dot(N, L). 0 is the geometric terminator;
// negative keeps more of the form lit, which is how a comic panel is usually lit.
uniform float terminator : hint_range(-1.0, 1.0) = 0.14;
// Second, deeper step. The one that turns a flat fill into a volume.
uniform float core_level : hint_range(-1.0, 1.0) = -0.34;
// Edge width, in screen pixels, applied to both steps. The value is a *pixel*
// count because the width is taken from the derivative of the lighting term, so
// it means the same thing everywhere on the model.
uniform float edge_pixels : hint_range(0.5, 4.0) = 1.2;

group_uniforms cast_shadow;
// How much the engine's soft shadow edge is snapped back to a hard one.
//
// A filtered shadow map fades over several pixels, which is correct and reads as
// photography. An inker draws a shape with a boundary. At 1 the thrown shadow is
// a shape; at 0 it is whatever the shadow map gave.
uniform float cast_hardness : hint_range(0.0, 1.0) = 0.9;
// How dense the screen is inside a thrown shadow. Constant across it rather than
// growing, because a thrown shadow is a flat area of tone — the modelling is done
// by the surface it falls on, not by the shadow.
uniform float cast_screen : hint_range(0.0, 1.5) = 0.62;
// A stroke along the thrown shadow's own edge, the same gesture the terminator
// gets. This is the single detail that makes a cast shadow read as drawn rather
// than as a dark patch.
uniform float cast_line : hint_range(0.0, 1.0) = 0.30;

group_uniforms shadow;
// The hue the shadow leans towards. Comics cool and *saturate* a shadow rather
// than greying it — grey is what makes stylised colour look muddy.
uniform vec4 shadow_hue : source_color = vec4(0.42, 0.47, 0.78, 1.0);
uniform float shadow_depth : hint_range(0.0, 1.0) = 0.34;
uniform float shadow_hue_mix : hint_range(0.0, 1.0) = 0.38;
uniform float shadow_saturate : hint_range(0.0, 1.0) = 0.22;
// How much deeper the core step goes than the first.
uniform float core_extra : hint_range(0.0, 0.6) = 0.18;

group_uniforms screentone;
uniform float dots_amount : hint_range(0.0, 1.0) = 0.70;
// Side of one dot cell in pixels. Screen space, not UV: a halftone belongs to
// the paper, so it must not scale with the model or slide across the surface.
uniform float dots_size : hint_range(3.0, 40.0) = 8.0;
uniform float dots_angle : hint_range(0.0, 90.0) = 45.0;
// Largest a dot grows, as a share of its cell. Past about 0.9 the cells touch
// and the tone fills solid, which loses the print.
uniform float dots_max : hint_range(0.1, 1.0) = 0.72;
// How far past the terminator the dots reach full size, on dot(N, L).
uniform float dots_reach : hint_range(0.05, 1.5) = 0.70;
// How much darker a dot is than the surface it sits on.
uniform float dots_darken : hint_range(0.0, 1.0) = 0.26;

group_uniforms screentone_core;
// A second, finer screen confined to the core shadow, turned off the first so
// the two grids beat against each other the way two sheets of screentone do.
uniform float core_dots_amount : hint_range(0.0, 1.0) = 0.55;
uniform float core_dots_size : hint_range(2.0, 24.0) = 4.5;
// Degrees off the first screen. Keep it away from 0, 45 and 90 or the two grids
// line up and the second one disappears into the first.
uniform float core_dots_turn : hint_range(0.0, 90.0) = 27.0;
uniform float core_dots_max : hint_range(0.1, 1.0) = 0.66;
uniform float core_dots_reach : hint_range(0.05, 1.5) = 0.45;
uniform float core_dots_darken : hint_range(0.0, 1.0) = 0.22;

group_uniforms edge;
// A darker line just inside the shadow, running along the terminator.
//
// This is where a light bounce would go, and it is its opposite. A bounce is a
// bright band on the shaded silhouette — physically right, and it reads as gloss,
// which is the one thing this look must not have. An inker draws the other thing
// there: a heavier stroke on the shadow side of the edge, so the boundary is a
// *line* and not merely where two fills meet.
uniform float edge_line : hint_range(0.0, 1.0) = 0.28;
// How far into the shadow the line reaches, on dot(N, L).
uniform float edge_line_width : hint_range(0.0, 0.5) = 0.10;

group_uniforms chatter;
// Wobble on the terminator, in the units of dot(N, L), from a noise fixed to the
// surface rather than to the screen — so it travels with the object the way a
// drawn line would, instead of crawling under it.
//
// A shadow boundary computed from a normal is perfectly smooth, and perfectly
// smooth is the tell. Small on purpose: enough that the eye reads a stroke, not
// enough to read as noise.
uniform float chatter_amount : hint_range(0.0, 0.2) = 0.035;
uniform float chatter_scale : hint_range(1.0, 200.0) = 46.0;

group_uniforms lamp;
// What a light that is not the sun does.
//
// It adds and never re-shades: a lantern puts a warm pool on the ground, it does
// not decide where the page's shadows are. Stepped like everything else, so a
// pool has an edge instead of a falloff.
uniform float lamp_warmth : hint_range(0.0, 2.0) = 0.85;
uniform float lamp_steps : hint_range(1.0, 5.0) = 2.0;

group_uniforms toon;
// Bands rather than a ramp, wrapped so the unlit side keeps its colour instead of
// going black, and a terminator that is a statement rather than a gradient.
uniform float toon_bands : hint_range(1.0, 8.0) = 3.0;
uniform float toon_band_softness : hint_range(0.0, 0.2) = 0.035;
uniform float toon_wrap : hint_range(0.0, 1.0) = 0.35;
uniform vec4 toon_shadow_tint : source_color = vec4(0.42, 0.47, 0.68, 1.0);
// How fast the normal turns across one pixel: high on a fold, near zero on a flat
// panel. A curvature signal that needs no baked map, which matters because none of
// these models ship one.
uniform float toon_crease_strength : hint_range(0.0, 4.0) = 1.15;
uniform float toon_crease_bias : hint_range(0.0, 0.2) = 0.02;
uniform vec4 toon_crease_tint : source_color = vec4(0.30, 0.36, 0.52, 1.0);
// Undersides sit down, tops catch the sky. Subtle on purpose: enough to give a
// chibi body weight, not enough to read as a second light.
uniform float toon_ground_shade : hint_range(0.0, 0.6) = 0.22;
uniform float toon_spec_sharpness : hint_range(1.0, 128.0) = 28.0;
uniform float toon_spec_edge : hint_range(0.0, 1.0) = 0.42;
uniform float toon_spec_strength : hint_range(0.0, 2.0) = 0.35;
uniform float toon_spec_softness : hint_range(0.0, 0.5) = 0.08;
// A pale surface has less room for a highlight than a dark one.
uniform float toon_spec_adapt : hint_range(0.0, 1.0) = 0.65;
uniform float toon_spec_tint : hint_range(0.0, 1.0) = 0.35;
uniform float toon_spec_fresnel : hint_range(0.0, 1.0) = 0.40;
uniform float toon_rim_width : hint_range(0.0, 1.0) = 0.42;
uniform float toon_rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec4 toon_rim_colour : source_color = vec4(1.0, 0.97, 0.88, 1.0);

group_uniforms bd;
// Lit or shadow, and nothing in between, on a term remapped to 0..1 — which is
// why this terminator sits near the middle where the others sit near zero.
uniform float bd_levels : hint_range(0.0, 24.0) = 6.0;
uniform float bd_terminator : hint_range(0.0, 1.0) = 0.46;
uniform float bd_terminator_softness : hint_range(0.0, 0.2) = 0.018;
uniform vec4 bd_shadow_tint : source_color = vec4(0.66, 0.68, 0.86, 1.0);
uniform float bd_shadow_depth : hint_range(0.0, 1.0) = 0.26;
uniform float bd_dots_amount : hint_range(0.0, 1.0) = 0.45;
uniform float bd_dots_size : hint_range(1.0, 40.0) = 11.0;
uniform float bd_dots_angle : hint_range(0.0, 90.0) = 45.0;
uniform float bd_dots_max : hint_range(0.0, 1.0) = 0.60;
uniform float bd_dots_softness : hint_range(0.0, 0.5) = 0.12;
// The toon look tints a fold; this one inks it.
uniform vec4 bd_ink_colour : source_color = vec4(0.09, 0.08, 0.13, 1.0);
uniform float bd_crease_ink : hint_range(0.0, 1.0) = 0.70;
uniform float bd_crease_bias : hint_range(0.0, 0.2) = 0.025;
uniform float bd_crease_width : hint_range(0.0, 0.2) = 0.045;

group_uniforms vinyl;
// Left as a gradient, and no banding: the whole point of this look is that the
// terminator is not a statement.
uniform float vinyl_wrap : hint_range(0.0, 1.0) = 0.55;
uniform vec4 vinyl_shadow_hue : source_color = vec4(0.54, 0.60, 0.80, 1.0);
uniform float vinyl_shadow_hue_mix : hint_range(0.0, 1.0) = 0.28;
uniform vec4 vinyl_light_hue : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float vinyl_light_hue_mix : hint_range(0.0, 1.0) = 0.10;
uniform float vinyl_ground_shade : hint_range(0.0, 0.6) = 0.08;

group_uniforms ramp;
// The whole light response, read off a strip. Nothing else shades this look.
uniform sampler2D shading_ramp : source_color, hint_default_white,
		filter_linear, repeat_disable;
uniform float ramp_wrap : hint_range(0.0, 1.0) = 0.30;
uniform float ramp_row : hint_range(0.0, 1.0) = 0.5;
uniform float ramp_ground_shade : hint_range(0.0, 0.6) = 0.08;

group_uniforms typelit;
// The element's colour, pushed in by the creature runtime. Two tones, and the
// shadow is the element darkened rather than grey.
uniform vec4 accent : source_color = vec4(0.72, 0.75, 0.82, 1.0);
uniform float typelit_wrap : hint_range(0.0, 1.0) = 0.22;
uniform float typelit_terminator : hint_range(0.0, 1.0) = 0.46;
uniform float typelit_terminator_softness : hint_range(0.0, 0.2) = 0.03;
uniform float typelit_shadow_depth : hint_range(0.0, 1.0) = 0.34;
// Neither tone reaches full light: at 1.0 the lit side is white on anything pale,
// and a two-tone look has no third step to rescue it.
uniform float typelit_lit_level : hint_range(0.0, 1.0) = 0.86;
uniform float typelit_shadow_accent : hint_range(0.0, 1.0) = 0.45;
uniform float typelit_rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform float typelit_rim_width : hint_range(0.0, 1.0) = 0.30;

// How fast a normal has to be turning for an edge to count as one.
//
// Shared by the two looks that draw a rim, because it answers the same question
// for both: is this a silhouette, or merely a surface seen at a glancing angle?
uniform float rim_turn : hint_range(0.001, 0.2) = 0.02;

group_uniforms form;
// Blend the shading normal towards the one a sphere would have at this point,
// around the mesh's own centre — pushed in by the runtime script.
//
// The mesh normal is faithful, and faithful is the problem: a torso is not a
// smooth ovoid, it has soft undulations, and a razor terminator crossing them
// breaks into blotches. An illustrator draws the shadow of the *form*, not of the
// surface. Left at zero on the world, where a wall is genuinely flat.
uniform vec3 shape_centre = vec3(0.0, 0.0, 0.0);
uniform float shape_round : hint_range(0.0, 1.0) = 0.35;

group_uniforms model;
// The mesh's own vertical extent, written per item by the tile library builder.
//
// One quantity, one name. The grass needs it to know where a blade is hinged and
// how far up its tip is; the contact shadow needs it to know where a model meets
// the ground.
uniform float model_base = 0.0;
uniform float model_height : hint_range(0.05, 8.0) = 2.0;

group_uniforms grain;
// How much the fill varies across the world, as a share of its own value.
//
// Off by default, and raised on the world rather than on creatures — the patches
// are fixed to **world** space, so on anything that moves they would swim across
// the surface instead of belonging to it.
//
// World space and not UV space is not a preference: the ground tile in the
// quarantined pack carries no UVs at all. It also means the pattern crosses a
// tile boundary without a seam, so a floor of a hundred identical tiles stops
// reading as a hundred identical tiles.
uniform float grain_amount : hint_range(0.0, 0.6) = 0.0;
uniform float grain_size : hint_range(0.1, 20.0) = 4.5;
// **Snapped, not smooth.** A gradient laid over a flat fill is the polish this
// look exists to avoid; patches of flat tone are what a screentone is.
uniform float grain_steps : hint_range(2.0, 6.0) = 3.0;

group_uniforms contact;
// A darker band where a model meets the ground, and how far up its own height it
// climbs.
//
// It survives the arrival of real shadows because it answers a different
// question: a shadow map says what the sun cannot see, and at the foot of a trunk
// the sun often can. What sits there in a drawing is an inker's mark saying *this
// touches*. Stepped, measured up the model's own height so it is right wherever
// the cell sits.
uniform float contact_shade : hint_range(0.0, 0.8) = 0.0;
uniform float contact_reach : hint_range(0.01, 0.5) = 0.10;

// World position, for the grain and the chatter.
varying vec3 world_here;

// The surface normal in world space. Not the same thing as `NORMAL`, which the
// engine hands to `light()` in view space: three of the looks darken undersides
// and lighten tops, and that question only means anything against the world's
// own up.
varying vec3 world_normal;
// The point's offset from the model's centre, for `shape_round`.
varying vec3 round_normal;
// Where this fragment sits up the model, 0 at its base and 1 at its top.
varying float model_up;
// Carried rather than read, because `UV` belongs to the fragment stage and the
// paint is needed in `light()`.
varying vec2 look_uv;

// **All four are assigned by each shader's own `vertex()`**, not by a helper here.
// The language forbids the tidier thing: a varying may only be written inside
// `vertex()`, never in a function it calls. So the maths lives in `comic_point`
// and `comic_up`, and the four lines belong to the caller — which is also what
// lets a shader that displaces its geometry hand over the *moved* vertex, as the
// grass and the foliage both do.


// Value noise on a world position. Small and self-contained: the alternative is
// a texture, and a texture would have to be shipped, imported and kept in sync
// with three copies of a shader that otherwise needs nothing.
float hash31(vec3 point) {
	vec3 wrapped = fract(point * 0.3183099 + vec3(0.11, 0.27, 0.43)) * 17.0;
	return fract(wrapped.x * wrapped.y * wrapped.z * (wrapped.x + wrapped.y + wrapped.z));
}

float noise31(vec3 point) {
	vec3 cell = floor(point);
	vec3 part = fract(point);
	part = part * part * (3.0 - 2.0 * part);
	return mix(
		mix(mix(hash31(cell), hash31(cell + vec3(1, 0, 0)), part.x),
			mix(hash31(cell + vec3(0, 1, 0)), hash31(cell + vec3(1, 1, 0)), part.x), part.y),
		mix(mix(hash31(cell + vec3(0, 0, 1)), hash31(cell + vec3(1, 0, 1)), part.x),
			mix(hash31(cell + vec3(0, 1, 1)), hash31(cell + vec3(1, 1, 1)), part.x), part.y),
		part.z);
}

// Push a colour away from its own luminance. Keeps the hue, lifts the paint.
vec3 enrich(vec3 colour) {
	float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	vec3 richer = mix(vec3(luma), colour, saturation);
	return clamp(richer + lift * richer, vec3(0.0), vec3(1.0));
}

vec3 posterise(vec3 colour) {
	if (flat_levels < 2.0) {
		return colour;
	}
	return floor(colour * flat_levels + 0.5) / flat_levels;
}

// The paint as it appears in shadow: darker, cooler, and a little more saturated
// than the lit side rather than a little less.
vec3 shaded(vec3 paint, float depth) {
	vec3 darker = paint * (1.0 - depth);
	vec3 cooled = mix(darker, darker * shadow_hue.rgb, shadow_hue_mix);
	// Pushed *past* its own colour, not towards grey: a comic shadow keeps its
	// hue and gains chroma, and that is what stops it reading as dirt.
	float luma = dot(cooled, vec3(0.2126, 0.7152, 0.0722));
	return clamp(mix(vec3(luma), cooled, 1.0 + shadow_saturate),
			vec3(0.0), vec3(1.0));
}

// A value quantised into `count` steps, each edge softened. The toon look's
// terminator, and the only place a band count means anything.
float step_bands(float value, float count, float softness) {
	float scaled = value * count;
	float lower = floor(scaled);
	float edge = smoothstep(0.5 - softness, 0.5 + softness, scaled - lower);
	return clamp((lower + edge) / count, 0.0, 1.0);
}


// `posterise` against a level count that is not the shared one. The `bd` look
// flattens its paint hard where the others leave it alone.
vec3 posterise_at(vec3 colour, float levels) {
	if (levels < 2.0) {
		return colour;
	}
	return floor(colour * levels + 0.5) / levels;
}


// One halftone cell's coverage, for a dot of `radius` in cell units.
//
// The edge is a fixed number of pixels rather than a fraction of the dot, so a
// dot stays equally crisp whether it is a speck at the terminator or nearly
// filling its cell deep in shadow. `fract` would break `fwidth` at the cell seam,
// so the width is derived from the cell size instead of measured.
float halftone(vec2 pixel, float radius, float size, float degrees) {
	float angle = radians(degrees);
	mat2 turn = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	vec2 cell = fract(turn * (pixel / max(size, 3.0))) - 0.5;
	// Doubled so the reading runs 0 at the centre to 1 at the cell edge, which
	// makes `radius` read directly as a share of the cell.
	float reading = length(cell) * 2.0;
	float aa = 1.6 / max(size, 3.0);
	return smoothstep(radius + aa, radius - aa, reading);
}


// How far up its own height a vertex sits. Model space, so it travels with the
// object and means the same thing wherever the object is put.
float comic_up(float vertex_y) {
	return clamp((vertex_y - model_base) / max(model_height, 0.001), 0.0, 1.0);
}


// Patches of slightly darker tone, fixed to the world. Only ever darkens: the lit
// fill stays the ceiling, so raising this cannot blow a colour out.
float comic_grain(vec3 here) {
	if (grain_amount <= 0.0) {
		return 1.0;
	}
	float patch = noise31(here / max(grain_size, 0.01));
	patch = floor(patch * grain_steps) / max(grain_steps - 1.0, 1.0);
	return 1.0 - grain_amount * (1.0 - clamp(patch, 0.0, 1.0));
}


// The drawn mark where a model meets the ground. The edge is one screen pixel
// wide, taken from the derivative the same way the terminator's is, so the band
// is as crisp on a distant fence post as on a trunk filling the screen.
float comic_contact() {
	if (contact_shade <= 0.0) {
		return 1.0;
	}
	float climbed = model_up / clamp(contact_reach, 0.001, 1.0);
	float width = max(fwidth(climbed), 1e-5);
	float above = smoothstep(1.0 - width, 1.0 + width, climbed);
	return mix(1.0 - contact_shade, 1.0, above);
}


// The flat colour of a surface before any light touches it: its texture, its
// colour, or both, worked over by the grain and the contact.
//
// Both go in before `enrich`, so they are part of the paint rather than something
// laid on top of it — a patch the saturation then treats as a colour of its own,
// which is what stops it reading as a dirty overlay.
vec3 comic_paint() {
	vec3 sampled = texture(albedo_tex, fract(look_uv + uv_offset)).rgb * albedo.rgb;
	sampled *= comic_grain(world_here) * comic_contact();
	return posterise(enrich(sampled)) * ink;
}


// --- what a shader wires up ---------------------------------------------------


// A normal of the model in world space.
vec3 comic_normal(vec3 normal, mat4 model) {
	return normalize((model * vec4(normal, 0.0)).xyz);
}


// A point of the model in world space.
//
// Kept as its own function because a shader often needs the world position before
// it has finished moving the vertex — the foliage asks for it to phase the wind,
// then displaces, then hands the moved vertex to `comic_vertex`.
vec3 comic_point(vec3 vertex, mat4 model) {
	return (model * vec4(vertex, 1.0)).xyz;
}




// What the fragment stage owes the look: a white surface, no gloss, and the
// shading normal the form wants rather than the one the topology has.
//
// White because the renderer multiplies `DIFFUSE_LIGHT` by `ALBEDO` — see the top
// of this file. The paint is recomputed in `light()`.
void comic_fragment(inout vec3 normal, mat4 view) {
	if (shape_round > 0.0 && length(round_normal) > 1e-5) {
		vec3 rounded = (view * vec4(normalize(round_normal), 0.0)).xyz;
		normal = normalize(mix(normal, normalize(rounded), shape_round));
	}
}




// --- the looks ----------------------------------------------------------------
//
// Each takes the paint and the light, and hands back a finished colour. None of
// them writes a built-in: the surface is white and `comic_shade` multiplies the
// result by the light's own colour, so a look is a pure function of what it is
// given. That is what lets six of them live in one shader without any of them
// having to know that the others exist.
//
// `shadowed` is the sun's shadow term, 1 in the light and 0 in something's
// shadow. Every look multiplies by it, which is how five looks that never had a
// cast shadow acquired one.

const int LOOK_COMIC = 0;
const int LOOK_TOON = 1;
const int LOOK_BD = 2;
const int LOOK_VINYL = 3;
const int LOOK_RAMP = 4;
const int LOOK_TYPELIT = 5;


// Bands, a fold tint, a sky gradient, a highlight and a rim.
vec3 look_toon(vec3 paint, vec3 normal, vec3 towards, vec3 eye, float shadowed) {
	// The fold tint and the sky, which used to sit in the fragment stage. They
	// belong to the paint rather than to the light, so they go in first.
	float bend = length(fwidth(normal));
	float crease = clamp((bend - toon_crease_bias) * toon_crease_strength, 0.0, 1.0);
	vec3 colour = mix(paint, paint * toon_crease_tint.rgb, crease);
	float sky = normalize(world_normal).y * 0.5 + 0.5;
	colour *= mix(1.0 - toon_ground_shade, 1.0, sky);

	// Wrapped so the unlit side keeps its colour instead of going black, then
	// banded so the terminator is a statement rather than a gradient.
	float raw = dot(normal, towards);
	float wrapped = (raw + toon_wrap) / (1.0 + toon_wrap);
	float level = step_bands(clamp(wrapped, 0.0, 1.0), toon_bands, toon_band_softness);
	colour = colour * mix(toon_shadow_tint.rgb, vec3(1.0), level) * shadowed;

	vec3 half_vector = normalize(eye + towards);
	float gloss = pow(clamp(dot(normal, half_vector), 0.0, 1.0), toon_spec_sharpness);
	float edge = max(toon_spec_edge * toon_spec_softness, 0.001);
	float blob = smoothstep(toon_spec_edge - edge, toon_spec_edge + edge, gloss);
	// Grazing angles keep more of the highlight, so it hugs the silhouette.
	float grazing = 1.0 - clamp(dot(normal, eye), 0.0, 1.0);
	blob *= mix(1.0, grazing, toon_spec_fresnel);
	float luma = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	float room = mix(1.0, 1.0 - luma, toon_spec_adapt);
	// Lifted towards white before tinting, or a dark surface would drag its own
	// highlight down to nothing and the adaptation would be counted twice.
	vec3 hue = mix(vec3(1.0), clamp(paint + vec3(0.35), 0.0, 1.0), toon_spec_tint);
	colour += blob * toon_spec_strength * room * hue * shadowed;

	// The rim was emission, which the engine adds after the light. Added here
	// instead, which comes to the same thing on a white surface and keeps the look
	// a single function.
	// **Gated by how fast the surface turns**, which is what keeps a rim on a
	// silhouette instead of across a floor. `1 - dot(N, V)` reaches one at any
	// grazing angle, and on a creature that is only the silhouette — but a ground
	// plane is grazing for half its area, so the ungated rim washed the far side
	// of the world white. A normal that is not turning is not an edge.
	float turning = clamp(length(fwidth(normal)) / max(rim_turn, 1e-4), 0.0, 1.0);
	float rim = 1.0 - clamp(dot(normal, eye), 0.0, 1.0);
	colour += toon_rim_colour.rgb * smoothstep(1.0 - toon_rim_width, 1.0, rim)
		* toon_rim_strength * turning;
	return colour;
}


// Two tones, a screentone and an inked fold. Was the one look here that lit
// itself; it takes the sun now like the rest.
vec3 look_bd(vec3 paint, vec3 normal, vec3 towards, float shadowed, vec2 pixel) {
	vec3 paper = posterise_at(paint, bd_levels);

	// Remapped to 0..1, which is why this terminator sits near the middle.
	float facing = dot(normal, towards) * 0.5 + 0.5;
	float lit = smoothstep(bd_terminator - bd_terminator_softness,
			bd_terminator + bd_terminator_softness, facing) * shadowed;

	vec3 shade = paper * mix(vec3(1.0), bd_shadow_tint.rgb, bd_shadow_depth);
	vec3 colour = mix(shade, paper, lit);

	// The dots grow with how far past the terminator the surface has turned, not
	// with the stepped tone — that is what gives a screentone its ramp instead of
	// a flat field of identical dots.
	float depth = clamp((bd_terminator - facing) / max(bd_terminator, 0.001), 0.0, 1.0);
	// A thrown shadow is as deep as the far side, so it takes the same screen.
	depth = max(depth, 1.0 - shadowed);
	float soft = max(bd_dots_softness, 0.001);
	float angle = radians(bd_dots_angle);
	mat2 turn = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
	vec2 cell = fract(turn * (pixel / max(bd_dots_size, 1.0))) - 0.5;
	float reading = length(cell) * 2.0;
	float radius = depth * bd_dots_max;
	float dots = smoothstep(radius + soft, radius - soft, reading);
	colour = mix(colour, bd_ink_colour.rgb, dots * bd_dots_amount * (1.0 - lit));

	float bend = length(fwidth(normal));
	float line = smoothstep(bd_crease_bias, bd_crease_bias + bd_crease_width, bend);
	return mix(colour, bd_ink_colour.rgb, line * bd_crease_ink);
}


// A gradient, warm into cool, and nothing stepped anywhere.
vec3 look_vinyl(vec3 paint, vec3 normal, vec3 towards, float shadowed) {
	float sky = normalize(world_normal).y * 0.5 + 0.5;
	vec3 colour = paint * mix(1.0 - vinyl_ground_shade, 1.0, sky);

	float level = clamp((dot(normal, towards) + vinyl_wrap) / (1.0 + vinyl_wrap),
			0.0, 1.0) * shadowed;
	vec3 cool = mix(vec3(1.0), vinyl_shadow_hue.rgb, vinyl_shadow_hue_mix);
	vec3 warm = mix(vec3(1.0), vinyl_light_hue.rgb, vinyl_light_hue_mix);
	return colour * mix(cool, warm, level) * level;
}


// The light response read off a strip, and nothing else.
vec3 look_ramp(vec3 paint, vec3 normal, vec3 towards, float shadowed) {
	float sky = normalize(world_normal).y * 0.5 + 0.5;
	vec3 colour = paint * mix(1.0 - ramp_ground_shade, 1.0, sky);

	float level = clamp((dot(normal, towards) + ramp_wrap) / (1.0 + ramp_wrap),
			0.0, 1.0) * shadowed;
	// Clamped off both edges: sampling exactly at 0 or 1 with a linear filter
	// bleeds the strip's border texel, which shows as a hairline of the wrong
	// colour right where the shadow is deepest.
	return colour * texture(shading_ramp,
			vec2(clamp(level, 0.002, 0.998), ramp_row)).rgb;
}


// Two tones in the creature's own element colour, and a rim that survives shadow.
vec3 look_typelit(vec3 paint, vec3 normal, vec3 towards, vec3 eye, float shadowed) {
	float level = clamp((dot(normal, towards) + typelit_wrap) / (1.0 + typelit_wrap),
			0.0, 1.0);
	float lit = smoothstep(typelit_terminator - typelit_terminator_softness,
			typelit_terminator + typelit_terminator_softness, level) * shadowed;

	// The shadow is the element's colour, darkened — not grey. That is what makes
	// the two tones read as one creature rather than as a creature and a stain.
	vec3 shade = mix(vec3(1.0 - typelit_shadow_depth),
			accent.rgb * (1.0 - typelit_shadow_depth * 0.6), typelit_shadow_accent);
	vec3 colour = paint * mix(shade, vec3(typelit_lit_level), lit);

	// The rim was emission, so it survived being in shadow — which is the whole
	// reason it reads at thumbnail size. Added after the light for the same effect.
	// **Gated by how fast the surface turns**, which is what keeps a rim on a
	// silhouette instead of across a floor. `1 - dot(N, V)` reaches one at any
	// grazing angle, and on a creature that is only the silhouette — but a ground
	// plane is grazing for half its area, so the ungated rim washed the far side
	// of the world white. A normal that is not turning is not an edge.
	float turning = clamp(length(fwidth(normal)) / max(rim_turn, 1e-4), 0.0, 1.0);
	float facing = 1.0 - clamp(dot(normal, eye), 0.0, 1.0);
	float band = smoothstep(1.0 - typelit_rim_width, 1.0, facing);
	return colour
		+ accent.rgb * band * typelit_rim_strength * turning * (1.0 - face_flat);
}


// The printed surface, for one light.
//
// `shadowed` is the engine's shadow term: 1 in the sun, 0 in a thrown shadow, and
// soft in between until `cast_hardness` snaps it. That one value is what the whole
// rework was for.
// The printed look itself: two steps, two screens and a stroke.
vec3 look_comic(vec3 paint, vec3 normal, vec3 towards, float shadowed, vec2 pixel) {
	float facing = dot(normal, towards);

	// The wobble goes in before the steps, so both tones and the edge line pick it
	// up together and the shadow keeps one boundary rather than three.
	facing += (noise31(world_here * chatter_scale) - 0.5) * chatter_amount;

	// The whole reason the edge holds up: its width is the screen footprint of the
	// lighting term at this pixel, so it is `edge_pixels` wide everywhere.
	float width = max(fwidth(facing), 1e-5) * edge_pixels;

	// The thrown shadow, snapped from a filtered gradient back into a shape.
	float thrown = mix(shadowed, smoothstep(0.35, 0.65, shadowed), cast_hardness);

	// Lit means facing the sun *and* not in something's shadow. The core step is
	// attached shading only: a thrown shadow is one flat tone, because the form
	// under it is described by the surface it falls on, not by the shadow.
	float lit = smoothstep(terminator - width, terminator + width, facing) * thrown;
	float above_core = smoothstep(core_level - width, core_level + width, facing);

	vec3 first = shaded(paint, shadow_depth);
	vec3 core = shaded(paint, min(shadow_depth + core_extra, 0.95));
	vec3 colour = mix(core, first, above_core);
	colour = mix(colour, paint, lit);

	float printable = 1.0 - face_flat;

	// One coarse screen over everything in shadow of either kind, so a dark side
	// and a thrown shadow speak the same language. The attached side grows denser
	// the further past the terminator it has turned; the thrown side is constant.
	float attached = clamp((terminator - facing) / max(dots_reach, 0.001), 0.0, 1.0);
	float depth = max(attached, (1.0 - thrown) * cast_screen);
	float coarse = halftone(pixel, min(depth, 1.0) * dots_max, dots_size, dots_angle);
	colour = mix(colour, colour * (1.0 - dots_darken),
			coarse * dots_amount * (1.0 - lit) * printable);

	// The second is finer and turned off the first, so the two grids beat against
	// each other the way two sheets do. Confined to the core, so the deepest part
	// of the form gains density instead of only darkness.
	float core_depth = clamp((core_level - facing) / max(core_dots_reach, 0.001),
			0.0, 1.0);
	float fine = halftone(pixel, core_depth * core_dots_max, core_dots_size,
			dots_angle + core_dots_turn);
	colour = mix(colour, colour * (1.0 - core_dots_darken),
			fine * core_dots_amount * (1.0 - above_core) * printable);

	// The stroke on the shadow side of the terminator. Everything above draws
	// areas; this draws the line between them.
	float inner = smoothstep(terminator - edge_line_width - width,
			terminator - edge_line_width + width, facing);
	colour = mix(colour, colour * (1.0 - edge_line), inner * (1.0 - lit) * printable);

	// The same gesture along the thrown shadow's own edge. A band rather than a
	// step: it is drawn where the shadow term is crossing, which is exactly where
	// an inker would put a heavier stroke.
	float rim = (1.0 - abs(thrown * 2.0 - 1.0));
	return mix(colour, colour * (1.0 - cast_line), rim * rim * printable);
}


// One surface, one light, whichever look is chosen.
//
// `paint` is the surface's finished flat colour. Passed in rather than computed
// here because each shader has its own to add — a blade is darker in the thatch,
// a leaf carries its own tone, the mat under the turf is darker than the ground.
// All of it is built from varyings, which `light()` can see, so every caller
// builds its paint at the call site and the look stays the only thing shared.
// `towards_eye` is `VIEW`, handed over rather than read: a built-in belongs to
// the stage it is declared in, and an include has no stage of its own. Three of
// the looks need it — a rim, a highlight, a grazing angle.
void comic_shade(
	vec3 paint, vec3 normal, vec3 towards_light, vec3 towards_eye,
	vec3 light_colour, float shadowed, bool is_sun, vec2 pixel, inout vec3 diffuse
) {
	vec3 towards = normalize(towards_light);
	vec3 facing_normal = normalize(normal);
	vec3 eye = normalize(towards_eye);

	if (!is_sun) {
		// A lamp adds and never re-shades, whatever the look. Stepped so a pool of
		// light has an edge rather than a falloff — the one thing every look here
		// agrees on is that a boundary should be visible.
		float pool = clamp(dot(facing_normal, towards), 0.0, 1.0) * shadowed;
		pool = ceil(pool * lamp_steps) / max(lamp_steps, 1.0);
		diffuse += paint * light_colour * OVER_PI * pool * lamp_warmth;
		return;
	}

	vec3 colour;
	if (look_mode == LOOK_TOON) {
		colour = look_toon(paint, facing_normal, towards, eye, shadowed);
	} else if (look_mode == LOOK_BD) {
		colour = look_bd(paint, facing_normal, towards, shadowed, pixel);
	} else if (look_mode == LOOK_VINYL) {
		colour = look_vinyl(paint, facing_normal, towards, shadowed);
	} else if (look_mode == LOOK_RAMP) {
		colour = look_ramp(paint, facing_normal, towards, shadowed);
	} else if (look_mode == LOOK_TYPELIT) {
		colour = look_typelit(paint, facing_normal, towards, eye, shadowed);
	} else {
		colour = look_comic(paint, facing_normal, towards, shadowed, pixel);
	}
	diffuse += colour * light_colour * OVER_PI;
}

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
// ## One pipeline, five quantisers
//
// Decision 0069. Everything below is one sequence, in this order, for every
// surface and every look:
//
//     paint      the flat colour: texture, tint, grain, contact, saturation
//       |
//     tones      three colours built from it — sunlit, shade, core
//       |
//     quantise   how the surface travels between them. THE ONLY PART THAT
//       |        DIFFERS BETWEEN LOOKS. Five of them; see `look_mode`.
//     thrown     the cast shadow, composited between the attached result and
//       |        the surface's own darkest tone
//     screen     halftone, over anything in shadow of either kind
//       |
//     ink        roughcast, terminator stroke, cast-shadow stroke, fold
//       |
//     add        highlight, rim
//
// **A uniform belongs to a stage, not to a look.** That is the whole of the
// reorganisation: there was a `terminator` and a `bd_terminator` on two different
// scales, four shadow tints, four wraps, three sky gradients and two halftones,
// and the panel that drove them only knew one look's half of it. There is now one
// name per question, and a look is a set of answers — exactly what `comic-noir`
// already was.
//
// Nine uniforms are genuinely local to one quantiser and they are the only ones
// that carry no general meaning: `bands`; `core_level`, `core_extra` and the six
// `core_dots_*`; `shading_ramp` and `ramp_row`.
//
// ## It is lit
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
// the gitignored placeholder quarantine by the asset pipeline (decision 0027),
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

// Godot hands `LIGHT_COLOR` already multiplied by pi.
//
// The engine's own lighting path divides it out again inside the Lambert term,
// which carries a 1/pi. A shader that writes its own `light()` never reaches that
// term, so it has to do the division itself — and one that forgets renders every
// surface **3.14 times too bright**. Decision 0067.
const float OVER_PI = 0.3183098861837907;

// Rec. 709, the luminance every desaturation and every adaptation here measures
// against. One vector, so two of them cannot disagree about what "bright" means.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);


// --- the surface itself -------------------------------------------------------
//
// Per object, not part of a look: a preset never names any of these, and `Look`
// never clears them. They describe *this* mesh, and the look is what is done to it.

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
//
// **Every drawn stage honours it**, which is new: the screen, the roughcast, both
// strokes, the fold and the rim all multiply by `1 - face_flat`. It used to be
// consulted by two looks out of six, so wearing `bd` put a halftone across the
// whites of the eyes and wearing `toon` drew a rim around them.
uniform float face_flat : hint_range(0.0, 1.0) = 0.0;

// The creature's element colour, pushed in by the creature runtime.
//
// A property of the subject rather than of the look, which is why it sits here and
// not under `shadow` or `rim` — two stages read it, through `accent_shadow` and
// `rim_accent`, and both of those are the look's business while this is not.
uniform vec4 accent : source_color = vec4(0.72, 0.75, 0.82, 1.0);

// Blend the shading normal towards the one a sphere would have at this point,
// around the mesh's own centre — pushed in by the runtime script.
//
// The mesh normal is faithful, and faithful is the problem: a torso is not a
// smooth ovoid, it has soft undulations, and a razor terminator crossing them
// breaks into blotches. An illustrator draws the shadow of the *form*, not of the
// surface. Left at zero on the world, where a wall is genuinely flat.
uniform vec3 shape_centre = vec3(0.0, 0.0, 0.0);
uniform float shape_round : hint_range(0.0, 1.0) = 0.35;

// The mesh's own vertical extent, written per item by the tile library builder.
//
// One quantity, one name. The grass needs it to know where a blade is hinged and
// how far up its tip is; the contact shadow needs it to know where a model meets
// the ground.
uniform float model_base = 0.0;
uniform float model_height : hint_range(0.05, 8.0) = 2.0;


// --- which quantiser ----------------------------------------------------------

// How this surface steps from its shadow into the sun. **The only thing a look
// changes about the pipeline.**
//
// One shader and not five files: the world reaches the screen through five shaders
// which differ only by `render_mode` — a blade of grass draws from both sides, a
// crate does not — and `render_mode` is per shader, not per material. A quantiser
// per shader would be twenty-five files of the same maths and they would drift
// within a month. A branch on a uniform is coherent across a draw call and costs
// nothing measurable.
//
// **The names say what they do, not what they are for.** `toon` is `bands` with
// three of them; `bd` and `typelit` are both `step`, and differ only in their
// numbers; `vinyl` is `smooth`. Those six names still exist — as presets, in
// `style_presets.json`, which is where a set of numbers has always belonged. What
// was a look that could not be saved is now a look like any other.
uniform int look_mode : hint_enum("comic", "bands", "step", "smooth", "ramp") = 0;

const int LOOK_COMIC = 0;
const int LOOK_BANDS = 1;
const int LOOK_STEP = 2;
const int LOOK_SMOOTH = 3;
const int LOOK_RAMP = 4;


// --- stage 1: the paint -------------------------------------------------------

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

// How dark the brightest fill is, against the paper it is printed on.
//
// **This was called `ink` and the name was a lie.** It is not a line and it draws
// nothing: it is a ceiling on the paint, and the reason the lit side stopped
// burning. On a page nothing is ever as bright as the paper, and a fill printed at
// the paper's own value is exactly what "over-exposed" looks like. Pulling the
// whole paint down keeps the ratio between lit and shadow and puts the surface
// back underneath the page. The real ink is `ink_colour`, further down, and it is
// what every stroke and every dot in this file is drawn with.
//
// It also absorbs `typelit`'s old `lit_level`, which asked the same question in
// the same units and answered it one look at a time.
uniform float fill_ceiling : hint_range(0.3, 1.0) = 0.92;

// Snap each channel to this many levels — the ink count of a press. Off below 2,
// and off by default: these atlases are already flat, and quantising faithful
// artwork is a way to lose it, not to stylise it. The `bd` preset is the one that
// turns it on, where it used to be a second uniform of its own.
uniform float flat_levels : hint_range(0.0, 24.0) = 0.0;

// Undersides sit down, tops catch the sky.
//
// Subtle on purpose: enough to give a chibi body weight, not enough to read as a
// second light. Measured against the world's own up, which is what `world_normal`
// is carried for. Three looks each had their own copy of this under three names
// and with the same three lines behind it.
uniform float ground_shade : hint_range(0.0, 0.6) = 0.0;

group_uniforms grain;

// How much the fill varies across the world, as a share of its own value.
//
// Off by default, and raised on the world rather than on creatures — the patches
// are fixed to **world** space, so on anything that moves they would swim across
// the surface instead of belonging to it.
//
// World space and not UV space is not a preference: the ground tile in the
// placeholder pack carries no UVs at all. It also means the pattern crosses a
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


// --- stage 2: the tones -------------------------------------------------------

group_uniforms shadow;

// The hue a shadow leans towards. Comics cool and *saturate* a shadow rather than
// greying it — grey is what makes stylised colour look muddy.
//
// **One shadow tone for the whole game.** There were four: this one, plus a tint
// for `toon`, a tint and a depth for `bd`, a hue and a mix for `vinyl`, and a
// depth of its own for `typelit`. Four sets of numbers answering one question,
// and — worse — the cast shadow took this one while the attached shadow took the
// look's, so on four looks out of six a thrown shadow and a dark side were two
// different colours in the same picture.
uniform vec4 shadow_hue : source_color = vec4(0.42, 0.47, 0.78, 1.0);
uniform float shadow_depth : hint_range(0.0, 1.0) = 0.34;
uniform float shadow_hue_mix : hint_range(0.0, 1.0) = 0.38;
uniform float shadow_saturate : hint_range(0.0, 1.0) = 0.22;

// How far the shadow's hue is replaced by the creature's own element colour.
//
// `typelit`'s whole idea, generalised: a shadow that is the element darkened
// rather than grey is what makes two tones read as one creature instead of as a
// creature and a stain. Zero everywhere else, where `accent` means nothing.
uniform float accent_shadow : hint_range(0.0, 1.0) = 0.0;

// How much deeper the core tone goes than the first. Read by the `comic`
// quantiser, which has a second step, and by the fine screen below.
uniform float core_extra : hint_range(0.0, 0.6) = 0.18;

group_uniforms lit_side;

// A tint on the sunlit side, the counterpart of `shadow_hue`.
//
// `vinyl`'s warm-into-cool gradient is the only thing that used it, under two
// names of its own. Off by default: a page's lit side is its paint, and tinting it
// is a choice rather than the rule the shadow tint is.
uniform vec4 light_hue : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float light_hue_mix : hint_range(0.0, 1.0) = 0.0;


// --- stage 3: the quantiser ---------------------------------------------------

group_uniforms lighting;

// How far round the far side the light reaches, before anything is stepped.
//
// **One wrap, and it is what fixed the scale.** Four looks each had their own —
// 0.35, 0.55, 0.30, 0.22 — and `comic` had none at all, which is why `terminator`
// meant 0.14 on a raw dot product there and 0.46 on a remapped one in `bd`. The
// same word, two scales, and a shared slider between them would have been wrong
// wherever it was pointed.
//
// Everything downstream now reads one term: `(dot(N, L) + wrap) / (1 + wrap)`,
// where 1 is facing the key and 0 is the wrapped edge. `comic` sits at a half,
// which is what puts its old core step back inside the range.
uniform float wrap : hint_range(0.0, 1.0) = 0.5;

// Where the lit tone gives way, on that term.
//
// Read by `comic` and `step` as the position of a step, and by every look as where
// the screen starts to build — which is why it is not one of the nine local ones.
uniform float terminator : hint_range(0.0, 1.0) = 0.4267;

// Edge width, in screen pixels, for every edge in the file.
//
// The value is a *pixel* count because the width is taken from the derivative of
// the lighting term, so it means the same thing on a crate filling the screen and
// on a fence post forty metres away. It replaces three fixed softness constants —
// `toon_band_softness`, `bd_terminator_softness`, `typelit_terminator_softness` —
// each of which was a number in lighting units and each of which therefore drifted
// with distance.
uniform float edge_pixels : hint_range(0.5, 4.0) = 1.2;

// Wobble on the term, from a noise fixed to the surface rather than to the screen
// — so it travels with the object the way a drawn line would, instead of crawling
// under it.
//
// A shadow boundary computed from a normal is perfectly smooth, and perfectly
// smooth is the tell. Small on purpose: enough that the eye reads a stroke, not
// enough to read as noise.
uniform float chatter_amount : hint_range(0.0, 0.2) = 0.0233;
uniform float chatter_scale : hint_range(1.0, 200.0) = 46.0;

group_uniforms quantiser_bands;
// How many steps the `bands` quantiser cuts. Local to it and meaningless to the
// other four.
uniform float bands : hint_range(1.0, 8.0) = 3.0;

group_uniforms quantiser_comic;
// The `comic` quantiser's second, deeper step — the one that turns a flat fill
// into a volume. On the same term as `terminator` and below it.
uniform float core_level : hint_range(0.0, 1.0) = 0.1067;

group_uniforms quantiser_ramp;
// The `ramp` quantiser's whole light response, read off a strip. Nothing else
// shades that look.
uniform sampler2D shading_ramp : source_color, hint_default_white,
		filter_linear, repeat_disable;
uniform float ramp_row : hint_range(0.0, 1.0) = 0.5;


// --- stage 4: the cast shadow -------------------------------------------------

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

// How edge-on to the key a surface may be before a thrown shadow stops touching
// it, on the raw `dot(N, L)`.
//
// **This is the shadow terminator problem, and it had to be answered here.** A
// surface turning away from the key is already in its own shadow, and it is
// exactly there that the shadow map's depth test is most grazing and least
// reliable — so it reports a speckle of hits and misses along the terminator,
// which is textbook self-shadow acne. `cast_hardness` then snaps that speckle into
// hard teeth, because snapping a boundary is precisely what it is for.
//
// Measured: with the shadow map switched off the band edge on a sphere is clean;
// with it on and the snap at 0.9 the same edge grows a comb. It was always there
// and `comic` hid it under a screentone.
//
// So the thrown shadow is released back to nothing as the surface turns edge-on,
// and the attached shading owns that boundary alone. Which is also the right
// answer artistically: nobody draws a cast shadow onto a face already in shade.
//
// **Measured on the raw `dot(N, L)`, not on the look's own terminator**, and that
// correction matters. Anchoring it on `terminator` reads well for `comic` and
// `step`, where the terminator is a real boundary — and means nothing for `bands`,
// `smooth` and `ramp`, which do not put one there. The first look tuned after this
// landed set `terminator` to zero, which is a perfectly reasonable thing to do on
// a smooth gradient, and the acne came straight back. The shadow map is unreliable
// where the surface is edge-on to the light, full stop; that is geometry, and it
// does not depend on which look is worn.
uniform float cast_grip : hint_range(0.0, 0.5) = 0.12;


// --- stage 5: the screen ------------------------------------------------------

group_uniforms screentone;
uniform float dots_amount : hint_range(0.0, 1.0) = 0.70;
// Side of one dot cell in pixels. Screen space, not UV: a halftone belongs to
// the paper, so it must not scale with the model or slide across the surface.
uniform float dots_size : hint_range(3.0, 40.0) = 8.0;
uniform float dots_angle : hint_range(0.0, 90.0) = 45.0;
// Largest a dot grows, as a share of its cell. Past about 0.9 the cells touch
// and the tone fills solid, which loses the print.
uniform float dots_max : hint_range(0.1, 1.0) = 0.72;
// How far past the terminator the dots reach full size, on the lighting term.
uniform float dots_reach : hint_range(0.05, 1.5) = 0.4667;
// How far towards `ink_colour` a dot takes the tone under it.
uniform float dots_darken : hint_range(0.0, 1.0) = 0.26;

group_uniforms screentone_core;
// A second, finer screen confined to the deepest tone, turned off the first so the
// two grids beat against each other the way two sheets of screentone do.
//
// Built around `core_level`, so it is at its densest exactly where the `comic`
// quantiser puts its second step — but it is a stage like any other and any look
// may raise it.
uniform float core_dots_amount : hint_range(0.0, 1.0) = 0.55;
uniform float core_dots_size : hint_range(2.0, 24.0) = 4.5;
// Degrees off the first screen. Keep it away from 0, 45 and 90 or the two grids
// line up and the second one disappears into the first.
uniform float core_dots_turn : hint_range(0.0, 90.0) = 27.0;
uniform float core_dots_max : hint_range(0.1, 1.0) = 0.66;
uniform float core_dots_reach : hint_range(0.05, 1.5) = 0.30;
uniform float core_dots_darken : hint_range(0.0, 1.0) = 0.22;


// --- stage 6: the ink ---------------------------------------------------------

group_uniforms ink;

// **The one ink in the file.** Every dot, every speck and every stroke below mixes
// the tone under it towards this colour, by its own strength.
//
// Black by default, where a mix towards it is exactly the multiply each of these
// stages used to do by hand — so `comic` comes out unchanged to the bit. `bd` is
// the preset that makes it a colour: a near-black blue-violet, which is what a
// two-colour press actually puts down and what stops its fold lines reading as
// holes in the page.
uniform vec4 ink_colour : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// A darker line just inside the shadow, running along the terminator.
//
// This is where a light bounce would go, and it is its opposite. A bounce is a
// bright band on the shaded silhouette — physically right, and it reads as gloss,
// which is the one thing this look must not have. An inker draws the other thing
// there: a heavier stroke on the shadow side of the edge, so the boundary is a
// *line* and not merely where two fills meet.
uniform float edge_line : hint_range(0.0, 1.0) = 0.28;
// How far into the shadow the line reaches, on the lighting term.
uniform float edge_line_width : hint_range(0.0, 0.5) = 0.0667;

// The fold line, drawn where the normal turns fastest: high on a crease, near zero
// on a flat panel. A curvature signal that needs no baked map, which matters
// because none of these models ship one.
//
// One set of numbers, where `toon` tinted a fold and `bd` inked one with two
// different formulas. Inking won: it is drawn after the light rather than before
// it, and an ink line is not something the sun gets to brighten.
uniform float crease_ink : hint_range(0.0, 1.0) = 0.0;
uniform float crease_bias : hint_range(0.0, 0.2) = 0.025;
uniform float crease_width : hint_range(0.0, 0.2) = 0.045;

group_uniforms roughcast;

// Roughcast: a granular rendered skin, stippled into the tone. Decision 0065.
//
// **Drawn into the value, not into the lighting.** The first attempt perturbed the
// lighting term the way the chatter does, on the reasoning that a rendered wall
// only shows where light rakes across it and that the hard steps would mask it
// everywhere else for free. Rendered and measured, it did almost nothing: this
// geometry is flat shaded, so the lighting term is *constant across a face* and a
// perturbation either flips a whole face or is clipped away. That reasoning was
// right for a sphere and wrong for a crate, which is most of a town.
//
// So it is a stipple, which is what an inker draws on a rendered wall anyway: two
// octaves of world-space noise, thresholded into specks rather than left as a
// wash, taking the tone underneath towards `ink_colour` like every other mark
// here.
uniform float stucco_amount : hint_range(0.0, 0.6) = 0.0;

// The two grains, as how many repeat per metre. The aggregate you can see and the
// sand you can only feel — one octave alone reads as television static.
//
// **Sized for the camera, not for the hand.** A grain has to be about five pixels
// across to be cut into a crisp speck and about two to exist at all; below that
// the fade removes it, correctly, and the surface goes clean. This game looks at
// the world from roughly seven metres, where one pixel covers about seventeen
// millimetres — so a grain under four centimetres is invisible no matter what the
// amount says. Tuned at a metre first, the whole layer rendered as **nothing** on
// a palm trunk in the overworld, and the measurement was zero pixels changed.
//
// Ten and thirty per metre is ten and three centimetres, which survives that
// camera with room to spare. Bring both up for a scene the player walks close to.
uniform float stucco_coarse : hint_range(1.0, 200.0) = 10.0;
uniform float stucco_fine : hint_range(1.0, 400.0) = 30.0;
uniform float stucco_fine_share : hint_range(0.0, 1.0) = 0.45;

// Where the noise is cut into specks. Lower leaves fewer, larger pits; at a half
// the surface is half pitted and stops reading as a wall.
uniform float stucco_pits : hint_range(0.05, 0.8) = 0.50;

// How much of the roughcast still shows on a surface in full light.
//
// Not zero and not one. A rendered wall does show most where the light rakes
// across it — that is the physical truth — but a lit face that went perfectly
// smooth would undo the whole point on every south wall in the game.
uniform float stucco_lit_share : hint_range(0.0, 1.0) = 0.60;


// --- stage 7: what is added ---------------------------------------------------

group_uniforms highlight;

// A stepped specular blob. Off by default — `comic` has no gloss and must not —
// and raised by the `toon` preset, which is where it came from.
//
// **It dies in a thrown shadow**, because it is the key reflecting off the surface
// and a surface the key cannot see does not reflect it. The rim below is the
// opposite case and the pair is deliberate.
uniform float spec_strength : hint_range(0.0, 2.0) = 0.0;
uniform float spec_sharpness : hint_range(1.0, 128.0) = 28.0;
uniform float spec_edge : hint_range(0.0, 1.0) = 0.42;
uniform float spec_softness : hint_range(0.0, 0.5) = 0.08;
// A pale surface has less room for a highlight than a dark one.
uniform float spec_adapt : hint_range(0.0, 1.0) = 0.65;
uniform float spec_tint : hint_range(0.0, 1.0) = 0.35;
// Grazing angles keep more of the highlight, so it hugs the silhouette.
uniform float spec_fresnel : hint_range(0.0, 1.0) = 0.40;

group_uniforms rim;

// A bright edge along the silhouette. Off by default; `toon` and `typelit` are the
// presets that raise it, and they had two copies of these five lines between them.
//
// **It survives a thrown shadow**, because it is not light — it is the drawing's
// own edge, and it is the whole reason a creature still reads at thumbnail size.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_width : hint_range(0.0, 1.0) = 0.42;
uniform vec4 rim_colour : source_color = vec4(1.0, 0.97, 0.88, 1.0);
// How far the rim's colour is replaced by the creature's element. `typelit` puts
// it at one, which is what made that look read as the creature's type at a glance.
uniform float rim_accent : hint_range(0.0, 1.0) = 0.0;

// How fast a normal has to be turning for an edge to count as one.
//
// `1 - dot(N, V)` reaches one at any grazing angle, and on a creature that is only
// the silhouette — but a ground plane is grazing for half its area, so an ungated
// rim washes the far side of the world white. A normal that is not turning is not
// an edge.
uniform float rim_turn : hint_range(0.001, 0.2) = 0.02;


// --- the other lights ---------------------------------------------------------

group_uniforms lamp;

// What a light that is not the sun does.
//
// It adds and never re-shades: a lantern puts a warm pool on the ground, it does
// not decide where the page's shadows are. Stepped like everything else, so a
// pool has an edge instead of a falloff.
uniform float lamp_warmth : hint_range(0.0, 2.0) = 0.85;
uniform float lamp_steps : hint_range(1.0, 5.0) = 2.0;


// --- varyings -----------------------------------------------------------------

// World position, for the grain, the roughcast and the chatter.
varying vec3 world_here;

// The surface normal in world space. Not the same thing as `NORMAL`, which the
// engine hands to `light()` in view space: `ground_shade` darkens undersides and
// lightens tops, and that question only means anything against the world's own up.
varying vec3 world_normal;

// The point's offset from the model's centre, for `shape_round`.
varying vec3 round_normal;

// Where this fragment sits up the model, 0 at its base and 1 at its top.
varying float model_up;

// Carried rather than read, because `UV` belongs to the fragment stage and the
// paint is needed in `light()`.
varying vec2 look_uv;

// **All five are assigned by each shader's own `vertex()`**, not by a helper here.
// The language forbids the tidier thing: a varying may only be written inside
// `vertex()`, never in a function it calls. So the maths lives in `comic_point`
// and `comic_up`, and the five lines belong to the caller — which is also what
// lets a shader that displaces its geometry hand over the *moved* vertex, as the
// grass and the foliage both do.


// --- small shared maths -------------------------------------------------------

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


// How much world one pixel covers here, in metres. The unit every grain is
// measured against.
float comic_footprint(vec3 here) {
	return max(length(fwidth(here)), 1e-6);
}


// How much of a grain of this size is still worth drawing, 1 near and 0 far.
//
// **This is the whole difference between a surface that has a material and a
// surface that sparkles.** A grain a centimetre across is a material at two metres
// and is pure noise at twenty: one pixel then spans several grains, nothing in it
// can be resolved, and sampling it once per pixel gives a different answer every
// frame the camera moves. That crawl gives a stylised surface away instantly.
//
// The two edges are anchored on sampling, not on taste. Two samples per grain is
// Nyquist and is the point past which a grain carries no information at all, so
// the band is gone by then; it starts going at five samples per grain, which is
// where a threshold stops being able to cut a crisp speck.
float comic_detail(float scale, float footprint) {
	float period = 1.0 / max(scale, 1e-4);
	return 1.0 - smoothstep(period * 0.2, period * 0.5, footprint);
}


// One octave's worth of pits: the share of this pixel the specks cover.
//
// **Thresholded per octave and not on the sum.** Mixing two noises and cutting the
// result once looks equivalent and is not: an octave on its way out collapses
// towards its own mean, which sits right on the threshold, and drags the sum with
// it. Measured, that capped the effect at a sixth of the strength asked for.
//
// Spread before it is cut, for the same reason: value noise built from eight
// hashes is a bell far too narrow to cut specks out of — nearly all of it within a
// tenth of the middle — so one smoothstep pushes the mass out to the ends, which
// is what makes `stucco_pits` behave as a coverage rather than as a dead slider.
float comic_pits(vec3 here, float scale, float footprint) {
	float left = comic_detail(scale, footprint);
	if (left <= 0.0) {
		return 0.0;
	}
	float grain = smoothstep(0.35, 0.65, noise31(here * scale));
	float width = max(fwidth(grain), 1e-4);
	return (1.0 - smoothstep(stucco_pits - width, stucco_pits + width, grain)) * left;
}


// The roughcast, as the share of this pixel that sits in a pit.
//
// World space throughout: this geometry has no UVs worth the name, and a grain
// keyed on world position crosses the seam between two tiles without showing it.
float comic_roughcast(vec3 here, float footprint) {
	if (stucco_amount <= 0.0) {
		return 0.0;
	}
	float aggregate = comic_pits(here, stucco_coarse, footprint);
	float sand = comic_pits(here, stucco_fine, footprint) * stucco_fine_share;
	// Laid over one another rather than averaged, the way two sheets of screentone
	// are: a pixel is pitted if either screen pits it. Averaging would halve both
	// and give a grey wash, which is the thing this is not.
	return 1.0 - (1.0 - aggregate) * (1.0 - sand);
}


// Push a colour away from its own luminance. Keeps the hue, lifts the paint.
vec3 enrich(vec3 colour) {
	float luma = dot(colour, LUMA);
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
//
// **The one shadow tone in the file**, for the attached side and the thrown one
// alike, in all five quantisers. That is what stops a dark side and a cast shadow
// being two different colours in the same picture.
vec3 shaded(vec3 paint, float depth) {
	vec3 hue = mix(shadow_hue.rgb, accent.rgb, accent_shadow);
	vec3 darker = paint * (1.0 - depth);
	vec3 cooled = mix(darker, darker * hue, shadow_hue_mix);
	// Pushed *past* its own colour, not towards grey: a comic shadow keeps its hue
	// and gains chroma, and that is what stops it reading as dirt.
	float luma = dot(cooled, LUMA);
	return clamp(mix(vec3(luma), cooled, 1.0 + shadow_saturate), vec3(0.0), vec3(1.0));
}


// One halftone cell's coverage, for a dot of `radius` in cell units.
//
// The edge is a fixed number of pixels rather than a fraction of the dot, so a dot
// stays equally crisp whether it is a speck at the terminator or nearly filling
// its cell deep in shadow. `fract` would break `fwidth` at the cell seam, so the
// width is derived from the cell size instead of measured.
//
// **Called by every screen in the file.** The `bd` look used to carry this same
// rotation, the same `fract`, and the same `length(cell) * 2.0` inlined by hand,
// with a fixed softness where this one derives its own.
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


// A value quantised into `count` steps, each edge one screen pixel wide.
//
// The width comes from the derivative rather than from a constant, which is the
// same discipline every other edge here follows: a band boundary is `edge_pixels`
// across on a creature filling the screen and on one twenty metres away.
float step_bands(float value, float count, float width) {
	float scaled = value * count;
	float lower = floor(scaled);
	float edge = smoothstep(0.5 - width * count, 0.5 + width * count, scaled - lower);
	return clamp((lower + edge) / count, 0.0, 1.0);
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
	return posterise(enrich(sampled)) * fill_ceiling;
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
// then displaces, then hands the moved vertex over.
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


// --- the five quantisers ------------------------------------------------------
//
// **The only thing a look changes.** Each is handed the same four tones, built
// from the paint once by the stage above, and answers the same two questions
// besides its own colour:
//
//   return   this surface as the key alone shades it
//   `dark`   the same surface with the key fully blocked — the tone a thrown
//            shadow composites towards, so a cast shadow lands in the look's own
//            darkest colour rather than in a colour borrowed from `comic`
//   `level`  how lit it ended up, 0 to 1, which the ink and the screen read to
//            know where to stay off
//
// `term` is the one lighting term: `(dot(N, L) + wrap) / (1 + wrap)`, chattered,
// where 1 faces the key. `width` is `edge_pixels` worth of it at this pixel.
//
// None of them writes a built-in and none of them knows the others exist. What
// used to live inside each — the sky gradient, the crease, the rim, the screen,
// the cast shadow — is a stage now, and is the same for all five.


// Two steps and a core. The printed page.
vec3 look_comic(vec3 paint, vec3 sunlit, vec3 shade, vec3 core, float term,
		float width, out vec3 dark, out float level) {
	// The second step is attached shading only: a thrown shadow is one flat tone,
	// because the form under it is described by the surface it falls on.
	float above_core = smoothstep(core_level - width, core_level + width, term);
	dark = mix(core, shade, above_core);
	level = smoothstep(terminator - width, terminator + width, term);
	return mix(dark, sunlit, level);
}


// N soft-edged steps. `toon` is this with three.
vec3 look_bands(vec3 sunlit, vec3 shade, float term, float width,
		out vec3 dark, out float level) {
	dark = shade;
	level = step_bands(clamp(term, 0.0, 1.0), bands, width);
	return mix(shade, sunlit, level);
}


// One hard step, placed by `terminator`. `bd` and `typelit` are both this.
vec3 look_step(vec3 sunlit, vec3 shade, float term, float width,
		out vec3 dark, out float level) {
	dark = shade;
	level = smoothstep(terminator - width, terminator + width, term);
	return mix(shade, sunlit, level);
}


// No step at all. `vinyl` is this, and the whole point of it is that the
// terminator is not a statement.
vec3 look_smooth(vec3 sunlit, vec3 shade, float term, out vec3 dark, out float level) {
	dark = shade;
	level = clamp(term, 0.0, 1.0);
	return mix(shade, sunlit, level);
}


// The light response read off a strip, and nothing else.
//
// The only quantiser whose shadow is not `shade`: its darkest tone is the strip's
// own first texel, because a ramp that composited a cast shadow towards a colour
// the strip never contains would contradict itself.
vec3 look_ramp(vec3 paint, float term, out vec3 dark, out float level) {
	// Clamped off both edges: sampling exactly at 0 or 1 with a linear filter
	// bleeds the strip's border texel, which shows as a hairline of the wrong
	// colour right where the shadow is deepest.
	dark = paint * texture(shading_ramp, vec2(0.002, ramp_row)).rgb;
	level = clamp(term, 0.0, 1.0);
	return paint * texture(shading_ramp,
			vec2(clamp(level, 0.002, 0.998), ramp_row)).rgb;
}


// --- the shared stages --------------------------------------------------------


// Both screens, over anything in shadow of either kind.
//
// The coarse one grows with how far past the terminator the surface has turned,
// not with the stepped tone — that is what gives a screentone its ramp instead of
// a flat field of identical dots. A thrown shadow is as deep as the far side, so
// it takes the same screen at a constant density.
vec3 comic_screen(vec3 colour, float term, float thrown, float lit, vec2 pixel,
		float printable) {
	if (dots_amount > 0.0) {
		float attached = clamp((terminator - term) / max(dots_reach, 0.001), 0.0, 1.0);
		float tone = max(attached, (1.0 - thrown) * cast_screen);
		float coarse = halftone(pixel, min(tone, 1.0) * dots_max, dots_size, dots_angle);
		colour = mix(colour, ink_colour.rgb,
				coarse * dots_amount * dots_darken * (1.0 - lit) * printable);
	}
	if (core_dots_amount > 0.0) {
		float deep = clamp((core_level - term) / max(core_dots_reach, 0.001), 0.0, 1.0);
		float fine = halftone(pixel, deep * core_dots_max, core_dots_size,
				dots_angle + core_dots_turn);
		colour = mix(colour, ink_colour.rgb,
				fine * core_dots_amount * core_dots_darken * printable);
	}
	return colour;
}


// Everything drawn as a line: the roughcast, then the two strokes, then the fold.
//
// The order is an inker's. The roughcast is a skin over whatever tone the surface
// ended up with, so it goes under; the strokes land on top of it the way a last
// pass does.
vec3 comic_ink(vec3 colour, vec3 normal, float term, float thrown, float lit,
		float width, float printable) {
	if (stucco_amount > 0.0) {
		float rough = comic_roughcast(world_here, comic_footprint(world_here));
		colour = mix(colour, ink_colour.rgb,
				stucco_amount * rough * mix(1.0, stucco_lit_share, lit) * printable);
	}

	if (edge_line > 0.0) {
		// A band just inside the shadow: 1 above the line's position, and gated by
		// `1 - lit` so it stops at the terminator itself.
		float inner = smoothstep(terminator - edge_line_width - width,
				terminator - edge_line_width + width, term);
		colour = mix(colour, ink_colour.rgb, edge_line * inner * (1.0 - lit) * printable);
	}

	if (cast_line > 0.0) {
		// Drawn where the shadow term is crossing, which is exactly where an inker
		// would put a heavier stroke. A band rather than a step.
		float crossing = 1.0 - abs(thrown * 2.0 - 1.0);
		colour = mix(colour, ink_colour.rgb,
				cast_line * crossing * crossing * printable);
	}

	if (crease_ink > 0.0) {
		float bend = length(fwidth(normal));
		float fold = smoothstep(crease_bias, crease_bias + crease_width, bend);
		colour = mix(colour, ink_colour.rgb, crease_ink * fold * printable);
	}
	return colour;
}


// The highlight and the rim, in that order. Both add; neither is a tone.
vec3 comic_added(vec3 colour, vec3 paint, vec3 normal, vec3 towards, vec3 eye,
		float thrown, float printable) {
	// How fast the surface is turning here. Both marks below are marks of a *form*
	// — a body has a highlight and an edge, a floor has neither — and a normal that
	// is not turning does not belong to a form. Ungated, the highlight blooms
	// across a ground plane as a metre-wide pale disc, which is what it did the
	// first time these two looks were asked to dress the world rather than a
	// creature.
	float turning = clamp(length(fwidth(normal)) / max(rim_turn, 1e-4), 0.0, 1.0);

	if (spec_strength > 0.0) {
		vec3 half_vector = normalize(eye + towards);
		float gloss = pow(clamp(dot(normal, half_vector), 0.0, 1.0), spec_sharpness);
		float edge = max(spec_edge * spec_softness, 0.001);
		float blob = smoothstep(spec_edge - edge, spec_edge + edge, gloss);
		float grazing = 1.0 - clamp(dot(normal, eye), 0.0, 1.0);
		blob *= mix(1.0, grazing, spec_fresnel);
		float luma = dot(paint, LUMA);
		float room = mix(1.0, 1.0 - luma, spec_adapt);
		// Lifted towards white before tinting, or a dark surface would drag its own
		// highlight down to nothing and the adaptation would be counted twice.
		vec3 hue = mix(vec3(1.0), clamp(paint + vec3(0.35), 0.0, 1.0), spec_tint);
		// Multiplied by the thrown term: the key cannot glint off a surface it
		// cannot see. The rim below deliberately is not.
		colour += blob * spec_strength * room * hue * thrown * turning * printable;
	}

	if (rim_strength > 0.0) {
		float facing = 1.0 - clamp(dot(normal, eye), 0.0, 1.0);
		float band = smoothstep(1.0 - rim_width, 1.0, facing);
		vec3 hue = mix(rim_colour.rgb, accent.rgb, rim_accent);
		colour += hue * band * rim_strength * turning * printable;
	}
	return colour;
}


// --- the pipeline -------------------------------------------------------------

// One surface, one light, whichever quantiser is chosen.
//
// `paint` is the surface's finished flat colour. Passed in rather than computed
// here because each shader has its own to add — a blade is darker in the thatch, a
// leaf carries its own tone, the mat under the turf is darker than the ground. All
// of it is built from varyings, which `light()` can see, so every caller builds
// its paint at the call site and the look stays the only thing shared.
//
// `towards_eye` is `VIEW`, handed over rather than read: a built-in belongs to the
// stage it is declared in, and an include has no stage of its own.
void comic_shade(
	vec3 paint, vec3 normal, vec3 towards_light, vec3 towards_eye,
	vec3 light_colour, float shadowed, bool is_sun, vec2 pixel, inout vec3 diffuse
) {
	vec3 towards = normalize(towards_light);
	vec3 facing_normal = normalize(normal);
	vec3 eye = normalize(towards_eye);

	if (!is_sun) {
		// A lamp adds and never re-shades, whatever the look. Stepped so a pool of
		// light has an edge rather than a falloff — the one thing every quantiser
		// here agrees on is that a boundary should be visible.
		float pool = clamp(dot(facing_normal, towards), 0.0, 1.0) * shadowed;
		pool = ceil(pool * lamp_steps) / max(lamp_steps, 1.0);
		diffuse += paint * light_colour * OVER_PI * pool * lamp_warmth;
		return;
	}

	// --- stage 1 and 2: the paint, and the three tones built from it ------------
	//
	// The sky gradient is part of the paint rather than of the light: it says which
	// way a surface points, not where the key is, so it must survive being in
	// shadow. Three looks each had their own copy of it.
	float sky = normalize(world_normal).y * 0.5 + 0.5;
	vec3 here = paint * mix(1.0 - ground_shade, 1.0, sky);

	vec3 sunlit = here * mix(vec3(1.0), light_hue.rgb, light_hue_mix);
	vec3 shade = shaded(here, shadow_depth);
	vec3 core = shaded(here, min(shadow_depth + core_extra, 0.95));

	// --- stage 3: the one lighting term, then the quantiser ---------------------
	//
	// The chatter goes in before the steps, so every tone and every stroke picks it
	// up together and the shadow keeps one boundary rather than three.
	float lambert = dot(facing_normal, towards);
	float term = (lambert + wrap) / (1.0 + wrap);
	term += (noise31(world_here * chatter_scale) - 0.5) * chatter_amount;
	// The screen footprint of the lighting term at this pixel, which is what makes
	// every edge below `edge_pixels` wide everywhere on every model.
	float width = max(fwidth(term), 1e-5) * edge_pixels;

	vec3 dark;
	float level;
	vec3 colour;
	if (look_mode == LOOK_BANDS) {
		colour = look_bands(sunlit, shade, term, width, dark, level);
	} else if (look_mode == LOOK_STEP) {
		colour = look_step(sunlit, shade, term, width, dark, level);
	} else if (look_mode == LOOK_SMOOTH) {
		colour = look_smooth(sunlit, shade, term, dark, level);
	} else if (look_mode == LOOK_RAMP) {
		colour = look_ramp(here, term, dark, level);
	} else {
		colour = look_comic(here, sunlit, shade, core, term, width, dark, level);
	}

	// --- stage 4: the thrown shadow ---------------------------------------------
	//
	// **Composited, not multiplied.** Every look used to multiply its result by the
	// shadow term, which sends three of them to pure black wherever a tree falls —
	// and `wrap` exists precisely so that an unlit side keeps its colour. A thrown
	// shadow takes the surface to its own darkest tone and no further.
	float thrown = mix(shadowed, smoothstep(0.35, 0.65, shadowed), cast_hardness);
	// Released where the surface is turning edge-on to the key — see `cast_grip`.
	// Without it the shadow map's acne there is snapped into hard teeth. Measured on
	// the raw lambert, because where a shadow map stops being reliable is geometry
	// and has nothing to do with which look is worn.
	thrown = mix(1.0, thrown, smoothstep(0.0, cast_grip, lambert));
	colour = mix(dark, colour, thrown);

	// Lit means facing the key *and* not in something's shadow. Everything drawn
	// below reads this to know where to stay off.
	float lit = level * thrown;
	float printable = 1.0 - face_flat;

	// --- stages 5 to 7 ----------------------------------------------------------
	colour = comic_screen(colour, term, thrown, lit, pixel, printable);
	colour = comic_ink(colour, facing_normal, term, thrown, lit, width, printable);
	colour = comic_added(colour, here, facing_normal, towards, eye, thrown, printable);

	diffuse += colour * light_colour * OVER_PI;
}

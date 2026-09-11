// The printed look, once, for every surface in the game.
//
// This was the body of `comic.gdshader` and nothing in it has changed in kind:
// the uniforms, the helpers and the order of operations are the ones that were
// tuned there. What changed is that it is no longer only the creatures' look. The
// world wears it too — tiles, props, grass, the character — and a look computed
// in two files is a look that drifts. One terminator, one pair of screens, one
// shadow tint, one place to change them.
//
// **The wind is deliberately not here.** Grass moves and almost nothing else
// does, so the wind stays in `grass_parting.gdshader` where its three decisions
// already live (0059 to 0061). This file is what a surface *looks* like; how a
// surface *moves* is the shader's own business. That separation is the reason the
// grass shader can include this without the tiles inheriting a vertex stage they
// have no use for.
//
// ## Why it lives at this address
//
// `comic.gdshader` exists in two copies: this one, tracked, and a copy written
// into the gitignored placeholder quarantine by the asset pipeline (decision
// 0027), which a standalone flat viewer project also uses. A relative include
// resolves in all three places only if the file sits beside the shader that
// includes it — so it sits here, and the world shaders reach it by absolute path.
// The address says `creature`; the contents are the whole game's.
//
// ## What a shader has to do to use it
//
//   shader_type spatial;
//   render_mode unshaded, shadows_disabled, cull_back;
//   #include "res://game/presentation/creature/comic_look.gdshaderinc"
//
//   void vertex() {
//       world_normal = comic_normal(NORMAL, MODEL_MATRIX);
//       world_here = comic_point(VERTEX, MODEL_MATRIX);
//       round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
//   }
//   void fragment() {
//       ALBEDO = comic_shade(comic_paint(UV), SCREEN_UV * VIEWPORT_SIZE,
//               INV_VIEW_MATRIX);
//   }
//
// The built-ins are passed in rather than read here, because a built-in belongs
// to the stage it is declared in and an include has no stage of its own.
//
// `unshaded` is not optional. The pass lights itself from `light_direction`: the
// screentone has to be laid out in screen space against the same value that picks
// the tone, and Godot's `light()` stage runs once per light with no screen
// coordinates in scope. Every surface therefore reads identically under every
// scene — which is what a printed page wants — at the cost of scene lights not
// touching anything. That is why the project has no sun.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable,
		hint_default_white;

// The flat colour under the texture, multiplied into it.
//
// For everything that has no texture at all, which is most of the world: these
// models carry their colour in their materials and nothing else. White by
// default, so a surface that does have a texture is unaffected by its presence —
// which is what keeps the creatures looking exactly as they did.
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Cell offset for the face sheets. Zero on every other surface, which is why the
// body and the eyes can share one shader.
uniform vec2 uv_offset = vec2(0.0, 0.0);

// Raised to 1 on the eye and mouth surfaces by the runtime script. Their artwork
// is already a drawing — laying tone over it fills the whites of the eyes with
// dots and ages the face by twenty years.
uniform float face_flat : hint_range(0.0, 1.0) = 0.0;

group_uniforms paint;
uniform float saturation : hint_range(0.5, 3.0) = 1.34;
uniform float lift : hint_range(0.0, 0.5) = 0.05;
// Snap each channel to this many levels — the ink count of a press. Off below 2,
// and off by default: these atlases are already flat, and quantising faithful
// artwork is a way to lose it, not to stylise it.
uniform float flat_levels : hint_range(0.0, 24.0) = 0.0;

group_uniforms lighting;
// Where the key comes from, world space. Normalised in the shader.
uniform vec3 light_direction = vec3(-0.62, 0.55, 0.56);
// The same key, expressed relative to the camera: x right, y up, z towards the
// viewer.
uniform vec3 light_from_camera = vec3(-0.55, 0.5, 0.67);
// How much the key is pinned to the camera rather than to the world.
//
// This is the difference between a lit model and a *drawn* one. A world-fixed
// key is correct for a lit scene and wrong for a printed page: turn the creature
// and it walks through fully lit, then fully shaded, and the shadow stops
// describing the form. An illustrator relights every panel so the shape always
// reads, and this is that, in one number. Kept short of 1 so a turn still feels
// like a turn instead of a sticker rotating.
//
// **The world sets this to zero**, and that is not an inconsistency. A creature
// is a subject and gets relit so it always reads; the ground is not a subject,
// and a key that swung with the camera would slide the shading across the
// terrain as the player turned. A subject follows the camera, a set does not.
uniform float key_follows_camera : hint_range(0.0, 1.0) = 0.7;
// Where the lit tone gives way, on dot(N, L). 0 is the geometric terminator;
// negative keeps more of the form lit, which is how a comic panel is usually lit.
uniform float terminator : hint_range(-1.0, 1.0) = 0.14;
// Second, deeper step. The one that turns a flat fill into a volume.
uniform float core_level : hint_range(-1.0, 1.0) = -0.34;
// Edge width, in screen pixels, applied to both steps. The value is a *pixel*
// count because the width is taken from the derivative of the lighting term, so
// it means the same thing everywhere on the model.
uniform float edge_pixels : hint_range(0.5, 4.0) = 1.2;

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
// This is the difference between a shadow that is darker and a shadow that is
// worked.
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
// This is where the light bounce used to be, and it is its opposite. A bounce is
// a bright band on the shaded silhouette — physically right, and it reads as
// gloss, which is the one thing this look must not have. An inker draws the
// other thing there: a heavier stroke on the shadow side of the edge, so the
// boundary is a *line* and not merely where two fills meet.
//
// On the world this is the only ink there is. A creature gets a silhouette from
// the separate `outline.gdshader` pass hung on its material; ninety-two library
// items each growing a second pass is a cost nobody has measured and nobody
// asked for, so world props carry the terminator stroke and no outline.
uniform float edge_line : hint_range(0.0, 1.0) = 0.28;
// How far into the shadow the line reaches, on dot(N, L).
uniform float edge_line_width : hint_range(0.0, 0.5) = 0.10;

group_uniforms chatter;
// Wobble on the terminator, in the units of dot(N, L), from a noise fixed to the
// surface rather than to the screen — so it travels with the creature the way a
// drawn line would, instead of crawling under it.
//
// A shadow boundary computed from a normal is perfectly smooth, and perfectly
// smooth is the tell. This is small on purpose: enough that the eye reads a
// stroke, not enough to read as noise.
uniform float chatter_amount : hint_range(0.0, 0.2) = 0.035;
uniform float chatter_scale : hint_range(1.0, 200.0) = 46.0;

group_uniforms form;
// Blend the shading normal towards the one a sphere would have at this point,
// around the mesh's own centre — pushed in by the runtime script.
//
// The mesh normal is faithful, and faithful is the problem: a torso is not a
// smooth ovoid, it has soft undulations, and a razor terminator crossing them
// breaks into blotches. An illustrator draws the shadow of the *form*, not of
// the surface. Rounding the normal is how that reads, and it costs one mix.
// Past about half the model stops turning at all, so this stays a correction.
//
// Left at zero on the world, where a wall is genuinely flat and rounding its
// normal would bend a shadow across something the eye knows to be straight.
uniform vec3 shape_centre = vec3(0.0, 0.0, 0.0);
uniform float shape_round : hint_range(0.0, 1.0) = 0.35;

group_uniforms volume;
// A whisper of sky above and ground below. Off by default: it is a smooth ramp,
// and a smooth ramp across a flat fill is exactly what made the belly read as
// polished. The three tones carry the volume instead.
uniform float ground_shade : hint_range(0.0, 0.6) = 0.0;

varying vec3 world_normal;
varying vec3 round_normal;
varying vec3 world_here;


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

// One halftone cell's coverage, for a dot of `radius` in cell units.
//
// The edge is a fixed number of pixels rather than a fraction of the dot, so a
// dot stays equally crisp whether it is a speck at the terminator or nearly
// filling its cell deep in shadow. `fract` would break `fwidth` at the cell
// seam, so the width is derived from the cell size instead of measured.
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


// What the vertex stage owes the look: the surface, in world space.
//
// Two pure functions rather than one that fills the varyings, because the language
// forbids the tidier thing — **a varying may only be assigned inside `vertex()`**,
// not in a function it calls. So the maths lives here and the three assignments
// belong to each shader:
//
//   void vertex() {
//       world_normal = comic_normal(NORMAL, MODEL_MATRIX);
//       world_here = comic_point(VERTEX, MODEL_MATRIX);
//       round_normal = world_here - comic_point(shape_centre, MODEL_MATRIX);
//   }
//
// Both take the vertex and normal rather than reading `VERTEX` and `NORMAL`, so a
// shader that moves its geometry hands over the moved version. The grass does
// exactly that, and a normal left behind by a displaced vertex is the usual way
// animated foliage ends up shaded wrong.
vec3 comic_normal(vec3 normal, mat4 model) {
	return normalize((model * vec4(normal, 0.0)).xyz);
}

vec3 comic_point(vec3 vertex, mat4 model) {
	return (model * vec4(vertex, 1.0)).xyz;
}


// The flat colour of a surface before any light touches it: its texture, its
// colour, or both.
vec3 comic_paint(vec2 uv) {
	vec3 sampled = texture(albedo_tex, fract(uv + uv_offset)).rgb * albedo.rgb;
	return posterise(enrich(sampled));
}


// The printed surface: two steps, two screens and a stroke.
//
// `pixel` is the position on screen in pixels, which is where the halftone lives
// — a screen belongs to the paper, not to the model. `inv_view` turns the
// camera-relative key into a world one.
vec3 comic_shade(vec3 paint, vec2 pixel, mat4 inv_view) {
	vec3 normal = normalize(world_normal);
	if (length(round_normal) > 1e-5) {
		normal = normalize(mix(normal, normalize(round_normal), shape_round));
	}
	vec3 from_camera = (inv_view * vec4(normalize(light_from_camera), 0.0)).xyz;
	vec3 key = normalize(mix(normalize(light_direction), normalize(from_camera),
			key_follows_camera));
	float facing = dot(normal, key);
	// The wobble goes in before the steps, so both tones and the edge line pick
	// it up together and the shadow keeps one boundary rather than three.
	facing += (noise31(world_here * chatter_scale) - 0.5) * chatter_amount;

	// The whole reason the edge holds up: its width is the screen footprint of
	// the lighting term at this pixel, so it is `edge_pixels` wide everywhere.
	float width = max(fwidth(facing), 1e-5) * edge_pixels;

	float lit = smoothstep(terminator - width, terminator + width, facing);
	float above_core = smoothstep(core_level - width, core_level + width, facing);

	vec3 first = shaded(paint, shadow_depth);
	vec3 core = shaded(paint, min(shadow_depth + core_extra, 0.95));
	vec3 colour = mix(core, first, above_core);
	colour = mix(colour, paint, lit);

	float printable = (1.0 - face_flat);

	// Two tones, not one, and that is what makes the shadow read as worked
	// rather than filled. The first is a coarse screen laid across the whole
	// shaded side, growing with how far past the terminator the surface has
	// turned. Keying it to the stepped value instead would give a flat field of
	// identical dots.
	float depth = clamp((terminator - facing) / max(dots_reach, 0.001), 0.0, 1.0);
	float coarse = halftone(pixel, depth * dots_max, dots_size, dots_angle);
	colour = mix(colour, colour * (1.0 - dots_darken),
			coarse * dots_amount * (1.0 - lit) * printable);

	// The second is finer and turned off the first, so the two grids beat against
	// each other the way two screentone sheets do. It is confined to the core, so
	// the deepest part of the form gains density instead of only darkness.
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

	// Sky above, ground below. Off by default — see `ground_shade`.
	if (ground_shade > 0.0) {
		float sky = normal.y * 0.5 + 0.5;
		colour *= mix(1.0 - ground_shade, 1.0, sky);
	}

	return colour;
}

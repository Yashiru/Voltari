shader_type spatial;

// Comic-book surface for the creatures. Third look in the set, sitting beside
// `toon.gdshader` and `bd.gdshader` — nothing is replaced, pick one with the
// `style` property on the placeholder root or `style=comic` on the viewer.
//
// The brief: flat, printed, no gloss, screentone in the shadow, and it must not
// make a low-poly model look low-poly.
//
// That last one is the whole design. The first attempt drew its interior lines
// from `fwidth(NORMAL)` — how fast the normal turns across a pixel. On a smooth
// model that is a crease; on these models it is *the wireframe*, because every
// polygon edge is a step in the normal. It inked the topology and the creature
// read as faceted. There is no interior ink here at all: the silhouette is the
// outline pass's job, and anything that keys on per-face normal change is a
// topology detector wearing a costume.
//
// What carries the form instead:
//
//   1. one terminator, and it is razor sharp — but anti-aliased *analytically*,
//      from the screen-space derivative of the lighting term itself, so the edge
//      is the same one or two pixels wide on a broad belly and on a tight ear.
//      A fixed softness is what makes stylised shading read as mushy on one part
//      and jagged on another.
//   2. two shadow steps, not one. The core shadow is what stops a flat fill from
//      looking like a sticker, and it is the cheapest volume there is.
//   3. two screentones, not one. A coarse screen across the whole shaded side
//      and a finer one turned 27 degrees off it, confined to the core, so the
//      two grids beat against each other the way two sheets do. Both printed in
//      the material's *own* colour darkened — never in black. Black dots on a
//      yellow body read as dirt.
//   4. a stroke on the shadow side of the terminator. Everything above draws
//      areas; this draws the line between them, which is what an inker does.
//   5. a wobble on the terminator, from a noise fixed to the surface. A boundary
//      computed from a normal is perfectly smooth, and perfectly smooth is the
//      tell.
//
// There is no highlight and no bounce, and no smooth ramp anywhere. An earlier
// pass had a bright band along the shaded silhouette — reflected light, which is
// physically right and reads as gloss — and a gentle sky-to-ground gradient.
// Between them they put a polish on every belly. Both are gone; the tones carry
// the volume.
//
// The pass is `unshaded` and lights itself from `light_direction`. The screentone
// has to be laid out in screen space against the same value that picks the tone,
// and Godot's `light()` stage runs once per light with no screen coordinates in
// scope. Lighting here makes every creature read identically under every scene —
// which is what a printed page wants — at the cost of scene lights not touching
// them. Deliberate, and the reason the light direction is exposed.

render_mode blend_mix, cull_back, unshaded, shadows_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

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

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_here = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 middle = (MODEL_MATRIX * vec4(shape_centre, 1.0)).xyz;
	round_normal = world_here - middle;
}

void fragment() {
	vec3 paint = posterise(enrich(texture(albedo_tex, fract(UV + uv_offset)).rgb));

	vec3 normal = normalize(world_normal);
	if (length(round_normal) > 1e-5) {
		normal = normalize(mix(normal, normalize(round_normal), shape_round));
	}
	vec3 from_camera = (INV_VIEW_MATRIX * vec4(normalize(light_from_camera), 0.0)).xyz;
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

	vec2 pixel = SCREEN_UV * VIEWPORT_SIZE;
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

	ALBEDO = colour;
}

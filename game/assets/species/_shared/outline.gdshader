shader_type spatial;

// Ink line, drawn as a second pass on the same mesh: the shell is grown along
// its normals and its front faces are culled, so only the part that pokes out
// behind the silhouette survives.
//
// The growth happens in view space, scaled by distance, so the line keeps the
// same thickness on screen whether the creature is a 0.9 m Bulbasaur or a 2.4 m
// Charizard. Growing in local space instead made the line thickness track the
// model's size, which is exactly wrong for a roster meant to read as one set.

render_mode cull_front, unshaded, shadows_disabled, depth_draw_opaque;

uniform float thickness : hint_range(0.0, 8.0) = 1.8;
uniform vec4 line_colour : source_color = vec4(0.10, 0.09, 0.14, 1.0);

// How much the line takes on the creature's own colour. Pure black reads as a
// sticker cut out of the background; a line tinted towards the surface keeps
// the drawing warm.
uniform float tint_from_albedo : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	view.xyz += view_normal * thickness * (-view.z) * 0.0016;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	ALBEDO = mix(line_colour.rgb, line_colour.rgb * tint.rgb, tint_from_albedo);
}

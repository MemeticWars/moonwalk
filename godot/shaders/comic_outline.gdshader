shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, cull_disabled;

// Full-screen comic outline: depth-only edge detection, no model changes.
// Normal edge detection was removed -- it outlined every grass blade and every
// small surface detail. The second-difference depth operator below fires on
// silhouettes and hard creases but stays quiet on smooth slopes and on a dense
// field of grass. Needs the Forward+ renderer.
//
// Known limitation: alpha-transparent geometry drawn in the same transparent
// pass (rain, wheel tracks, greenhouse glass, the helmet visor) is not
// reliably present in screen_texture here, so it loses its colour under this
// outline regardless of render_priority. See the comment on `outline` in
// theia.gd for what was tried (SubViewport exclusion mask -- fixed ink but
// not the erasure; CanvasLayer canvas_item -- blocked by canvas_item not
// supporting hint_depth_texture in this Godot version) and what the real fix
// would take (a CompositorEffect, not yet implemented).

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 line_color : source_color = vec4(0.02, 0.02, 0.03, 1.0);
uniform float line_width : hint_range(0.5, 5.0) = 1.4;
// Raise this if fine detail (grass, gravel) still gets outlined: 0.045, then 0.07.
uniform float depth_threshold : hint_range(0.001, 0.3) = 0.08;
// Metres past which outlines fade out, so the far horizon stays clean.
uniform float far_fade_m : hint_range(50.0, 20000.0) = 3000.0;

varying mat4 inv_proj;

float linear_depth(vec2 uv) {
	float depth = texture(depth_texture, uv).r;
	vec4 view = inv_proj * vec4(vec3(uv * 2.0 - 1.0, depth), 1.0);
	return -(view.xyz / view.w).z;
}

void vertex() {
	// Quad covers the whole screen; sits at the near plane (Godot reverse-Z).
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
	inv_proj = inverse(PROJECTION_MATRIX);
}

void fragment() {
	vec2 pixel = 1.0 / vec2(textureSize(screen_texture, 0));
	vec2 step_uv = pixel * line_width;

	vec3 original = texture(screen_texture, SCREEN_UV).rgb;

	float d0 = linear_depth(SCREEN_UV);
	float d1 = linear_depth(SCREEN_UV + vec2(step_uv.x, 0.0));
	float d2 = linear_depth(SCREEN_UV - vec2(step_uv.x, 0.0));
	float d3 = linear_depth(SCREEN_UV + vec2(0.0, step_uv.y));
	float d4 = linear_depth(SCREEN_UV - vec2(0.0, step_uv.y));

	// Second difference: fires on silhouettes and creases, not on smooth slopes.
	float depth_edge = max(abs(d1 + d2 - 2.0 * d0), abs(d3 + d4 - 2.0 * d0));
	depth_edge /= max(d0, 0.01);

	float edge = smoothstep(depth_threshold, depth_threshold * 2.0, depth_edge);

	// No outline on the sky / very distant geometry.
	edge *= 1.0 - smoothstep(far_fade_m * 0.6, far_fade_m, d0);

	ALBEDO = mix(original, line_color.rgb, edge * line_color.a);
}

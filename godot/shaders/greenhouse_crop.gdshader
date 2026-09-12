shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_alpha_prepass;

uniform sampler2D crop_texture : source_color, filter_linear_mipmap;

void fragment() {
	vec4 colour = texture(crop_texture, UV);
	// The supplied crop renders use a saturated blue studio background.
	if (colour.b > colour.r * 1.24 && colour.b > colour.g * 1.12 && colour.b > 0.28) {
		discard;
	}
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
}

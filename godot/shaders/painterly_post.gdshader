shader_type canvas_item;
render_mode unshaded;

// Full-screen painterly post-process. Sits on a CanvasLayer (layer 0) above the
// 3D view — including the comic/Moebius outline quad — and below the HUD. It
// never touches models, materials or lights. Cycle with B.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform int style = 0;
// 0 = realistic (pass-through)
// 1 = pastel
// 2 = watercolor
// 3 = oil paint (Kuwahara)
// 4 = ink + watercolor
uniform float strength : hint_range(0.0, 1.0) = 1.0;
// Style 4 ink tuning. threshold: higher = fewer lines. strength: line opacity
// (1.0 = solid black). scale: Sobel sample spacing in pixels — larger skips
// regolith micro-speckle and only inks real edges.
uniform float ink_threshold : hint_range(0.02, 1.0) = 0.52;
uniform float ink_strength : hint_range(0.0, 1.0) = 0.5;
uniform float ink_scale : hint_range(1.0, 5.0) = 2.4;


/* ========================= HELPERS ========================= */

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 posterize(vec3 c, float levels) {
	return floor(c * levels + 0.5) / levels;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


/* ========================= PASTEL ========================= */

vec3 pastel(vec3 color) {
	float l = luminance(color);
	// lightly reduce saturation
	vec3 desaturated = mix(vec3(l), color, 0.72);
	// lift the blacks
	desaturated = desaturated * 0.86 + 0.11;
	// gentle lift
	desaturated = pow(desaturated, vec3(0.90));
	// faintly warm highlights
	desaturated *= vec3(1.03, 1.00, 0.96);
	return clamp(desaturated, 0.0, 1.0);
}


/* ========================= WATERCOLOR ========================= */

vec3 watercolor(vec2 uv, vec2 px) {
	vec3 c = vec3(0.0);
	// soft 3x3 blur
	c += texture(screen_texture, uv).rgb * 4.0;
	c += texture(screen_texture, uv + vec2(px.x, 0.0)).rgb * 2.0;
	c += texture(screen_texture, uv - vec2(px.x, 0.0)).rgb * 2.0;
	c += texture(screen_texture, uv + vec2(0.0, px.y)).rgb * 2.0;
	c += texture(screen_texture, uv - vec2(0.0, px.y)).rgb * 2.0;
	c += texture(screen_texture, uv + px).rgb;
	c += texture(screen_texture, uv - px).rgb;
	c += texture(screen_texture, uv + vec2(px.x, -px.y)).rgb;
	c += texture(screen_texture, uv + vec2(-px.x, px.y)).rgb;
	c /= 16.0;

	// palette reduction
	c = posterize(c, 14.0);

	float l = luminance(c);
	// faintly pastel pigments
	c = mix(vec3(l), c, 0.82);

	// paper / uneven-pigment grain
	float grain = hash(floor(uv * vec2(900.0, 600.0)));
	grain = (grain - 0.5) * 0.035;
	c += grain;

	// bright paper bleeding through the paint
	c = mix(c, vec3(1.0), 0.035);

	return clamp(c, 0.0, 1.0);
}


/* ========================= OIL PAINT / KUWAHARA ========================= */

vec3 oil_paint(vec2 uv, vec2 px) {
	const int R = 3;

	vec3 mean0 = vec3(0.0);
	vec3 mean1 = vec3(0.0);
	vec3 mean2 = vec3(0.0);
	vec3 mean3 = vec3(0.0);

	vec3 sq0 = vec3(0.0);
	vec3 sq1 = vec3(0.0);
	vec3 sq2 = vec3(0.0);
	vec3 sq3 = vec3(0.0);

	float count = float((R + 1) * (R + 1));

	// top-left
	for (int y = -R; y <= 0; y++) {
		for (int x = -R; x <= 0; x++) {
			vec3 c = texture(screen_texture, uv + vec2(float(x), float(y)) * px).rgb;
			mean0 += c;
			sq0 += c * c;
		}
	}
	// top-right
	for (int y = -R; y <= 0; y++) {
		for (int x = 0; x <= R; x++) {
			vec3 c = texture(screen_texture, uv + vec2(float(x), float(y)) * px).rgb;
			mean1 += c;
			sq1 += c * c;
		}
	}
	// bottom-left
	for (int y = 0; y <= R; y++) {
		for (int x = -R; x <= 0; x++) {
			vec3 c = texture(screen_texture, uv + vec2(float(x), float(y)) * px).rgb;
			mean2 += c;
			sq2 += c * c;
		}
	}
	// bottom-right
	for (int y = 0; y <= R; y++) {
		for (int x = 0; x <= R; x++) {
			vec3 c = texture(screen_texture, uv + vec2(float(x), float(y)) * px).rgb;
			mean3 += c;
			sq3 += c * c;
		}
	}

	mean0 /= count;
	mean1 /= count;
	mean2 /= count;
	mean3 /= count;

	sq0 /= count;
	sq1 /= count;
	sq2 /= count;
	sq3 /= count;

	vec3 var0 = abs(sq0 - mean0 * mean0);
	vec3 var1 = abs(sq1 - mean1 * mean1);
	vec3 var2 = abs(sq2 - mean2 * mean2);
	vec3 var3 = abs(sq3 - mean3 * mean3);

	float v0 = var0.r + var0.g + var0.b;
	float v1 = var1.r + var1.g + var1.b;
	float v2 = var2.r + var2.g + var2.b;
	float v3 = var3.r + var3.g + var3.b;

	vec3 result = mean0;
	float lowest = v0;

	if (v1 < lowest) {
		lowest = v1;
		result = mean1;
	}
	if (v2 < lowest) {
		lowest = v2;
		result = mean2;
	}
	if (v3 < lowest) {
		result = mean3;
	}

	// a little palette reduction reads as more painterly
	result = posterize(result, 24.0);
	return result;
}


/* ========================= INK + WATERCOLOR ========================= */

// Luminance sampled with a small cross blur, so single-pixel regolith speckle
// doesn't trip the Sobel — only real tonal edges do.
float ink_luma(vec2 uv, vec2 px) {
	float c = luminance(texture(screen_texture, uv).rgb);
	c += luminance(texture(screen_texture, uv + vec2(px.x, 0.0)).rgb);
	c += luminance(texture(screen_texture, uv - vec2(px.x, 0.0)).rgb);
	c += luminance(texture(screen_texture, uv + vec2(0.0, px.y)).rgb);
	c += luminance(texture(screen_texture, uv - vec2(0.0, px.y)).rgb);
	return c / 5.0;
}

// Watercolored fills with an ink line pulled from a luminance Sobel on the sharp
// screen, composited on top so the line stays crisp. Only style where the K
// outline (drawn into the screen before this pass) survives, instead of being
// smeared by the blur.
vec3 ink_watercolor(vec2 uv, vec2 px) {
	vec3 fill = watercolor(uv, px);

	vec2 e = px * ink_scale;
	float l00 = ink_luma(uv + vec2(-e.x, -e.y), px);
	float l10 = ink_luma(uv + vec2(0.0, -e.y), px);
	float l20 = ink_luma(uv + vec2(e.x, -e.y), px);
	float l01 = ink_luma(uv + vec2(-e.x, 0.0), px);
	float l21 = ink_luma(uv + vec2(e.x, 0.0), px);
	float l02 = ink_luma(uv + vec2(-e.x, e.y), px);
	float l12 = ink_luma(uv + vec2(0.0, e.y), px);
	float l22 = ink_luma(uv + vec2(e.x, e.y), px);

	float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
	float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
	float edge = length(vec2(gx, gy));

	// Wide smoothstep band + capped opacity: thinner, sparser lines that read as
	// pen strokes on the big shapes rather than crosshatching every pebble.
	float ink = smoothstep(ink_threshold, ink_threshold * 3.0, edge) * ink_strength;
	return mix(fill, vec3(0.05, 0.05, 0.06), ink);
}


/* ========================= MAIN ========================= */

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;

	vec3 original = texture(screen_texture, uv).rgb;
	vec3 result = original;

	if (style == 1) {
		result = pastel(original);
	} else if (style == 2) {
		result = watercolor(uv, px);
	} else if (style == 3) {
		result = oil_paint(uv, px);
	} else if (style == 4) {
		result = ink_watercolor(uv, px);
	}

	COLOR = vec4(mix(original, result, strength), 1.0);
}

shader_type spatial;
render_mode cull_disabled;

// Lawn grass blade for a MultiMesh. Per instance, INSTANCE_CUSTOM carries
//   x = heading (yaw)      y = wind phase
//   z = blade height (m)   w = shade jitter 0..1
// so the mesh transform can stay translation-only (needed to bend in world space
// without an inverse model matrix). Blades bend away from recent walker
// positions ("disturbers") and wobble for ~1 s as the disturbance decays.
// Shorter blades are tinted lighter; every blade also gets a small random shade.

uniform vec3 color_tall : source_color = vec3(0.15, 0.52, 0.09);   // long blades: deep green
uniform vec3 color_short : source_color = vec3(0.47, 0.87, 0.32);  // short blades: bright pale green
uniform float emission_amount : hint_range(0.0, 2.0) = 0.5;
uniform float mesh_height = 0.4;   // the quad's built height; per-blade height rescales it
uniform float short_ref = 0.15;    // height that reads as fully "short"
uniform float tall_ref = 0.60;     // height that reads as fully "tall"

// xyz = world position, w = strength 0..1 (decayed on the CPU side).
uniform vec4 disturbers[8];
uniform int disturber_count = 0;
uniform float reach = 0.45;       // only blades right around Agnes's feet/legs react
uniform float push_strength = 0.33;
uniform float breeze = 0.012;     // idle sway amplitude at the tip

varying vec3 blade_tint;

void vertex() {
	float yaw = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float h = INSTANCE_CUSTOM.z > 0.001 ? INSTANCE_CUSTOM.z : mesh_height;
	float jitter = INSTANCE_CUSTOM.w;

	float cs = cos(yaw);
	float sn = sin(yaw);
	// Spin the quad (XY plane, facing +Z) around Y and stretch it to this blade's height.
	vec3 v = vec3(VERTEX.x * cs, VERTEX.y * (h / mesh_height), VERTEX.x * sn);
	float up = clamp(VERTEX.y / mesh_height, 0.0, 1.0);

	vec3 base = MODEL_MATRIX[3].xyz;  // instance transform is translation only
	vec2 bend = vec2(0.35, 0.15) * (breeze * sin(TIME * 1.7 + phase));
	for (int i = 0; i < disturber_count; i++) {
		vec2 delta = base.xz - disturbers[i].xz;
		float dist = length(delta);
		float infl = disturbers[i].w * smoothstep(reach, 0.0, dist);
		vec2 away = dist > 1e-4 ? delta / dist : vec2(1.0, 0.0);
		bend += away * infl * (push_strength + 0.14 * sin(TIME * 16.0 + phase));
	}
	v.xz += bend * up;
	VERTEX = v;
	NORMAL = normalize(vec3(sn, 0.4, cs));

	float shortness = clamp((tall_ref - h) / (tall_ref - short_ref), 0.0, 1.0);
	vec3 col = mix(color_tall, color_short, shortness);
	col *= mix(0.87, 1.13, jitter);   // per-blade shade variation
	blade_tint = clamp(col, vec3(0.0), vec3(1.0));
}

void fragment() {
	ALBEDO = blade_tint;
	ROUGHNESS = 1.0;
	EMISSION = blade_tint * emission_amount;
}

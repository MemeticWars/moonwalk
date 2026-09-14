extends Node3D
## Excavated D1 (1 m) and m3 (1.5 m) ponds, linked by a rounded brook.
## The terrain owns the 50 cm wide/deep U-shaped bed and its collision;
## this node owns only the level water surface and decorative fish.
## All water surfaces share one ShaderMaterial built from the vendored
## Boujie Water Shader (godot/addons/boujie_water_shader), its ocean-scale
## defaults rescaled down for garden-pond size.
const City := preload("res://scripts/tycho_city.gd")
const Layout := preload("res://scripts/tycho_water_layout.gd")
const WATER_SHADER := preload("res://addons/boujie_water_shader/shader/water.gdshader")
const SHADER_DIR := "res://addons/boujie_water_shader/shader/"

## Terrain, water and grass all use the same shared layout.
const POND1_CENTER := City.POND1_CENTER
const POND1_RADII := City.POND1_RADII
const STREAM_WIDTH := City.STREAM_WIDTH
const POND2_RADII := City.POND2_RADII
const WATER_LEVEL_OFFSET := -0.125 # 10 cm below the previous -0.025 m surface.

var terrain: Node3D
var built := false

func _ready() -> void:
	name = "TychoWaterFeature"

func _sites() -> Array[Vector2]:
	return [POND1_CENTER, Layout.POND2_CENTER]

func _process(_delta: float) -> void:
	var near := false
	for site: Vector2 in _sites():
		var tile := Vector2i(floori(site.x / terrain.TILE), floori(site.y / terrain.TILE))
		if maxi(absi(tile.x - terrain.center.x), absi(tile.y - terrain.center.y)) <= terrain.FAR_RADIUS:
			near = true
			break
	# The m3 pond needs m3's own graded pad level (registered by
	# TychoEastAnnex._build()) to already exist, so terrain.height_at() there
	# reads the flat pad rather than the raw crater-floor slope.
	var annex: Node = get_parent().get_node_or_null("TychoEastAnnex")
	var ready_to_build: bool = near and annex != null and annex.built
	if ready_to_build == built:
		return
	built = ready_to_build
	if built:
		_build()
	else:
		for child in get_children():
			child.queue_free()

func _make_water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	# Keep the project's opaque water-shader fork: its lack of screen/depth
	# reads makes the surface visible with the default outline effect.
	# albedo_fresnel is the grazing-angle colour (what a near-horizontal view
	# blends toward, i.e. what reads as "the sky reflecting off the water") --
	# a pale blue-grey here instead of near-black keeps the lunar sky's black
	# from dominating the pond at shallow viewing angles. Raised roughness
	# softens the mirror-sharp reflection that made that blackness so stark.
	mat.set_shader_parameter("albedo_fresnel", Color(0.22, 0.34, 0.40, 1.0))
	mat.set_shader_parameter("specular", 0.6)
	mat.set_shader_parameter("roughness", 0.30)
	mat.set_shader_parameter("metallic", 0.0)
	# True alpha would move water into the transparent pass, where the current
	# outline effect erases it. Screen-door coverage instead leaves stable holes
	# in the opaque surface, so the excavated bed and swimming fish really show
	# through while the remaining samples preserve reflections and wave light.
	mat.set_shader_parameter("coverage_shallow", 0.56)
	mat.set_shader_parameter("coverage_deep", 0.80)
	mat.set_shader_parameter("vertex_displace_from_mesh_normal", true)
	mat.set_shader_parameter("normal_wave_from_mesh_normal", true)
	mat.set_shader_parameter("texture_albedo", load(SHADER_DIR + "ocean_albedo_white_highcontrast.png"))
	mat.set_shader_parameter("refraction", 0.03)
	mat.set_shader_parameter("refraction_texture_channel", Vector4(1, 0, 0, 0))
	mat.set_shader_parameter("refraction_opacity", 0.5)
	mat.set_shader_parameter("texture_refraction", load(SHADER_DIR + "refraction.png"))
	mat.set_shader_parameter("shore_start_blend", 0.05)
	mat.set_shader_parameter("shore_end_blend", 0.6)
	mat.set_shader_parameter("texture_foam", load(SHADER_DIR + "foam_2.png"))
	mat.set_shader_parameter("distance_fade_min", 300.0)
	mat.set_shader_parameter("distance_fade_max", 800.0)
	mat.set_shader_parameter("near_fade_min", 0.3)
	mat.set_shader_parameter("near_fade_max", 0.5)
	mat.set_shader_parameter("foam_fade_min", 400.0)
	mat.set_shader_parameter("foam_fade_max", 800.0)
	mat.set_shader_parameter("shore_fade_min", 400.0)
	mat.set_shader_parameter("shore_fade_max", 800.0)
	mat.set_shader_parameter("vertex_wave_fade_min", 400.0)
	mat.set_shader_parameter("vertex_wave_fade_max", 800.0)
	mat.set_shader_parameter("depth_fog_fade_min", 400.0)
	mat.set_shader_parameter("depth_fog_fade_max", 800.0)
	mat.set_shader_parameter("refraction_scaling_distance_min", 20.0)
	mat.set_shader_parameter("uv_blend_sharpness", 2.0)
	mat.set_shader_parameter("uv_tri_scale", Vector3(6.0, 6.0, 6.0))
	mat.set_shader_parameter("uv_tri_offset", Vector3.ZERO)
	# Excavation is real geometry, but the outline post-process forbids this
	# material from reading the depth texture (see the shader's top-of-file
	# comment), so "deep" vs "shallow" can't be read from actual water depth.
	# Instead color_deep/color_shallow are blended by vertex COLOR.r, a 1.0
	# (pond centre) -> 0.0 (pond rim / anywhere along the uniformly-shallow
	# stream) weight baked in when the mesh is built (_add_pond/_add_stream).
	mat.set_shader_parameter("color_deep", Color(0.03, 0.16, 0.30, 1.0))
	mat.set_shader_parameter("color_shallow", Color(0.42, 0.58, 0.58, 1.0))
	mat.set_shader_parameter("beers_law", 2.2)
	mat.set_shader_parameter("depth_offset", -0.6)
	mat.set_shader_parameter("albedo_snell", Color(0.025, 0.035, 0.04, 1.0))
	mat.set_shader_parameter("snell_direction", Vector3(0, 1, 0))
	mat.set_shader_parameter("snell_tightness", 0.6)
	# Steepnesses are direct vertical displacement in metres (P_DEG's result.y
	# = Steepness * sin(...)); the old 0.25 m on a ~3-4.5 m-radius garden pond
	# mesh dwarfed the pond itself. Cut roughly 6x across the board.
	mat.set_shader_parameter("WaveCount", 3)
	mat.set_shader_parameter("WaveSteepnesses", PackedFloat32Array([0.04, 0.025, 0.015]))
	mat.set_shader_parameter("WaveAmplitudes", PackedFloat32Array([0.0008, 0.0006, 0.0004]))
	mat.set_shader_parameter("WaveDirectionsDegrees", PackedFloat32Array([15, 110, 200]))
	mat.set_shader_parameter("WaveFrequencies", PackedFloat32Array([0.35, 0.5, 0.7]))
	mat.set_shader_parameter("WaveSpeeds", PackedFloat32Array([0.6, 0.5, 0.8]))
	mat.set_shader_parameter("WavePhases", PackedFloat32Array([0, 0, 0]))
	mat.set_shader_parameter("FoamWaveCount", 2)
	mat.set_shader_parameter("FoamWaveSteepnesses", PackedFloat32Array([0.3, 0.2]))
	mat.set_shader_parameter("FoamWaveAmplitudes", PackedFloat32Array([0.15, 0.1]))
	mat.set_shader_parameter("FoamWaveDirectionsDegrees", PackedFloat32Array([20, 190]))
	mat.set_shader_parameter("FoamWaveFrequencies", PackedFloat32Array([0.4, 0.6]))
	mat.set_shader_parameter("FoamWaveSpeeds", PackedFloat32Array([0.5, 0.4]))
	mat.set_shader_parameter("FoamWavePhases", PackedFloat32Array([0, 0]))
	mat.set_shader_parameter("UVWaveCount", 2)
	mat.set_shader_parameter("UVWaveSteepnesses", PackedFloat32Array([0.08, 0.06]))
	mat.set_shader_parameter("UVWaveAmplitudes", PackedFloat32Array([0.4, 0.3]))
	mat.set_shader_parameter("UVWaveDirectionsDegrees", PackedFloat32Array([300, 90]))
	mat.set_shader_parameter("UVWaveFrequencies", PackedFloat32Array([0.6, 0.4]))
	mat.set_shader_parameter("UVWaveSpeeds", PackedFloat32Array([0.5, 0.3]))
	mat.set_shader_parameter("UVWavePhases", PackedFloat32Array([0, 0]))
	return mat

func _build() -> void:
	var water_material := _make_water_material()
	_add_pond(POND1_CENTER, POND1_RADII, water_material)
	_add_stream(water_material)
	_add_pond(Layout.POND2_CENTER, POND2_RADII, water_material)
	_add_fish(POND1_CENTER, POND1_RADII * 0.6, terrain.city_level + WATER_LEVEL_OFFSET - 0.275, 3)
	_add_fish(Layout.POND2_CENTER, POND2_RADII * 0.6, terrain.city_level + WATER_LEVEL_OFFSET - 0.375, 7)
	# The old free-roaming stream fish left the narrow curved channel.

func _add_pond(center: Vector2, radii: Vector2, material: ShaderMaterial) -> void:
	var level: float = terrain.city_level + WATER_LEVEL_OFFSET
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var segments := 48
	# Subdivided into concentric rings rather than one centre-to-rim fan: a
	# single fan means every triangle shares the one centre vertex, so vertex-
	# shader wave displacement moved that one point sharply relative to the
	# rim and rendered as flat-shaded triangular spikes ("tongues") radiating
	# out, with a visibly jagged (not smooth-oval) boundary. More rings let
	# the wave vary gradually across many vertices instead.
	var rings := 6
	for ring in range(rings):
		var t0 := float(ring) / float(rings)
		var t1 := float(ring + 1) / float(rings)
		# Vertex colour R is a depth weight (1.0 at centre, 0.0 at rim) the
		# shader blends color_deep/color_shallow by -- see water.gdshader.
		# Squared falloff keeps full "deep" colour to a small core and lets
		# most of the pond read as the paler "shallow" colour, per the
		# request that only the depth read as blue and the banks read as
		# more transparent, not a 50/50 split.
		var w0 := Color(pow(1.0 - t0, 2.0), 0.0, 0.0)
		var w1 := Color(pow(1.0 - t1, 2.0), 0.0, 0.0)
		for i in segments:
			var a0 := TAU * float(i) / float(segments)
			var a1 := TAU * float(i + 1) / float(segments)
			var inner_a := Vector3(radii.x * t0 * cos(a0), 0.0, radii.y * t0 * sin(a0))
			var inner_b := Vector3(radii.x * t0 * cos(a1), 0.0, radii.y * t0 * sin(a1))
			var outer_a := Vector3(radii.x * t1 * cos(a0), 0.0, radii.y * t1 * sin(a0))
			var outer_b := Vector3(radii.x * t1 * cos(a1), 0.0, radii.y * t1 * sin(a1))
			if ring == 0:
				# Innermost ring collapses to the shared centre point.
				st.set_color(w0); st.add_vertex(Vector3.ZERO)
				st.set_color(w1); st.add_vertex(outer_a)
				st.set_color(w1); st.add_vertex(outer_b)
			else:
				st.set_color(w0); st.add_vertex(inner_a)
				st.set_color(w1); st.add_vertex(outer_a)
				st.set_color(w1); st.add_vertex(outer_b)
				st.set_color(w0); st.add_vertex(inner_a)
				st.set_color(w1); st.add_vertex(outer_b)
				st.set_color(w0); st.add_vertex(inner_b)
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Pond"
	mesh.mesh = st.commit()
	mesh.position = Vector3(center.x, level, center.y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _add_stream(material: ShaderMaterial) -> void:
	var STREAM_WAYPOINTS := Layout.route()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var origin := STREAM_WAYPOINTS[0]
	var origin_y: float = terrain.city_level + WATER_LEVEL_OFFSET
	var prev_left := Vector3.ZERO
	var prev_right := Vector3.ZERO
	var have_prev := false
	# Uniformly shallow (50 cm deep, see index/water.md) -- no depth gradient,
	# unlike the ponds. Persists for every add_vertex() call below.
	st.set_color(Color(0.0, 0.0, 0.0))
	for i in range(STREAM_WAYPOINTS.size() - 1):
		var a: Vector2 = STREAM_WAYPOINTS[i]
		var b: Vector2 = STREAM_WAYPOINTS[i + 1]
		var a_y := origin_y
		var b_y := origin_y
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x) * (STREAM_WIDTH * 0.5)
		var a_left := Vector3(a.x + side.x, a_y, a.y + side.y) - Vector3(origin.x, origin_y, origin.y)
		var a_right := Vector3(a.x - side.x, a_y, a.y - side.y) - Vector3(origin.x, origin_y, origin.y)
		var b_left := Vector3(b.x + side.x, b_y, b.y + side.y) - Vector3(origin.x, origin_y, origin.y)
		var b_right := Vector3(b.x - side.x, b_y, b.y - side.y) - Vector3(origin.x, origin_y, origin.y)
		if not have_prev:
			prev_left = a_left
			prev_right = a_right
			have_prev = true
		st.add_vertex(prev_left)
		st.add_vertex(prev_right)
		st.add_vertex(b_right)
		st.add_vertex(prev_left)
		st.add_vertex(b_right)
		st.add_vertex(b_left)
		prev_left = b_left
		prev_right = b_right
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Stream"
	mesh.mesh = st.commit()
	mesh.position = Vector3(origin.x, origin_y, origin.y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _add_fish(center: Vector2, radii: Vector2, level: float, count: int) -> void:
	for i in count:
		var fish := preload("res://scripts/pond_fish.gd").new()
		fish.center = center
		fish.radii = radii
		fish.water_y = level + 0.02
		add_child(fish)

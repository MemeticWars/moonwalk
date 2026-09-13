extends Node3D
## A small pond in D1's west park, a stream flowing from it (through the
## grass alongside the park/service roads, out through D1's m2 airlock
## tunnel) into a large fish pond filling much of m2 -- the west mini-dome,
## picked because it sits due west of D1, same side as the park garden.
## All water surfaces share one ShaderMaterial built from the vendored
## Boujie Water Shader (godot/addons/boujie_water_shader), its ocean-scale
## defaults rescaled down for garden-pond size. Water sits flush on top of
## the already-flat graded pad (no dug basin, no collision) like the
## project's other ground overlays (CityLawn, the road rects) -- fish are
## purely decorative, not walked on.
const City := preload("res://scripts/tycho_city.gd")
const WATER_SHADER := preload("res://addons/boujie_water_shader/shader/water.gdshader")
const SHADER_DIR := "res://addons/boujie_water_shader/shader/"

## Site constants (POND1_CENTER/RADII, STREAM_WAYPOINTS/WIDTH, POND2_RADII)
## live on tycho_city.gd, alongside the other site consts, so its
## _build_grass() can carve matching grass keep-outs out of the same numbers.
const POND1_CENTER := City.POND1_CENTER
const POND1_RADII := City.POND1_RADII
const STREAM_WAYPOINTS := City.STREAM_WAYPOINTS
const STREAM_WIDTH := City.STREAM_WIDTH
const POND2_RADII := City.POND2_RADII

var terrain: Node3D
var built := false

func _ready() -> void:
	name = "TychoWaterFeature"

func _sites() -> Array[Vector2]:
	return [POND1_CENTER, City.M2_CENTER]

func _process(_delta: float) -> void:
	var near := false
	for site: Vector2 in _sites():
		var tile := Vector2i(floori(site.x / terrain.TILE), floori(site.y / terrain.TILE))
		if maxi(absi(tile.x - terrain.center.x), absi(tile.y - terrain.center.y)) <= terrain.FAR_RADIUS:
			near = true
			break
	# The m2 pond needs m2's own graded pad level (registered by
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
	# Alpha is high (not the usual ocean ~0.6): with no dug basin, the
	# "depth" the shader reads between water surface and the ground right
	# beneath it is always near zero, so a translucent shallow-water look
	# would blend in mostly raw ground colour and barely read as water
	# against plain grey terrain (a small garden pond needs to read as
	# water at a glance, not just add a subtle reflection like open ocean).
	#
	# Known limitation, same class as human_base.gd's rain/glass/visor
	# comment above _build_outline(): this material is alpha-blended
	# (Forward+ transparent pass), and the Kreska/K outline post-process
	# (default ON, style "Moebius") reads hint_screen_texture in a way that
	# does not reliably include OTHER alpha-blended geometry from that same
	# pass -- so with the outline on, this water loses its colour exactly
	# like rain does. Not fixable here; the outline's own doc block already
	# explains why (needs a CompositorEffect rewrite, not started). Verify
	# any capture of this water with the outline off first
	# (`theia.set_outline_style(0)`), or the water will appear to not render.
	mat.set_shader_parameter("albedo", Color(0.07, 0.34, 0.48, 0.92))
	mat.set_shader_parameter("albedo_fresnel", Color(0.35, 0.68, 0.82, 1.0))
	mat.set_shader_parameter("specular", 0.6)
	mat.set_shader_parameter("roughness", 0.03)
	mat.set_shader_parameter("metallic", 0.0)
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
	mat.set_shader_parameter("color_deep", Color(0.03, 0.12, 0.2, 1.0))
	# Fully opaque, not the usual transparent shallow-water look: these
	# ponds/streams are shallow decorative overlays on flat, already-graded
	# ground (no dug basin), so depth_blend_power always reads near zero --
	# an alpha-0 shallow colour would let DEPTH_FOG pass the raw screen
	# colour straight through unblended, which is indistinguishable from
	# bare ground on m2's ungrassed floor.
	mat.set_shader_parameter("color_shallow", Color(0.07, 0.34, 0.48, 1.0))
	mat.set_shader_parameter("beers_law", 2.2)
	mat.set_shader_parameter("depth_offset", -0.6)
	mat.set_shader_parameter("albedo_snell", Color(0.0, 0.08, 0.18, 1.0))
	mat.set_shader_parameter("snell_direction", Vector3(0, 1, 0))
	mat.set_shader_parameter("snell_tightness", 0.6)
	mat.set_shader_parameter("WaveCount", 3)
	mat.set_shader_parameter("WaveSteepnesses", PackedFloat32Array([0.25, 0.15, 0.1]))
	mat.set_shader_parameter("WaveAmplitudes", PackedFloat32Array([0.04, 0.03, 0.02]))
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
	_add_pond(City.M2_CENTER, POND2_RADII, water_material)
	_add_fish(POND1_CENTER, POND1_RADII * 0.75, terrain.height_at(POND1_CENTER.x, POND1_CENTER.y), 3)
	_add_fish(City.M2_CENTER, POND2_RADII * 0.75, terrain.height_at(City.M2_CENTER.x, City.M2_CENTER.y), 7)
	for i in range(STREAM_WAYPOINTS.size() - 1):
		var a: Vector2 = STREAM_WAYPOINTS[i]
		var b: Vector2 = STREAM_WAYPOINTS[i + 1]
		var mid := (a + b) * 0.5
		_add_fish(mid, Vector2(a.distance_to(b) * 0.5, STREAM_WIDTH * 0.35), terrain.height_at(mid.x, mid.y), 1)

func _add_pond(center: Vector2, radii: Vector2, material: ShaderMaterial) -> void:
	var level: float = terrain.height_at(center.x, center.y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var segments := 48
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(radii.x * cos(a0), 0.0, radii.y * sin(a0)))
		st.add_vertex(Vector3(radii.x * cos(a1), 0.0, radii.y * sin(a1)))
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "Pond"
	mesh.mesh = st.commit()
	mesh.position = Vector3(center.x, level + 0.05, center.y)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _add_stream(material: ShaderMaterial) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var origin := STREAM_WAYPOINTS[0]
	var origin_y: float = terrain.height_at(origin.x, origin.y) + 0.05
	var prev_left := Vector3.ZERO
	var prev_right := Vector3.ZERO
	var have_prev := false
	for i in range(STREAM_WAYPOINTS.size() - 1):
		var a: Vector2 = STREAM_WAYPOINTS[i]
		var b: Vector2 = STREAM_WAYPOINTS[i + 1]
		var a_y: float = terrain.height_at(a.x, a.y) + 0.05
		var b_y: float = terrain.height_at(b.x, b.y) + 0.05
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
		st.add_vertex(b_right)
		st.add_vertex(prev_right)
		st.add_vertex(prev_left)
		st.add_vertex(b_left)
		st.add_vertex(b_right)
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

extends CharacterBody3D

signal outline_style_changed(index: int)
signal painterly_style_changed(index: int)

var terrain: Node3D
var camera := Camera3D.new()
var pivot := Node3D.new()
var visuals: Array[Node3D] = []
var players: Array[AnimationPlayer] = []
var yaw := 0.25
var pitch := 0.24
var distance := 6.0
var mode := 0
var enabled := true
var visual_yaw := PI
const REFERENCE_HEIGHT_M := 2.0  # suited standing height, also the physics capsule
var reference_height_m := REFERENCE_HEIGHT_M
var collision_radius_m := 0.30
var eye_height_m := 1.75
## Assigned by the active lunar sector before this actor enters the scene.
## Keep the horizontal coordinates so readiness can seat the body on streamed terrain.
var spawn_position := Vector3.ZERO
var total_distance := 0.0
var last_foot := Vector3.ZERO
var footprint_root: Node3D
var footprints: Array[MeshInstance3D] = []
var foot_side := 1.0
## Known limitation, present since this system was first written (not a
## regression from any recent change): rain, wheel tracks, greenhouse glass
## and the helmet visor are alpha-transparent and lose their colour under
## this outline. Measured directly (temp ALBEDO = screen_texture passthrough,
## no edge math at all) -- Godot's hint_screen_texture back-buffer copy for a
## Forward+ transparent-pass spatial material does not reliably contain OTHER
## alpha-blended geometry from the same pass, regardless of render_priority/
## draw order. A CanvasLayer + canvas_item shader (like painterly_post below)
## would read the fully composited frame instead, but canvas_item shaders
## don't support hint_depth_texture in this Godot version (4.6.1) -- confirmed
## by a shader compile error -- so that route is closed here. The real fix
## needs a CompositorEffect (RenderingDevice-level, runs post-transparent
## pass with access to both the composited colour AND depth, no second scene
## render) -- a bigger job, not started. A SubViewport-based "exclusion mask"
## was tried and worked as a mask, but doesn't address the erasure (rain is
## missing from screen_texture regardless of any mask), cost an extra full
## viewport render every frame, and was removed.
var outline: MeshInstance3D
## 0 = off, 1 = Comic, 2 = Moebius. K starts in the Moebius mode by default.
var outline_style := 2
const OUTLINE_STYLES := ["Wyłączona", "Komiks", "Moebius"]
const OUTLINE_SHADERS := [
	null,
	preload("res://shaders/comic_outline.gdshader"),
	preload("res://shaders/moebius_outline.gdshader"),
]
## Painterly surface post-process, independent of the outline. 0 = realistic;
## B starts in this realistic mode by default.
## (layer hidden). Cycled with B or the pause-menu picker.
var painterly_layer: CanvasLayer
var painterly_rect: ColorRect
var painterly_style := 0
const PAINTERLY_STYLES := ["Realistyczny", "Pastelowy", "Akwarela", "Farba olejna", "Tusz + akwarela"]
const PAINTERLY_SHADER := preload("res://shaders/painterly_post.gdshader")
var character_name := "Theia"
var model_paths := ["res://assets/theia/theia_hooded_walking.glb", "res://assets/theia/Theia_hooded_RunFast_withSkin.glb", "res://assets/theia/Theia_Hooded_Turn_Left_withSkin.glb", "res://assets/theia/Theia_Hooded_Turn_Right_withSkin.glb"]
var atlas_path := "res://assets/theia/theia_hooded_walking_texture_0.png"

func _ready() -> void:
	name = character_name
	for pair in [["move_left", KEY_A], ["move_right", KEY_D], ["move_forward", KEY_W], ["move_back", KEY_S]]:
		if not InputMap.has_action(pair[0]): InputMap.add_action(pair[0])
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		if not InputMap.action_has_event(pair[0], key): InputMap.action_add_event(pair[0], key)
	floor_snap_length = 0.65
	floor_max_angle = deg_to_rad(48)
	var shape := CapsuleShape3D.new()
	shape.radius = collision_radius_m
	shape.height = reference_height_m
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = reference_height_m * 0.5
	add_child(collision)
	add_child(pivot)
	for visual_index in model_paths.size():
		var visual := _load_character_visual(visual_index, model_paths[visual_index])
		if visual == null:
			enabled = false
			return
		pivot.add_child(visual)
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			for index in mesh.mesh.get_surface_count():
				var source := mesh.get_active_material(index)
				if source is StandardMaterial3D:
					var cloth := source.duplicate() as StandardMaterial3D
					cloth.metallic = 0.0
					cloth.roughness = 0.92
					# The source character is emissive; lunar cloth must follow scene shadows.
					cloth.emission_enabled = false
					if not atlas_path.is_empty(): cloth.albedo_texture = load(atlas_path)
					cloth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					mesh.set_surface_override_material(index, cloth)
		var anim := visual.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var animation_name := anim.get_animation_list()[0]
		for candidate in anim.get_animation_list():
			if candidate != "RESET":
				animation_name = candidate
				break
		var animation := anim.get_animation(animation_name)
		animation.loop_mode = Animation.LOOP_LINEAR
		anim.play(animation_name)
		anim.advance(0)
		anim.speed_scale = 0
		visual.visible = visuals.is_empty()
		visuals.append(visual)
		players.append(anim)
	# Meshy.ai exports import at an arbitrary size (the suit rig lands near 1.5 m).
	# Measure the real bind-pose height and apply one character-specific scale to
	# every clip, including its rigid backpack and attached helmet.
	# so 1 unit stays 1 metre against the terrain and the rover.
	var raw_height: float = _character_visual_height(visuals[0])
	pivot.scale = Vector3.ONE * (reference_height_m / raw_height) if raw_height > 0.01 else Vector3.ONE
	add_child(camera)
	camera.top_level = true
	camera.near = 0.08
	# A lunar horizon can be tens of kilometres away; this does not change the
	# near clipping used for character-scale interactions.
	camera.far = 250000
	camera.fov = 57
	camera.current = true
	_build_outline()
	_build_painterly()
	footprint_root = Node3D.new()
	get_parent().add_child(footprint_root)
	position.x = spawn_position.x
	position.z = spawn_position.z
	position.y = terrain.height_at(position.x, position.z) + 0.15
	_update_camera()
	if "--capture-outline" in OS.get_cmdline_user_args():
		_capture_outline.call_deferred()
	if "--capture-painterly" in OS.get_cmdline_user_args():
		_capture_painterly.call_deferred()
	if "--capture-grass" in OS.get_cmdline_user_args():
		_capture_grass.call_deferred()

func _capture_outline() -> void:
	await get_tree().create_timer(6.0).timeout
	for frame in 240:
		await get_tree().process_frame
		if terrain.queue.is_empty():
			break
	for style in ["off", "comic", "moebius"].size():
		set_outline_style(style)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/outline_%d_%s.png" % [style, ["off", "comic", "moebius"][style]])
	# Regression check: Tycho's dense lawn grass used to get hatched solid by the
	# old normal-edge term. Harmless (just an extra shot) on colonies without grass.
	if terrain.has_method("height_at") and "city_level" in terrain:
		enabled = false
		velocity = Vector3.ZERO
		var ground: float = terrain.height_at(18.0, 20.0)
		var grass_shots := [
			[Vector3(19.0, ground + 1.5, 21.0), Vector3(16.0, ground + 0.4, 4.0), "close"],
			[Vector3(19.0, ground + 4.5, 27.0), Vector3(16.0, ground + 0.6, 4.0), "tpp"],
		]
		for grass_shot in grass_shots:
			camera.global_position = grass_shot[0]
			camera.look_at(grass_shot[1])
			for style in [1, 2]:
				set_outline_style(style)
				await get_tree().create_timer(0.3).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://../artifacts/outline_grass_%s_%s.png" % [grass_shot[2], ["off", "comic", "moebius"][style]])
	print("OUTLINE CAPTURE: 3 styles saved")
	get_tree().quit()

func _capture_painterly() -> void:
	await get_tree().create_timer(6.0).timeout
	for frame in 240:
		await get_tree().process_frame
		if terrain.queue.is_empty():
			break
	# Previews show each painterly style on its own; the K outline is a separate FX.
	var keep_outline := outline_style
	set_outline_style(0)
	var names := ["realistic", "pastel", "watercolor", "oil", "ink_watercolor"]
	for s in names.size():
		set_painterly_style(s)
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/painterly_%d_%s.png" % [s, names[s]])
	set_painterly_style(0)
	set_outline_style(keep_outline)
	print("PAINTERLY CAPTURE: %d styles saved" % names.size())
	get_tree().quit()

func _capture_grass() -> void:
	await get_tree().create_timer(7.0).timeout
	for frame in 900:
		await get_tree().process_frame
		if terrain.queue.is_empty():
			break
	enabled = false
	velocity = Vector3.ZERO
	set_outline_style(0)  # show the grass itself, not the K ink on every blade
	var ground: float = terrain.height_at(18.0, 20.0)
	var shots := [
		[Vector3(19.0, ground + 1.7, 21.0), Vector3(15.0, ground + 0.2, -8.0), "tycho_grass.png"],
		[Vector3(-34.0, ground + 2.4, 26.0), Vector3(-18.0, ground + 0.3, -8.0), "tycho_grass_trees.png"],
		[Vector3(36.0, ground + 4.5, -14.0), Vector3(23.0, ground + 1.4, -22.0), "tycho_grass_greenhouse.png"],
		[Vector3(0.0, ground + 62.0, 118.0), Vector3(0.0, ground, 20.0), "tycho_grass_overview.png"],
		[Vector3(-8.0, ground + 6.0, -18.0), Vector3(12.0, ground + 2.0, -130.0), "tycho_gate.png"],
		[Vector3(6.0, ground + 22.0, -96.0), Vector3(104.0, ground + 8.0, -150.0), "tycho_cosmoport.png"],
		[Vector3(0.0, ground + 78.0, -170.0), Vector3(80.0, ground, -120.0), "tycho_cosmoport_wide.png"],
		[Vector3(70.0, ground + 45.0, -60.0), Vector3(20.0, ground + 5.0, -125.0), "tycho_ramp_junction.png"],
		[Vector3(39.4, ground + 10.0, -58.0), Vector3(6.3, ground + 8.0, -94.8), "tycho_gate_side.png"],
		[Vector3(16.0, ground + 65.0, -95.0), Vector3(16.0, ground, -95.0), "tycho_gate_top.png"],
		[Vector3(-4.0, ground + 2.5, -84.0), Vector3(6.3, ground + 8.0, -94.8), "tycho_gate_lamp_check.png"],
	]
	for shot in shots:
		camera.global_position = shot[0]
		camera.look_at(shot[1])
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../artifacts/%s" % shot[2])
	print("GRASS CAPTURE saved")
	get_tree().quit()

# Camera and movement are supplied by elvenpass_controller.gd.
func _update_camera() -> void:
	pass

# Empty on purpose: GDScript's `super._process()` only compiles if some
# ancestor script actually defines _process, so this exists as a stable base
# for elvenpass_controller.gd's override to extend. Without it, a silently
# shadowed base _process cost a whole debugging session once already.
func _process(_delta: float) -> void:
	pass

func _build_outline() -> void:
	# Full-screen outline post-process. The vertex shader forces the quad to cover
	# clip space, so its own transform is irrelevant; a big cull margin keeps it
	# from being frustum-culled when the camera swings around.
	outline = MeshInstance3D.new()
	outline.name = "OutlineStyle"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	outline.mesh = quad
	outline.material_override = ShaderMaterial.new()
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.extra_cull_margin = 16384.0
	outline.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	# render_priority lives on the MATERIAL, not the node. Ensures correct
	# draw order among transparent-pass materials (this quad last). Does NOT
	# by itself put other transparent geometry into screen_texture -- see the
	# class-level comment on `outline` above for the erasure bug this doesn't fix.
	(outline.material_override as ShaderMaterial).render_priority = 127
	camera.add_child(outline)
	_apply_outline_style()

func _apply_outline_style() -> void:
	if outline == null:
		return
	outline_style = clampi(outline_style, 0, OUTLINE_SHADERS.size() - 1)
	var shader = OUTLINE_SHADERS[outline_style]
	outline.visible = shader != null
	if shader != null:
		(outline.material_override as ShaderMaterial).shader = shader

func set_outline_style(index: int) -> void:
	outline_style = index
	_apply_outline_style()
	outline_style_changed.emit(outline_style)

func cycle_outline_style() -> void:
	set_outline_style((outline_style + 1) % OUTLINE_SHADERS.size())

# Back-compat: earlier code toggled a single style on/off.
func set_outline(on: bool) -> void:
	set_outline_style(1 if on else 0)

func _build_painterly() -> void:
	# CanvasLayer 0 composites over the 3D view (outline quad included) and under
	# the HUD (moonwalk's UI canvas is layer 1). A full-rect ColorRect that
	# ignores the mouse carries the shader.
	painterly_layer = CanvasLayer.new()
	painterly_layer.name = "PainterlyPost"
	painterly_layer.layer = 0
	add_child(painterly_layer)
	painterly_rect = ColorRect.new()
	painterly_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	painterly_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PAINTERLY_SHADER
	painterly_rect.material = mat
	painterly_layer.add_child(painterly_rect)
	_apply_painterly_style()

func _apply_painterly_style() -> void:
	if painterly_rect == null:
		return
	painterly_style = clampi(painterly_style, 0, PAINTERLY_STYLES.size() - 1)
	(painterly_rect.material as ShaderMaterial).set_shader_parameter("style", painterly_style)
	# Realistic = nothing to do; skip the pass entirely. Also hidden whenever this
	# camera is not the active one (globe / capture views).
	painterly_layer.visible = painterly_style != 0 and camera.current

func set_painterly_style(index: int) -> void:
	painterly_style = index
	_apply_painterly_style()
	painterly_style_changed.emit(painterly_style)

func cycle_painterly_style() -> void:
	set_painterly_style((painterly_style + 1) % PAINTERLY_STYLES.size())

func _visual_mesh_bounds(node: Node, xform: Transform3D) -> AABB:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	var out := AABB()
	var seeded := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var local: AABB = (node as MeshInstance3D).mesh.get_aabb()
		for i in 8:
			var p: Vector3 = t * local.get_endpoint(i)
			if not seeded:
				out = AABB(p, Vector3.ZERO)
				seeded = true
			else:
				out = out.expand(p)
	for child in node.get_children():
		var sub := _visual_mesh_bounds(child, t)
		if sub.size != Vector3.ZERO:
			out = sub if not seeded else out.merge(sub)
			seeded = true
	return out

func _stamp_foot() -> void:
	var footprint := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.13, 0.31) * (reference_height_m / REFERENCE_HEIGHT_M)
	footprint.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.116, 0.11)
	mat.roughness = 1
	footprint.material_override = mat
	footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint_root.add_child(footprint)
	var p := _foot_position_for_stamp()
	p.y = terrain.height_at(p.x, p.z) + 0.025
	footprint.position = p
	var normal := Vector3(terrain.height_at(p.x - 0.15, p.z) - terrain.height_at(p.x + 0.15, p.z), 0.3, terrain.height_at(p.x, p.z - 0.15) - terrain.height_at(p.x, p.z + 0.15)).normalized()
	var forward := Basis(Vector3.UP, visual_yaw) * Vector3.FORWARD
	var right := forward.cross(normal).normalized()
	footprint.basis = Basis(right, normal, right.cross(normal))
	foot_side *= -1
	footprints.append(footprint)
	if footprints.size() > 160:
		footprints.pop_front().queue_free()

func _foot_position_for_stamp() -> Vector3:
	return position + Basis(Vector3.UP, visual_yaw) * Vector3(0.12 * foot_side, 0, 0)

func _load_character_visual(_index: int, path: String) -> Node3D:
	return (load(path) as PackedScene).instantiate() as Node3D

func _character_visual_height(visual: Node3D) -> float:
	return _visual_mesh_bounds(visual, Transform3D.IDENTITY).size.y

extends SceneTree
## Run with --headless --path godot --script res://tools/build_highways.gd
const Roads := preload("res://scripts/road_streamer.gd")
const Lorry := preload("res://scripts/lunar_lorry.gd")
const Network := preload("res://scripts/highway_network.gd")

class AssetGround extends Node:
	var center := Vector2i.ZERO
	var grade := 0.0
	func height_at(x: float, _z: float) -> float:
		return x * grade

func _initialize() -> void:
	build.call_deferred()

func own_children(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		own_children(child, owner_node)

func build() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	var file := FileAccess.open("res://assets/roads/world_routes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 2, "distance_source": "lunar great-circle; approximate colony coordinates", "limit_km_exclusive": 700, "lighting": {"asset": "res://assets/roads/lamp/industrial_lamp.glb", "spacing_m_per_side": 40, "height_m": 12}, "distance_limit_exceptions": {"farside_region": Network.FARSIDE_LOCATIONS}, "routes": Network.build(data.locations)}, "  ") + "\n")
	file.close()
	for variant in ["straight", "curve", "incline"]:
		var ground := AssetGround.new()
		ground.grade = 0.04 if variant == "incline" else 0.0
		var roads := Roads.new()
		roads.terrain = ground
		roads.lane_width = 2.0 * Lorry.highway_vehicle_width()
		var points: Array[Vector2] = [Vector2.ZERO, Vector2(96, 0)]
		if variant == "curve":
			points = [Vector2.ZERO, Vector2(100, 0), Vector2(180, 80), Vector2(180, 180)]
		roads._bake_route(variant, points, 5.0)
		roads.lamp_descriptors_by_tile = roads.Lamps.layout(roads.descriptors_by_tile, roads.lane_width + 0.4)
		var asset := Node3D.new()
		asset.name = "Highway_" + variant
		for key: Vector2i in roads.descriptors_by_tile:
			asset.add_child(roads._build_road_tile(key, 0))
		own_children(asset, asset)
		var scene := PackedScene.new()
		assert(scene.pack(asset) == OK)
		assert(ResourceSaver.save(scene, "res://assets/roads/highway_%s.scn" % variant) == OK)
		asset.free()
		roads.free()
		ground.free()
	print("Exported highway catalogue and 3 original concrete/steel assets")
	quit()

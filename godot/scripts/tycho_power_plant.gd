extends Node3D
## Solar/comms site on the real crest of Tycho's central peak: the highest
## sample (+217 m over the station anchor) inside the baked NAC_DTM_TYCHOPK
## sector, found by scanning godot/assets/sectors/tycho_station/*.bin for the
## tallest value -- a genuine rounded summit in the surrounding samples, not a
## single-cell spike. Tycho Station itself was relocated onto this same peak
## (see tycho_site.gd) and now sits ~270 m east-northeast, at a lower, gentler
## shoulder (~157 m); this SITE point stays outside TychoSite's RADIUS+BLEND
## (145 m) grading, so terrain.height_at() here still returns the unflattened
## real DEM.
##
## The simplified local sun (lunar_sky.gd's direction(12, 3)) sits low in the
## north (~3 deg elevation) and shines south, so the dome and its towers cast
## long shadows over their own flat site. This north-facing summit clears
## that shadow instead -- unlike the two fotovoltaic-panels pairs previously
## parked at the dome's south edge, still under the glass. The array sits on
## the summit's north (sunward) shoulder; the mast and comms building sit
## just south of it, so their own shadows fall away from the panels.
const ASSETS := "res://assets/colonies/tycho/modules/"
const SITE := Vector2(-524.0, -1256.0)
const TILE := 64.0
var terrain: Node3D
var dimensions: Dictionary = {}
var built := false

func _ready() -> void:
	name = "TychoPowerPlant"
	dimensions = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "modules.json"))

func _process(_delta: float) -> void:
	var tile := Vector2i(floori(SITE.x / TILE), floori(SITE.y / TILE))
	var distance := maxi(absi(tile.x - terrain.center.x), absi(tile.y - terrain.center.y))
	var wanted: bool = distance <= terrain.FAR_RADIUS
	if wanted == built:
		return
	built = wanted
	if wanted:
		_build()
	else:
		for child in get_children():
			child.queue_free()

func _place(kind: String, x: float, z: float) -> Node3D:
	var point := SITE + Vector2(x, z)
	# These GLBs are already resident from the main city build (same kinds,
	# already placed near the dome), so a plain synchronous load() just hits
	# the resource cache instead of hitting disk on approach.
	var root := (load(ASSETS + kind + ".glb") as PackedScene).instantiate() as Node3D
	root.name = kind
	root.position = Vector3(point.x, terrain.height_at(point.x, point.y), point.y)
	add_child(root)
	return root

func _add_box_collider(target: Node3D, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	target.add_child(body)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	var box := BoxShape3D.new()
	box.size = box_size
	collider.shape = box
	collider.position.y = box_size.y * 0.5
	body.add_child(collider)

func _build() -> void:
	_place("radio-mast", 0.0, 0.0)
	var building := _place("central-building", 0.0, 22.0)
	var building_size: Array = dimensions["central-building"].size_m
	# Same height cut the base building's own collider uses: the dish/mast
	# above the 8 m body stays free of a giant invisible wall around it.
	_add_box_collider(building, Vector3(float(building_size[0]) * 0.85, 8.0, float(building_size[2]) * 0.85))
	var panel_size: Array = dimensions["fotovoltaic-panels"].size_m
	var panel_box := Vector3(float(panel_size[0]), float(panel_size[1]), float(panel_size[2]))
	for row_z in [-25.0, -35.0]:
		for x in [-39.0, -13.0, 13.0, 39.0]:
			_add_box_collider(_place("fotovoltaic-panels", x, row_z), panel_box)

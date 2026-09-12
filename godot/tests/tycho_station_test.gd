extends SceneTree
## The authored Tycho city GLB was removed (placeholder art, replacement pending).
## What still matters: the Tycho anchor in colonies.json must match the anchor the
## DTM sector was baked against, or terrain.height_at drifts from the real DEM.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moon/colonies.json"))
	var tycho: Dictionary = {}
	for location: Dictionary in data.locations:
		if location.name == "Tycho Station":
			tycho = location
	check(tycho.latitude == -43.66 and tycho.longitude == -11.3, "Tycho must sit on the flat floor inside the NAC_DTM_TYCHOPK footprint")

	var sector_path := "res://assets/sectors/tycho_station/sector.json"
	check(FileAccess.file_exists(sector_path), "Tycho DTM sector must be baked")
	if FileAccess.file_exists(sector_path):
		var sector: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(sector_path))
		check(sector.anchor_lat == tycho.latitude and sector.anchor_lon == tycho.longitude,
			"Baked sector anchor must match the colony registry (rebake tools/bake_sector_dtm.mjs if this fails)")
		check(sector.source == "NAC_DTM_TYCHOPK.TIF", "Tycho sector must be baked from the NAC 2 m/px DTM")

	print("TYCHO STATION TEST: %d failures; anchor %s/%s" % [failures, tycho.latitude, tycho.longitude])
	quit(1 if failures else 0)

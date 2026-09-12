extends FogVolume
## A low, physically integrated column of humid air inside Tycho's dome.
## Unlike billboards, it has depth from every camera angle and fades objects
## according to their actual distance through the air.
const HEIGHT_M := 1.0
const WIDTH_M := 188.0

func _ready() -> void:
	name = "TychoLowMist"
	set_meta("height_m", HEIGHT_M)
	set_meta("width_m", WIDTH_M)
	set_meta("fog_type", "volumetric_air_column")
	# FogVolume's shape enum is not exposed under a stable symbolic name in 4.6;
	# value 3 is the engine's box volume.
	shape = 3
	size = Vector3(WIDTH_M, HEIGHT_M, WIDTH_M)
	position.y = HEIGHT_M * 0.5
	var air := FogMaterial.new()
	air.density = 0.035
	air.albedo = Color(0.72, 0.80, 0.88)
	air.emission = Color(0.12, 0.16, 0.20)
	material = air

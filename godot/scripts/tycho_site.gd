extends RefCounted
## Local metres inside the existing NAC_DTM_TYCHOPK 2 m sector.
const CENTER := Vector2(0.0, 25.0)
const RADIUS := 100.0
const BLEND := 45.0

static func weight(x: float, z: float) -> float:
	return 1.0 - smoothstep(RADIUS, RADIUS + BLEND, Vector2(x, z).distance_to(CENTER))

extends RefCounted
## Bounded shared LRU cache: 24 MiB instead of a 506 MiB global raster.
const WIDTH := 23040
const HEIGHT := 11520
const SIZE := 512
const MAX_TILES := 48
const PATH := "res://assets/moon/meso/"
static var cache: Dictionary = {}
static var available := FileAccess.file_exists(PATH + "metadata.json")

static func sample(latitude: float, longitude: float) -> float:
	if not available:
		return NAN
	var u := fposmod((longitude + 180.0) / 360.0, 1.0) * WIDTH - 0.5
	var v := clampf((90.0 - latitude) / 180.0 * HEIGHT - 0.5, 0.0, HEIGHT - 1.0)
	var x := floori(u)
	var y := floori(v)
	return lerpf(lerpf(_pixel(x, y), _pixel(x + 1, y), u - floor(u)),
		lerpf(_pixel(x, mini(y + 1, HEIGHT - 1)), _pixel(x + 1, mini(y + 1, HEIGHT - 1)), u - floor(u)), v - floor(v))

static func _pixel(x: int, y: int) -> float:
	x = posmod(x, WIDTH)
	var key := Vector2i(x / SIZE, y / SIZE)
	var bytes: PackedByteArray
	if cache.has(key):
		bytes = cache[key]
		cache.erase(key)
	else:
		bytes = FileAccess.get_file_as_bytes(PATH + "%d_%d.bin" % [key.x, key.y])
		if bytes.size() != SIZE * SIZE * 2:
			return NAN
	cache[key] = bytes
	if cache.size() > MAX_TILES:
		cache.erase(cache.keys()[0])
	return bytes.decode_u16(((y % SIZE) * SIZE + x % SIZE) * 2) * 0.5 - 10000.0

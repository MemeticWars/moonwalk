extends Node

signal tile_available(key: Vector2i)
var enabled := false
var endpoint := ""
var revision := ""
var sector := "silesia"
var cache_dir := ""
var request := HTTPRequest.new()
var pending: Array[Vector2i] = []
var failed_until: Dictionary = {}
var busy := false
var current := Vector2i.ZERO
var center := Vector2i.ZERO
var downloaded := 0
var disk_cap := 256 * 1024 * 1024

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("res://terrain_server.cfg") != OK:
		return
	enabled = config.get_value("server", "enabled", false)
	endpoint = config.get_value("server", "url", "")
	revision = config.get_value("server", "revision", "v1")
	sector = config.get_value("server", "sector", "silesia")
	disk_cap = int(config.get_value("server", "disk_cache_mb", 256)) * 1024 * 1024
	cache_dir = "user://terrain/" + revision.validate_filename() + "/" + sector.validate_filename()
	DirAccess.make_dir_recursive_absolute(cache_dir)
	request.timeout = 8.0
	request.body_size_limit = 4 * 1024 * 1024
	request.use_threads = true
	add_child(request)
	request.request_completed.connect(_completed)
	_prune_cache()

func set_sector(name: String) -> void:
	sector = name
	cache_dir = "user://terrain/" + revision.validate_filename() + "/" + sector.validate_filename()
	DirAccess.make_dir_recursive_absolute(cache_dir)
	pending.clear()
	failed_until.clear()

func cache_path(key: Vector2i) -> String:
	return cache_dir + "/%d_%d.json" % [key.x, key.y]

func read_tile(key: Vector2i) -> Dictionary:
	if not enabled or not FileAccess.file_exists(cache_path(key)):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(cache_path(key)))
	if not valid_tile(data, key):
		DirAccess.remove_absolute(cache_path(key))
		return {}
	return data

func valid_tile(data: Variant, key: Vector2i) -> bool:
	if not data is Dictionary:
		return false
	if data.get("version") != revision or data.get("sector") != sector or data.get("x") != key.x or data.get("z") != key.y or data.get("grid") != 35 or data.get("step_m") != 2:
		return false
	var heights := Marshalls.base64_to_raw(data.get("height_f32", "")).to_float32_array()
	if heights.size() != 1225:
		return false
	for value in heights:
		if not is_finite(value) or absf(value) > 25000:
			return false
	return true

func set_focus(key: Vector2i) -> void:
	center = key
	pending = pending.filter(func(p: Vector2i) -> bool: return maxi(absi(p.x - key.x), absi(p.y - key.y)) <= 5)
	for old: Vector2i in failed_until.keys():
		if maxi(absi(old.x - key.x), absi(old.y - key.y)) > 6:
			failed_until.erase(old)

func enqueue(key: Vector2i) -> void:
	if not enabled or pending.has(key) or (busy and current == key) or FileAccess.file_exists(cache_path(key)):
		return
	if failed_until.get(key, 0) > Time.get_ticks_msec():
		return
	pending.append(key)
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared())

func _process(_delta: float) -> void:
	if not enabled or busy or pending.is_empty():
		return
	current = pending.pop_front()
	busy = true
	var error := request.request(endpoint + "/v1/%s/%s/%d/%d.json" % [revision.uri_encode(), sector.uri_encode(), current.x, current.y])
	if error != OK:
		busy = false
		failed_until[current] = Time.get_ticks_msec() + 30000

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if not valid_tile(data, current):
		failed_until[current] = Time.get_ticks_msec() + 30000
		return
	var file := FileAccess.open(cache_path(current) + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(body)
	file.close()
	DirAccess.rename_absolute(cache_path(current) + ".tmp", cache_path(current))
	downloaded += 1
	_prune_cache()
	tile_available.emit(current)

func _prune_cache() -> void:
	# A single cap across revisions, including abandoned versions.
	var files: Array[Dictionary] = []
	_scan_cache("user://terrain", files)
	var total := 0
	for file in files:
		total += file.size
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
	for file in files:
		if total <= disk_cap:
			break
		if DirAccess.remove_absolute(file.path) == OK:
			total -= file.size

func _scan_cache(path: String, files: Array[Dictionary]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		var full := path + "/" + name
		var file := FileAccess.open(full, FileAccess.READ)
		if file != null:
			files.append({"path": full, "size": file.get_length(), "time": FileAccess.get_modified_time(full)})
	for name in dir.get_directories():
		_scan_cache(path + "/" + name, files)

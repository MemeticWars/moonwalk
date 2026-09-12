extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(2)
	return condition

func _run() -> void:
	var client := preload("res://scripts/terrain_stream.gd").new()
	root.add_child(client)
	client.enabled = true
	client.revision = "test-v1"
	client.sector = "silesia"
	client.cache_dir = "user://terrain/integration_" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(client.cache_dir)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--endpoint="):
			client.endpoint = arg.trim_prefix("--endpoint=")
	client.enqueue(Vector2i.ZERO)
	var deadline := Time.get_ticks_msec() + 15000
	while client.downloaded == 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if not require(client.downloaded == 1, "HTTP tile download must complete"):
		return
	var tile: Dictionary = client.read_tile(Vector2i.ZERO)
	if not require(not tile.is_empty(), "Downloaded tile must round-trip through disk cache"):
		return
	var heights := Marshalls.base64_to_raw(tile.height_f32).to_float32_array()
	if not require(is_equal_approx(heights[36], 500.0), "Height units and halo index must survive HTTP/base64/disk"):
		return
	client.enqueue(Vector2i.ZERO)
	await create_timer(0.1).timeout
	if not require(client.pending.is_empty() and client.downloaded == 1, "Cache hit must skip the network"):
		return
	tile["version"] = "old"
	if not require(not client.valid_tile(tile, Vector2i.ZERO), "Stale revision must be rejected"):
		return
	client.enqueue(Vector2i(99, 0))
	deadline = Time.get_ticks_msec() + 10000
	while not client.failed_until.has(Vector2i(99, 0)) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if not require(client.failed_until.has(Vector2i(99, 0)) and client.read_tile(Vector2i(99, 0)).is_empty(), "Unavailable coverage must back off without poisoning cache"):
		return
	print("STREAM PASS: HTTP, float heights, halo, disk cache, stale revision, 404 fallback")
	quit(0)

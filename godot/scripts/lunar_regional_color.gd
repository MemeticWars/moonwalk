extends RefCounted
static var texture: ImageTexture

static func get_texture() -> ImageTexture:
	if texture == null:
		texture = load("res://assets/moon/regional_albedo.res")
	return texture

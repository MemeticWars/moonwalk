extends Node3D
## Lawn grass that bends where Agnes has just walked. The blade shader does the
## bending; this node holds the MultiMesh chunks (built by TychoCity) and keeps a
## short trail of recent player positions, fading each out over ~1 second. Every
## chunk shares one ShaderMaterial, so the trail is pushed once per frame.

var terrain: Node3D
var material: ShaderMaterial  # the shared blade material, assigned by the builder

const TRAIL := 8
const FADE_SECONDS := 1.0
const STEP := 0.22  # metres between trail samples (tight, so the wake hugs her feet)

var _points: Array[Vector3] = []
var _strength: Array[float] = []

func _process(delta: float) -> void:
	if terrain == null or material == null:
		return
	var p: Vector3 = terrain.focus
	if _points.is_empty() or _points[_points.size() - 1].distance_to(p) > STEP:
		_points.append(p)
		_strength.append(1.0)
		if _points.size() > TRAIL:
			_points.remove_at(0)
			_strength.remove_at(0)
	elif not _strength.is_empty():
		_strength[_strength.size() - 1] = 1.0  # standing still keeps the spot fresh

	var packed := PackedVector4Array()
	for i in _points.size():
		_strength[i] -= delta / FADE_SECONDS
		if _strength[i] > 0.0:
			packed.append(Vector4(_points[i].x, _points[i].y, _points[i].z, _strength[i]))
	while not _strength.is_empty() and _strength[0] <= 0.0:
		_points.remove_at(0)
		_strength.remove_at(0)

	var live := packed.size()
	while packed.size() < TRAIL:
		packed.append(Vector4.ZERO)
	material.set_shader_parameter("disturbers", packed)
	material.set_shader_parameter("disturber_count", live)

extends RefCounted
## Initial vertical descent, broad turn, then an extended glide toward the site.
const VERTICAL_SECONDS := 14.0
const TURN_SECONDS := 14.0
const GLIDE_SECONDS := 38.0
const DURATION := VERTICAL_SECONDS + TURN_SECONDS + GLIDE_SECONDS
const RANGE_M := 8000.0

static func pose(seconds: float, start: Vector3, target: Vector3) -> Dictionary:
	var column := Vector3(start.x, target.y+8000.0, start.z)
	var far := target+Vector3(0,3500,RANGE_M)
	var finish := target+Vector3(0,240,280)
	var p: Vector3
	var look: Vector3
	if seconds <= VERTICAL_SECONDS:
		var t := smoothstep(0.0,VERTICAL_SECONDS,seconds)
		# Exponential height distribution retains detail near the end of descent.
		var h := exp(lerpf(log(maxf(8000.0,start.y-target.y)),log(8000.0),t))
		p = Vector3(start.x,target.y+h,start.z)
		look = Vector3(0,-1,-0.0001).normalized()
	elif seconds <= VERTICAL_SECONDS+TURN_SECONDS:
		var t := smoothstep(0.0,1.0,(seconds-VERTICAL_SECONDS)/TURN_SECONDS)
		p = column.bezier_interpolate(column+Vector3(0,-1600,0),far+Vector3(0,1200,-1800),far,t)
		look = Vector3(0,-1,-0.0001).slerp((target-p).normalized(),t).normalized()
	else:
		var t := smoothstep(0.0,1.0,(seconds-VERTICAL_SECONDS-TURN_SECONDS)/GLIDE_SECONDS)
		p = far.bezier_interpolate(far+Vector3(0,-600,-2200),target+Vector3(0,650,1900),finish,t)
		look = (target-p).normalized()
	return {"position":p,"look":look}

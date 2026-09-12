extends SceneTree
const Flight = preload("res://scripts/lunar_approach.gd")
func _initialize() -> void:
	var start := Vector3(12,70000,-25)
	var target := Vector3(-26,10,-67)
	for i in 141:
		var p: Vector3 = Flight.pose(i*0.1,start,target).position
		assert(absf(p.x-start.x)<0.001 and absf(p.z-start.z)<0.001,"Initial descent must keep the same ground footprint")
	var widest := 0.0
	var oblique_seconds := 0.0
	for i in int(Flight.DURATION*10)+1:
		var pose := Flight.pose(i*0.1,start,target)
		widest = maxf(widest,Vector2(pose.position.x-target.x,pose.position.z-target.z).length())
		if absf(pose.look.y)<0.85: oblique_seconds += 0.1
		assert(absf(pose.look.length()-1.0)<0.0001)
	assert(widest>=7999.0,"The glide must span kilometres, not a 90 m camera wiggle")
	assert(oblique_seconds>30.0,"Relief must remain visible obliquely for an extended time")
	for boundary in [Flight.VERTICAL_SECONDS,Flight.VERTICAL_SECONDS+Flight.TURN_SECONDS]:
		var a := Flight.pose(boundary-0.001,start,target)
		var b := Flight.pose(boundary+0.001,start,target)
		assert(a.position.distance_to(b.position)<0.1,"Flight stages must join without a camera jump")
		assert(a.look.angle_to(b.look)<0.001,"Camera direction must be continuous")
	print("APPROACH PATH PASS: vertical footprint, 8 km range, >30 s oblique view, continuous joins")
	quit()

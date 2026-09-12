extends SceneTree
## Robust regional colour, deliberately without photographic crater shadows.
func _initialize() -> void:
	var source := Image.load_from_file("res://assets/moon/albedo.jpg")
	var result := Image.create(128, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 128:
			var samples: Array[Color] = []
			for sy in 16:
				for sx in 16:
					var px := mini(source.get_width()-1, int((x+(sx+0.5)/16.0)*source.get_width()/128.0))
					var py := mini(source.get_height()-1, int((y+(sy+0.5)/16.0)*source.get_height()/64.0))
					samples.append(source.get_pixel(px,py))
			samples.sort_custom(func(a: Color,b: Color) -> bool: return a.get_luminance()<b.get_luminance())
			var sum := Color(0,0,0,0)
			# Exclude the darker 55% and the brightest 15% (glints / ejecta).
			for i in range(141,218): sum += samples[i]
			var average := sum / 77.0
			var value := clampf(pow(average.get_luminance()/0.45, 0.45),0.75,1.12)
			var tint := Color(0.62,0.60,0.57)*value
			tint.a = 1.0
			result.set_pixel(x,y,tint)
	result.save_png("res://assets/moon/regional_albedo.png")
	result.generate_mipmaps()
	ResourceSaver.save(ImageTexture.create_from_image(result), "res://assets/moon/regional_albedo.res")
	print("Regional albedo: 128x64, bright midtones, no photographic shadows")
	quit()

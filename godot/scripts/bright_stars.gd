extends RefCounted

# Rounded J2000 positions and apparent magnitudes, AstroPixels / Hipparcos:
# https://astropixels.com/stars/brightstars.html
# name, right ascension (hours, minutes), declination (degrees), V magnitude, spectral class.
const DATA := [
	["Sirius", 6, 45, -16.7, -1.44, "A"],
	["Canopus", 6, 24, -52.7, -0.62, "F"],
	["Alpha Centauri", 14, 40, -60.8, -0.28, "G"],
	["Arcturus", 14, 16, 19.2, -0.05, "K"],
	["Vega", 18, 37, 38.8, 0.03, "A"],
	["Capella", 5, 17, 46.0, 0.08, "G"],
	["Rigel", 5, 15, -8.2, 0.18, "B"],
	["Procyon", 7, 39, 5.2, 0.40, "F"],
	["Betelgeuse", 5, 55, 7.4, 0.45, "M"],
	["Achernar", 1, 38, -57.2, 0.45, "B"],
	["Hadar", 14, 4, -60.4, 0.61, "B"],
	["Altair", 19, 51, 8.9, 0.76, "A"],
	["Acrux", 12, 27, -63.1, 0.77, "B"],
	["Aldebaran", 4, 36, 16.5, 0.87, "K"],
	["Spica", 13, 25, -11.2, 0.98, "B"],
	["Antares", 16, 29, -26.4, 1.06, "M"],
	["Pollux", 7, 45, 28.0, 1.16, "K"],
	["Fomalhaut", 22, 58, -29.6, 1.17, "A"],
	["Deneb", 20, 41, 45.3, 1.25, "A"],
	["Mimosa", 12, 48, -59.7, 1.25, "B"],
	["Regulus", 10, 8, 12.0, 1.36, "B"],
	["Adhara", 6, 59, -29.0, 1.50, "B"],
	["Castor", 7, 35, 31.9, 1.58, "A"],
	["Gacrux", 12, 31, -57.1, 1.59, "M"],
	["Shaula", 17, 34, -37.1, 1.62, "B"],
	["Bellatrix", 5, 25, 6.3, 1.64, "B"],
	["Elnath", 5, 26, 28.6, 1.65, "B"],
	["Miaplacidus", 9, 13, -69.7, 1.67, "A"],
	["Alnilam", 5, 36, -1.2, 1.69, "B"],
	["Alnair", 22, 8, -47.0, 1.73, "B"],
	["Alnitak", 5, 41, -1.9, 1.74, "B"],
	["Regor", 8, 10, -47.3, 1.75, "B"],
]

static func configure(material: ShaderMaterial) -> void:
	var stars := PackedVector4Array()
	var colors := PackedVector3Array()
	var palette := {"B": Vector3(0.68, 0.8, 1.0), "A": Vector3(0.88, 0.93, 1.0), "F": Vector3(1.0, 0.96, 0.85), "G": Vector3(1.0, 0.88, 0.66), "K": Vector3(1.0, 0.72, 0.45), "M": Vector3(1.0, 0.54, 0.32)}
	# Artistic horizon orientation, NOT the observer's dated lunar ephemeris.
	# Rotating the whole catalog preserves the relative positions of the stars.
	var orientation := Basis(Vector3.RIGHT, deg_to_rad(30)) * Basis(Vector3.UP, deg_to_rad(100))
	for entry in DATA:
		var ra := deg_to_rad((float(entry[1]) + float(entry[2]) / 60.0) * 15.0)
		var dec := deg_to_rad(float(entry[3]))
		var ray: Vector3 = orientation * Vector3(cos(dec) * sin(ra), sin(dec), -cos(dec) * cos(ra))
		# Compressed brightness range keeps less bright catalog members readable.
		stars.append(Vector4(ray.x, ray.y, ray.z, pow(10.0, -0.2 * float(entry[4]))))
		colors.append(palette[entry[5]])
	material.set_shader_parameter("stars", stars)
	material.set_shader_parameter("star_colors", colors)

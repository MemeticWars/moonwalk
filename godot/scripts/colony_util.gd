extends RefCounted
## Shared helpers for turning a colonies.json record into sector identifiers.

static func slug(name: String) -> String:
	return name.to_lower().replace("'", "").replace(" ", "_")

static func find(locations: Array, name: String) -> Dictionary:
	for location: Dictionary in locations:
		if location.get("name") == name:
			return location
	return {}

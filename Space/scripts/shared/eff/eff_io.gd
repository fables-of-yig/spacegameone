extends RefCounted

# Effects registry IO. Mirrors EntIO/BehIO: copy-on-write to the user pack,
# falls back to the shipped layer, synthesizes empty if neither exists.
# Effects are data-driven particle bursts rendered by MvAuthoredFx and spawned
# by MvFx. MvFx layers a pack's Effects/effects.json on top of default_effects()
# so every pack has a usable starter palette without writing any files.
#
# effects.json shape: { "effects": [ <effect def>, ... ] }
# effect def fields: see default_effect().

const PackPaths := preload("res://Space/scripts/shared/pack_paths.gd")


static func user_pack_dir(pack_id: String) -> String:
	return PackPaths.writable_pack_dir(pack_id)


static func shipped_pack_dir(pack_id: String) -> String:
	return "res://Content/%s/" % pack_id


static func effects_json_path(pack_id: String) -> String:
	return user_pack_dir(pack_id) + "Effects/effects.json"


static func shipped_effects_json_path(pack_id: String) -> String:
	return shipped_pack_dir(pack_id) + "Effects/effects.json"


static func load_or_init(pack_id: String) -> Dictionary:
	_ensure_dir(user_pack_dir(pack_id) + "Effects")
	var user_path := effects_json_path(pack_id)
	if FileAccess.file_exists(user_path):
		return _read_json(user_path)
	var shipped_path := shipped_effects_json_path(pack_id)
	if FileAccess.file_exists(shipped_path):
		return _read_json(shipped_path)
	return {"effects": []}


static func save_effects(pack_id: String, data: Dictionary) -> bool:
	_ensure_dir(user_pack_dir(pack_id) + "Effects")
	var path := effects_json_path(pack_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("EffIO: cannot open %s for write" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


# A blank effect with sane defaults, used to seed the workshop's effect creator.
static func default_effect(id: String) -> Dictionary:
	return {
		"id": id,
		"name": id.capitalize(),
		"count": 8,
		"colors": ["#ffeb99", "#ff9429"],
		"speed_min": 18.0,
		"speed_max": 52.0,
		"size_min": 0.8,
		"size_max": 1.8,
		"lifetime": 0.18,
		"gravity": 0.0,
		"drag": 0.85,
		"spread": TAU,
		"directional": false,
	}


# Built-in seed effects — always available even with no effects.json on disk.
static func default_effects() -> Array:
	return [
		{"id": "spark_burst", "name": "Spark Burst", "count": 6, "colors": ["#ffeb99", "#ff9429"], "speed_min": 18.0, "speed_max": 52.0, "size_min": 0.8, "size_max": 1.7, "lifetime": 0.16, "gravity": 0.0, "drag": 0.82, "spread": 2.3, "directional": true},
		{"id": "blood_puff", "name": "Blood Puff", "count": 10, "colors": ["#b41818", "#7a0f0f"], "speed_min": 24.0, "speed_max": 70.0, "size_min": 1.0, "size_max": 2.2, "lifetime": 0.32, "gravity": 520.0, "drag": 0.9, "spread": 2.6, "directional": true},
		{"id": "explosion_pop", "name": "Explosion Pop", "count": 18, "colors": ["#fff2c2", "#ff9429", "#ff5a2a"], "speed_min": 40.0, "speed_max": 150.0, "size_min": 1.4, "size_max": 3.2, "lifetime": 0.42, "gravity": 80.0, "drag": 0.88, "spread": 6.283, "directional": false},
		{"id": "smoke_puff", "name": "Smoke Puff", "count": 8, "colors": ["#9aa0a6", "#c8ccd0"], "speed_min": 8.0, "speed_max": 26.0, "size_min": 2.0, "size_max": 4.0, "lifetime": 0.7, "gravity": -40.0, "drag": 0.92, "spread": 6.283, "directional": false},
		{"id": "sparkle", "name": "Sparkle", "count": 7, "colors": ["#bff6ff", "#ffffff", "#7fd4ff"], "speed_min": 10.0, "speed_max": 40.0, "size_min": 0.6, "size_max": 1.4, "lifetime": 0.5, "gravity": 0.0, "drag": 0.9, "spread": 6.283, "directional": false},
		{"id": "death_poof", "name": "Death Poof", "count": 14, "colors": ["#d6b3ff", "#ffffff", "#9a6cff"], "speed_min": 20.0, "speed_max": 90.0, "size_min": 1.2, "size_max": 2.6, "lifetime": 0.45, "gravity": -20.0, "drag": 0.88, "spread": 6.283, "directional": false},
	]


static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"effects": []}
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return {"effects": []}
	if not raw.has("effects") or typeof(raw["effects"]) != TYPE_ARRAY:
		raw["effects"] = []
	return raw


static func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)

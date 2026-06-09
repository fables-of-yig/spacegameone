extends RefCounted

# Encounter def-table IO for the in-game Encounters Editor. The shipped game
# loads its global def table from res://Space/data/encounters/encounters.json
# (via DataManager); this lets a pack override/author it copy-on-write to
# user://Packs/<pack>/GameTuning/encounter_defs.json. Load cascade: user pack ->
# shipped pack -> demo -> global game data. The table is int-string-keyed
# ("0","1",...) -> encounter def (see default_encounter for the shape).

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const GLOBAL_DEFS := "res://Space/data/encounters/encounters.json"
const FOLDER := "GameTuning"
const FILE := "encounter_defs.json"


static func load_defs(pack_id: String) -> Dictionary:
	for path in [
		PedIO.user_file(pack_id, FOLDER, FILE),
		PedIO.shipped_file(pack_id, FOLDER, FILE),
		PedIO.demo_file(FOLDER, FILE),
		GLOBAL_DEFS,
	]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var raw: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(raw) == TYPE_DICTIONARY and not (raw as Dictionary).is_empty():
			return raw
	return {}


static func save_defs(pack_id: String, data: Dictionary) -> bool:
	var path := PedIO.user_file(pack_id, FOLDER, FILE)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


static func next_key(data: Dictionary) -> String:
	var n := 0
	for k in data:
		n = maxi(n, int(str(k)) + 1)
	return str(n)


static func default_encounter(id: int) -> Dictionary:
	return {
		"id": id,
		"title": "New Encounter",
		"tags": [],
		"threat": "none",
		"weight": 10,
		"min_day": 0,
		"max_day": -1,
		"required_flags": [],
		"excluded_flags": [],
		"sets_flags": [],
		"unique": false,
		"enabled": true,
		"cooldown_hours": 24,
		"chain_prev": -1,
		"chain_next": -1,
		"spawn": [],
		"nodes": {
			"start": {
				"speaker": "",
				"text": "New encounter.",
				"choices": [{"label": "Continue on your way.", "next": "", "effects": []}],
			},
		},
	}


static func default_spawn() -> Dictionary:
	return {
		"type": "npc_ship", "npc_type": "trader", "faction": "independent",
		"name": "Unknown Ship", "hostile": false, "distance": 400, "angle": "random", "wormhole": true,
	}


static func default_node() -> Dictionary:
	return {"speaker": "", "text": "", "choices": [{"label": "Continue.", "next": "", "effects": []}]}

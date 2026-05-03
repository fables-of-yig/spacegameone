class_name QuestIO
extends RefCounted

const PackPaths := preload("res://Space/scripts/editor/pack_paths.gd")


static func load_or_init(pack_id: String) -> Dictionary:
	var root := _load_pack_json_root(pack_id, "Quests/quests.json")
	if root.is_empty():
		return default_quests()
	if typeof(root.get("quests", [])) != TYPE_ARRAY:
		root["quests"] = []
	return root


static func save(pack_id: String, data: Dictionary) -> bool:
	var path := PackPaths.writable_pack_file(pack_id.strip_edges(), "Quests/quests.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func default_quests() -> Dictionary:
	return {"quests": []}


static func starter_quest(quest_id: String = "first_steps") -> Dictionary:
	var id := quest_id.strip_edges()
	if id.is_empty():
		id = "first_steps"
	return {
		"id": id,
		"title": id.capitalize(),
		"description": "A pack-authored quest.",
		"repeatable": false,
		"stages": [
			{
				"id": "start",
				"title": "Begin",
				"description": "Complete the first objective.",
				"objectives": [],
				"rewards": {"items": [], "abilities": [], "events": []},
			},
		],
	}


static func _load_pack_json_root(pack_id: String, rel_path: String) -> Dictionary:
	for path in [
		PackPaths.writable_pack_file(pack_id, rel_path),
		PackPaths.shipped_pack_file(pack_id, rel_path),
	]:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return {}

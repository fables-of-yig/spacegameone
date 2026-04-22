class_name TriggerRoot
extends RefCounted


static func default_root() -> Dictionary:
	return {
		"triggers": [],
		"libraries": [],
	}


static func normalize_root(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_ARRAY:
		return {
			"triggers": _normalize_rules(value as Array),
			"libraries": [],
		}
	if typeof(value) != TYPE_DICTIONARY:
		return default_root()
	var raw: Dictionary = value
	var root := default_root()
	root["triggers"] = _normalize_rules(_as_array(raw.get("triggers", [])))
	root["libraries"] = _normalize_libraries(_as_array(raw.get("libraries", [])))
	return root


static func flatten_rules(value: Variant) -> Array:
	var root := normalize_root(value)
	var out: Array = []
	out.append_array(_normalize_rules(_as_array(root.get("triggers", []))))
	for lib_v in _as_array(root.get("libraries", [])):
		if typeof(lib_v) != TYPE_DICTIONARY:
			continue
		var lib: Dictionary = lib_v
		out.append_array(_normalize_rules(_as_array(lib.get("triggers", []))))
		out.append_array(_flatten_folder_rules(_as_array(lib.get("folders", []))))
	return out


static func rule_count(value: Variant) -> int:
	return flatten_rules(value).size()


static func _normalize_libraries(entries: Array) -> Array:
	var out: Array = []
	for i in range(entries.size()):
		var entry_v: Variant = entries[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		out.append({
			"id": str(entry.get("id", "library_%d" % i)).strip_edges(),
			"name": str(entry.get("name", "Library %d" % (i + 1))).strip_edges(),
			"triggers": _normalize_rules(_as_array(entry.get("triggers", []))),
			"folders": _normalize_folders(_as_array(entry.get("folders", []))),
		})
	return out


static func _normalize_folders(entries: Array) -> Array:
	var out: Array = []
	for i in range(entries.size()):
		var entry_v: Variant = entries[i]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		out.append({
			"id": str(entry.get("id", "folder_%d" % i)).strip_edges(),
			"name": str(entry.get("name", "Folder %d" % (i + 1))).strip_edges(),
			"triggers": _normalize_rules(_as_array(entry.get("triggers", []))),
			"folders": _normalize_folders(_as_array(entry.get("folders", []))),
		})
	return out


static func _normalize_rules(entries: Array) -> Array:
	var out: Array = []
	for entry_v in entries:
		if typeof(entry_v) == TYPE_DICTIONARY:
			out.append((entry_v as Dictionary).duplicate(true))
	return out


static func _as_array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


static func _flatten_folder_rules(entries: Array) -> Array:
	var out: Array = []
	for entry_v in entries:
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_v
		out.append_array(_normalize_rules(_as_array(entry.get("triggers", []))))
		out.append_array(_flatten_folder_rules(_as_array(entry.get("folders", []))))
	return out

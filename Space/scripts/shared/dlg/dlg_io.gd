extends RefCounted

# Dialogue IO for the in-game dialogue editor (Frontier 2). A dialogue is
# Dialogue/<id>.json = { "lines": [ {speaker, text, condition?, actions?,
# choices?:[{text, next_line, condition?, actions?}]} ] } — the same shape
# MvDialogueRunner plays. Copy-on-write to the user pack; reads cascade
# user -> shipped (matches MvDialogueRunner._load_dialogue).

const PackPaths := preload("res://Space/scripts/shared/pack_paths.gd")


static func user_dir(pack_id: String) -> String:
	return PackPaths.writable_pack_dir(pack_id) + "Dialogue/"


static func shipped_dir(pack_id: String) -> String:
	return PackPaths.shipped_pack_dir(pack_id) + "Dialogue/"


static func default_dialogue() -> Dictionary:
	return {"lines": [{"speaker": "", "text": "New line."}]}


# Load a dialogue by id (user layer first, then shipped). Returns a default
# one-line dialogue if neither exists.
static func load_dialogue(pack_id: String, id: String) -> Dictionary:
	for base: String in [user_dir(pack_id), shipped_dir(pack_id)]:
		var path := base + id + ".json"
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(txt)
		if typeof(parsed) == TYPE_DICTIONARY:
			return parsed
	return default_dialogue()


static func save_dialogue(pack_id: String, id: String, data: Dictionary) -> bool:
	if id.strip_edges().is_empty():
		return false
	var dir := user_dir(pack_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + id + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return true


# All dialogue ids available to the pack (user + shipped), sorted, deduped.
static func list_dialogues(pack_id: String) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for base: String in [user_dir(pack_id), shipped_dir(pack_id)]:
		var d := DirAccess.open(base)
		if d == null:
			continue
		d.list_dir_begin()
		var fn := d.get_next()
		while fn != "":
			if not d.current_is_dir() and fn.ends_with(".json"):
				var id := fn.substr(0, fn.length() - 5)
				if not seen.has(id):
					seen[id] = true
					out.append(id)
			fn = d.get_next()
		d.list_dir_end()
	out.sort()
	return out


static func exists(pack_id: String, id: String) -> bool:
	return FileAccess.file_exists(user_dir(pack_id) + id + ".json") \
		or FileAccess.file_exists(shipped_dir(pack_id) + id + ".json")


# Remove a dialogue's user-pack file (shipped copy, if any, is left alone).
static func delete_dialogue(pack_id: String, id: String) -> bool:
	var path := user_dir(pack_id) + id + ".json"
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

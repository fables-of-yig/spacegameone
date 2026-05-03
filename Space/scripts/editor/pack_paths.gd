extends RefCounted

const PACK_ROOT_DIR: String = "Content"


static func writable_packs_root() -> String:
	if OS.has_feature("editor"):
		return "res://%s/" % PACK_ROOT_DIR
	var exe_dir := OS.get_executable_path().get_base_dir().replace("\\", "/")
	if exe_dir.is_empty():
		return "%s/" % PACK_ROOT_DIR
	return exe_dir.path_join(PACK_ROOT_DIR).replace("\\", "/").rstrip("/") + "/"


static func writable_pack_dir(pack_id: String) -> String:
	return writable_packs_root() + _clean_pack_id(pack_id) + "/"


static func writable_pack_file(pack_id: String, rel_path: String) -> String:
	var clean_rel := rel_path.strip_edges().replace("\\", "/")
	while clean_rel.begins_with("/"):
		clean_rel = clean_rel.substr(1)
	return writable_pack_dir(pack_id) + clean_rel


static func shipped_pack_dir(pack_id: String) -> String:
	return "res://Content/%s/" % _clean_pack_id(pack_id)


static func shipped_pack_file(pack_id: String, rel_path: String) -> String:
	var clean_rel := rel_path.strip_edges().replace("\\", "/")
	while clean_rel.begins_with("/"):
		clean_rel = clean_rel.substr(1)
	return shipped_pack_dir(pack_id) + clean_rel


static func _clean_pack_id(pack_id: String) -> String:
	var clean := pack_id.strip_edges()
	if clean.is_empty():
		return "demo"
	return clean

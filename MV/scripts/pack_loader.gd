class_name MvPackLoader

const UIIo := preload("res://Space/scripts/editor/ui/ui_io.gd")
const PORTABLE_PACK_ID_TOKEN := "__BUNDLED_PACK_ID__"

# Resolves content-pack paths and loads pack metadata + physics profile.
#
# Dual-path layer: every pack lives in two locations.
#   - res://Content/{packId}/  — shipped read-only (baseline, in the .pck)
#   - user://Packs/{packId}/   — user override layer (writeable, persists)
#
# Use: call MvPackLoader.load_pack("demo") once at startup (Main._ready)
# before anything reads pack assets.

static var current_pack: MvPackRef
static var _last_loaded_pack_id: String = ""


static func load_pack(pack_id: String) -> MvPackRef:
	var shipped := "res://Content/%s/" % pack_id
	var user_path := "user://Packs/%s/" % pack_id

	_ensure_user_pack_dir(user_path)

	var manifest_path := _resolve_read_static(user_path, shipped, "Pack.json")
	var manifest := read_json_dict(manifest_path)
	if manifest.is_empty():
		push_error("MvPackLoader: missing or invalid manifest at %s" % manifest_path)
		return null

	# Physics profile: try a GDScript-native .tres in the user layer first;
	# if nothing suitable exists, fall back to a fresh MvPhysicsProfile with
	# the hardcoded defaults (which already match the shipped C# .tres).
	var physics: MvPhysicsProfile = _load_physics_profile(user_path, shipped)
	if physics == null:
		physics = MvPhysicsProfile.new()

	# Fresh-pack state reset: when loading a different pack than last time,
	# clear inventory + global tags. Same-pack re-entry (planet revisits)
	# preserves state so progression carries across Space↔MV handoffs.
	if not _last_loaded_pack_id.is_empty() and _last_loaded_pack_id != pack_id:
		PlayerInventory.clear()
		MvTriggerEngine.clear_global_tags()
	_last_loaded_pack_id = pack_id

	var pack := MvPackRef.new()
	pack.pack_id = pack_id
	pack.path = shipped
	pack.user_path = user_path
	pack.manifest = manifest
	pack.physics = physics
	current_pack = pack
	print("[MvPackLoader] loaded '%s' — %s v%s" % [
		pack_id, manifest.get("name", ""), manifest.get("version", "")
	])
	return pack


# Force-clear the cached pack_id so the next load_pack triggers a state reset.
# Use from save-load flows where the caller wants fresh inventory+tags even
# if the pack_id matches (e.g. "start new game" on the same pack).
static func reset_last_loaded_pack_id() -> void:
	_last_loaded_pack_id = ""


static func _ensure_user_pack_dir(user_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(user_path)
	var subs := [
		"Rooms", "Tilesets", "Sprites", "Beams",
		"Audio/Music", "Audio/Sfx",
		"Entities", "Items", "Dialogue", "Shops", "Triggers", "Abilities",
	]
	for sub in subs:
		DirAccess.make_dir_recursive_absolute(user_path + sub)


static func _resolve_read_static(user_path: String, shipped: String, rel: String) -> String:
	var user := user_path + rel
	return user if FileAccess.file_exists(user) else shipped + rel


# 3-layer pack-asset cascade: user edits → shipped pack baseline → demo fallback.
# Returns the first path that exists, or the demo path if none do (caller can
# check FileAccess.file_exists on the result to detect "truly missing").
static func resolve_read_cascade(pack_id: String, folder: String, file_name: String) -> String:
	var user := "user://Packs/%s/%s/%s" % [pack_id, folder, file_name]
	if FileAccess.file_exists(user):
		return user
	var shipped := "res://Content/%s/%s/%s" % [pack_id, folder, file_name]
	if FileAccess.file_exists(shipped):
		return shipped
	return "res://Content/demo/%s/%s" % [folder, file_name]


# Open+parse+validate a JSON file as a Dictionary. Returns {} on any failure
# (file missing, open error, parse error, or wrong JSON root type). Callers
# that want to distinguish "missing" from "corrupt" should FileAccess.file_exists
# check first.
static func read_json_dict(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var raw = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


static func _load_physics_profile(user_path: String, shipped: String) -> MvPhysicsProfile:
	var candidate := _resolve_read_static(user_path, shipped, "PhysicsProfile.tres")
	if not FileAccess.file_exists(candidate):
		return null
	var res = load(candidate)
	if res is MvPhysicsProfile:
		# Duplicate so runtime mutations (StatsApplier, region gravity_mult,
		# trigger set_physics actions) don't persist into Godot's resource
		# cache and leak across MV re-entries.
		return (res as MvPhysicsProfile).duplicate()
	return null


# Create an empty pack skeleton under user://Packs/<pack_id>/. Writes a
# minimal Pack.json and ensures every standard subdir exists. Safe to call
# on an existing directory — won't clobber an existing Pack.json. Returns
# true on success.
static func create_empty_pack(pack_id: String, display_name: String = "") -> bool:
	if pack_id.is_empty():
		push_error("MvPackLoader.create_empty_pack: empty pack_id")
		return false
	var user_path := "user://Packs/%s/" % pack_id
	_ensure_user_pack_dir(user_path)

	var manifest_path := user_path + "Pack.json"
	if FileAccess.file_exists(manifest_path):
		UIIo.ensure_stock_screens(pack_id)
		return true

	var final_name := display_name if not display_name.is_empty() else pack_id
	var manifest := {
		"pack_id": pack_id,
		"name": final_name,
		"version": "0.1.0",
		"author": "",
		"description": "",
		"entry_room": "",
		"start_realm": "",
	}
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_error("MvPackLoader.create_empty_pack: cannot open %s" % manifest_path)
		return false
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	UIIo.ensure_stock_screens(pack_id)
	return true


# List every pack under user://Packs/, reading each Pack.json for display
# metadata. Each entry includes `has_shipped` — true when a shipped pack
# of the same id exists under res://Content/ (meaning edits here are an
# override layer rather than an independent new pack). Returns an array of
# {id, display_name, modified_at, has_shipped, source} dicts sorted by
# modified_at descending.
static func list_user_packs() -> Array:
	var out: Array = []
	var packs_root := "user://Packs/"
	if not DirAccess.dir_exists_absolute(packs_root):
		return out
	var dir := DirAccess.open(packs_root)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if not dir.current_is_dir():
			continue
		var pack_dir := packs_root + entry + "/"
		var manifest_path := pack_dir + "Pack.json"
		var display_name := entry
		var mtime: int = 0
		if FileAccess.file_exists(manifest_path):
			var manifest := read_json_dict(manifest_path)
			if not manifest.is_empty():
				display_name = str(manifest.get("name", entry))
			mtime = int(FileAccess.get_modified_time(manifest_path))
		var has_shipped: bool = _shipped_pack_exists(entry)
		out.append({
			"id": entry,
			"display_name": display_name,
			"modified_at": mtime,
			"has_shipped": has_shipped,
			"source": "override" if has_shipped else "user",
		})
	dir.list_dir_end()
	out.sort_custom(func(a, b): return a["modified_at"] > b["modified_at"])
	return out


# True when res://Content/<pack_id>/Pack.json exists — i.e. this pack id
# is shipped as part of the baseline content. Used to distinguish "user
# override of a shipped pack" from "user-authored new pack".
static func _shipped_pack_exists(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	var manifest_path := "res://Content/%s/Pack.json" % pack_id
	if FileAccess.file_exists(manifest_path):
		return true
	return ResourceLoader.exists(manifest_path)


# List every pack the runtime can see — user overrides AND shipped-only
# packs that have never been edited. Shipped-only entries have source="shipped"
# and has_shipped=true; clicking one in the picker should offer to clone
# it into the user layer before editing.
static func list_all_packs() -> Array:
	var out: Array = list_user_packs()
	var have_ids: Dictionary = {}
	for entry_v in out:
		var entry: Dictionary = entry_v
		have_ids[str(entry.get("id", ""))] = true
	var shipped_root := "res://Content/"
	var dir := DirAccess.open(shipped_root)
	if dir == null:
		return out
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		if not dir.current_is_dir():
			continue
		if have_ids.has(name):
			continue
		var manifest_path := shipped_root + name + "/Pack.json"
		if not (FileAccess.file_exists(manifest_path) or ResourceLoader.exists(manifest_path)):
			continue
		var manifest := read_json_dict(manifest_path)
		var display_name := name
		if not manifest.is_empty():
			display_name = str(manifest.get("name", name))
		out.append({
			"id": name,
			"display_name": display_name,
			"modified_at": 0,
			"has_shipped": true,
			"source": "shipped",
		})
	dir.list_dir_end()
	return out


# Clone a shipped pack into the user layer so the author can start editing
# it. Copies res://Content/<pack_id>/ recursively to user://Packs/<pack_id>/.
# Skips if the user pack already exists. Returns true on success.
static func clone_shipped_pack(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	var user_path := "user://Packs/%s/" % pack_id
	if DirAccess.dir_exists_absolute(user_path) and FileAccess.file_exists(user_path + "Pack.json"):
		return true
	var shipped_path := "res://Content/%s/" % pack_id
	if not DirAccess.dir_exists_absolute(shipped_path):
		push_error("MvPackLoader.clone_shipped_pack: no shipped pack '%s'" % pack_id)
		return false
	_ensure_user_pack_dir(user_path)
	_copy_dir_recursive(shipped_path, user_path)
	print("[MvPackLoader] cloned shipped pack '%s' into user layer" % pack_id)
	return true


static func export_portable_pack(pack_id: String, archive_path: String) -> Dictionary:
	var clean_pack_id := pack_id.strip_edges()
	var clean_archive_path := archive_path.strip_edges()
	if clean_pack_id.is_empty():
		return {"success": false, "error": "Missing pack id."}
	if clean_archive_path.is_empty():
		return {"success": false, "error": "Missing export path."}

	var files := _collect_effective_pack_files(clean_pack_id)
	if files.is_empty():
		return {
			"success": false,
			"error": "Pack '%s' has no exportable files." % clean_pack_id,
		}
	var build := _build_portable_bundle_files(clean_pack_id, files)
	if not bool(build.get("success", false)):
		return build

	var zipper := ZIPPacker.new()
	var open_err := zipper.open(clean_archive_path)
	if open_err != OK:
		return {
			"success": false,
			"error": "Couldn't open archive for writing (%s)." % error_string(open_err),
		}

	var bundle_files: Dictionary = build.get("files", {})
	var rel_paths: Array = bundle_files.keys()
	rel_paths.sort()
	var bundle_manifest := {
		"bundle_format": "mv_pack_bundle_v1",
		"pack_id": clean_pack_id,
		"exported_at_unix": Time.get_unix_time_from_system(),
		"file_count": rel_paths.size(),
	}
	var bundle_err := _zip_write_text(zipper, "bundle.json", JSON.stringify(bundle_manifest, "\t"))
	if bundle_err != OK:
		zipper.close()
		return {
			"success": false,
			"error": "Couldn't write bundle manifest (%s)." % error_string(bundle_err),
		}

	for rel_path_v in rel_paths:
		var rel_path := str(rel_path_v)
		var bytes: PackedByteArray = bundle_files.get(rel_path, PackedByteArray())
		var file_err := _zip_write_bytes(zipper, "pack/" + rel_path, bytes)
		if file_err != OK:
			zipper.close()
			return {
				"success": false,
				"error": "Couldn't write '%s' (%s)." % [rel_path, error_string(file_err)],
			}

	zipper.close()
	return {
		"success": true,
		"pack_id": clean_pack_id,
		"archive_path": clean_archive_path,
		"file_count": rel_paths.size(),
	}


static func import_portable_pack(archive_path: String) -> Dictionary:
	var clean_archive_path := archive_path.strip_edges()
	if clean_archive_path.is_empty():
		return {"success": false, "error": "Missing import path."}

	var reader := ZIPReader.new()
	var open_err := reader.open(clean_archive_path)
	if open_err != OK:
		return {
			"success": false,
			"error": "Couldn't open archive (%s)." % error_string(open_err),
		}

	var zip_files: Array = reader.get_files()
	var uses_pack_prefix := false
	for zip_path_v in zip_files:
		var zip_path := str(zip_path_v)
		if zip_path.begins_with("pack/"):
			uses_pack_prefix = true
			break

	var payload_files: Array = []
	var manifest_zip_path := ""
	for zip_path_v in zip_files:
		var zip_path := str(zip_path_v)
		if zip_path.ends_with("/"):
			continue
		if uses_pack_prefix:
			if not zip_path.begins_with("pack/"):
				continue
			var rel_path := zip_path.substr(5)
			if rel_path.is_empty():
				continue
			if not _is_safe_bundle_rel_path(rel_path):
				reader.close()
				return {
					"success": false,
					"error": "Archive contains an unsafe path '%s'." % rel_path,
				}
			payload_files.append(rel_path)
			if rel_path == "Pack.json":
				manifest_zip_path = zip_path
		else:
			if zip_path == "bundle.json":
				continue
			if not _is_safe_bundle_rel_path(zip_path):
				reader.close()
				return {
					"success": false,
					"error": "Archive contains an unsafe path '%s'." % zip_path,
				}
			payload_files.append(zip_path)
			if zip_path == "Pack.json":
				manifest_zip_path = zip_path

	if manifest_zip_path.is_empty():
		reader.close()
		return {
			"success": false,
			"error": "Archive doesn't contain a pack manifest.",
		}

	var manifest_bytes: PackedByteArray = reader.read_file(manifest_zip_path)
	var parsed_manifest: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	var manifest: Dictionary = {}
	if typeof(parsed_manifest) == TYPE_DICTIONARY:
		manifest = parsed_manifest

	var source_pack_id := _sanitize_import_pack_id(
		str(manifest.get("pack_id", clean_archive_path.get_file().get_basename())),
		"imported_pack"
	)
	var final_pack_id := _unique_import_pack_id(source_pack_id)
	var user_root := "user://Packs/%s/" % final_pack_id
	_ensure_user_pack_dir(user_root)

	payload_files.sort()
	for rel_path_v in payload_files:
		var rel_path := str(rel_path_v)
		var zip_path := "pack/" + rel_path if uses_pack_prefix else rel_path
		var file_bytes: PackedByteArray = reader.read_file(zip_path)
		if rel_path == "Pack.json":
			var rewritten_manifest := manifest.duplicate(true)
			rewritten_manifest["pack_id"] = final_pack_id
			if not rewritten_manifest.has("name"):
				rewritten_manifest["name"] = final_pack_id
			file_bytes = _rewrite_imported_bundle_text(
				JSON.stringify(rewritten_manifest, "\t"),
				final_pack_id
			).to_utf8_buffer()
		elif _is_text_bundle_file(rel_path):
			file_bytes = _rewrite_imported_bundle_text(
				file_bytes.get_string_from_utf8(),
				final_pack_id
			).to_utf8_buffer()
		var dst_path := user_root + rel_path
		_ensure_parent_dir(dst_path)
		var wf := FileAccess.open(dst_path, FileAccess.WRITE)
		if wf == null:
			reader.close()
			return {
				"success": false,
				"error": "Couldn't write imported file '%s'." % rel_path,
			}
		wf.store_buffer(file_bytes)
		wf.close()

	reader.close()
	UIIo.ensure_stock_screens(final_pack_id)
	return {
		"success": true,
		"pack_id": final_pack_id,
		"source_pack_id": source_pack_id,
		"archive_path": clean_archive_path,
		"file_count": payload_files.size(),
		"renamed": final_pack_id != source_pack_id,
	}


static func _copy_dir_recursive(src: String, dst: String) -> void:
	var dir := DirAccess.open(src)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name.is_empty():
			break
		var src_full := src.rstrip("/") + "/" + name
		var dst_full := dst.rstrip("/") + "/" + name
		if dir.current_is_dir():
			DirAccess.make_dir_recursive_absolute(dst_full)
			_copy_dir_recursive(src_full, dst_full)
		else:
			if FileAccess.file_exists(dst_full):
				continue
			if name.ends_with(".import") or name.ends_with(".uid"):
				continue
			var rf := FileAccess.open(src_full, FileAccess.READ)
			if rf == null:
				continue
			var buf := rf.get_buffer(rf.get_length())
			rf.close()
			var wf := FileAccess.open(dst_full, FileAccess.WRITE)
			if wf == null:
				continue
			wf.store_buffer(buf)
			wf.close()
	dir.list_dir_end()


static func _build_portable_bundle_files(pack_id: String, pack_files: Dictionary) -> Dictionary:
	var pending: Array = []
	var scheduled: Dictionary = {}
	var bundle_files: Dictionary = {}
	for rel_path_v in pack_files.keys():
		var rel_path := str(rel_path_v)
		pending.append({
			"bundle_rel": rel_path,
			"source_path": str(pack_files.get(rel_path, "")),
		})
		scheduled[rel_path] = true

	while not pending.is_empty():
		var entry: Dictionary = pending[0]
		pending.remove_at(0)
		var bundle_rel := str(entry.get("bundle_rel", ""))
		var source_path := str(entry.get("source_path", ""))
		if bundle_rel.is_empty() or source_path.is_empty():
			continue
		if bundle_files.has(bundle_rel):
			continue
		if _is_text_bundle_file(bundle_rel):
			var prepared := _prepare_text_bundle_file(pack_id, source_path, pending, scheduled)
			if not bool(prepared.get("success", false)):
				return prepared
			bundle_files[bundle_rel] = prepared.get("bytes", PackedByteArray())
		else:
			bundle_files[bundle_rel] = _read_all_bytes(source_path)

	return {
		"success": true,
		"files": bundle_files,
	}


static func _prepare_text_bundle_file(pack_id: String, source_path: String,
		pending: Array, scheduled: Dictionary) -> Dictionary:
	var text := _read_all_text(source_path)
	var refs: Array = _find_referenced_paths(text)
	var replacements: Dictionary = {}
	for ref_v in refs:
		var ref := str(ref_v)
		var plan := _plan_export_reference(pack_id, ref)
		if plan.is_empty():
			continue
		var replacement := str(plan.get("replacement", ""))
		if replacement.is_empty():
			continue
		replacements[ref] = replacement
		if str(plan.get("action", "")) != "bundle_external":
			continue
		var bundle_rel := str(plan.get("bundle_rel", ""))
		if bundle_rel.is_empty() or scheduled.has(bundle_rel):
			continue
		pending.append({
			"bundle_rel": bundle_rel,
			"source_path": str(plan.get("source_path", "")),
		})
		scheduled[bundle_rel] = true

	for ref_v in _sort_strings_by_length_desc(replacements.keys()):
		var ref := str(ref_v)
		text = text.replace(ref, str(replacements.get(ref, ref)))

	return {
		"success": true,
		"bytes": text.to_utf8_buffer(),
	}


static func _collect_effective_pack_files(pack_id: String) -> Dictionary:
	var files: Dictionary = {}
	var shipped_root := "res://Content/%s/" % pack_id
	var user_root := "user://Packs/%s/" % pack_id
	if DirAccess.dir_exists_absolute(shipped_root):
		_scan_pack_dir_recursive(shipped_root, "", files)
	if DirAccess.dir_exists_absolute(user_root):
		_scan_pack_dir_recursive(user_root, "", files)
	return files


static func _scan_pack_dir_recursive(root: String, rel_dir: String, out: Dictionary) -> void:
	var dir_path := root + rel_dir
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var rel_path := entry if rel_dir.is_empty() else rel_dir + "/" + entry
		var full_path := root + rel_path
		if dir.current_is_dir():
			_scan_pack_dir_recursive(root, rel_path, out)
			continue
		if entry.ends_with(".import") or entry.ends_with(".uid"):
			continue
		out[rel_path] = full_path
	dir.list_dir_end()


static func _read_all_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes


static func _read_all_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


static func _zip_write_text(zipper: ZIPPacker, zip_path: String, text: String) -> int:
	return _zip_write_bytes(zipper, zip_path, text.to_utf8_buffer())


static func _zip_write_bytes(zipper: ZIPPacker, zip_path: String, bytes: PackedByteArray) -> int:
	var start_err := zipper.start_file(zip_path)
	if start_err != OK:
		return start_err
	zipper.write_file(bytes)
	zipper.close_file()
	return OK


static func _sanitize_import_pack_id(pack_id: String, fallback: String) -> String:
	var safe_id := pack_id.to_lower().strip_edges().replace(" ", "_")
	for ch in "!@#$%^&*(){}[]|\\:;\"'<>,./?\t\n":
		safe_id = safe_id.replace(ch, "")
	if safe_id.is_empty():
		safe_id = fallback
	return safe_id


static func _unique_import_pack_id(pack_id: String) -> String:
	if not _pack_id_exists_anywhere(pack_id):
		return pack_id
	var base := "%s_imported" % pack_id
	var candidate := base
	var n: int = 2
	while _pack_id_exists_anywhere(candidate):
		candidate = "%s_%d" % [base, n]
		n += 1
	return candidate


static func _pack_id_exists_anywhere(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	if DirAccess.dir_exists_absolute("user://Packs/%s" % pack_id):
		return true
	return _shipped_pack_exists(pack_id)


static func _ensure_parent_dir(file_path: String) -> void:
	var slash := file_path.rfind("/")
	if slash <= 0:
		return
	DirAccess.make_dir_recursive_absolute(file_path.substr(0, slash))


static func _find_referenced_paths(text: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var regex := RegEx.new()
	if regex.compile("(?:res://|user://)[^\\s\\\"'\\]\\)\\}]+") != OK:
		return out
	for match_v in regex.search_all(text):
		var match: RegExMatch = match_v
		var found := str(match.get_string())
		if found.is_empty() or seen.has(found):
			continue
		seen[found] = true
		out.append(found)
	return out


static func _plan_export_reference(pack_id: String, ref_path: String) -> Dictionary:
	var normalized := ref_path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return {}
	var pack_user_root := "user://Packs/%s/" % pack_id
	var pack_shipped_root := "res://Content/%s/" % pack_id
	if normalized.begins_with(pack_user_root):
		var rel := normalized.substr(pack_user_root.length())
		return {
			"action": "rewrite_internal",
			"replacement": _portable_pack_user_path(rel),
		}
	if normalized.begins_with(pack_shipped_root):
		var rel := normalized.substr(pack_shipped_root.length())
		return {
			"action": "rewrite_internal",
			"replacement": _portable_pack_user_path(rel),
		}
	if not _should_bundle_external_reference(normalized):
		return {}
	if not _resource_exists(normalized):
		return {}
	var bundle_rel := _bundle_external_rel_path(normalized)
	if bundle_rel.is_empty():
		return {}
	return {
		"action": "bundle_external",
		"replacement": _portable_pack_user_path(bundle_rel),
		"bundle_rel": bundle_rel,
		"source_path": normalized,
	}


static func _should_bundle_external_reference(path: String) -> bool:
	if not _is_supported_external_asset(path):
		return false
	if path.begins_with("res://Assets/"):
		return true
	if path.begins_with("res://Space/art/"):
		return true
	if path.begins_with("res://Content/"):
		return true
	if path.begins_with("user://Packs/"):
		return true
	return path.contains(":/")


static func _is_supported_external_asset(path: String) -> bool:
	var lower := path.to_lower()
	for ext_v in [
		".png",
		".jpg",
		".jpeg",
		".webp",
		".bmp",
		".tga",
		".svg",
		".ogg",
		".wav",
		".mp3",
		".flac",
		".tres",
		".res",
	]:
		if lower.ends_with(str(ext_v)):
			return true
	return false


static func _bundle_external_rel_path(source_path: String) -> String:
	var clean := source_path.replace("\\", "/")
	if clean.begins_with("res://"):
		return "BundledAssets/res/" + clean.substr("res://".length())
	if clean.begins_with("user://"):
		return "BundledAssets/user/" + clean.substr("user://".length())
	if clean.length() > 2 and clean.substr(1, 2) == ":/":
		var drive := clean.substr(0, 1)
		var tail := clean.substr(3)
		return "BundledAssets/fs/%s/%s" % [drive, tail]
	if clean.begins_with("/"):
		return "BundledAssets/fs/root/" + clean.substr(1)
	return ""


static func _portable_pack_user_path(rel_path: String) -> String:
	var clean := rel_path.strip_edges().replace("\\", "/")
	while clean.begins_with("/"):
		clean = clean.substr(1)
	return "user://Packs/%s/%s" % [PORTABLE_PACK_ID_TOKEN, clean]


static func _rewrite_imported_bundle_text(text: String, final_pack_id: String) -> String:
	return text.replace(
		"user://Packs/%s/" % PORTABLE_PACK_ID_TOKEN,
		"user://Packs/%s/" % final_pack_id
	)


static func _resource_exists(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	return ResourceLoader.exists(path)


static func _is_text_bundle_file(path: String) -> bool:
	var lower := path.to_lower()
	for ext_v in [".json", ".tres", ".tscn", ".cfg", ".txt"]:
		if lower.ends_with(str(ext_v)):
			return true
	return false


static func _sort_strings_by_length_desc(values: Array) -> Array:
	var out: Array = []
	for value_v in values:
		out.append(str(value_v))
	out.sort_custom(func(a, b):
		if a.length() == b.length():
			return a < b
		return a.length() > b.length()
	)
	return out


static func _is_safe_bundle_rel_path(rel_path: String) -> bool:
	if rel_path.is_empty():
		return false
	if rel_path.begins_with("/") or rel_path.begins_with("\\"):
		return false
	if rel_path.find("..") >= 0:
		return false
	return true


# Auto-generate the next "new_campaign_<n>" id that doesn't already exist
# under user://Packs/. Used by the campaign picker's "+ NEW CAMPAIGN" flow
# so the user doesn't have to type a name before editing.
static func next_new_campaign_id() -> String:
	var packs_root := "user://Packs/"
	var n: int = 1
	while true:
		var candidate := "new_campaign_%d" % n
		if not DirAccess.dir_exists_absolute(packs_root + candidate):
			return candidate
		n += 1
	return "new_campaign_1"


# Rename a pack's display name by rewriting Pack.json. The directory name
# (pack_id) stays the same — only the manifest "name" field changes.
static func rename_pack(pack_id: String, new_display_name: String) -> bool:
	if pack_id.is_empty() or new_display_name.strip_edges().is_empty():
		return false
	var manifest_path := "user://Packs/%s/Pack.json" % pack_id
	var manifest := read_json_dict(manifest_path)
	if manifest.is_empty():
		manifest = {"pack_id": pack_id}
	manifest["name"] = new_display_name.strip_edges()
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_error("MvPackLoader.rename_pack: cannot write %s" % manifest_path)
		return false
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	return true


# Delete a user pack by removing its entire directory. Only works on
# user://Packs/ — shipped packs under res:// are never touched.
static func delete_pack(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	var pack_dir := "user://Packs/%s" % pack_id
	if not DirAccess.dir_exists_absolute(pack_dir):
		return false
	# Recursively remove all files and subdirectories.
	_remove_dir_recursive(pack_dir)
	return true


static func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry := dir.get_next()
		if entry.is_empty():
			break
		var full := path.rstrip("/") + "/" + entry
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
	dir.list_dir_end()
	DirAccess.remove_absolute(path)

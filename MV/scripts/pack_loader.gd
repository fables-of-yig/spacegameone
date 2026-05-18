class_name MvPackLoader

const RegIO := preload("res://Space/scripts/editor/reg/reg_io.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")
const UIIo := preload("res://Space/scripts/editor/ui/ui_io.gd")
const PedIO := preload("res://Space/scripts/editor/ped/ped_io.gd")
const PspIO := preload("res://Space/scripts/editor/psp/psp_io.gd")
const PackPaths := preload("res://Space/scripts/editor/pack_paths.gd")
const PORTABLE_PACK_ID_TOKEN := "__BUNDLED_PACK_ID__"
const INTERNAL_TOOL_PACK_IDS := {
	"phase1_bootstrap": true,
	"phase2_runtime_smoke": true,
	"phase2_sprite_smoke_codex": true,
	"trigger_recipe_smoke": true,
	"world_recipe_smoke": true,
	"reference_index_smoke": true,
	"reference_refactor_smoke": true,
	"quest_schema_smoke": true,
}

# Resolves content-pack paths and loads pack metadata + physics profile.
#
# Dual-path layer: every pack lives in two locations.
#   - res://Content/{packId}/  — shipped read-only (baseline, in the .pck)
#   - Content/{packId}/        - writable exported authoring tree
#
# Use: call MvPackLoader.load_pack("demo") once at startup (Main._ready)
# before anything reads pack assets.

static var current_pack: MvPackRef
static var _last_loaded_pack_id: String = ""


static func load_pack(pack_id: String) -> MvPackRef:
	var shipped := PackPaths.shipped_pack_dir(pack_id)
	var user_path := PackPaths.writable_pack_dir(pack_id)

	_ensure_user_pack_dir(user_path)
	repair_shipped_pack(pack_id)

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
		_clear_inventory()
		_clear_global_tags()
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


static func clear_runtime_state() -> void:
	current_pack = null
	_last_loaded_pack_id = ""
	_clear_inventory()
	_clear_global_tags()
	_clear_room_state()
	_clear_map_state()


static func _ensure_user_pack_dir(user_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(user_path)
	var subs := [
		"Rooms", "Tilesets", "Sprites", "Beams",
		"Audio/Music", "Audio/Sfx",
		"Entities", "Items", "Dialogue", "Shops", "Triggers", "Abilities",
		"Systems", "Regions", "Player", "Projectiles", "UI", "UI/screens",
		"Assets", "Assets/UI", "Ships", "ShipTemplates",
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
	var user := PackPaths.writable_pack_file(pack_id, "%s/%s" % [folder, file_name])
	if FileAccess.file_exists(user):
		return user
	var shipped := PackPaths.shipped_pack_file(pack_id, "%s/%s" % [folder, file_name])
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


# Create an empty pack skeleton under Content/<pack_id>/ and seed the
# Phase 1 starter data. Safe to call on an existing directory: authored
# manifest values are preserved while missing bootstrap fields are filled.
# Returns true on success.
static func create_empty_pack(pack_id: String, display_name: String = "") -> bool:
	if pack_id.is_empty():
		push_error("MvPackLoader.create_empty_pack: empty pack_id")
		return false
	var user_path := PackPaths.writable_pack_dir(pack_id)
	_ensure_user_pack_dir(user_path)

	var manifest_path := user_path + "Pack.json"
	var starter_world: Dictionary = RegIO.ensure_starter_world(pack_id)
	var starter_region_id: String = str(starter_world.get("region_id", RegIO.DEFAULT_REGION_ID)).strip_edges()
	var starter_room_addr: String = str(starter_world.get("room_addr", RegIO.STARTER_ROOM_ADDR)).strip_edges()
	var starter_spawn_pos := _resolve_starter_spawn_pos(
		pack_id,
		starter_region_id,
		starter_room_addr
	)
	# Phase 5+ shape: SystemIO.ensure_starter_system seeds a starter POI
	# with a single regions[] entry built from the region/room/spawn_pos
	# provided here. No realm_id slot anymore.
	var start_system_id := SystemIO.ensure_starter_system(
		pack_id,
		starter_region_id,
		starter_room_addr,
		starter_spawn_pos
	)
	UIIo.ensure_stock_screens(pack_id)
	PedIO.ensure_starter_player_data(pack_id)
	PspIO.ensure_starter_player_sprites(pack_id)

	var manifest := read_json_dict(manifest_path)
	var original_manifest := manifest.duplicate(true)
	var final_name := display_name.strip_edges() if not display_name.strip_edges().is_empty() else pack_id
	_set_manifest_default(manifest, "schema_version", "1.0")
	_set_manifest_default(manifest, "pack_id", pack_id)
	_set_manifest_default(manifest, "name", final_name)
	_set_manifest_default(manifest, "version", "0.1.0")
	_set_manifest_default(manifest, "author", "", false)
	_set_manifest_default(manifest, "description", "", false)
	_set_manifest_default(manifest, "start_system",
		start_system_id if not start_system_id.is_empty() else SystemIO.STARTER_SYSTEM_ID)
	_set_manifest_default(manifest, "start_ship_template", "startship")
	_set_manifest_default(manifest, "start_region", starter_region_id)
	_set_manifest_default(manifest, "entry_room",
		str(starter_world.get("start_room",
			RegIO.runtime_room_addr(starter_region_id, starter_room_addr))))

	if FileAccess.file_exists(manifest_path) and manifest == original_manifest:
		return true
	var f := FileAccess.open(manifest_path, FileAccess.WRITE)
	if f == null:
		push_error("MvPackLoader.create_empty_pack: cannot open %s" % manifest_path)
		return false
	f.store_string(JSON.stringify(manifest, "\t"))
	f.close()
	return true


static func _set_manifest_default(manifest: Dictionary, key: String, value: Variant,
		fill_empty: bool = true) -> void:
	if not manifest.has(key):
		manifest[key] = value
		return
	if fill_empty and str(manifest.get(key, "")).strip_edges().is_empty():
		manifest[key] = value


static func _resolve_starter_spawn_pos(pack_id: String, region_id: String,
		room_addr: String) -> Vector2:
	var rooms_root: Dictionary = RegIO.load_region_rooms(pack_id, region_id)
	var rooms_v: Variant = rooms_root.get("rooms", {})
	if typeof(rooms_v) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var rooms: Dictionary = rooms_v
	var room_v: Variant = rooms.get(room_addr, {})
	if typeof(room_v) != TYPE_DICTIONARY:
		return Vector2.ZERO
	var room: Dictionary = room_v
	return _find_player_spawn_pos(room)


static func _find_player_spawn_pos(room: Dictionary) -> Vector2:
	var entities_v: Variant = room.get("entities", [])
	if typeof(entities_v) != TYPE_ARRAY:
		return Vector2.ZERO
	for entity_v in entities_v:
		if typeof(entity_v) != TYPE_DICTIONARY:
			continue
		var entity: Dictionary = entity_v
		if str(entity.get("type", "")).strip_edges() != "player_spawn":
			continue
		var position_v: Variant = entity.get("position", null)
		if position_v is Vector2:
			var position_vec: Vector2 = position_v
			return position_vec
		if position_v is Vector2i:
			var position_vec_i: Vector2i = position_v
			return Vector2(position_vec_i)
		if typeof(position_v) == TYPE_ARRAY:
			var position_arr: Array = position_v
			if position_arr.size() >= 2:
				return Vector2(float(position_arr[0]), float(position_arr[1]))
		if typeof(position_v) == TYPE_DICTIONARY:
			var position: Dictionary = position_v
			return Vector2(
				float(position.get("x", entity.get("x", 0.0))),
				float(position.get("y", entity.get("y", 0.0)))
			)
		return Vector2(float(entity.get("x", 0.0)), float(entity.get("y", 0.0)))
	return Vector2.ZERO


static func _clear_inventory() -> void:
	var inv := _autoload_node("PlayerInventory")
	if inv != null and inv.has_method("clear"):
		inv.call("clear")


static func _clear_global_tags() -> void:
	var trigger_engine := _autoload_node("MvTriggerEngine")
	if trigger_engine != null and trigger_engine.has_method("clear"):
		trigger_engine.call("clear")
		return
	if trigger_engine != null and trigger_engine.has_method("clear_global_tags"):
		trigger_engine.call("clear_global_tags")


static func _clear_room_state() -> void:
	var room_state := _autoload_node("MvRoomState")
	if room_state != null and room_state.has_method("clear"):
		room_state.call("clear")


static func _clear_map_state() -> void:
	var map_screen := _autoload_node("MvMapScreen")
	if map_screen != null and map_screen.has_method("clear"):
		map_screen.call("clear")


static func _autoload_node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


# List every pack under the writable Content root, reading each Pack.json for display
# metadata. Each entry includes `has_shipped` — true when a shipped pack
# of the same id exists under res://Content/ (meaning edits here are an
# override layer rather than an independent new pack). Returns an array of
# {id, display_name, modified_at, has_shipped, source} dicts sorted by
# modified_at descending.
static func list_user_packs() -> Array:
	var out: Array = []
	var packs_root := PackPaths.writable_packs_root()
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
		if _is_internal_tool_pack_id(entry):
			continue
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
	var manifest_path := PackPaths.shipped_pack_file(pack_id, "Pack.json")
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
		if _is_internal_tool_pack_id(name):
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
# it. Copies missing files from res://Content/<pack_id>/ recursively to
# Content/<pack_id>/ without overwriting user edits. This is also a
# repair pass for exported builds that previously created a partial user
# pack before all raw authoring assets were bundled.
static func clone_shipped_pack(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	var user_path := PackPaths.writable_pack_dir(pack_id)
	var shipped_path := PackPaths.shipped_pack_dir(pack_id)
	if user_path == shipped_path:
		return true
	if not DirAccess.dir_exists_absolute(shipped_path):
		push_error("MvPackLoader.clone_shipped_pack: no shipped pack '%s'" % pack_id)
		return false
	_ensure_user_pack_dir(user_path)
	_copy_dir_recursive(shipped_path, user_path)
	_write_shipped_repair_marker(pack_id)
	print("[MvPackLoader] cloned shipped pack '%s' into user layer" % pack_id)
	return true


# Repair an existing user override for a shipped pack by copying any missing
# bundled files into user://. Existing user-edited files are left untouched.
static func repair_shipped_pack(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	if not _shipped_pack_exists(pack_id):
		return true
	if PackPaths.writable_pack_dir(pack_id) == PackPaths.shipped_pack_dir(pack_id):
		return true
	if _shipped_repair_marker_current(pack_id):
		return true
	return clone_shipped_pack(pack_id)


static func _shipped_repair_marker_current(pack_id: String) -> bool:
	var marker_path := PackPaths.writable_pack_file(pack_id, ".shipped_repair_version")
	if not FileAccess.file_exists(marker_path):
		return false
	var f := FileAccess.open(marker_path, FileAccess.READ)
	if f == null:
		return false
	var marker_version := f.get_as_text().strip_edges()
	f.close()
	if marker_version.is_empty() or marker_version != _current_app_version():
		return false
	return _shipped_repair_sentinels_ok(pack_id)


static func _shipped_repair_sentinels_ok(pack_id: String) -> bool:
	var user_path := PackPaths.writable_pack_dir(pack_id)
	var json_files := [
		"Pack.json",
		"Entities/entities.json",
		"Sprites/player_frames.json",
	]
	for rel_v in json_files:
		var rel := str(rel_v)
		if _read_json_any(user_path + rel) == null:
			return false
	if not _image_file_has_visible_pixels(user_path + "Sprites/Idle/Normal/idle_down.png"):
		return false
	return true


static func _write_shipped_repair_marker(pack_id: String) -> void:
	var marker_path := PackPaths.writable_pack_file(pack_id, ".shipped_repair_version")
	_ensure_parent_dir(marker_path)
	var f := FileAccess.open(marker_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(_current_app_version())
	f.close()


static func _current_app_version() -> String:
	for path in ["res://version.txt", "user://version.txt"]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var version := f.get_as_text().strip_edges()
		f.close()
		if not version.is_empty():
			return version
	return "0"


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
	var user_root := PackPaths.writable_pack_dir(final_pack_id)
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
			if name.ends_with(".import"):
				var imported_source_name := name.substr(0, name.length() - ".import".length())
				var imported_src := src.rstrip("/") + "/" + imported_source_name
				var imported_dst := dst.rstrip("/") + "/" + imported_source_name
				if _should_copy_shipped_file(imported_src, imported_dst):
					_copy_file_bytes(imported_src, imported_dst)
				continue
			if not _should_copy_shipped_file(src_full, dst_full):
				continue
			if name.ends_with(".uid"):
				continue
			_copy_file_bytes(src_full, dst_full)
	dir.list_dir_end()


static func _should_copy_shipped_file(src_path: String, dst_path: String) -> bool:
	if not FileAccess.file_exists(src_path):
		return false
	if not FileAccess.file_exists(dst_path):
		return true
	var lower := src_path.to_lower()
	if lower.ends_with(".json"):
		return _read_json_any(dst_path) == null and _read_json_any(src_path) != null
	if _is_image_path(lower):
		return not _image_file_has_visible_pixels(dst_path) and _image_file_has_visible_pixels(src_path)
	if _is_binary_asset_path(lower):
		return _file_length(dst_path) <= 0 and _file_length(src_path) > 0
	return false


static func _read_json_any(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _is_image_path(lower_path: String) -> bool:
	for ext_v in [".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga"]:
		var ext: String = str(ext_v)
		if lower_path.ends_with(ext):
			return true
	return false


static func _is_binary_asset_path(lower_path: String) -> bool:
	for ext_v in [".ogg", ".wav", ".mp3", ".flac", ".tres", ".res"]:
		var ext: String = str(ext_v)
		if lower_path.ends_with(ext):
			return true
	return false


static func _file_length(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var length := int(f.get_length())
	f.close()
	return length


static func _image_file_has_visible_pixels(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.is_empty():
		return false
	var img := Image.new()
	var ext := path.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	match ext:
		"png":
			if not _bytes_have_png_signature(bytes):
				return false
			err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg":
			if not _bytes_have_jpeg_signature(bytes):
				return false
			err = img.load_jpg_from_buffer(bytes)
		"webp":
			if not _bytes_have_webp_signature(bytes):
				return false
			err = img.load_webp_from_buffer(bytes)
		"bmp":
			if not _bytes_have_bmp_signature(bytes):
				return false
			err = img.load_bmp_from_buffer(bytes)
		"tga":
			err = img.load_tga_from_buffer(bytes)
		_:
			err = img.load(path)
	if err != OK or img.get_width() <= 0 or img.get_height() <= 0:
		return false
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.01:
				return true
	return false


static func _bytes_have_png_signature(bytes: PackedByteArray) -> bool:
	var sig := PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
	if bytes.size() < sig.size():
		return false
	for i in range(sig.size()):
		if bytes[i] != sig[i]:
			return false
	return true


static func _bytes_have_jpeg_signature(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff


static func _bytes_have_webp_signature(bytes: PackedByteArray) -> bool:
	return (
		bytes.size() >= 12
		and bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46
		and bytes[8] == 0x57 and bytes[9] == 0x45 and bytes[10] == 0x42 and bytes[11] == 0x50
	)


static func _bytes_have_bmp_signature(bytes: PackedByteArray) -> bool:
	return bytes.size() >= 2 and bytes[0] == 0x42 and bytes[1] == 0x4d


static func _copy_file_bytes(src_path: String, dst_path: String) -> bool:
	var rf := FileAccess.open(src_path, FileAccess.READ)
	if rf == null:
		return false
	var buf := rf.get_buffer(rf.get_length())
	rf.close()
	var wf := FileAccess.open(dst_path, FileAccess.WRITE)
	if wf == null:
		return false
	wf.store_buffer(buf)
	wf.close()
	return true


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
	var shipped_root := PackPaths.shipped_pack_dir(pack_id)
	var user_root := PackPaths.writable_pack_dir(pack_id)
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
			if entry.ends_with(".import"):
				var imported_rel := rel_path.substr(0, rel_path.length() - ".import".length())
				var imported_full := root + imported_rel
				if FileAccess.file_exists(imported_full) and not out.has(imported_rel):
					out[imported_rel] = imported_full
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
	if DirAccess.dir_exists_absolute(PackPaths.writable_pack_dir(pack_id).rstrip("/")):
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


static func _is_internal_tool_pack_id(pack_id: String) -> bool:
	return INTERNAL_TOOL_PACK_IDS.has(pack_id.strip_edges())


static func _plan_export_reference(pack_id: String, ref_path: String) -> Dictionary:
	var normalized := ref_path.strip_edges().replace("\\", "/")
	if normalized.is_empty():
		return {}
	var pack_user_root := PackPaths.writable_pack_dir(pack_id)
	var pack_shipped_root := PackPaths.shipped_pack_dir(pack_id)
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
	if path.begins_with(PackPaths.writable_packs_root()):
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
	return "pack://%s/%s" % [PORTABLE_PACK_ID_TOKEN, clean]


static func _rewrite_imported_bundle_text(text: String, final_pack_id: String) -> String:
	var rewritten := text.replace(
		"pack://%s/" % PORTABLE_PACK_ID_TOKEN,
		PackPaths.writable_pack_dir(final_pack_id)
	)
	rewritten = rewritten.replace(
		"user://Packs/%s/" % PORTABLE_PACK_ID_TOKEN,
		PackPaths.writable_pack_dir(final_pack_id)
	)
	return rewritten


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
# under the writable Content root. Used by the campaign picker's "+ NEW CAMPAIGN" flow
# so the user doesn't have to type a name before editing.
static func next_new_campaign_id() -> String:
	var packs_root := PackPaths.writable_packs_root()
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
	var manifest_path := PackPaths.writable_pack_file(pack_id, "Pack.json")
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
# the writable Content root. Shipped packs under res:// are never touched.
static func delete_pack(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	var pack_dir := PackPaths.writable_pack_dir(pack_id).rstrip("/")
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

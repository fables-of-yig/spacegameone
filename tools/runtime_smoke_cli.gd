extends SceneTree

const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")
const SystemIO := preload("res://Space/scripts/editor/system_io.gd")


func _init() -> void:
	_run_and_quit.call_deferred(OS.get_cmdline_user_args())


func _run_and_quit(args: Array) -> void:
	var ok := await _run(args)
	quit(0 if ok else 1)


func _run(args: Array) -> bool:
	var command := "authored-route"
	var pack_id := "phase2_runtime_smoke"
	var slot := 5
	var skip_bootstrap := false
	if not args.is_empty() and not str(args[0]).begins_with("--"):
		command = str(args[0])
	var i := 1 if command == str(args[0]) else 0
	while i < args.size():
		var arg := str(args[i])
		match arg:
			"--pack":
				i += 1
				if i < args.size():
					pack_id = str(args[i]).strip_edges()
			"--slot":
				i += 1
				if i < args.size():
					slot = int(args[i])
			"--skip-bootstrap":
				skip_bootstrap = true
			_:
				push_error("runtime_smoke_cli: unknown arg '%s'" % arg)
				return false
		i += 1
	if command != "authored-route":
		push_error("runtime_smoke_cli: unknown command '%s'" % command)
		return false
	if pack_id.is_empty():
		push_error("runtime_smoke_cli: empty pack id")
		return false
	return await _run_authored_route(pack_id, slot, skip_bootstrap)


func _run_authored_route(pack_id: String, slot: int, skip_bootstrap: bool) -> bool:
	var pi := root.get_node_or_null("PlanetaryInterface")
	var inv := root.get_node_or_null("PlayerInventory")
	var room_state := root.get_node_or_null("MvRoomState")
	var map_screen := root.get_node_or_null("MvMapScreen")
	var trigger_engine := root.get_node_or_null("MvTriggerEngine")
	var game_manager := root.get_node_or_null("GameManager")
	if pi == null or inv == null or room_state == null or map_screen == null \
			or trigger_engine == null or game_manager == null:
		push_error("runtime_smoke_cli: required autoload missing")
		return false

	if not skip_bootstrap and not MvPackLoader.create_empty_pack(pack_id, "Phase 2 Runtime Smoke"):
		push_error("runtime_smoke_cli: bootstrap failed")
		return false
	if not _validate_pack(pack_id):
		return false

	var planet_data := _starter_planet_data(pack_id)
	if planet_data.is_empty():
		return false
	var expected_snapshot_key := "%s::%s" % [pack_id, str(planet_data.get("planet_key", ""))]

	MvPackLoader.clear_runtime_state()
	pi.call("reset_runtime_state", true, true)

	var save_path := "user://saves/save_%d.json" % slot
	var save_backup := _read_text_if_exists(save_path)
	var had_save := FileAccess.file_exists(save_path)

	var space_scene := load("res://Space/scenes/main.tscn") as PackedScene
	if space_scene == null:
		push_error("runtime_smoke_cli: failed to load Space main scene")
		return false
	var space := space_scene.instantiate()
	root.add_child(space)
	await process_frame
	await process_frame

	paused = false
	space.set("menu_open", false)
	var main_menu: Variant = space.get("main_menu")
	if main_menu != null:
		main_menu.visible = false
	space.call("_on_planet_entered", planet_data)
	var mv := await _wait_for_planet_main(space, 90)
	if mv == null:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: MV runtime did not boot")
		return false

	if MvPackLoader.current_pack == null or MvPackLoader.current_pack.pack_id != pack_id:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: MV loaded wrong pack")
		return false
	if str(pi.get("pending_planet_key")) != expected_snapshot_key:
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: pending planet key mismatch")
		return false

	var room_addr := str(mv.call("get_current_room_addr")).strip_edges()
	if room_addr.is_empty():
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: MV current room is empty")
		return false
	mv.call("load_from_snapshot", room_addr, Vector2(144, 96), 7)
	pi.call("set_planet_flag", "smoke_planet_flag", "visited")
	pi.call("set_global_flag", "smoke_global_flag", "persisted")
	trigger_engine.call("set_global_tag", "smoke_tag", "yes")
	inv.call("set_var", "smoke_var", 42)
	room_state.call("set_room_var", room_addr, "smoke_room_var", "ok")
	map_screen.call("mark_visited", room_addr)

	pi.call("begin_launch", mv)
	await process_frame
	if space.get("planet_main_instance") != null or bool(space.get("on_surface")):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: launch did not return to Space")
		return false

	var state: Dictionary = pi.call("snapshot_all")
	var snapshots: Dictionary = state.get("planet_snapshots", {})
	if not snapshots.has(expected_snapshot_key):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: missing planet snapshot")
		return false
	var snap: Dictionary = snapshots[expected_snapshot_key]
	if not _snapshot_matches(snap, room_addr):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		return false

	if not bool(game_manager.call("save_game", slot)):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: GameManager.save_game failed")
		return false
	pi.call("reset_runtime_state", true, true)
	MvPackLoader.clear_runtime_state()
	if not bool(game_manager.call("load_game", slot)):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: GameManager.load_game failed")
		return false
	var loaded_state: Dictionary = pi.call("snapshot_all")
	var loaded_snapshots: Dictionary = loaded_state.get("planet_snapshots", {})
	if not loaded_snapshots.has(expected_snapshot_key):
		_restore_save(save_path, had_save, save_backup)
		space.queue_free()
		push_error("runtime_smoke_cli: save/load did not restore planet snapshot")
		return false

	_restore_save(save_path, had_save, save_backup)
	space.queue_free()
	print("[runtime_smoke_cli] PASS authored-route pack='%s' snapshot='%s'" % [pack_id, expected_snapshot_key])
	return true


func _validate_pack(pack_id: String) -> bool:
	var issues := ContentValidator.validate(pack_id)
	var errors := 0
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			errors += 1
			push_error("[runtime_smoke_cli] %s - %s" % [issue_v.source, issue_v.message])
	if errors > 0:
		push_error("runtime_smoke_cli: validation failed with %d error(s)" % errors)
	return errors == 0


func _starter_planet_data(pack_id: String) -> Dictionary:
	var systems := SystemIO.load_existing(pack_id)
	var system: Dictionary = systems.get(SystemIO.STARTER_SYSTEM_ID, {})
	if system.is_empty():
		push_error("runtime_smoke_cli: starter system missing")
		return {}
	var pois_v: Variant = system.get("pois", [])
	if typeof(pois_v) != TYPE_ARRAY:
		push_error("runtime_smoke_cli: starter system has no POI array")
		return {}
	for poi_v in pois_v:
		if typeof(poi_v) != TYPE_DICTIONARY:
			continue
		var poi: Dictionary = poi_v
		if str(poi.get("type", "")).strip_edges() != "planet":
			continue
		var planet_v: Variant = poi.get("planet_data", {})
		if typeof(planet_v) != TYPE_DICTIONARY:
			continue
		var planet: Dictionary = (planet_v as Dictionary).duplicate(true)
		planet["pack_id"] = pack_id
		planet["source_system"] = SystemIO.STARTER_SYSTEM_ID
		planet["poi_name"] = str(poi.get("name", SystemIO.STARTER_PLANET_NAME))
		planet["planet_key"] = "start/starter_planet"
		return planet
	push_error("runtime_smoke_cli: starter planet missing")
	return {}


func _wait_for_planet_main(space: Node, max_frames: int) -> Node:
	for _i in range(max_frames):
		var mv: Variant = space.get("planet_main_instance")
		if mv != null:
			return mv
		await process_frame
	return null


func _snapshot_matches(snap: Dictionary, room_addr: String) -> bool:
	if str(snap.get("room", "")) != room_addr:
		push_error("runtime_smoke_cli: snapshot room mismatch")
		return false
	var player: Dictionary = snap.get("player", {})
	if int(player.get("hp", -1)) != 7:
		push_error("runtime_smoke_cli: snapshot player hp mismatch")
		return false
	var inventory: Dictionary = snap.get("inventory", {})
	var vars: Dictionary = inventory.get("game_vars", {})
	if int(vars.get("smoke_var", -1)) != 42:
		push_error("runtime_smoke_cli: snapshot inventory var mismatch")
		return false
	var room_state: Dictionary = snap.get("room_state", {})
	var rooms: Dictionary = room_state.get("rooms", {})
	var room_data: Dictionary = rooms.get(room_addr, {})
	var room_vars: Dictionary = room_data.get("vars", {})
	if str(room_vars.get("smoke_room_var", "")) != "ok":
		push_error("runtime_smoke_cli: snapshot room state mismatch")
		return false
	var trigger_state: Dictionary = snap.get("trigger_state", {})
	var tags: Dictionary = trigger_state.get("global_tags", snap.get("global_tags", {}))
	if str(tags.get("smoke_tag", "")) != "yes":
		push_error("runtime_smoke_cli: snapshot trigger tag mismatch")
		return false
	var planet_flags: Dictionary = snap.get("planet_flags", {})
	if str(planet_flags.get("smoke_planet_flag", "")) != "visited":
		push_error("runtime_smoke_cli: snapshot planet flag mismatch")
		return false
	var global_flags: Dictionary = snap.get("global_flags", {})
	if str(global_flags.get("smoke_global_flag", "")) != "persisted":
		push_error("runtime_smoke_cli: snapshot global flag mismatch")
		return false
	var map_visited: Dictionary = snap.get("map_visited", {})
	if not map_visited.has(room_addr):
		push_error("runtime_smoke_cli: snapshot map visited mismatch")
		return false
	return true


func _read_text_if_exists(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _restore_save(path: String, had_save: bool, save_backup: String) -> void:
	if had_save:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(save_backup)
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

extends SceneTree

const DEFAULT_PACK_ID := "phase2_runtime_smoke"
const ContentValidator := preload("res://Space/scripts/editor/content_validator.gd")


class SmokeMain:
	extends Node

	var room_addr: String = "realm_main/region_default/start"
	var player_snapshot: Dictionary = {"x": 42.0, "y": 84.0, "hp": 7}
	var restored_room: String = ""
	var restored_pos: Vector2 = Vector2(-1, -1)
	var restored_hp: int = -1

	func get_current_room_addr() -> String:
		return room_addr

	func get_player_snapshot() -> Dictionary:
		return player_snapshot.duplicate(true)

	func load_from_snapshot(p_room_addr: String, pos: Vector2, hp: int) -> void:
		restored_room = p_room_addr
		restored_pos = pos
		restored_hp = hp


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pack_id := DEFAULT_PACK_ID
	if not args.is_empty():
		pack_id = str(args[0]).strip_edges()
	if pack_id.is_empty():
		push_error("phase2_runtime_smoke: empty pack id")
		quit(2)
		return

	_run_and_quit.call_deferred(pack_id)


func _run_and_quit(pack_id: String) -> void:
	var ok := _run(pack_id)
	quit(0 if ok else 1)


func _run(pack_id: String) -> bool:
	var pi := root.get_node_or_null("PlanetaryInterface")
	var inv := root.get_node_or_null("PlayerInventory")
	var room_state := root.get_node_or_null("MvRoomState")
	var map_screen := root.get_node_or_null("MvMapScreen")
	var trigger_engine := root.get_node_or_null("MvTriggerEngine")
	if pi == null or inv == null or room_state == null or map_screen == null or trigger_engine == null:
		push_error("phase2_runtime_smoke: required autoload missing")
		return false

	if not MvPackLoader.create_empty_pack(pack_id, "Phase 2 Runtime Smoke"):
		push_error("phase2_runtime_smoke: bootstrap failed")
		return false

	var issues := ContentValidator.validate(pack_id)
	var errors := 0
	for issue_v in issues:
		if issue_v != null and issue_v.severity == "error":
			errors += 1
			push_error("[phase2_runtime_smoke] %s - %s" % [issue_v.source, issue_v.message])
	if errors > 0:
		push_error("phase2_runtime_smoke: validation failed with %d error(s)" % errors)
		return false

	MvPackLoader.clear_runtime_state()
	pi.call("reset_runtime_state", true, true)
	var pack := MvPackLoader.load_pack(pack_id)
	if pack == null:
		push_error("phase2_runtime_smoke: pack load failed")
		return false

	var room_addr := "realm_main/region_default/start"
	var planet_key := "smoke/start_planet"
	pi.call("begin_landing", pack_id, room_addr, Vector2(42, 84), "realm_main", planet_key)
	var expected_snapshot_key := "%s::%s" % [pack_id, planet_key]
	if str(pi.get("pending_planet_key")) != expected_snapshot_key:
		push_error("phase2_runtime_smoke: pending planet key mismatch")
		return false

	var main := SmokeMain.new()
	main.room_addr = room_addr
	main.player_snapshot = {"x": 42.0, "y": 84.0, "hp": 7}

	inv.call("clear")
	room_state.call("clear")
	map_screen.call("clear")
	trigger_engine.call("clear")
	inv.call("add_item", "smoke_item", 2)
	inv.call("set_var", "smoke_var", "set")
	room_state.call("set_room_var", room_addr, "door_opened", true)
	map_screen.call("mark_visited", room_addr)
	trigger_engine.call("set_global_tag", "smoke_tag", "seen")
	pi.call("set_planet_flag", "smoke_planet_flag", true)

	if not bool(pi.call("snapshot_current_mv", main)):
		push_error("phase2_runtime_smoke: snapshot_current_mv failed")
		return false
	var all_state: Dictionary = pi.call("snapshot_all")
	var snapshots_v: Variant = all_state.get("planet_snapshots", {})
	if typeof(snapshots_v) != TYPE_DICTIONARY or not (snapshots_v as Dictionary).has(expected_snapshot_key):
		push_error("phase2_runtime_smoke: snapshot was not stored under expected key")
		return false

	inv.call("clear")
	room_state.call("clear")
	map_screen.call("clear")
	trigger_engine.call("clear")
	pi.call("clear_planet_flags")

	pi.call("begin_landing", pack_id, room_addr, Vector2.ZERO, "realm_main", planet_key)
	var restored := bool(pi.call("restore_pending_if_any", main))
	if not restored:
		push_error("phase2_runtime_smoke: restore_pending_if_any returned false")
		return false
	if main.restored_room != room_addr or main.restored_pos != Vector2(42, 84) or main.restored_hp != 7:
		push_error("phase2_runtime_smoke: player snapshot restore mismatch")
		return false
	if not bool(inv.call("has_item", "smoke_item", 2)):
		push_error("phase2_runtime_smoke: inventory did not restore")
		return false
	if str(inv.call("get_var", "smoke_var", "")) != "set":
		push_error("phase2_runtime_smoke: inventory vars did not restore")
		return false
	if room_state.call("get_room_var", room_addr, "door_opened", false) != true:
		push_error("phase2_runtime_smoke: room state did not restore")
		return false
	var visited: Dictionary = map_screen.call("visited_snapshot")
	if not visited.has(room_addr):
		push_error("phase2_runtime_smoke: map visited state did not restore")
		return false
	if str(trigger_engine.call("get_global_tag", "smoke_tag", "")) != "seen":
		push_error("phase2_runtime_smoke: trigger state did not restore")
		return false
	if pi.call("get_planet_flag", "smoke_planet_flag", false) != true:
		push_error("phase2_runtime_smoke: planet flags did not restore")
		main.free()
		return false

	main.free()
	print("[phase2_runtime_smoke] PASS pack='%s' snapshot='%s'" % [pack_id, expected_snapshot_key])
	return true

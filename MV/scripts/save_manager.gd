extends Node

# Save/load coordinator. Autoloaded as `MvSaveManager`.
# Collects snapshots from PlayerInventory, MvRoomState, and player
# position/room, writes to user://Saves/<pack_id>/slot_<N>.json.

const MAX_SLOTS: int = 3

signal game_saved(slot: int)
signal game_loaded(slot: int)


func save_game(slot: int) -> bool:
	var pack_id := _current_pack_id()
	var player := _find_player()

	var data: Dictionary = {
		"pack_id": pack_id,
		"slot": slot,
		"timestamp": Time.get_unix_time_from_system(),
		"inventory": PlayerInventory.snapshot(),
		"global_tags": MvTriggerEngine.snapshot_global_tags(),
		"trigger_state": MvTriggerEngine.snapshot_runtime_state() if MvTriggerEngine.has_method("snapshot_runtime_state") else {},
		"room_state": MvRoomState.snapshot(),
		"map_visited": MvMapScreen.visited_snapshot(),
		"player": {
			"room": _current_room_addr(),
			"position_x": player.position.x if player != null else 0.0,
			"position_y": player.position.y if player != null else 0.0,
			"hp": player.hp if player != null else 99,
			"max_hp": player.max_hp if player != null else 99,
			"energy": player.energy if player != null else 100,
			"max_energy": player.max_energy if player != null else 100,
		},
	}

	var path := _save_path(pack_id, slot)
	var dir := path.substr(0, path.rfind("/"))
	DirAccess.make_dir_recursive_absolute(dir)

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("MvSaveManager: cannot open %s" % path)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("[MvSaveManager] saved slot %d" % slot)
	game_saved.emit(slot)
	MvTriggerEngine.fire_event("save_game", { "slot": slot, "pack_id": pack_id })
	return true


func load_game(slot: int) -> bool:
	var pack_id := _current_pack_id()
	var path := _save_path(pack_id, slot)
	if not FileAccess.file_exists(path):
		push_warning("MvSaveManager: no save at %s" % path)
		return false

	var data := MvPackLoader.read_json_dict(path)
	if data.is_empty():
		return false
	PlayerInventory.restore(data.get("inventory", {}))
	MvTriggerEngine.restore_global_tags(data.get("global_tags", {}))
	if MvTriggerEngine.has_method("restore_runtime_state"):
		MvTriggerEngine.restore_runtime_state(data.get("trigger_state", {}))
	MvRoomState.restore(data.get("room_state", {}))
	MvMapScreen.restore_visited(data.get("map_visited", {}))

	var player_data: Dictionary = data.get("player", {})
	var target_room: String = str(player_data.get("room", ""))
	var target_pos := Vector2(
		float(player_data.get("position_x", 0)),
		float(player_data.get("position_y", 0)))

	var room_mgr: Node = MvGame.room_manager
	if room_mgr != null and not target_room.is_empty() and room_mgr.has_method("load_room"):
		room_mgr.call("load_room", target_room)

	var player := _find_player()
	if player != null:
		player.position = target_pos
		player.hp = int(player_data.get("hp", player.max_hp))
		player.max_hp = int(player_data.get("max_hp", 99))
		player.max_energy = int(player_data.get("max_energy", player.max_energy))
		player.energy = int(player_data.get("energy", player.max_energy))

	print("[MvSaveManager] loaded slot %d" % slot)
	game_loaded.emit(slot)
	MvTriggerEngine.fire_event("load_game", { "slot": slot, "pack_id": pack_id })
	return true


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(_save_path(_current_pack_id(), slot))


func list_saves() -> Array:
	var out: Array = []
	var pack_id := _current_pack_id()
	for i in MAX_SLOTS:
		var path := _save_path(pack_id, i)
		if FileAccess.file_exists(path):
			var raw := MvPackLoader.read_json_dict(path)
			if not raw.is_empty():
				out.append({
					"slot": i,
					"timestamp": raw.get("timestamp", 0),
					"room": raw.get("player", {}).get("room", ""),
				})
				continue
		out.append({ "slot": i, "empty": true })
	return out


func delete_save(slot: int) -> void:
	var path := _save_path(_current_pack_id(), slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _save_path(pack_id: String, slot: int) -> String:
	return "user://Saves/%s/slot_%d.json" % [pack_id, slot]


func _current_pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return MvPackLoader.current_pack.pack_id
	return "demo"


func _current_room_addr() -> String:
	var room_mgr: Node = MvGame.room_manager
	if room_mgr != null and room_mgr.has_method("current_room"):
		var info: Dictionary = room_mgr.current_room()
		return str(info.get("addr", ""))
	return ""


func _find_player() -> Node:
	var players := get_tree().get_nodes_in_group("mv_player")
	if players.is_empty():
		return null
	return players[0]

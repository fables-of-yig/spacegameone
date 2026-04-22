extends Node

# Per-room entity state persistence. Autoloaded as `MvRoomState`.
# Tracks which pickups have been collected, which enemies are dead, and
# which doors are open so returning to a room restores the correct state.

var _state: Dictionary = {}


# ── Pickups ─────────────────────────────────────────────────────────────

func mark_collected(room_id: String, entity_id: String) -> void:
	_ensure(room_id)["collected"][entity_id] = true


func is_collected(room_id: String, entity_id: String) -> bool:
	return _ensure(room_id)["collected"].has(entity_id)


# ── Enemies ─────────────────────────────────────────────────────────────

func mark_dead(room_id: String, entity_id: String) -> void:
	_ensure(room_id)["dead"][entity_id] = true


func is_dead(room_id: String, entity_id: String) -> bool:
	return _ensure(room_id)["dead"].has(entity_id)


# ── Doors ───────────────────────────────────────────────────────────────

func set_door_state(room_id: String, door_id: String, opened: bool) -> void:
	_ensure(room_id)["doors"][door_id] = opened


func is_door_open(room_id: String, door_id: String) -> bool:
	return _ensure(room_id)["doors"].get(door_id, false)


# ── Generic key-value per room ──────────────────────────────────────────

func set_room_var(room_id: String, key: String, value: Variant) -> void:
	_ensure(room_id)["vars"][key] = value


func get_room_var(room_id: String, key: String, default: Variant = null) -> Variant:
	return _ensure(room_id)["vars"].get(key, default)


# ── Snapshot / Restore ──────────────────────────────────────────────────

func snapshot() -> Dictionary:
	return _state.duplicate(true)


func restore(data: Dictionary) -> void:
	_state = data.duplicate(true)


func clear() -> void:
	_state.clear()


# ── Internal ────────────────────────────────────────────────────────────

func _ensure(room_id: String) -> Dictionary:
	if not _state.has(room_id):
		_state[room_id] = {
			"collected": {},
			"dead": {},
			"doors": {},
			"vars": {},
		}
	return _state[room_id]

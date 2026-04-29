extends Node

# Per-room entity state persistence. Autoloaded as `MvRoomState`.
# Tracks which pickups have been collected, which enemies are dead, and
# which doors are open so returning to a room restores the correct state.

var _state: Dictionary = {}
var _door_state_overrides: Dictionary = {}


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


func set_door_enabled(door_id: String, enabled: bool) -> void:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty():
		return
	_ensure_door_override(trimmed)["enabled"] = enabled


func get_door_enabled(door_id: String, default_value: bool = true) -> bool:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty():
		return default_value
	if not _door_state_overrides.has(trimmed):
		return default_value
	return bool((_door_state_overrides[trimmed] as Dictionary).get("enabled", default_value))


func has_door_enabled_override(door_id: String) -> bool:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty() or not _door_state_overrides.has(trimmed):
		return false
	return (_door_state_overrides[trimmed] as Dictionary).has("enabled")


func set_door_locked(door_id: String, locked: bool) -> void:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty():
		return
	_ensure_door_override(trimmed)["locked"] = locked


func get_door_locked(door_id: String, default_value: bool = false) -> bool:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty():
		return default_value
	if not _door_state_overrides.has(trimmed):
		return default_value
	return bool((_door_state_overrides[trimmed] as Dictionary).get("locked", default_value))


func has_door_locked_override(door_id: String) -> bool:
	var trimmed := door_id.strip_edges()
	if trimmed.is_empty() or not _door_state_overrides.has(trimmed):
		return false
	return (_door_state_overrides[trimmed] as Dictionary).has("locked")


# ── Generic key-value per room ──────────────────────────────────────────

func set_room_var(room_id: String, key: String, value: Variant) -> void:
	_ensure(room_id)["vars"][key] = value


func get_room_var(room_id: String, key: String, default: Variant = null) -> Variant:
	return _ensure(room_id)["vars"].get(key, default)


# ── Snapshot / Restore ──────────────────────────────────────────────────

func snapshot() -> Dictionary:
	return {
		"rooms": _state.duplicate(true),
		"door_overrides": _door_state_overrides.duplicate(true),
	}


func restore(data: Dictionary) -> void:
	_state.clear()
	_door_state_overrides.clear()
	if data == null:
		return
	if data.has("rooms") or data.has("door_overrides"):
		var rooms_v: Variant = data.get("rooms", {})
		if typeof(rooms_v) == TYPE_DICTIONARY:
			_state = (rooms_v as Dictionary).duplicate(true)
		var overrides_v: Variant = data.get("door_overrides", {})
		if typeof(overrides_v) == TYPE_DICTIONARY:
			_door_state_overrides = (overrides_v as Dictionary).duplicate(true)
		return
	_state = data.duplicate(true)


func clear() -> void:
	_state.clear()
	_door_state_overrides.clear()


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


func _ensure_door_override(door_id: String) -> Dictionary:
	if not _door_state_overrides.has(door_id):
		_door_state_overrides[door_id] = {}
	return _door_state_overrides[door_id]

extends Node

# Authoritative state holder for the cross-project planet handoff.
# Read/written by both Space (SSB) and MV layers. begin_landing stages a
# pack id + POI + region for MvMain._enter_tree to read; begin_launch
# snapshots the current planet and emits launch_requested so SSB can tear
# the viewport down.

signal launch_requested(pack_id: String)

var hosted: bool = false
var pending_pack_id: String = ""
var pending_poi_id: String = ""
var pending_region_id: String = ""
var pending_planet_key: String = ""
var pending_spawn_room: String = ""
var pending_spawn_pos: Vector2 = Vector2.ZERO
# When true, MvMain opens the editor overlay on first frame. SSB sets this
# from the EDITOR main-menu chooser when "Sidescroller" is selected. Cleared
# by Main on read. (Editor overlay itself is deferred; this flag is live.)
var pending_edit_mode: bool = false

# Editor ↔ runtime round-trip state. environment_editor.request_playtest
# stashes the active pack/region/room here before scene-changing to MV
# so that the Ctrl+9 return path in MvMain can scene-change back
# to Space and re-open the editor at exactly the same spot. Consumed
# (and cleared) by Space main._ready when the flag is set.
var pending_return_to_editor: bool = false
var pending_editor_pack_id: String = ""
var pending_editor_region_id: String = ""
var pending_editor_room_addr: String = ""

# Internal snapshot store: planet_key → snapshot dict ({pack, room, player, vars, inventory}).
# begin_launch writes here; restore_pending_if_any reads and clears on re-landing.
var _pending_snapshot: Dictionary = {}
var _planet_snapshots: Dictionary = {}
var _player_progression_snapshot: Dictionary = {}

# ─── Unified flag bridge ──────────────────────────────────────────────────
#
# Two namespaces share the same accessor shape:
#   _planet_flags   — wiped on planet entry, snapshotted in begin_launch,
#                     restored on re-landing. Used by MVMania trigger
#                     conditions (when the trigger engine rebuild lands).
#                     Scoped per visit to a planet.
#   _global_flags   — never wiped automatically. Lives across every planet
#                     landing, save/load, and SSB ↔ MV transition. Use for
#                     credits, faction reputation, story flags, etc.
#
# Any write fires `flag_changed(scope, name, old_value, new_value)` for
# future trigger handlers to subscribe to.

signal flag_changed(scope: String, name: String, old_value: Variant, new_value: Variant)

var _planet_flags: Dictionary = {}
var _global_flags: Dictionary = {}

# Queued ship spawns for systems the player isn't currently in. MV triggers
# push entries via queue_ship_spawn(); Space drains them on system_enter via
# consume_ship_spawn_queue() and spawns each ship through the existing
# spawn manager. Schema: { system_id: [class_id_string, ...] }.
var _pending_ship_spawns: Dictionary = {}

func has_planet_flag(flag_name: String) -> bool:
    return _planet_flags.has(flag_name)

func get_planet_flag(flag_name: String, default_value = null):
    return _planet_flags.get(flag_name, default_value)

func set_planet_flag(flag_name: String, value):
    var old = _planet_flags.get(flag_name, null)
    _planet_flags[flag_name] = value
    flag_changed.emit("planet", flag_name, old, value)

func clear_planet_flags():
    _planet_flags.clear()

func snapshot_planet_flags() -> Dictionary:
    return _planet_flags.duplicate(true)

func restore_planet_flags(snap):
    _planet_flags.clear()
    if snap != null and typeof(snap) == TYPE_DICTIONARY:
        for k in snap.keys():
            _planet_flags[k] = snap[k]

func has_global_flag(flag_name: String) -> bool:
    return _global_flags.has(flag_name)

func get_global_flag(flag_name: String, default_value = null):
    return _global_flags.get(flag_name, default_value)

func set_global_flag(flag_name: String, value):
    var old = _global_flags.get(flag_name, null)
    _global_flags[flag_name] = value
    flag_changed.emit("global", flag_name, old, value)

func clear_global_flags():
    _global_flags.clear()


# Single-flag clear (the existing clear_global_flags wipes the whole bag).
# Emits flag_changed("global", name, old, null) so listeners can react.
func clear_global_flag(flag_name: String) -> void:
    if not _global_flags.has(flag_name):
        return
    var old = _global_flags.get(flag_name, null)
    _global_flags.erase(flag_name)
    flag_changed.emit("global", flag_name, old, null)


# Append a ship class to the pending-spawn list for `system_id`. The next
# time the player jumps into that system, Space drains this queue and
# spawns each entry. Queueing the same system again stacks — no dedup.
func queue_ship_spawn(system_id: String, class_id: String) -> void:
    var sid := system_id.strip_edges()
    var cid := class_id.strip_edges()
    if sid.is_empty() or cid.is_empty():
        return
    var bucket_v: Variant = _pending_ship_spawns.get(sid, [])
    var bucket: Array = bucket_v if typeof(bucket_v) == TYPE_ARRAY else []
    bucket.append(cid)
    _pending_ship_spawns[sid] = bucket


# Returns and removes the queued ship class ids for a system. Space calls
# this on space_system_enter to spawn the ships at the system's center.
func consume_ship_spawn_queue(system_id: String) -> Array:
    var sid := system_id.strip_edges()
    var bucket_v: Variant = _pending_ship_spawns.get(sid, [])
    if typeof(bucket_v) != TYPE_ARRAY:
        return []
    var out: Array = (bucket_v as Array).duplicate()
    _pending_ship_spawns.erase(sid)
    return out

# Convenience helpers for SSB-side iteration (the in-editor flag inspector
# uses these to render the current state). Returns sorted key arrays so the
# UI is stable across draws.
func list_planet_flag_names() -> Array:
    var keys = _planet_flags.keys()
    keys.sort()
    return keys

func list_global_flag_names() -> Array:
    var keys = _global_flags.keys()
    keys.sort()
    return keys

func has_pending_snapshot() -> bool:
    return not _pending_snapshot.is_empty()

# Called by SSB when the player picks a region from a POI's location list.
# Stages the pack id, POI id, region id, and spawn coords for MvMain._enter_tree
# to read, and pulls any prior snapshot for that planet+region so MvMain._ready
# can rehydrate state.
func begin_landing(pack_id: String, poi_id: String, region_id: String,
        spawn_room: String, spawn_pos: Vector2) -> void:
    pack_id = pack_id.strip_edges()
    if pack_id.is_empty():
        push_error("PlanetaryInterface.begin_landing: empty pack_id")
        return
    var resolved_planet_key := _resolve_planet_key(pack_id, poi_id, region_id)
    hosted = true
    pending_pack_id = pack_id
    pending_poi_id = poi_id.strip_edges()
    pending_region_id = region_id.strip_edges()
    pending_planet_key = resolved_planet_key
    pending_spawn_room = spawn_room
    pending_spawn_pos = spawn_pos
    if _planet_snapshots.has(resolved_planet_key):
        _pending_snapshot = _planet_snapshots[resolved_planet_key].duplicate(true)
    else:
        _pending_snapshot = {}
    if _pending_snapshot.has("planet_flags"):
        restore_planet_flags(_pending_snapshot.get("planet_flags", {}))
    else:
        clear_planet_flags()
    print("planetary_interface: begin_landing pack='%s' poi='%s' region='%s' spawn_room='%s' has_snapshot=%s" %
        [pack_id, pending_poi_id, pending_region_id, spawn_room, not _pending_snapshot.is_empty()])


# Called by restore_pending_if_any to fetch (and clear) the pending snapshot.
# Returns an empty dict if there's nothing to restore.
func _consume_pending_snapshot() -> Dictionary:
    var snap = _pending_snapshot
    _pending_snapshot = {}
    return snap

# Called by begin_launch to store the just-snapshotted planet state under
# its planet key. Next visit to that planet+region rehydrates from here.
func _save_snapshot(snapshot_key: String, snap: Dictionary):
    _planet_snapshots[snapshot_key] = snap.duplicate(true)
    print("planetary_interface: snapshotted '%s' (%d keys)" % [snapshot_key, snap.size()])


func has_player_progression_snapshot() -> bool:
    return not _player_progression_snapshot.is_empty()


func _capture_player_progression(snap: Dictionary) -> void:
    var out: Dictionary = {}
    var inventory_v: Variant = snap.get("inventory", {})
    if typeof(inventory_v) == TYPE_DICTIONARY and not (inventory_v as Dictionary).is_empty():
        out["inventory"] = (inventory_v as Dictionary).duplicate(true)
    var player_v: Variant = snap.get("player", {})
    if typeof(player_v) == TYPE_DICTIONARY:
        var player_data: Dictionary = player_v
        var player_out: Dictionary = {}
        if player_data.has("hp"):
            player_out["hp"] = int(player_data.get("hp", 0))
        if player_data.has("max_hp"):
            player_out["max_hp"] = int(player_data.get("max_hp", 0))
        if not player_out.is_empty():
            out["player"] = player_out
    if not out.is_empty():
        _player_progression_snapshot = out


func _restore_player_progression(main: Node, fallback_snap: Dictionary = {}) -> void:
    var progression: Dictionary = _player_progression_snapshot
    if progression.is_empty() and not fallback_snap.is_empty():
        var fallback: Dictionary = {}
        var fallback_inv_v: Variant = fallback_snap.get("inventory", {})
        if typeof(fallback_inv_v) == TYPE_DICTIONARY and not (fallback_inv_v as Dictionary).is_empty():
            fallback["inventory"] = (fallback_inv_v as Dictionary).duplicate(true)
        var fallback_player_v: Variant = fallback_snap.get("player", {})
        if typeof(fallback_player_v) == TYPE_DICTIONARY:
            fallback["player"] = (fallback_player_v as Dictionary).duplicate(true)
        progression = fallback
    if progression.is_empty():
        return
    var inv_v: Variant = progression.get("inventory", {})
    if typeof(inv_v) == TYPE_DICTIONARY and PlayerInventory != null and PlayerInventory.has_method("restore"):
        PlayerInventory.restore(inv_v)
    var player_v: Variant = progression.get("player", {})
    if typeof(player_v) != TYPE_DICTIONARY or main == null:
        return
    var player: Node = main.get("_player") as Node
    if player == null:
        return
    var player_data: Dictionary = player_v
    if player_data.has("max_hp"):
        player.set("max_hp", int(player_data.get("max_hp", int(player.get("max_hp")))))
    if player_data.has("hp"):
        player.set("hp", mini(int(player_data.get("hp", int(player.get("hp")))), int(player.get("max_hp"))))

# Called by MvMain when an exit_to_space door tag is traversed (and by
# future return_to_space triggers). Clears live state and emits the launch
# signal that SSB main.gd listens for.
func _emit_launch_after_snapshot():
    var launching: String = pending_pack_id
    hosted = false
    pending_pack_id = ""
    pending_poi_id = ""
    pending_region_id = ""
    pending_planet_key = ""
    pending_spawn_room = ""
    pending_spawn_pos = Vector2.ZERO
    _pending_snapshot = {}
    launch_requested.emit(launching)


# Called by the exit_to_space door handler in MvMain._load_destination_room
# and by the future return_to_space trigger action. Snapshots the current
# planet's full state into the per-planet store, then triggers the launch
# signal. vars/inventory fields are empty stubs until those systems come
# back in the post-port rebuild.
func begin_launch(main: Node) -> void:
    var pack_id := pending_pack_id
    if pack_id.is_empty():
        push_error("PlanetaryInterface.begin_launch: no pending_pack_id")
        return
    var snapshot_key := pending_planet_key.strip_edges()
    if snapshot_key.is_empty():
        snapshot_key = _resolve_planet_key(pack_id, pending_poi_id, pending_region_id)

    var snap: Dictionary = {
        "pack":      pack_id,
        "poi":       pending_poi_id,
        "region":    pending_region_id,
        "room":      "",
        "player":    {},
        "vars":      {},       # deferred — VarStore not ported
        "inventory": {},       # deferred — PlayerInventory snapshot not ported
        "snapshot_key": snapshot_key,
        "planet_key": pending_planet_key,
        "room_state": {},
        "map_visited": {},
        "global_tags": {},
        "trigger_state": {},
        "planet_flags": snapshot_planet_flags(),
        "global_flags": _global_flags.duplicate(true),
    }
    if main != null:
        if main.has_method("get_current_room_addr"):
            snap["room"] = str(main.call("get_current_room_addr"))
        if main.has_method("get_player_snapshot"):
            var ps = main.call("get_player_snapshot")
            if typeof(ps) == TYPE_DICTIONARY:
                snap["player"] = ps

        # Prefer the live pack id from MvPackLoader if available, so a
        # test/dev session that loaded a pack directly (without going
        # through begin_landing) still snapshots under the right key.
        if MvPackLoader.current_pack != null:
            snap["pack"] = MvPackLoader.current_pack.pack_id
        if PlayerInventory != null and PlayerInventory.has_method("snapshot"):
            snap["inventory"] = PlayerInventory.snapshot()
        if MvRoomState != null and MvRoomState.has_method("snapshot"):
            snap["room_state"] = MvRoomState.snapshot()
        if MvMapScreen != null and MvMapScreen.has_method("visited_snapshot"):
            snap["map_visited"] = MvMapScreen.visited_snapshot()
        if MvTriggerEngine != null and MvTriggerEngine.has_method("snapshot_global_tags"):
            snap["global_tags"] = MvTriggerEngine.snapshot_global_tags()
        if MvTriggerEngine != null and MvTriggerEngine.has_method("snapshot_runtime_state"):
            snap["trigger_state"] = MvTriggerEngine.snapshot_runtime_state()

    _save_snapshot(snapshot_key, snap)
    _capture_player_progression(snap)
    _emit_launch_after_snapshot()


func snapshot_current_mv(main: Node) -> bool:
    var pack_id := pending_pack_id.strip_edges()
    if pack_id.is_empty():
        return false
    var snapshot_key := pending_planet_key.strip_edges()
    if snapshot_key.is_empty():
        snapshot_key = _resolve_planet_key(pack_id, pending_poi_id, pending_region_id)
    var snap: Dictionary = {
        "pack": pack_id,
        "poi": pending_poi_id,
        "region": pending_region_id,
        "room": "",
        "player": {},
        "inventory": {},
        "snapshot_key": snapshot_key,
        "planet_key": pending_planet_key,
        "room_state": {},
        "map_visited": {},
        "global_tags": {},
        "trigger_state": {},
        "planet_flags": snapshot_planet_flags(),
        "global_flags": _global_flags.duplicate(true),
    }
    if main != null:
        if main.has_method("get_current_room_addr"):
            snap["room"] = str(main.call("get_current_room_addr"))
        if main.has_method("get_player_snapshot"):
            var ps = main.call("get_player_snapshot")
            if typeof(ps) == TYPE_DICTIONARY:
                snap["player"] = ps
    if MvPackLoader.current_pack != null:
        snap["pack"] = MvPackLoader.current_pack.pack_id
    if PlayerInventory != null and PlayerInventory.has_method("snapshot"):
        snap["inventory"] = PlayerInventory.snapshot()
    if MvRoomState != null and MvRoomState.has_method("snapshot"):
        snap["room_state"] = MvRoomState.snapshot()
    if MvMapScreen != null and MvMapScreen.has_method("visited_snapshot"):
        snap["map_visited"] = MvMapScreen.visited_snapshot()
    if MvTriggerEngine != null and MvTriggerEngine.has_method("snapshot_global_tags"):
        snap["global_tags"] = MvTriggerEngine.snapshot_global_tags()
    if MvTriggerEngine != null and MvTriggerEngine.has_method("snapshot_runtime_state"):
        snap["trigger_state"] = MvTriggerEngine.snapshot_runtime_state()
    _save_snapshot(snapshot_key, snap)
    _capture_player_progression(snap)
    return true


# Called by MvMain._ready after the initial pack load + room spawn. Pulls
# the pending snapshot from the wrapper's store and applies the minimal
# fields we still carry (room address + player position + hp). No-op on
# fresh boots and on first visits to a planet.
func restore_pending_if_any(main: Node) -> bool:
    if main == null:
        return false
    var snap := _consume_pending_snapshot()
    var has_planet_snapshot := not snap.is_empty()
    if not has_planet_snapshot:
        _restore_player_progression(main)
        return false
    _restore_player_progression(main, snap)
    if snap.has("room_state") and MvRoomState != null and MvRoomState.has_method("restore"):
        var room_state_v: Variant = snap.get("room_state", {})
        if typeof(room_state_v) == TYPE_DICTIONARY:
            MvRoomState.restore(room_state_v)
    if snap.has("map_visited") and MvMapScreen != null and MvMapScreen.has_method("restore_visited"):
        var map_v: Variant = snap.get("map_visited", {})
        if typeof(map_v) == TYPE_DICTIONARY:
            MvMapScreen.restore_visited(map_v)
    if snap.has("global_tags") and MvTriggerEngine != null and MvTriggerEngine.has_method("restore_global_tags"):
        var tags_v: Variant = snap.get("global_tags", {})
        if typeof(tags_v) == TYPE_DICTIONARY:
            MvTriggerEngine.restore_global_tags(tags_v)
    if snap.has("trigger_state") and MvTriggerEngine != null and MvTriggerEngine.has_method("restore_runtime_state"):
        var trigger_state_v: Variant = snap.get("trigger_state", {})
        if typeof(trigger_state_v) == TYPE_DICTIONARY:
            MvTriggerEngine.restore_runtime_state(trigger_state_v)
    if snap.has("planet_flags"):
        restore_planet_flags(snap.get("planet_flags", {}))

    var room_addr := str(snap.get("room", ""))
    var pos := Vector2.ZERO
    var hp := -1
    var max_hp := -1
    if snap.has("player") and typeof(snap["player"]) == TYPE_DICTIONARY:
        var pd: Dictionary = snap["player"]
        if pd.has("x") and pd.has("y"):
            pos = Vector2(float(pd["x"]), float(pd["y"]))
        if pd.has("hp"):
            hp = int(pd["hp"])
        if pd.has("max_hp"):
            max_hp = int(pd["max_hp"])

    if main.has_method("load_from_snapshot"):
        main.call("load_from_snapshot", room_addr, pos, hp, max_hp)
    print("PlanetaryInterface: restored snapshot")
    return true


# Stash the editor's current pack/region/room so MvMain's Ctrl+9
# return handler can scene-change back to Space and Space main can
# re-open the environment editor at the same spot.
func stage_return_to_editor(pack_id: String, region_id: String, room_addr: String) -> void:
    pending_return_to_editor = true
    pending_editor_pack_id = pack_id
    pending_editor_region_id = region_id
    pending_editor_room_addr = room_addr


func reset_runtime_state(clear_editor_return: bool = true, clear_snapshots: bool = true) -> void:
    hosted = false
    pending_pack_id = ""
    pending_poi_id = ""
    pending_region_id = ""
    pending_planet_key = ""
    pending_spawn_room = ""
    pending_spawn_pos = Vector2.ZERO
    pending_edit_mode = false
    _pending_snapshot = {}
    if clear_snapshots:
        _planet_snapshots = {}
        _player_progression_snapshot = {}
    if clear_editor_return:
        pending_return_to_editor = false
        pending_editor_pack_id = ""
        pending_editor_region_id = ""
        pending_editor_room_addr = ""


func snapshot_all() -> Dictionary:
    return {
        "hosted": hosted,
        "pending_pack_id": pending_pack_id,
        "pending_poi_id": pending_poi_id,
        "pending_region_id": pending_region_id,
        "pending_planet_key": pending_planet_key,
        "pending_spawn_room": pending_spawn_room,
        "pending_spawn_pos": [pending_spawn_pos.x, pending_spawn_pos.y],
        "planet_flags": _planet_flags.duplicate(true),
        "global_flags": _global_flags.duplicate(true),
        "planet_snapshots": _planet_snapshots.duplicate(true),
        "player_progression": _player_progression_snapshot.duplicate(true),
    }


func restore_all(data: Dictionary) -> void:
    if data.is_empty():
        return
    hosted = bool(data.get("hosted", false))
    pending_pack_id = str(data.get("pending_pack_id", "")).strip_edges()
    pending_poi_id = str(data.get("pending_poi_id", "")).strip_edges()
    pending_region_id = str(data.get("pending_region_id", "")).strip_edges()
    pending_planet_key = str(data.get("pending_planet_key", "")).strip_edges()
    pending_spawn_room = str(data.get("pending_spawn_room", "")).strip_edges()
    var pos_v: Variant = data.get("pending_spawn_pos", [0.0, 0.0])
    if typeof(pos_v) == TYPE_ARRAY and (pos_v as Array).size() >= 2:
        pending_spawn_pos = Vector2(float((pos_v as Array)[0]), float((pos_v as Array)[1]))
    else:
        pending_spawn_pos = Vector2.ZERO
    restore_planet_flags(data.get("planet_flags", {}))
    _global_flags.clear()
    var global_flags_v: Variant = data.get("global_flags", {})
    if typeof(global_flags_v) == TYPE_DICTIONARY:
        _global_flags = (global_flags_v as Dictionary).duplicate(true)
    var snapshots_v: Variant = data.get("planet_snapshots", {})
    _planet_snapshots = (snapshots_v as Dictionary).duplicate(true) if typeof(snapshots_v) == TYPE_DICTIONARY else {}
    var progression_v: Variant = data.get("player_progression", {})
    _player_progression_snapshot = (progression_v as Dictionary).duplicate(true) if typeof(progression_v) == TYPE_DICTIONARY else {}
    _pending_snapshot = {}


# Returns the stashed {pack_id, region_id, room_addr} and clears the
# staged state. Call once from Space main._ready when the flag is set.
func consume_return_to_editor() -> Dictionary:
    var out := {
        "pack_id": pending_editor_pack_id,
        "region_id": pending_editor_region_id,
        "room_addr": pending_editor_room_addr,
    }
    pending_return_to_editor = false
    pending_editor_pack_id = ""
    pending_editor_region_id = ""
    pending_editor_room_addr = ""
    return out


func _resolve_planet_key(pack_id: String, poi_id: String, region_id: String) -> String:
    var poi := poi_id.strip_edges()
    var region := region_id.strip_edges()
    if poi.is_empty() and region.is_empty():
        return "%s::default" % pack_id.strip_edges()
    if poi.is_empty():
        return "%s::%s" % [pack_id.strip_edges(), region]
    if region.is_empty():
        return "%s::%s" % [pack_id.strip_edges(), poi]
    return "%s::%s::%s" % [pack_id.strip_edges(), poi, region]

extends Node

# Authoritative state holder for the cross-project planet handoff.
# Read/written by both Space (SSB) and MV layers. begin_landing stages a
# pack id + spawn coords for MvMain._enter_tree to read; begin_launch
# snapshots the current planet and emits launch_requested so SSB can tear
# the viewport down.

signal launch_requested(pack_id: String)
signal return_to_overworld_requested(pack_id: String, realm_id: String, spawn_pos: Vector2)

var hosted: bool = false
var pending_pack_id: String = ""
var pending_realm_id: String = ""
var pending_spawn_room: String = ""
var pending_spawn_pos: Vector2 = Vector2.ZERO
# Region properties staged by Space main._on_overworld_land for MV to consume
# on startup. Keys mirror the region meta schema: music_id, encounter_id,
# gravity_mult, visual_theme, hazard_type.
var pending_region_id: String = ""
var pending_region_meta: Dictionary = {}
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
var pending_editor_realm_id: String = ""
var pending_editor_region_id: String = ""
var pending_editor_room_addr: String = ""

# Internal snapshot store: pack_id → snapshot dict ({pack, room, player, vars, inventory}).
# begin_launch writes here; restore_pending_if_any reads and clears on re-landing.
var _pending_snapshot: Dictionary = {}
var _planet_snapshots: Dictionary = {}

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

# Called by SSB when the player interacts with a planet POI. Stages the
# pack id and spawn coords for MvMain._enter_tree to read, and pulls any
# prior snapshot for that planet so MvMain._ready can rehydrate state.
func begin_landing(pack_id: String, spawn_room: String, spawn_pos: Vector2, realm_id: String = ""):
    if pack_id == "":
        pack_id = "demo"
    hosted = true
    pending_pack_id = pack_id
    pending_realm_id = realm_id.strip_edges()
    pending_spawn_room = spawn_room
    pending_spawn_pos = spawn_pos
    if _planet_snapshots.has(pack_id):
        _pending_snapshot = _planet_snapshots[pack_id].duplicate(true)
    else:
        _pending_snapshot = {}
    print("planetary_interface: begin_landing pack='%s' spawn_room='%s' has_snapshot=%s" %
        [pack_id, spawn_room, not _pending_snapshot.is_empty()])


# Called by MV trigger actions when an authored interactable or trigger
# should back the player out of the side-view room stack and reopen the
# current realm's atmosphere / overworld layer.
func request_return_to_overworld(pack_id: String, realm_id: String, spawn_pos: Vector2 = Vector2(-1, -1)) -> void:
    var target_pack_id: String = pack_id.strip_edges()
    if target_pack_id.is_empty():
        target_pack_id = pending_pack_id.strip_edges()
    if target_pack_id.is_empty():
        push_error("PlanetaryInterface.request_return_to_overworld: no pack id")
        return

    var target_realm_id: String = realm_id.strip_edges()
    if target_realm_id.is_empty():
        target_realm_id = pending_realm_id.strip_edges()

    hosted = true
    pending_pack_id = target_pack_id
    pending_realm_id = target_realm_id
    pending_spawn_room = ""
    pending_spawn_pos = Vector2.ZERO
    pending_region_id = ""
    pending_region_meta = {}
    return_to_overworld_requested.emit(target_pack_id, target_realm_id, spawn_pos)

# Called by restore_pending_if_any to fetch (and clear) the pending snapshot.
# Returns an empty dict if there's nothing to restore.
func _consume_pending_snapshot() -> Dictionary:
    var snap = _pending_snapshot
    _pending_snapshot = {}
    return snap

# Called by begin_launch to store the just-snapshotted planet state under
# its pack id. Next visit to that planet rehydrates from here.
func _save_snapshot(pack_id: String, snap: Dictionary):
    _planet_snapshots[pack_id] = snap.duplicate(true)
    print("planetary_interface: snapshotted '%s' (%d keys)" % [pack_id, snap.size()])

# Called by MvMain when an exit_to_space door tag is traversed (and by
# future return_to_space triggers). Clears live state and emits the launch
# signal that SSB main.gd listens for.
func _emit_launch_after_snapshot():
    var launching: String = pending_pack_id
    hosted = false
    pending_pack_id = ""
    pending_realm_id = ""
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

    var snap: Dictionary = {
        "pack":      pack_id,
        "room":      "",
        "player":    {},
        "vars":      {},       # deferred — VarStore not ported
        "inventory": {},       # deferred — PlayerInventory snapshot not ported
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

    _save_snapshot(pack_id, snap)
    _emit_launch_after_snapshot()


# Called by MvMain._ready after the initial pack load + room spawn. Pulls
# the pending snapshot from the wrapper's store and applies the minimal
# fields we still carry (room address + player position + hp). No-op on
# fresh boots and on first visits to a planet.
func restore_pending_if_any(main: Node) -> void:
    if main == null:
        return
    var snap := _consume_pending_snapshot()
    if snap.is_empty():
        return

    var room_addr := str(snap.get("room", ""))
    var pos := Vector2.ZERO
    var hp := -1
    if snap.has("player") and typeof(snap["player"]) == TYPE_DICTIONARY:
        var pd: Dictionary = snap["player"]
        if pd.has("x") and pd.has("y"):
            pos = Vector2(float(pd["x"]), float(pd["y"]))
        if pd.has("hp"):
            hp = int(pd["hp"])

    if main.has_method("load_from_snapshot"):
        main.call("load_from_snapshot", room_addr, pos, hp)
    print("PlanetaryInterface: restored snapshot")


# Stash the editor's current pack/region/room so MvMain's Ctrl+9
# return handler can scene-change back to Space and Space main can
# re-open the environment editor at the same spot.
func stage_return_to_editor(pack_id: String, realm_id: String, region_id: String, room_addr: String) -> void:
    pending_return_to_editor = true
    pending_editor_pack_id = pack_id
    pending_editor_realm_id = realm_id
    pending_editor_region_id = region_id
    pending_editor_room_addr = room_addr


# Returns the stashed {pack_id, region_id, room_addr} and clears the
# staged state. Call once from Space main._ready when the flag is set.
func consume_return_to_editor() -> Dictionary:
    var out := {
        "pack_id": pending_editor_pack_id,
        "realm_id": pending_editor_realm_id,
        "region_id": pending_editor_region_id,
        "room_addr": pending_editor_room_addr,
    }
    pending_return_to_editor = false
    pending_editor_pack_id = ""
    pending_editor_realm_id = ""
    pending_editor_region_id = ""
    pending_editor_room_addr = ""
    return out

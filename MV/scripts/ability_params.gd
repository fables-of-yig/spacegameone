class_name MvAbilityParams
extends RefCounted

# Runtime reader for the pack's Abilities/abilities.json. Caches the params
# Dictionary keyed by ability id the first time anything asks for a value,
# so the physics hot loop can call param_float / param_int every tick
# without re-parsing JSON.
#
# Editor saves go through PedIO to the user layer; call invalidate() after
# a save if you want a running game to pick up live edits without
# restarting. For the common "open editor, save, restart, play" workflow
# the cache just warms on the first lookup of the new session.

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")

static var _cached_pack: String = ""
static var _params_by_id: Dictionary = {}


static func param_float(ability_id: String, key: String, default_value: float) -> float:
    _ensure_loaded(_current_pack_id())
    if not _params_by_id.has(ability_id):
        return default_value
    var params: Dictionary = _params_by_id[ability_id]
    if not params.has(key):
        return default_value
    return float(params[key])


static func param_int(ability_id: String, key: String, default_value: int) -> int:
    _ensure_loaded(_current_pack_id())
    if not _params_by_id.has(ability_id):
        return default_value
    var params: Dictionary = _params_by_id[ability_id]
    if not params.has(key):
        return default_value
    return int(params[key])


static func invalidate() -> void:
    _cached_pack = ""
    _params_by_id.clear()


static func _ensure_loaded(pack_id: String) -> void:
    if pack_id == _cached_pack and not _params_by_id.is_empty():
        return
    _cached_pack = pack_id
    _params_by_id.clear()
    var data := PedIO.load_abilities(pack_id)
    var raw: Variant = data.get("abilities", [])
    if typeof(raw) != TYPE_ARRAY:
        return
    for entry in raw:
        if typeof(entry) != TYPE_DICTIONARY:
            continue
        var id_str := str(entry.get("id", ""))
        if id_str.is_empty():
            continue
        var params_v: Variant = entry.get("params", {})
        if typeof(params_v) == TYPE_DICTIONARY:
            _params_by_id[id_str] = params_v
        else:
            _params_by_id[id_str] = {}


static func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    return "demo"

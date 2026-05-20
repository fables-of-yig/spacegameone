extends RefCounted

# Per-pack faction table IO. Each pack ships its own list of factions
# under Content/<pack>/Factions/factions.json. The runtime reads this
# into DataManager.galaxy_data["factions"] when a pack is loaded, and a
# future Factions editor pane will author it.
#
# On-disk shape:
#   {
#     "factions": {
#       "<id>": {
#         "name": "Display Name",
#         "symbol_path": "Factions/Symbols/<id>.png",   # pack-relative; "" if none
#         "disposition_to_player": "friendly"|"neutral"|"hostile",
#         "player_rep_start": int (-100..100),
#         "relations": {
#           "<other_faction_id>": "ally"|"neutral"|"enemy"
#         },
#         "desc": "Free-form description.",
#       },
#       ...
#     }
#   }
#
# The runtime callers (npc_ship, station_entity, star_map, etc.) used to
# read a per-faction color tint; that's been dropped in favor of authored
# ship sprites and per-faction symbol PNGs. Unknown faction ids silently
# fall back to per-call defaults.
#
# Symbols are PNGs under Content/<pack>/Factions/Symbols/; the dialogue
# event panel pulls them via build_faction_symbol_map() and draws them
# next to the speaker portrait whenever a dialogue node sets
# speaker_faction = <faction_id>.

const SHIPPED_SEED_PACK: String = "demo"
const FILE_NAME: String = "factions.json"
const FOLDER: String = "Factions"
const SYMBOLS_SUBFOLDER: String = "Symbols"
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")

const ALLOWED_DISPOSITIONS: Array = ["friendly", "neutral", "hostile"]
const ALLOWED_RELATIONS: Array = ["ally", "neutral", "enemy"]


static func user_file(pack_id: String) -> String:
    return PackPaths.writable_pack_file(pack_id, "%s/%s" % [FOLDER, FILE_NAME])


static func shipped_file(pack_id: String) -> String:
    return "res://Content/%s/%s/%s" % [pack_id, FOLDER, FILE_NAME]


static func demo_file() -> String:
    return "res://Content/%s/%s/%s" % [SHIPPED_SEED_PACK, FOLDER, FILE_NAME]


# Returns the loaded faction dict for `pack_id`, or {} if no factions.json
# exists in any of: user override, shipped pack, demo fallback. Callers
# should treat {} as "this pack has no factions" — runtime lookups still
# fall back to per-call defaults so nothing crashes.
static func load_or_empty(pack_id: String) -> Dictionary:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        pid = SHIPPED_SEED_PACK
    for path in [user_file(pid), shipped_file(pid), demo_file()]:
        var data := _read(path)
        if not data.is_empty():
            return data
    return {}


# Loads only the pack's own factions.json, no demo fallback. Used by the
# editor when it needs to know what's actually authored for this pack.
static func load_existing(pack_id: String) -> Dictionary:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return {}
    for path in [user_file(pid), shipped_file(pid)]:
        var data := _read(path)
        if not data.is_empty():
            return data
    return {}


static func save(pack_id: String, factions: Dictionary) -> bool:
    var pid := pack_id.strip_edges()
    if pid.is_empty():
        return false
    var path := user_file(pid)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify({"factions": factions}, "\t"))
    file.close()
    return true


# Normalizes a raw faction entry so the runtime lookups (disposition
# switch, symbol lookup, reputation init) get the shape they expect even
# if a hand-edited file omits fields. Accepts legacy `disposition` and
# `color` for one-time migration; both are dropped from the output.
static func normalize_entry(entry: Variant) -> Dictionary:
    if typeof(entry) != TYPE_DICTIONARY:
        return {}
    var raw: Dictionary = entry
    var disp_raw: String = str(raw.get("disposition_to_player", raw.get("disposition", "neutral"))).strip_edges().to_lower()
    if not ALLOWED_DISPOSITIONS.has(disp_raw):
        disp_raw = "neutral"
    var rep_default: int = _default_rep_for(disp_raw)
    var rep: int = clampi(int(raw.get("player_rep_start", rep_default)), -100, 100)
    var relations: Dictionary = {}
    var rels_v: Variant = raw.get("relations", {})
    if typeof(rels_v) == TYPE_DICTIONARY:
        for k_v in (rels_v as Dictionary).keys():
            var k: String = str(k_v).strip_edges()
            if k.is_empty():
                continue
            var rel_val: String = str((rels_v as Dictionary)[k_v]).strip_edges().to_lower()
            if ALLOWED_RELATIONS.has(rel_val):
                relations[k] = rel_val
    return {
        "name": str(raw.get("name", "")).strip_edges(),
        "symbol_path": str(raw.get("symbol_path", "")).strip_edges(),
        "disposition_to_player": disp_raw,
        "player_rep_start": rep,
        "relations": relations,
        "desc": str(raw.get("desc", "")),
    }


static func _default_rep_for(disposition: String) -> int:
    match disposition:
        "friendly":
            return 25
        "hostile":
            return -25
        _:
            return 0


# Builds a faction_id → res:// path map for the active pack's symbol PNGs,
# mirroring PackAssetIndex.build_portrait_map(). Empty symbol_path entries
# are skipped so the dialogue panel renders nothing rather than a missing-
# texture box for factions whose author hasn't picked an icon yet.
static func build_faction_symbol_map(pack_id: String) -> Dictionary:
    var out: Dictionary = {}
    var factions := load_or_empty(pack_id)
    for fid_v in factions.keys():
        var fid: String = str(fid_v)
        var entry: Dictionary = factions[fid_v]
        var sym: String = str(entry.get("symbol_path", "")).strip_edges()
        if sym.is_empty():
            continue
        var abs_path: String = PackPaths.writable_pack_file(pack_id, sym)
        if not FileAccess.file_exists(abs_path):
            abs_path = "res://Content/%s/%s" % [pack_id, sym]
            if not FileAccess.file_exists(abs_path):
                continue
        out[fid] = abs_path
    return out


static func _read(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var root: Dictionary = parsed
    var factions_v: Variant = root.get("factions", null)
    if typeof(factions_v) != TYPE_DICTIONARY:
        return {}
    var out: Dictionary = {}
    for key_v in (factions_v as Dictionary).keys():
        var entry := normalize_entry((factions_v as Dictionary)[key_v])
        if entry.is_empty():
            continue
        out[str(key_v)] = entry
    return out

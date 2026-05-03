extends RefCounted

# IO for the behavior editor. Reads/writes the pack's behaviors.json
# registry, mirroring the dual-layer resolution pattern used by
# env_io.gd and ent_io.gd: writes always land in the user override
# layer, reads fall back to the shipped layer.

const BehTypes = preload("res://Space/scripts/editor/beh/beh_types.gd")
const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")


static func user_pack_dir(pack_id: String) -> String:
    return PackPaths.writable_pack_dir(pack_id)


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func behaviors_json_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "Entities/behaviors.json"


static func shipped_behaviors_json_path(pack_id: String) -> String:
    return shipped_pack_dir(pack_id) + "Entities/behaviors.json"


static func load_or_init(pack_id: String) -> Dictionary:
    _ensure_dir(user_pack_dir(pack_id) + "Entities")
    var user_path := behaviors_json_path(pack_id)
    if FileAccess.file_exists(user_path):
        return _read_json(user_path)
    var shipped_path := shipped_behaviors_json_path(pack_id)
    if FileAccess.file_exists(shipped_path):
        return _read_json(shipped_path)
    return {"behaviors": []}


static func save_behaviors(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "Entities")
    var path := behaviors_json_path(pack_id)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("BehIO: cannot open %s for write" % path)
        return false
    f.store_string(JSON.stringify(data, "  "))
    f.close()
    return true


# Generates a behavior dict with a minimal root sequence, used when
# adding a new row to the registry.
static func default_behavior(id: String) -> Dictionary:
    return {
        "id": id,
        "name": id.capitalize(),
        "description": "",
        "root": default_node("sequence", "root"),
    }


# Generates an empty node dict of the given type. Composites and
# decorators get a `children` array; leaves get type-specific default
# fields (action/condition name + params dict).
static func default_node(type: String, display_name: String = "") -> Dictionary:
    var n: Dictionary = {
        "type": type,
        "name": display_name if display_name != "" else type,
        "params": {},
    }
    if BehTypes.accepts_children(type):
        n["children"] = []
    if type == "action":
        n["action"] = "idle"
    elif type == "condition":
        n["condition"] = "always"
    return n


# Walks a root node via a path of child indices. An empty path returns
# the root itself. Returns {} if the path is invalid, letting callers
# fail soft rather than crash during UI operations on stale selection.
static func node_at_path(root: Dictionary, path: Array) -> Dictionary:
    var cur: Dictionary = root
    for step_v in path:
        var idx := int(step_v)
        if not cur.has("children") or typeof(cur["children"]) != TYPE_ARRAY:
            return {}
        var kids: Array = cur["children"]
        if idx < 0 or idx >= kids.size():
            return {}
        var child_v: Variant = kids[idx]
        if typeof(child_v) != TYPE_DICTIONARY:
            return {}
        cur = child_v
    return cur


# Returns the parent dict and the child index for the given path, or
# {} if the path points at the root (no parent) or is invalid.
static func parent_of(root: Dictionary, path: Array) -> Dictionary:
    if path.is_empty():
        return {}
    var parent_path: Array = path.slice(0, path.size() - 1)
    var parent := node_at_path(root, parent_path)
    if parent.is_empty():
        return {}
    return {
        "parent": parent,
        "index": int(path[path.size() - 1]),
    }


# Flattens a tree into an array of {node, path, depth} for the tree
# view's display loop. Depth-first pre-order traversal.
static func flatten(root: Dictionary) -> Array:
    var out: Array = []
    _flatten_recursive(root, [], 0, out)
    return out


static func _flatten_recursive(node: Dictionary, path: Array,
        depth: int, out: Array) -> void:
    out.append({
        "node": node,
        "path": path.duplicate(),
        "depth": depth,
    })
    if node.has("children") and typeof(node["children"]) == TYPE_ARRAY:
        var kids: Array = node["children"]
        for i in kids.size():
            var child_v: Variant = kids[i]
            if typeof(child_v) != TYPE_DICTIONARY:
                continue
            var next_path: Array = path.duplicate()
            next_path.append(i)
            _flatten_recursive(child_v, next_path, depth + 1, out)


static func _read_json(path: String) -> Dictionary:
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {"behaviors": []}
    var raw = JSON.parse_string(f.get_as_text())
    f.close()
    if typeof(raw) != TYPE_DICTIONARY:
        return {"behaviors": []}
    if not raw.has("behaviors") or typeof(raw["behaviors"]) != TYPE_ARRAY:
        raw["behaviors"] = []
    return raw


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)

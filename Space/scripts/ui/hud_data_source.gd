extends RefCounted

const UiBindingResolver = preload("res://MV/scripts/ui_binding_resolver.gd")

# Resolves binding source names (e.g. "player.health", "gamemanager.fuel")
# into live values for authored HUD rendering. The binding vocabulary is
# owned by UiContract; anything exposed by the editor should either
# resolve here or produce a visible runtime diagnostic.

var player: Node = null
var game_manager: Node = null


func _init(player_ref: Node = null, gm_ref: Node = null) -> void:
    player = player_ref
    game_manager = gm_ref


# Returns the raw value for a binding name. null when the ref isn't set
# or the path doesn't exist — callers render an empty string / zeroed bar.
func resolve(binding: String) -> Variant:
    if binding == null or binding == "":
        return null
    var parts := binding.split(".", false, 1)
    if parts.size() < 2:
        return _get_from(null, binding)
    var root_key := parts[0]
    var field := parts[1]
    match root_key:
        "player":
            var player_value: Variant = _resolve_player(field)
            return player_value if player_value != null else UiBindingResolver.resolve(binding)
        "gamemanager":
            var gm_value: Variant = _resolve_gm(field)
            return gm_value if gm_value != null else UiBindingResolver.resolve(binding)
        _:
            return UiBindingResolver.resolve(binding)


func has_binding(binding: String) -> bool:
    return UiBindingResolver.has_binding(binding)


func has_resolved_binding(binding: String) -> bool:
    return has_binding(binding) and resolve(binding) != null


func resolve_ratio(binding: String) -> float:
    var v: Variant = resolve(binding)
    if v == null:
        return 0.0
    if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
        return clampf(float(v), 0.0, 1.0)
    return 0.0


# Derives current/max into a 0..1 ratio for progress bars. Handles the
# case where max is 0 by returning 0 (avoids divide-by-zero).
func resolve_bar(current_bind: String, max_bind: String) -> float:
    # Editor conveniences: "player.health_pct" shortcuts a common pair.
    if current_bind != "" and current_bind.ends_with("_pct"):
        return resolve_ratio(current_bind)
    var cur_v: Variant = resolve(current_bind)
    var max_v: Variant = resolve(max_bind)
    if cur_v == null or max_v == null:
        return 0.0
    var cur := float(cur_v)
    var mx := float(max_v)
    if mx <= 0.0:
        return 0.0
    return clampf(cur / mx, 0.0, 1.0)


func _resolve_player(field: String) -> Variant:
    if player == null or not is_instance_valid(player):
        return null
    # Pre-computed ratios for convenience binds.
    match field:
        "health_pct":
            var mx: float = _player_float("max_health")
            if mx <= 0.0:
                return 0.0
            return clampf(_player_float("health") / mx, 0.0, 1.0)
        "shields_pct":
            var mx2: float = _player_float("max_shields")
            if mx2 <= 0.0:
                return 0.0
            return clampf(_player_float("shields") / mx2, 0.0, 1.0)
        "boost_ready_pct":
            var total: float = _player_float("boost_cooldown")
            if total <= 0.0:
                return 1.0
            var remaining: float = _player_float("boost_cd_timer")
            return clampf(1.0 - (remaining / total), 0.0, 1.0)
        "scan_ready_pct":
            var total2: float = _player_float("SCAN_COOLDOWN_TIME")
            if total2 <= 0.0:
                return 1.0
            var remaining2: float = _player_float("scan_cooldown")
            return clampf(1.0 - (remaining2 / total2), 0.0, 1.0)
        "scan_cooldown_time":
            return _player_get("SCAN_COOLDOWN_TIME")
    return _player_get(field)


func _resolve_gm(field: String) -> Variant:
    if game_manager == null or not is_instance_valid(game_manager):
        return null
    match field:
        "fuel_pct":
            var cap: float = _gm_float("fuel_capacity")
            if cap <= 0.0:
                return 0.0
            return clampf(_gm_float("fuel") / cap, 0.0, 1.0)
        "resources_total":
            if game_manager.has_method("get_total_resources"):
                return game_manager.get_total_resources()
            return 0
    return _gm_get(field)


func _player_get(field: String) -> Variant:
    return _get_from(player, field)


func _player_float(field: String) -> float:
    var v: Variant = _player_get(field)
    if v == null:
        return 0.0
    return float(v)


func _gm_get(field: String) -> Variant:
    return _get_from(game_manager, field)


func _gm_float(field: String) -> float:
    var v: Variant = _gm_get(field)
    if v == null:
        return 0.0
    return float(v)


func _get_from(obj: Object, field: String) -> Variant:
    if obj == null:
        return null
    if not (obj as Object).has_method("get"):
        return null
    var v: Variant = obj.get(field)
    return v

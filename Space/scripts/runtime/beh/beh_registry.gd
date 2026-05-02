extends RefCounted

# Runtime registry mapping action/condition names (as authored in the
# behavior editor) to GDScript leaf classes. The loader calls
# build_action / build_condition to produce live ActionLeaf /
# ConditionLeaf instances that it can add to a BeehaveTree.
#
# Leaves read their params from the `params` meta on the node, set by
# the loader at build time. That keeps the leaf classes pure — they
# don't need to know about the behavior editor's dict schema.
#
# Defaults register lazily on first use so test harnesses can preload
# the registry without triggering side effects.

static var _actions: Dictionary = {}
static var _conditions: Dictionary = {}
static var _defaults_registered: bool = false


static func register_action(action_name: String, script: GDScript) -> void:
    _actions[action_name] = script


static func register_condition(condition_name: String, script: GDScript) -> void:
    _conditions[condition_name] = script


static func build_action(action_name: String) -> ActionLeaf:
    _ensure_defaults()
    var script: GDScript = _actions.get(action_name)
    if script == null:
        push_error("[BehRegistry] unknown action '%s'" % action_name)
        return null
    return script.new()


static func build_condition(condition_name: String) -> ConditionLeaf:
    _ensure_defaults()
    var script: GDScript = _conditions.get(condition_name)
    if script == null:
        push_error("[BehRegistry] unknown condition '%s'" % condition_name)
        return null
    return script.new()


static func has_action(action_name: String) -> bool:
    _ensure_defaults()
    return _actions.has(action_name)


static func has_condition(condition_name: String) -> bool:
    _ensure_defaults()
    return _conditions.has(condition_name)


static func action_names() -> Array:
    _ensure_defaults()
    var names := _actions.keys()
    names.sort()
    return names


static func condition_names() -> Array:
    _ensure_defaults()
    var names := _conditions.keys()
    names.sort()
    return names


static func _ensure_defaults() -> void:
    if _defaults_registered:
        return
    _defaults_registered = true
    _actions["idle"] = preload("res://Space/scripts/runtime/beh/leaves/idle_action.gd")
    _actions["walk"] = preload("res://Space/scripts/runtime/beh/leaves/walk_action.gd")
    _actions["walk_left"] = preload("res://Space/scripts/runtime/beh/leaves/walk_left_action.gd")
    _actions["walk_right"] = preload("res://Space/scripts/runtime/beh/leaves/walk_right_action.gd")
    _actions["jump"] = preload("res://Space/scripts/runtime/beh/leaves/jump_action.gd")
    _actions["turn_around"] = preload("res://Space/scripts/runtime/beh/leaves/turn_around_action.gd")
    _actions["attack"] = preload("res://Space/scripts/runtime/beh/leaves/attack_action.gd")
    _actions["flee"] = preload("res://Space/scripts/runtime/beh/leaves/flee_action.gd")
    _actions["pursue"] = preload("res://Space/scripts/runtime/beh/leaves/pursue_action.gd")
    _actions["pursue_fly"] = preload("res://Space/scripts/runtime/beh/leaves/pursue_fly_action.gd")
    _actions["flee_fly"] = preload("res://Space/scripts/runtime/beh/leaves/flee_fly_action.gd")
    _actions["patrol_point"] = preload("res://Space/scripts/runtime/beh/leaves/patrol_point_action.gd")
    _actions["shoot"] = preload("res://Space/scripts/runtime/beh/leaves/shoot_action.gd")
    _actions["dash"] = preload("res://Space/scripts/runtime/beh/leaves/dash_action.gd")
    _conditions["always"] = preload("res://Space/scripts/runtime/beh/leaves/always_condition.gd")
    _conditions["wall_ahead"] = preload("res://Space/scripts/runtime/beh/leaves/wall_ahead_condition.gd")
    _conditions["player_near"] = preload("res://Space/scripts/runtime/beh/leaves/player_near_condition.gd")
    _conditions["edge_ahead"] = preload("res://Space/scripts/runtime/beh/leaves/edge_ahead_condition.gd")
    _conditions["player_seen"] = preload("res://Space/scripts/runtime/beh/leaves/player_seen_condition.gd")
    _conditions["hp_low"] = preload("res://Space/scripts/runtime/beh/leaves/hp_low_condition.gd")
    _conditions["grounded"] = preload("res://Space/scripts/runtime/beh/leaves/grounded_condition.gd")
    _conditions["in_air"] = preload("res://Space/scripts/runtime/beh/leaves/in_air_condition.gd")
    _conditions["cooldown_ready"] = preload("res://Space/scripts/runtime/beh/leaves/cooldown_ready_condition.gd")

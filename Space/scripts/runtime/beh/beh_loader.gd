extends RefCounted

const BehRegistry = preload("res://Space/scripts/runtime/beh/beh_registry.gd")
const BehTypes = preload("res://Space/scripts/shared/beh/beh_types.gd")

# Turns a behavior dict (as authored by the in-editor behavior builder
# and serialized to behaviors.json) into a live BeehaveTree Node with
# real composite / decorator / leaf children. Callers add the returned
# tree as a child of their actor (CharacterBody2D, Node2D, whatever);
# Beehave auto-resolves `actor` to the parent on _ready.
#
# Input schema (matches beh_io.gd):
#   behavior = {id, name, description, root: <node>}
#   node     = {type, name, children?, action?, condition?, params}
#
# Leaves get their authored params stashed on a "params" meta so they
# can be read at tick time by the leaf implementation. Composites and
# decorators also carry the meta for completeness, though they don't
# currently read it.


static func build_tree(behavior: Dictionary) -> BeehaveTree:
    var validation_errors := validate_behavior(behavior)
    if not validation_errors.is_empty():
        for error in validation_errors:
            push_error("[BehLoader] %s" % error)
        return null
    var tree := BeehaveTree.new()
    var label: String = str(behavior.get("name", behavior.get("id", "behavior")))
    if label == "":
        label = "behavior"
    tree.name = label
    var root_v: Variant = behavior.get("root", {})
    if typeof(root_v) != TYPE_DICTIONARY:
        return tree
    var root_node := _build_node(root_v)
    if root_node != null:
        tree.add_child(root_node)
    return tree


static func validate_behavior(behavior: Dictionary) -> Array:
    var errors: Array = []
    var behavior_id := str(behavior.get("id", behavior.get("name", "behavior"))).strip_edges()
    if behavior_id.is_empty():
        behavior_id = "behavior"
    var root_v: Variant = behavior.get("root", null)
    if typeof(root_v) != TYPE_DICTIONARY:
        errors.append("%s: missing root dictionary" % behavior_id)
        return errors
    _validate_node(root_v as Dictionary, "%s.root" % behavior_id, errors)
    return errors


static func _validate_node(dict: Dictionary, path: String, errors: Array) -> void:
    var type_str := str(dict.get("type", "")).strip_edges()
    if type_str == "delay":
        type_str = "delayer"
    if type_str.is_empty():
        errors.append("%s: missing node type" % path)
        return
    if not BehTypes.NODE_TYPES.has(type_str):
        errors.append("%s: unknown node type '%s'" % [path, type_str])
        return

    var kids_v: Variant = dict.get("children", [])
    var kids: Array = []
    if typeof(kids_v) == TYPE_ARRAY:
        kids = kids_v as Array
    elif dict.has("children"):
        errors.append("%s: children must be an array" % path)

    if BehTypes.LEAF_TYPES.has(type_str):
        if not kids.is_empty():
            errors.append("%s: leaf nodes cannot have children" % path)
        if type_str == "action":
            var action_name := str(dict.get("action", "")).strip_edges()
            if action_name.is_empty():
                errors.append("%s: action leaf is missing action name" % path)
            elif not BehRegistry.has_action(action_name):
                errors.append("%s: unknown action leaf '%s'" % [path, action_name])
        elif type_str == "condition":
            var condition_name := str(dict.get("condition", "")).strip_edges()
            if condition_name.is_empty():
                errors.append("%s: condition leaf is missing condition name" % path)
            elif not BehRegistry.has_condition(condition_name):
                errors.append("%s: unknown condition leaf '%s'" % [path, condition_name])
        return

    if BehTypes.DECORATOR_TYPES.has(type_str) and kids.size() != 1:
        errors.append("%s: decorator '%s' must have exactly one child" % [path, type_str])
    elif type_str == "simple_parallel" and kids.size() != 2:
        errors.append("%s: simple_parallel must have exactly two children" % path)
    elif BehTypes.COMPOSITE_TYPES.has(type_str) and type_str != "simple_parallel" and kids.size() < 1:
        errors.append("%s: composite '%s' must have at least one child" % [path, type_str])

    for i in range(kids.size()):
        var child_v: Variant = kids[i]
        if typeof(child_v) != TYPE_DICTIONARY:
            errors.append("%s.children[%d]: child is not a dictionary" % [path, i])
            continue
        _validate_node(child_v as Dictionary, "%s.children[%d]" % [path, i], errors)


static func _build_node(dict: Dictionary) -> BeehaveNode:
    var type_str := str(dict.get("type", ""))
    var node: BeehaveNode = _instantiate(type_str, dict)
    if node == null:
        return null

    var display_name: String = str(dict.get("name", type_str))
    if display_name == "":
        display_name = type_str
    node.name = display_name

    var params_v: Variant = dict.get("params", {})
    if typeof(params_v) == TYPE_DICTIONARY:
        node.set_meta("params", params_v)

    var kids_v: Variant = dict.get("children", [])
    if typeof(kids_v) == TYPE_ARRAY:
        for child_v in kids_v:
            if typeof(child_v) != TYPE_DICTIONARY:
                continue
            var child := _build_node(child_v)
            if child != null:
                node.add_child(child)
    return node


static func _instantiate(type_str: String, dict: Dictionary) -> BeehaveNode:
    match type_str:
        "sequence":
            return SequenceComposite.new()
        "sequence_reactive":
            return SequenceReactiveComposite.new()
        "sequence_star":
            return SequenceStarComposite.new()
        "selector":
            return SelectorComposite.new()
        "selector_random":
            return SelectorRandomComposite.new()
        "simple_parallel":
            return SimpleParallelComposite.new()
        "inverter":
            return InverterDecorator.new()
        "repeater":
            return RepeaterDecorator.new()
        "limiter":
            return LimiterDecorator.new()
        "cooldown":
            return CooldownDecorator.new()
        "delayer", "delay":
            return DelayDecorator.new()
        "until_fail":
            return UntilFailDecorator.new()
        "succeeder":
            return AlwaysSucceedDecorator.new()
        "failer":
            return AlwaysFailDecorator.new()
        "time_limiter":
            return TimeLimiterDecorator.new()
        "action":
            var action_name: String = str(dict.get("action", "idle"))
            return BehRegistry.build_action(action_name)
        "condition":
            var condition_name: String = str(dict.get("condition", "always"))
            return BehRegistry.build_condition(condition_name)
        _:
            push_warning("[BehLoader] unknown node type '%s'" % type_str)
            return null

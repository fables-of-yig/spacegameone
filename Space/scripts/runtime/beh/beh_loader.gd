extends RefCounted

const BehRegistry = preload("res://Space/scripts/runtime/beh/beh_registry.gd")

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

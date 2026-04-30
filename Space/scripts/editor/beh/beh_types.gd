extends RefCounted

# Shared constants for the behavior editor. Models Beehave's node
# taxonomy as a flat string enumeration plus a category lookup so the
# UI can color-code composites vs decorators vs leaves without needing
# to touch Beehave classes directly. The runtime binding layer (built
# separately) will consume this same data to instantiate BeehaveTrees.

const CAT_COMPOSITE: String = "composite"
const CAT_DECORATOR: String = "decorator"
const CAT_LEAF: String = "leaf"

const NODE_TYPES: Array = [
    "sequence",
    "sequence_reactive",
    "sequence_star",
    "selector",
    "selector_random",
    "simple_parallel",
    "inverter",
    "repeater",
    "limiter",
    "cooldown",
    "delayer",
    "until_fail",
    "succeeder",
    "failer",
    "time_limiter",
    "action",
    "condition",
]

const COMPOSITE_TYPES: Array = [
    "sequence",
    "sequence_reactive",
    "sequence_star",
    "selector",
    "selector_random",
    "simple_parallel",
]

const DECORATOR_TYPES: Array = [
    "inverter",
    "repeater",
    "limiter",
    "cooldown",
    "delayer",
    "until_fail",
    "succeeder",
    "failer",
    "time_limiter",
]

const LEAF_TYPES: Array = [
    "action",
    "condition",
]

# Preset action/condition vocab the editor suggests when a leaf is
# added. Runtime binding can ignore unknown values — these are purely
# for authoring ergonomics.
const ACTION_PRESETS: Array = [
    "walk_left",
    "walk_right",
    "idle",
    "jump",
    "turn_around",
    "attack",
    "flee",
    "pursue",
    "flee_fly",
    "pursue_fly",
    "patrol_point",
    "shoot",
    "dash",
]

const CONDITION_PRESETS: Array = [
    "wall_ahead",
    "edge_ahead",
    "player_seen",
    "player_near",
    "hp_low",
    "grounded",
    "in_air",
    "cooldown_ready",
    "always",
]


static func category_of(type: String) -> String:
    if COMPOSITE_TYPES.has(type):
        return CAT_COMPOSITE
    if DECORATOR_TYPES.has(type):
        return CAT_DECORATOR
    return CAT_LEAF


static func category_color(cat: String) -> Color:
    if cat == CAT_COMPOSITE:
        return Color(0.55, 0.85, 1.0, 1.0)
    if cat == CAT_DECORATOR:
        return Color(1.0, 0.75, 0.35, 1.0)
    return Color(0.55, 0.95, 0.55, 1.0)


static func type_color(type: String) -> Color:
    return category_color(category_of(type))


static func type_label(type: String) -> String:
    match type:
        "sequence":
            return "Do these in order"
        "sequence_reactive":
            return "Keep checking, then do these in order"
        "sequence_star":
            return "Continue this ordered list"
        "selector":
            return "Try these until one works"
        "selector_random":
            return "Try one of these at random"
        "simple_parallel":
            return "Do these at the same time"
        "inverter":
            return "Reverse the answer"
        "repeater":
            return "Repeat this"
        "limiter":
            return "Limit how often this runs"
        "cooldown":
            return "Wait before running again"
        "delayer":
            return "Delay before running"
        "until_fail":
            return "Repeat until this fails"
        "succeeder":
            return "Treat as success"
        "failer":
            return "Treat as failure"
        "time_limiter":
            return "Stop after time runs out"
        "action":
            return "Do an action"
        "condition":
            return "Check a condition"
        _:
            return type.replace("_", " ").capitalize()


static func type_help(type: String) -> String:
    match type:
        "sequence":
            return "Runs children in order. The list works only if every child succeeds."
        "selector":
            return "Runs children in order and stops at the first child that works."
        "simple_parallel":
            return "Ticks all children together every frame."
        "selector_random":
            return "Picks one child at random each tick. Useful for variety."
        "sequence_reactive":
            return "Like an ordered list, but earlier checks are re-tested every tick."
        "sequence_star":
            return "Like an ordered list, but resumes where it left off."
        "inverter":
            return "Flips its child's answer. Success becomes failure and failure becomes success."
        "repeater":
            return "Runs its child again and again."
        "limiter":
            return "Allows its child to run only a limited number of times."
        "until_fail":
            return "Keeps running its child until the child fails."
        "cooldown":
            return "Runs its child, then waits before allowing it again."
        "delayer":
            return "Waits before running its child."
        "action":
            return "Makes the actor do something."
        "condition":
            return "Checks the world and decides whether this branch may continue."
        _:
            return "Behavior node type %s." % type


# Returns true for types that can host children arrays. Composites take
# any number of children; decorators take exactly one; leaves take none.
static func accepts_children(type: String) -> bool:
    return COMPOSITE_TYPES.has(type) or DECORATOR_TYPES.has(type)


static func max_children(type: String) -> int:
    if COMPOSITE_TYPES.has(type):
        return -1  # unbounded
    if DECORATOR_TYPES.has(type):
        return 1
    return 0

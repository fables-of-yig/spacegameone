extends RefCounted

const UpdateContextAction = preload("res://Space/scripts/runtime/ship_ai/leaves/npc_ship_update_context_action.gd")
const ManeuverAction = preload("res://Space/scripts/runtime/ship_ai/leaves/npc_ship_maneuver_action.gd")
const FireAction = preload("res://Space/scripts/runtime/ship_ai/leaves/npc_ship_fire_action.gd")
const CoastAction = preload("res://Space/scripts/runtime/ship_ai/leaves/npc_ship_coast_action.gd")


static func build_tree() -> BeehaveTree:
    var tree := BeehaveTree.new()
    tree.name = "NpcShipCombatTree"
    tree.process_thread = BeehaveTree.ProcessThread.MANUAL

    var root := SelectorReactiveComposite.new()
    root.name = "NpcShipRoot"
    tree.add_child(root)

    var combat_seq := SequenceReactiveComposite.new()
    combat_seq.name = "CombatLoop"
    root.add_child(combat_seq)

    var update_ctx := UpdateContextAction.new()
    update_ctx.name = "UpdateCombatContext"
    combat_seq.add_child(update_ctx)

    var combat_parallel := SimpleParallelComposite.new()
    combat_parallel.name = "CombatParallel"
    combat_parallel.delay_mode = false
    combat_seq.add_child(combat_parallel)

    var move := ManeuverAction.new()
    move.name = "CombatManeuver"
    combat_parallel.add_child(move)

    var fire := FireAction.new()
    fire.name = "FireWeapons"
    combat_parallel.add_child(fire)

    var coast := CoastAction.new()
    coast.name = "Coast"
    root.add_child(coast)

    return tree

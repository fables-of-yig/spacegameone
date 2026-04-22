extends RefCounted

const UpdateContextAction = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_update_context_action.gd")
const HealthLowCondition = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_health_low_condition.gd")
const RetreatAction = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_retreat_action.gd")
const ManeuverAction = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_maneuver_action.gd")
const FireAction = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_fire_action.gd")
const CoastAction = preload("res://Space/scripts/runtime/ship_ai/leaves/enemy_ship_coast_action.gd")


static func build_tree() -> BeehaveTree:
    var tree := BeehaveTree.new()
    tree.name = "EnemyShipCombatTree"
    tree.process_thread = BeehaveTree.ProcessThread.MANUAL

    var root := SelectorReactiveComposite.new()
    root.name = "EnemyShipRoot"
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

    var movement_selector := SelectorReactiveComposite.new()
    movement_selector.name = "MovementSelector"
    combat_parallel.add_child(movement_selector)

    var retreat_seq := SequenceReactiveComposite.new()
    retreat_seq.name = "RetreatWhenLow"
    movement_selector.add_child(retreat_seq)

    var low_hp := HealthLowCondition.new()
    low_hp.name = "LowHealth"
    low_hp.set_meta("params", {"threshold": 0.22})
    retreat_seq.add_child(low_hp)

    var retreat := RetreatAction.new()
    retreat.name = "Retreat"
    retreat_seq.add_child(retreat)

    var maneuver := ManeuverAction.new()
    maneuver.name = "StyleManeuver"
    movement_selector.add_child(maneuver)

    var fire := FireAction.new()
    fire.name = "FireWeapons"
    combat_parallel.add_child(fire)

    var coast := CoastAction.new()
    coast.name = "Coast"
    root.add_child(coast)

    return tree

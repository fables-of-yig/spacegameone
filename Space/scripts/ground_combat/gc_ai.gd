extends RefCounted



var combat_map
var weapon_data: Dictionary = {}

func setup(map_ref, weapons: Dictionary) -> void :
    combat_map = map_ref
    weapon_data = weapons



func think(unit, all_player_units: Array, _all_enemy_units: Array, occupied: Dictionary) -> Array:
    var actions: Array = []
    if not unit.is_active():
        return actions


    var targets: Array = []
    for pu in all_player_units:
        if pu.is_alive():
            targets.append(pu)
    if targets.is_empty():
        return actions

    var wdef = unit.get_active_weapon_data(weapon_data)
    var w_range = int(wdef.get("range", 6))
    var ap_shot = int(wdef.get("ap_cost", 4))


    match unit.behavior:
        "aggressive":
            actions = _ai_aggressive(unit, targets, occupied, wdef, w_range, ap_shot)
        "defensive":
            actions = _ai_defensive(unit, targets, occupied, wdef, w_range, ap_shot)
        _:
            actions = _ai_balanced(unit, targets, occupied, wdef, w_range, ap_shot)

    return actions


func _ai_aggressive(unit, targets: Array, occupied: Dictionary, _wdef: Dictionary, w_range: int, ap_shot: int) -> Array:
    var actions: Array = []
    var target = _find_nearest_target(unit, targets)
    if target == null:
        return actions

    var dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
    var has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)


    if dist <= w_range and has_los and not unit.needs_reload():
        while unit.ap >= ap_shot and unit.is_active():
            if unit.needs_reload():
                actions.append({"type": "reload"})
                if not unit.reload(weapon_data):
                    break
                continue
            actions.append({"type": "shoot", "target_id": target.unit_id, "mode": "standard"})
            unit.spend_ap(ap_shot)
            unit.consume_ammo()
    elif unit.needs_reload() and unit.ap >= 2:
        actions.append({"type": "reload"})
        unit.reload(weapon_data)
    else:

        var move_actions = _move_toward(unit, target.hex_pos, occupied, w_range)
        actions.append_array(move_actions)

        dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
        has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)
        if dist <= w_range and has_los and unit.ap >= ap_shot and not unit.needs_reload():
            actions.append({"type": "shoot", "target_id": target.unit_id, "mode": "standard"})
            unit.spend_ap(ap_shot)
            unit.consume_ammo()
    return actions


func _ai_defensive(unit, targets: Array, occupied: Dictionary, _wdef: Dictionary, w_range: int, ap_shot: int) -> Array:
    var actions: Array = []
    var target = _find_nearest_target(unit, targets)
    if target == null:
        return actions

    var dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
    var has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)
    var my_cover = combat_map.get_cover(unit.hex_pos)


    if my_cover < 20:
        var cover_pos = _find_nearest_cover(unit, target, occupied, w_range)
        if cover_pos != Vector2i(-999, -999):
            var path = combat_map.find_path(unit.hex_pos, cover_pos, occupied)
            var moved = _execute_move(unit, path, occupied)
            if moved > 0:
                actions.append({"type": "move", "to": unit.hex_pos, "steps": moved})


    if unit.needs_reload() and unit.ap >= 2:
        actions.append({"type": "reload"})
        unit.reload(weapon_data)


    dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
    has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)
    if dist <= w_range and has_los and unit.ap >= ap_shot and not unit.needs_reload():
        actions.append({"type": "shoot", "target_id": target.unit_id, "mode": "standard"})
        unit.spend_ap(ap_shot)
        unit.consume_ammo()


    if unit.ap >= 2 and unit.ap < ap_shot:
        actions.append({"type": "hunker"})
        unit.spend_ap(2)
        unit.hunkered = true

    return actions


func _ai_balanced(unit, targets: Array, occupied: Dictionary, _wdef: Dictionary, w_range: int, ap_shot: int) -> Array:
    var actions: Array = []
    var target = _find_best_target(unit, targets)
    if target == null:
        return actions

    var dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
    var has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)


    if unit.needs_reload() and unit.ap >= 2:
        actions.append({"type": "reload"})
        unit.reload(weapon_data)


    if dist <= w_range and has_los and not unit.needs_reload():

        var shots = 0
        while unit.ap >= ap_shot and shots < 2 and not unit.needs_reload():
            actions.append({"type": "shoot", "target_id": target.unit_id, "mode": "standard"})
            unit.spend_ap(ap_shot)
            unit.consume_ammo()
            shots += 1

        if unit.ap >= 1 and combat_map.get_cover(unit.hex_pos) < 20:
            var cover_pos = _find_nearest_cover(unit, target, occupied, w_range)
            if cover_pos != Vector2i(-999, -999):
                var path = combat_map.find_path(unit.hex_pos, cover_pos, occupied)
                var moved = _execute_move(unit, path, occupied)
                if moved > 0:
                    actions.append({"type": "move", "to": unit.hex_pos, "steps": moved})
    else:

        var move_actions = _move_toward(unit, target.hex_pos, occupied, w_range)
        actions.append_array(move_actions)

        dist = HexUtil.hex_distance(unit.hex_pos, target.hex_pos)
        has_los = combat_map.has_los(unit.hex_pos, target.hex_pos)
        if dist <= w_range and has_los and unit.ap >= ap_shot and not unit.needs_reload():
            actions.append({"type": "shoot", "target_id": target.unit_id, "mode": "standard"})
            unit.spend_ap(ap_shot)
            unit.consume_ammo()

    return actions



func _find_nearest_target(unit, targets: Array):
    var best = null
    var best_dist = 999
    for t in targets:
        var d = HexUtil.hex_distance(unit.hex_pos, t.hex_pos)
        if d < best_dist:
            best_dist = d
            best = t
    return best

func _find_best_target(unit, targets: Array):

    var best = null
    var best_score: float = -999.0
    for t in targets:
        var d = HexUtil.hex_distance(unit.hex_pos, t.hex_pos)
        var score = - float(d)
        if t.get_hp_pct() < 0.5:
            score += 10.0
        if t.status == t.Status.CRITICAL:
            score += 20.0
        if score > best_score:
            best_score = score
            best = t
    return best

func _move_toward(unit, goal: Vector2i, occupied: Dictionary, desired_range: int) -> Array:
    var actions: Array = []

    var ideal_pos = _find_attack_position(unit, goal, occupied, desired_range)
    if ideal_pos == Vector2i(-999, -999):
        ideal_pos = goal
    var path = combat_map.find_path(unit.hex_pos, ideal_pos, occupied)
    if path.is_empty():
        return actions
    var moved = _execute_move(unit, path, occupied)
    if moved > 0:
        actions.append({"type": "move", "to": unit.hex_pos, "steps": moved})
    return actions

func _execute_move(unit, path: Array, occupied: Dictionary) -> int:
    var moved: int = 0
    for cell in path:
        var cost = combat_map.get_move_cost(cell)
        if unit.ap < cost:
            break
        if occupied.has(cell):
            break
        occupied.erase(unit.hex_pos)
        unit.spend_ap(cost)
        unit.hex_pos = cell
        occupied[cell] = true
        moved += 1
    return moved

func _find_attack_position(unit, target_pos: Vector2i, occupied: Dictionary, w_range: int) -> Vector2i:

    var reachable = combat_map.get_reachable(unit.hex_pos, unit.ap, occupied)
    var best_pos = Vector2i(-999, -999)
    var best_score: float = -999.0
    for pos in reachable:
        var dist = HexUtil.hex_distance(pos, target_pos)
        if dist > w_range:
            continue
        if not combat_map.has_los(pos, target_pos):
            continue
        var cover = combat_map.get_cover(pos)
        var score = float(cover) - float(reachable[pos]) * 0.5
        if score > best_score:
            best_score = score
            best_pos = pos
    return best_pos

func _find_nearest_cover(unit, target, occupied: Dictionary, w_range: int) -> Vector2i:

    var reachable = combat_map.get_reachable(unit.hex_pos, unit.ap, occupied)
    var best_pos = Vector2i(-999, -999)
    var best_score: float = -999.0
    for pos in reachable:
        var cover = combat_map.get_cover(pos)
        if cover < 20:
            continue
        var dist_to_target = HexUtil.hex_distance(pos, target.hex_pos)
        var has_los = combat_map.has_los(pos, target.hex_pos)
        var score = float(cover)
        if has_los and dist_to_target <= w_range:
            score += 20.0
        score -= float(reachable[pos]) * 0.3
        if score > best_score:
            best_score = score
            best_pos = pos
    return best_pos

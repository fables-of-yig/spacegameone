extends Control




signal closed
signal combat_finished(result: Dictionary)


const GCMap = preload("res://Space/scripts/ground_combat/gc_map.gd")
const GCUnit = preload("res://Space/scripts/ground_combat/gc_unit.gd")
const GCAI = preload("res://Space/scripts/ground_combat/gc_ai.gd")


const HEX_SIZE: float = 32.0
const UI_BG: Color = Color(0.08, 0.08, 0.12, 0.95)
const UI_BORDER: Color = Color(0.3, 0.4, 0.6)
const UI_TEXT: Color = Color(0.85, 0.85, 0.9)
const UI_DIM: Color = Color(0.5, 0.5, 0.55)
const UI_ACCENT: Color = Color(0.3, 0.7, 1.0)
const UI_DANGER: Color = Color(0.9, 0.3, 0.2)
const UI_HEAL: Color = Color(0.3, 0.9, 0.4)
const GRID_LINE: Color = Color(0.2, 0.25, 0.35, 0.4)
const MOVE_HIGHLIGHT: Color = Color(0.2, 0.5, 0.9, 0.25)
const ATTACK_HIGHLIGHT: Color = Color(0.9, 0.2, 0.2, 0.2)
const SELECTED_OUTLINE: Color = Color(0.9, 0.8, 0.2, 0.9)


const TILE_COLORS: Dictionary = {
    "open": Color(0.15, 0.18, 0.22), 
    "rough": Color(0.2, 0.18, 0.14), 
    "wall": Color(0.35, 0.3, 0.28), 
    "destructible_wall": Color(0.32, 0.28, 0.24), 
    "half_cover": Color(0.22, 0.25, 0.2), 
    "full_cover": Color(0.28, 0.3, 0.25), 
    "door": Color(0.25, 0.22, 0.18), 
    "water": Color(0.12, 0.2, 0.35), 
    "vegetation": Color(0.15, 0.28, 0.15), 
    "elevation": Color(0.25, 0.22, 0.3), 
    "objective": Color(0.3, 0.25, 0.1), 
    "rubble": Color(0.2, 0.18, 0.16), 
}


enum Phase{PLAYER_PHASE, ENEMY_PHASE, ROUND_END, ANIMATING, COMBAT_OVER}
var phase: int = Phase.PLAYER_PHASE
var round_number: int = 1


var grid_origin: Vector2 = Vector2.ZERO
var cam_offset: Vector2 = Vector2.ZERO
var cam_zoom: float = 1.0
var cam_dragging: bool = false
var cam_drag_start: Vector2 = Vector2.ZERO


var combat_map
var ai_brain
var player_units: Array = []
var enemy_units: Array = []
var selected_unit = null
var selected_unit_idx: int = -1
var hover_hex: Vector2i = Vector2i(-999, -999)


enum Mode{SELECT, MOVE, SHOOT, ITEM, ABILITY}
var mode: int = Mode.SELECT
var move_reachable: Dictionary = {}
var shoot_targets: Array = []
var active_item_idx: int = -1
var active_ability: String = ""


var weapon_data: Dictionary = {}
var armor_data: Dictionary = {}
var item_data: Dictionary = {}
var ability_data: Dictionary = {}


var anim_timer: float = 0.0
var anim_queue: Array = []
var anim_current: Dictionary = {}


var action_log: Array = []
const MAX_LOG: int = 12


var info_panel_rect: Rect2 = Rect2()
var action_bar_rect: Rect2 = Rect2()
var log_panel_rect: Rect2 = Rect2()
var unit_list_rect: Rect2 = Rect2()
var end_turn_rect: Rect2 = Rect2()


var _skip_close_frame: bool = false


var _occupied: Dictionary = {}


var _ai_unit_idx: int = 0
var _ai_actions: Array = []
var _ai_action_idx: int = 0
var _ai_delay: float = 0.0
const AI_ACTION_DELAY: float = 0.4


var _combat_result: Dictionary = {}

func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    process_mode = PROCESS_MODE_ALWAYS
    mouse_filter = MOUSE_FILTER_STOP
    focus_mode = FOCUS_ALL
    _update_layout()

func _update_layout():
    var w = size.x
    var h = size.y

    info_panel_rect = Rect2(w - 280, 0, 280, h - 200)

    action_bar_rect = Rect2(0, h - 60, w - 280, 60)

    log_panel_rect = Rect2(w - 280, h - 200, 280, 200)

    unit_list_rect = Rect2(0, 0, 180, minf(h - 60, player_units.size() * 48.0 + 40))

    end_turn_rect = Rect2(w - 280 - 130, h - 55, 120, 45)

    var grid_w = w - 280
    var grid_h = h - 60
    grid_origin = Vector2(grid_w * 0.5, grid_h * 0.5)


func start_combat(map_data: Dictionary, squad_crew: Array, wdata: Dictionary, adata: Dictionary, idata: Dictionary, abdata: Dictionary) -> void :
    weapon_data = wdata
    armor_data = adata
    item_data = idata
    ability_data = abdata


    combat_map = GCMap.new()
    combat_map.load_map(map_data)


    player_units.clear()
    var spawn_cells = combat_map.spawn_zones.get("player", [])
    for i in squad_crew.size():
        var crew = squad_crew[i]
        var unit = GCUnit.new()
        var loadout = crew.get("ground_loadout", _default_loadout())
        unit.init_from_crew(crew, loadout, weapon_data, armor_data, ability_data)
        if i < spawn_cells.size():
            unit.hex_pos = spawn_cells[i]
        unit.begin_turn()
        player_units.append(unit)


    enemy_units.clear()
    var enemy_spawns = combat_map.spawn_zones.get("enemy", [])
    var spawn_idx: int = 0
    var uid_counter: int = 1000
    for squad_entry in combat_map.enemy_squad:
        var template_id = squad_entry.get("template", "")
        var count = int(squad_entry.get("count", 1))
        var template = combat_map.enemy_templates.get(template_id, {})
        if template.is_empty():
            continue
        for _j in count:
            var unit = GCUnit.new()
            unit.init_from_template(template, uid_counter, weapon_data)
            if spawn_idx < enemy_spawns.size():
                unit.hex_pos = enemy_spawns[spawn_idx]
                spawn_idx += 1
            unit.begin_turn()
            enemy_units.append(unit)
            uid_counter += 1


    ai_brain = GCAI.new()
    ai_brain.setup(combat_map, weapon_data)


    phase = Phase.PLAYER_PHASE
    round_number = 1
    mode = Mode.SELECT
    selected_unit = null
    selected_unit_idx = -1
    action_log.clear()
    _rebuild_occupied()
    _log("=== ROUND %d ===" % round_number, UI_ACCENT)
    _log("Player Phase — Select a unit.", UI_TEXT)


    var center = _compute_map_center()
    cam_offset = - center

    visible = true
    grab_focus()
    _skip_close_frame = true
    _update_layout()
    queue_redraw()

func _default_loadout() -> Dictionary:
    return {
        "weapon_primary": "assault_rifle", 
        "weapon_secondary": "combat_knife", 
        "armor": "standard_vest", 
        "item_1": "medkit", 
        "item_2": "", 
        "item_3": ""
    }

func _compute_map_center() -> Vector2:
    var cells = combat_map.get_all_cells()
    if cells.is_empty():
        return Vector2.ZERO
    var sum = Vector2.ZERO
    for c in cells:
        sum += HexUtil.hex_to_pixel(c, HEX_SIZE)
    return sum / float(cells.size())

func _rebuild_occupied() -> void :
    _occupied.clear()
    for u in player_units:
        if u.is_alive():
            _occupied[u.hex_pos] = true
    for u in enemy_units:
        if u.is_alive():
            _occupied[u.hex_pos] = true



func _process(delta: float):
    if not visible:
        return
    if _skip_close_frame:
        _skip_close_frame = false
        queue_redraw()
        return


    if phase == Phase.ANIMATING:
        anim_timer -= delta
        if anim_timer <= 0:
            _advance_animation()
        queue_redraw()
        return


    if phase == Phase.ENEMY_PHASE:
        _ai_delay -= delta
        if _ai_delay <= 0:
            _process_enemy_turn()
        queue_redraw()
        return


    var mouse_pos = get_local_mouse_position()
    var world_mouse = (mouse_pos - grid_origin - cam_offset) / cam_zoom
    hover_hex = HexUtil.pixel_to_hex(world_mouse, HEX_SIZE)

    queue_redraw()



func _gui_input(event: InputEvent):
    if not visible:
        return
    if _skip_close_frame:
        return


    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if mode != Mode.SELECT:
            _cancel_mode()
            accept_event()
            return

        if phase == Phase.COMBAT_OVER:
            _close_combat()
            accept_event()
        return


    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_MIDDLE:
            if event.pressed:
                cam_dragging = true
                cam_drag_start = event.position
            else:
                cam_dragging = false
            accept_event()
            return

        if event.button_index == MOUSE_BUTTON_WHEEL_UP:
            cam_zoom = clampf(cam_zoom + 0.1, 0.4, 2.5)
            accept_event()
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            cam_zoom = clampf(cam_zoom - 0.1, 0.4, 2.5)
            accept_event()
            return

    if event is InputEventMouseMotion and cam_dragging:
        cam_offset += event.relative
        accept_event()
        return


    if phase != Phase.PLAYER_PHASE:
        return

    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        var pos = event.position
        _handle_left_click(pos)
        accept_event()
        return

    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:

        if selected_unit and mode == Mode.SELECT:
            var target = _get_enemy_at(hover_hex)
            if target and combat_map.has_los(selected_unit.hex_pos, hover_hex):
                _execute_shot(selected_unit, target, "standard")
            else:

                if combat_map.is_walkable(hover_hex) and not _occupied.has(hover_hex):
                    _enter_move_mode()
                    if move_reachable.has(hover_hex):
                        _execute_move(hover_hex)
        elif mode != Mode.SELECT:
            _cancel_mode()
        accept_event()
        return


    if event is InputEventKey and event.pressed:
        match event.keycode:
            KEY_TAB:
                _cycle_unit(1 if not event.shift_pressed else -1)
                accept_event()
            KEY_SPACE:
                if phase == Phase.PLAYER_PHASE:
                    _end_player_turn()
                    accept_event()
            KEY_ENTER:
                if phase == Phase.PLAYER_PHASE:
                    _end_player_turn()
                    accept_event()
            KEY_R:
                if selected_unit and not selected_unit.needs_reload():
                    pass
                elif selected_unit:
                    _execute_reload()
                    accept_event()
            KEY_W:
                if selected_unit:
                    selected_unit.swap_weapon()
                    _log("%s switches to %s" % [selected_unit.unit_name, _weapon_name(selected_unit.active_weapon)], UI_TEXT)
                    accept_event()
            KEY_H:
                if selected_unit and selected_unit.ap >= 2:
                    selected_unit.spend_ap(2)
                    selected_unit.hunkered = true
                    _log("%s hunkers down (+cover)" % selected_unit.unit_name, UI_ACCENT)
                    accept_event()
            KEY_O:
                if selected_unit and selected_unit.ap >= 5:
                    selected_unit.spend_ap(5)
                    selected_unit.overwatch = true
                    selected_unit.overwatch_ap = 5
                    _log("%s sets overwatch" % selected_unit.unit_name, UI_ACCENT)
                    accept_event()

func _handle_left_click(pos: Vector2) -> void :

    if end_turn_rect.has_point(pos) and phase == Phase.PLAYER_PHASE:
        _end_player_turn()
        return


    if unit_list_rect.has_point(pos):
        var idx = int((pos.y - unit_list_rect.position.y - 30) / 48.0)
        if idx >= 0 and idx < player_units.size():
            _select_unit(idx)
        return


    if action_bar_rect.has_point(pos) and selected_unit:
        _handle_action_bar_click(pos)
        return


    if info_panel_rect.has_point(pos):
        return


    match mode:
        Mode.SELECT:

            var pu = _get_player_unit_at(hover_hex)
            if pu:
                _select_unit(player_units.find(pu))
                return
            if selected_unit:
                var eu = _get_enemy_at(hover_hex)
                if eu and combat_map.has_los(selected_unit.hex_pos, hover_hex):
                    _execute_shot(selected_unit, eu, "standard")
                    return

                if combat_map.is_walkable(hover_hex) and not _occupied.has(hover_hex):
                    _enter_move_mode()
                    if move_reachable.has(hover_hex):
                        _execute_move(hover_hex)
                    else:
                        _cancel_mode()
        Mode.MOVE:
            if move_reachable.has(hover_hex):
                _execute_move(hover_hex)
            else:
                _cancel_mode()
        Mode.SHOOT:
            var target = _get_enemy_at(hover_hex)
            if target and target.unit_id in shoot_targets:
                _execute_shot(selected_unit, target, "standard")
            _cancel_mode()
        Mode.ITEM:
            _execute_item(hover_hex)
            _cancel_mode()
        Mode.ABILITY:
            _execute_ability(hover_hex)
            _cancel_mode()

func _handle_action_bar_click(pos: Vector2) -> void :
    if not selected_unit:
        return
    var bar_x = pos.x - action_bar_rect.position.x
    var btn_w: float = 100.0
    var btn_gap: float = 8.0
    var btn_idx = int(bar_x / (btn_w + btn_gap))

    match btn_idx:
        0: _enter_move_mode()
        1: _enter_shoot_mode("standard")
        2: _enter_shoot_mode("aimed")
        3: _enter_shoot_mode("quick")
        4: _execute_reload()
        5:
            selected_unit.swap_weapon()
            _log("%s switches to %s" % [selected_unit.unit_name, _weapon_name(selected_unit.active_weapon)], UI_TEXT)
        6: _enter_item_mode(0)
        7: _enter_item_mode(1)
        8: _enter_item_mode(2)



func _select_unit(idx: int) -> void :
    if idx < 0 or idx >= player_units.size():
        return
    selected_unit = player_units[idx]
    selected_unit_idx = idx
    mode = Mode.SELECT
    move_reachable.clear()

func _cycle_unit(dir: int) -> void :
    if player_units.is_empty():
        return
    var start = selected_unit_idx if selected_unit_idx >= 0 else -1
    var idx = start
    for _i in player_units.size():
        idx = (idx + dir) % player_units.size()
        if idx < 0:
            idx += player_units.size()
        if player_units[idx].is_active():
            _select_unit(idx)
            return

    for i in player_units.size():
        if player_units[i].is_alive():
            _select_unit(i)
            return

func _enter_move_mode() -> void :
    if not selected_unit or not selected_unit.is_active():
        return
    mode = Mode.MOVE
    _rebuild_occupied()
    move_reachable = combat_map.get_reachable(selected_unit.hex_pos, selected_unit.ap, _occupied)

func _enter_shoot_mode(shot_type: String) -> void :
    if not selected_unit or not selected_unit.is_active():
        return
    if selected_unit.needs_reload():
        _log("Need to reload!", UI_DANGER)
        return
    var wdef = selected_unit.get_active_weapon_data(weapon_data)
    var ap_key = "ap_cost"
    if shot_type == "aimed":
        ap_key = "ap_aimed"
    elif shot_type == "quick":
        ap_key = "ap_quick"
    var cost = int(wdef.get(ap_key, 4))
    if selected_unit.ap < cost:
        _log("Not enough AP! (%d/%d)" % [selected_unit.ap, cost], UI_DANGER)
        return
    mode = Mode.SHOOT

    var w_range = int(wdef.get("range", 6))
    shoot_targets.clear()
    for eu in enemy_units:
        if not eu.is_alive():
            continue
        var dist = HexUtil.hex_distance(selected_unit.hex_pos, eu.hex_pos)
        if dist <= w_range and combat_map.has_los(selected_unit.hex_pos, eu.hex_pos):
            shoot_targets.append(eu.unit_id)

func _cancel_mode() -> void :
    mode = Mode.SELECT
    move_reachable.clear()
    shoot_targets.clear()
    active_item_idx = -1
    active_ability = ""

func _execute_move(target: Vector2i) -> void :
    if not selected_unit:
        return
    _rebuild_occupied()
    var path = combat_map.find_path(selected_unit.hex_pos, target, _occupied)
    if path.is_empty():
        _cancel_mode()
        return

    var total_cost: int = 0
    var final_pos = selected_unit.hex_pos
    for cell in path:
        var cost = combat_map.get_move_cost(cell)
        if selected_unit.ap < cost:
            break
        selected_unit.spend_ap(cost)
        total_cost += cost
        final_pos = cell
    _occupied.erase(selected_unit.hex_pos)
    selected_unit.hex_pos = final_pos
    _occupied[final_pos] = true
    _log("%s moves (%d AP)" % [selected_unit.unit_name, total_cost], UI_TEXT)


    _check_overwatch_triggers(selected_unit, false)

    _cancel_mode()
    _check_auto_advance()

func _execute_shot(attacker, target, shot_type: String) -> void :
    if not attacker or not target:
        return
    var wdef = attacker.get_active_weapon_data(weapon_data)
    var ap_key = "ap_cost"
    var acc_mod: int = 0
    if shot_type == "aimed":
        ap_key = "ap_aimed"
        acc_mod = 15
    elif shot_type == "quick":
        ap_key = "ap_quick"
        acc_mod = -15
    var cost = int(wdef.get(ap_key, 4))
    if not attacker.spend_ap(cost):
        _log("Not enough AP!", UI_DANGER)
        return
    if not attacker.consume_ammo():
        _log("Weapon empty! Reload first.", UI_DANGER)
        attacker.ap += cost
        return


    var base_acc = int(wdef.get("accuracy", 60))
    var dist = HexUtil.hex_distance(attacker.hex_pos, target.hex_pos)
    @warning_ignore("integer_division")
    var w_range = int(wdef.get("range", 6))
    @warning_ignore("integer_division")
    var range_penalty = maxi(0, (dist - w_range / 2) * 5)
    var cover_penalty = combat_map.get_cover_vs(target.hex_pos, attacker.hex_pos)
    if target.hunkered:
        cover_penalty = int(float(cover_penalty) * 2.0)
    var dodge_penalty = target.dodge
    var hit_chance = base_acc + attacker.accuracy_bonus + acc_mod - range_penalty - cover_penalty - dodge_penalty
    hit_chance = clampi(hit_chance, 5, 95)

    var roll = randi() % 100
    if roll < hit_chance:

        var dmg = float(wdef.get("damage", 10))
        dmg *= 1.0 + float(attacker.combat_skill) * 0.05

        var crit_chance = 5 + int(wdef.get("crit_bonus", 0))
        var is_crit = (randi() % 100) < crit_chance
        if is_crit:
            dmg *= 1.5
        var actual = target.take_damage(dmg)
        var crit_str = " CRITICAL!" if is_crit else ""
        _log("%s hits %s for %d damage!%s" % [attacker.unit_name, target.unit_name, int(actual), crit_str], 
            UI_DANGER if is_crit else Color(0.9, 0.6, 0.3))
        if not target.is_alive():
            _log("%s is down!" % target.unit_name, UI_DANGER)
            _occupied.erase(target.hex_pos)
    else:
        _log("%s misses %s (%d%% chance)" % [attacker.unit_name, target.unit_name, hit_chance], UI_DIM)

    _cancel_mode()
    _check_victory()
    _check_auto_advance()

func _execute_reload() -> void :
    if not selected_unit:
        return
    if selected_unit.reload(weapon_data):
        _log("%s reloads %s" % [selected_unit.unit_name, _weapon_name(selected_unit.active_weapon)], UI_TEXT)
    else:
        _log("Can't reload!", UI_DANGER)
    _check_auto_advance()

func _enter_item_mode(idx: int) -> void :
    if not selected_unit or idx >= selected_unit.items.size():
        return
    active_item_idx = idx
    var item = selected_unit.items[idx]
    var idef = item_data.get(item.get("id", ""), {})
    var cost = int(idef.get("ap_cost", 4))
    if selected_unit.ap < cost:
        _log("Not enough AP for %s" % idef.get("name", "item"), UI_DANGER)
        active_item_idx = -1
        return
    mode = Mode.ITEM

func _execute_item(target_hex: Vector2i) -> void :
    if not selected_unit or active_item_idx < 0:
        return
    if active_item_idx >= selected_unit.items.size():
        return
    var item = selected_unit.items[active_item_idx]
    var item_id = item.get("id", "")
    var idef = item_data.get(item_id, {})
    var cost = int(idef.get("ap_cost", 4))
    var itype = idef.get("type", "")
    var use_range = int(idef.get("range", 0))

    match itype:
        "heal":

            var heal_target = null
            if target_hex == selected_unit.hex_pos:
                heal_target = selected_unit
            else:
                var dist = HexUtil.hex_distance(selected_unit.hex_pos, target_hex)
                if dist <= maxi(use_range, 1):
                    heal_target = _get_player_unit_at(target_hex)
            if heal_target == null:
                _log("No valid heal target!", UI_DANGER)
                return
            if not selected_unit.spend_ap(cost):
                return
            var heal_amt = float(idef.get("heal_amount", 30))
            var med_skill = int(selected_unit.crew_ref.get("skills", {}).get("medical", 0))
            heal_amt *= 1.0 + float(med_skill) * 0.1
            heal_target.heal(heal_amt)
            selected_unit.use_item(active_item_idx)
            _log("%s heals %s for %d HP" % [selected_unit.unit_name, heal_target.unit_name, int(heal_amt)], UI_HEAL)

        "grenade":
            var dist = HexUtil.hex_distance(selected_unit.hex_pos, target_hex)
            if dist > use_range:
                _log("Out of range!", UI_DANGER)
                return
            if not selected_unit.spend_ap(cost):
                return
            var blast_r = int(idef.get("blast_radius", 1))
            var dmg = float(idef.get("damage", 25))
            var blast_cells = HexUtil.hexes_in_radius(target_hex, blast_r)
            selected_unit.use_item(active_item_idx)
            _log("%s throws %s!" % [selected_unit.unit_name, idef.get("name", "grenade")], UI_DANGER)
            for cell in blast_cells:

                for u in player_units + enemy_units:
                    if u.is_alive() and u.hex_pos == cell:
                        var actual = u.take_damage(dmg)
                        _log("  %s takes %d blast damage" % [u.unit_name, int(actual)], UI_DANGER)
                        if not u.is_alive():
                            _log("  %s is down!" % u.unit_name, UI_DANGER)

                combat_map.damage_tile(cell, dmg)

        "smoke":
            var dist = HexUtil.hex_distance(selected_unit.hex_pos, target_hex)
            if dist > use_range:
                _log("Out of range!", UI_DANGER)
                return
            if not selected_unit.spend_ap(cost):
                return
            var radius = int(idef.get("blast_radius", 1))
            var duration = int(idef.get("duration", 3))
            combat_map.add_smoke(target_hex, radius, duration)
            selected_unit.use_item(active_item_idx)
            _log("%s deploys smoke" % selected_unit.unit_name, UI_ACCENT)

        "boost":
            if not selected_unit.spend_ap(cost):
                return
            var bonus = int(idef.get("ap_boost", 4))
            selected_unit.ap += bonus
            selected_unit.use_item(active_item_idx)
            _log("%s uses Stim Pack (+%d AP)" % [selected_unit.unit_name, bonus], UI_ACCENT)

        "breach":
            var dist = HexUtil.hex_distance(selected_unit.hex_pos, target_hex)
            if dist > maxi(use_range, 1):
                _log("Must be adjacent!", UI_DANGER)
                return
            if not selected_unit.spend_ap(cost):
                return
            var bdmg = float(idef.get("damage", 50))
            combat_map.damage_tile(target_hex, bdmg)
            selected_unit.use_item(active_item_idx)
            _log("%s places breach charge!" % selected_unit.unit_name, UI_DANGER)

    _check_victory()

func _execute_ability(_target_hex: Vector2i) -> void :

    pass



func _end_player_turn() -> void :
    if phase != Phase.PLAYER_PHASE:
        return
    _log("--- Enemy Phase ---", UI_DANGER)
    phase = Phase.ENEMY_PHASE
    _ai_unit_idx = 0
    _ai_actions.clear()
    _ai_action_idx = 0
    _ai_delay = 0.3

    for eu in enemy_units:
        if eu.is_alive():
            eu.begin_turn()
    _rebuild_occupied()

func _process_enemy_turn() -> void :

    if _ai_action_idx < _ai_actions.size():

        var action = _ai_actions[_ai_action_idx]
        _execute_ai_action(enemy_units[_ai_unit_idx], action)
        _ai_action_idx += 1
        _ai_delay = AI_ACTION_DELAY
        return


    _ai_unit_idx += 1
    while _ai_unit_idx < enemy_units.size():
        var eu = enemy_units[_ai_unit_idx]
        if eu.is_active():
            _rebuild_occupied()
            _ai_actions = ai_brain.think(eu, player_units, enemy_units, _occupied)
            _ai_action_idx = 0
            if not _ai_actions.is_empty():
                _ai_delay = AI_ACTION_DELAY
                return
        _ai_unit_idx += 1


    _end_round()

func _execute_ai_action(unit, action: Dictionary) -> void :

    match action.get("type", ""):
        "move":
            _log("%s moves" % unit.unit_name, UI_DIM)
            _rebuild_occupied()
        "shoot":
            var target_id = action.get("target_id", -1)
            var target = _find_unit_by_id(target_id, player_units)
            if target and target.is_alive():

                _resolve_ai_shot(unit, target, action.get("mode", "standard"))
        "reload":

            _log("%s reloads" % unit.unit_name, UI_DIM)
        "hunker":

            _log("%s hunkers down" % unit.unit_name, UI_DIM)


func _resolve_ai_shot(attacker, target, shot_type: String) -> void :
    var wdef = attacker.get_active_weapon_data(weapon_data)
    var acc_mod: int = 0
    if shot_type == "aimed":
        acc_mod = 15
    elif shot_type == "quick":
        acc_mod = -15
    var base_acc = int(wdef.get("accuracy", 60))
    var dist = HexUtil.hex_distance(attacker.hex_pos, target.hex_pos)
    @warning_ignore("integer_division")
    var w_range = int(wdef.get("range", 6))
    @warning_ignore("integer_division")
    var range_penalty = maxi(0, (dist - w_range / 2) * 5)
    var cover_penalty = combat_map.get_cover_vs(target.hex_pos, attacker.hex_pos)
    if target.hunkered:
        cover_penalty = int(float(cover_penalty) * 2.0)
    var dodge_penalty = target.dodge
    var hit_chance = base_acc + attacker.accuracy_bonus + acc_mod - range_penalty - cover_penalty - dodge_penalty
    hit_chance = clampi(hit_chance, 5, 95)
    var roll = randi() % 100
    if roll < hit_chance:
        var dmg = float(wdef.get("damage", 10))
        dmg *= 1.0 + float(attacker.combat_skill) * 0.05
        var crit_chance = 5 + int(wdef.get("crit_bonus", 0))
        var is_crit = (randi() % 100) < crit_chance
        if is_crit:
            dmg *= 1.5
        var actual = target.take_damage(dmg)
        var crit_str = " CRITICAL!" if is_crit else ""
        _log("%s hits %s for %d damage!%s" % [attacker.unit_name, target.unit_name, int(actual), crit_str], 
            UI_DANGER if is_crit else Color(0.9, 0.6, 0.3))
        if not target.is_alive():
            _log("%s is down!" % target.unit_name, UI_DANGER)
            _occupied.erase(target.hex_pos)
    else:
        _log("%s misses %s (%d%% chance)" % [attacker.unit_name, target.unit_name, hit_chance], UI_DIM)
    _check_victory()

func _end_round() -> void :
    round_number += 1
    combat_map.tick_smoke()
    _log("=== ROUND %d ===" % round_number, UI_ACCENT)
    _log("Player Phase", UI_TEXT)
    phase = Phase.PLAYER_PHASE

    for pu in player_units:
        if pu.is_alive():
            pu.begin_turn()
    _rebuild_occupied()

    _cycle_unit(1)
    _check_victory()

func _check_victory() -> void :
    var enemies_alive = false
    for eu in enemy_units:
        if eu.is_alive():
            enemies_alive = true
            break
    var players_alive = false
    for pu in player_units:
        if pu.is_alive():
            players_alive = true
            break
    if not enemies_alive:
        _log("=== VICTORY ===", UI_HEAL)
        phase = Phase.COMBAT_OVER
        _combat_result = _build_result(true)
    elif not players_alive:
        _log("=== DEFEAT ===", UI_DANGER)
        phase = Phase.COMBAT_OVER
        _combat_result = _build_result(false)

func _check_auto_advance() -> void :

    if phase != Phase.PLAYER_PHASE:
        return
    for pu in player_units:
        if pu.is_active():
            return
    _end_player_turn()

func _check_overwatch_triggers(mover, is_enemy: bool) -> void :

    var watchers = enemy_units if not is_enemy else player_units
    for w in watchers:
        if not w.overwatch or not w.is_alive():
            continue
        if not combat_map.has_los(w.hex_pos, mover.hex_pos):
            continue
        var wdef = w.get_active_weapon_data(weapon_data)
        var w_range = int(wdef.get("range", 6))
        if HexUtil.hex_distance(w.hex_pos, mover.hex_pos) > w_range:
            continue

        w.overwatch = false
        _log("%s fires overwatch!" % w.unit_name, UI_DANGER)
        _execute_shot(w, mover, "quick")

func _build_result(victory: bool) -> Dictionary:
    var xp_earned: int = 0
    if victory:
        for eu in enemy_units:
            xp_earned += eu.xp_value
    var crew_status: Array = []
    for pu in player_units:
        crew_status.append({
            "crew_id": pu.unit_id, 
            "name": pu.unit_name, 
            "hp": pu.hp, 
            "max_hp": pu.max_hp, 
            "status": pu.get_status_string(), 
        })
    return {
        "victory": victory, 
        "xp_earned": xp_earned, 
        "rounds": round_number, 
        "crew_status": crew_status, 
    }

func _close_combat() -> void :
    visible = false
    closed.emit()
    combat_finished.emit(_combat_result)



func _get_player_unit_at(pos: Vector2i):
    for u in player_units:
        if u.is_alive() and u.hex_pos == pos:
            return u
    return null

func _get_enemy_at(pos: Vector2i):
    for u in enemy_units:
        if u.is_alive() and u.hex_pos == pos:
            return u
    return null

func _find_unit_by_id(uid, unit_list: Array):
    for u in unit_list:
        if u.unit_id == uid:
            return u
    return null

func _weapon_name(wid: String) -> String:
    return weapon_data.get(wid, {}).get("name", wid)

func _log(text: String, color: Color = UI_TEXT) -> void :
    action_log.append({"text": text, "color": color})
    if action_log.size() > MAX_LOG:
        action_log.pop_front()

func _advance_animation() -> void :

    phase = Phase.PLAYER_PHASE

func _hex_screen_pos(hex: Vector2i) -> Vector2:
    return grid_origin + cam_offset + HexUtil.hex_to_pixel(hex, HEX_SIZE) * cam_zoom



func _draw():
    if not visible:
        return
    var vp_size = size


    draw_rect(Rect2(Vector2.ZERO, vp_size), Color(0.05, 0.05, 0.08))


    _draw_map()


    _draw_highlights()


    _draw_smoke()


    _draw_units()


    if combat_map and combat_map.has_cell(hover_hex):
        _draw_hex_outline(hover_hex, Color(0.8, 0.8, 0.8, 0.5), 2.0)


    _draw_unit_list()
    _draw_info_panel()
    _draw_action_bar()
    _draw_log_panel()
    _draw_end_turn_button()
    _draw_phase_banner()

func _draw_map() -> void :
    if not combat_map:
        return
    for cell in combat_map.get_all_cells():
        var ttype = combat_map.get_tile(cell)
        var color = TILE_COLORS.get(ttype, Color(0.15, 0.15, 0.2))
        var center = _hex_screen_pos(cell)
        var corners = HexUtil.hex_corners(center, HEX_SIZE * cam_zoom)

        for i in range(1, corners.size() - 1):
            draw_colored_polygon(PackedVector2Array([corners[0], corners[i], corners[i + 1]]), color)

        for i in corners.size():
            draw_line(corners[i], corners[(i + 1) % corners.size()], GRID_LINE, 1.0)

        var cover = combat_map.get_cover(cell)
        if cover > 0:
            var shield_color = Color(0.4, 0.7, 0.3, 0.6) if cover >= 40 else Color(0.6, 0.6, 0.3, 0.5)
            var sz = 4.0 * cam_zoom
            draw_rect(Rect2(center.x - sz, center.y - HEX_SIZE * cam_zoom * 0.6, sz * 2, sz), shield_color)

func _draw_highlights() -> void :
    if mode == Mode.MOVE:
        for cell in move_reachable:
            if cell == selected_unit.hex_pos:
                continue
            _draw_hex_fill(cell, MOVE_HIGHLIGHT)
    elif mode == Mode.SHOOT:
        for eu in enemy_units:
            if eu.is_alive() and eu.unit_id in shoot_targets:
                _draw_hex_fill(eu.hex_pos, ATTACK_HIGHLIGHT)
    elif mode == Mode.ITEM:

        if selected_unit and active_item_idx >= 0 and active_item_idx < selected_unit.items.size():
            var item = selected_unit.items[active_item_idx]
            var idef = item_data.get(item.get("id", ""), {})
            var r = int(idef.get("range", 0))
            if r > 0:
                var cells = HexUtil.hexes_in_radius(selected_unit.hex_pos, r)
                for cell in cells:
                    if combat_map.has_cell(cell):
                        _draw_hex_fill(cell, Color(0.2, 0.6, 0.2, 0.15))

func _draw_smoke() -> void :
    if not combat_map:
        return
    for cell in combat_map.smoke_tiles:
        _draw_hex_fill(cell, Color(0.6, 0.6, 0.6, 0.4))

func _draw_units() -> void :

    for u in player_units:
        if not u.is_alive() and u.status != u.Status.INCAPACITATED:
            continue
        var center = _hex_screen_pos(u.hex_pos)
        var r = HEX_SIZE * cam_zoom * 0.4
        var body_color = Color(0.2, 0.5, 0.9) if u.is_alive() else Color(0.3, 0.3, 0.4)
        if u.status == u.Status.WOUNDED:
            body_color = Color(0.6, 0.5, 0.2)
        elif u.status == u.Status.CRITICAL or u.status == u.Status.INCAPACITATED:
            body_color = Color(0.7, 0.2, 0.15)
        draw_circle(center, r, body_color)

        if u == selected_unit:
            draw_arc(center, r + 2.0 * cam_zoom, 0, TAU, 24, SELECTED_OUTLINE, 2.0 * cam_zoom)

        var font = ThemeDB.fallback_font
        var fs = 10.0 * cam_zoom
        draw_string(font, center + Vector2( - r, - r - 4 * cam_zoom), u.unit_name, HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, UI_TEXT)

        var bar_w = r * 1.6
        var bar_h = 3.0 * cam_zoom
        var bar_x = center.x - bar_w * 0.5
        var bar_y = center.y + r + 3 * cam_zoom
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.0, 0.0))
        draw_rect(Rect2(bar_x, bar_y, bar_w * u.get_hp_pct(), bar_h), u.get_status_color())

        if u.overwatch:
            draw_string(font, center + Vector2(-6 * cam_zoom, r + 14 * cam_zoom), "OW", HORIZONTAL_ALIGNMENT_LEFT, 40, int(8.0 * cam_zoom), UI_ACCENT)

        if u.hunkered:
            draw_string(font, center + Vector2(-6 * cam_zoom, r + 14 * cam_zoom), "HK", HORIZONTAL_ALIGNMENT_LEFT, 40, int(8.0 * cam_zoom), Color(0.4, 0.8, 0.3))


    for u in enemy_units:
        if not u.is_alive() and u.status != u.Status.INCAPACITATED:
            continue
        var center = _hex_screen_pos(u.hex_pos)
        var r = HEX_SIZE * cam_zoom * 0.4
        var body_color = Color(0.8, 0.2, 0.15) if u.is_alive() else Color(0.4, 0.2, 0.2)
        if u.status == u.Status.WOUNDED:
            body_color = Color(0.7, 0.4, 0.15)
        elif u.status == u.Status.CRITICAL or u.status == u.Status.INCAPACITATED:
            body_color = Color(0.5, 0.15, 0.1)
        draw_circle(center, r, body_color)

        var font = ThemeDB.fallback_font
        var fs = 10.0 * cam_zoom
        draw_string(font, center + Vector2( - r, - r - 4 * cam_zoom), u.unit_name, HORIZONTAL_ALIGNMENT_CENTER, r * 2, fs, Color(0.9, 0.7, 0.7))

        var bar_w = r * 1.6
        var bar_h = 3.0 * cam_zoom
        var bar_x = center.x - bar_w * 0.5
        var bar_y = center.y + r + 3 * cam_zoom
        draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.2, 0.0, 0.0))
        draw_rect(Rect2(bar_x, bar_y, bar_w * u.get_hp_pct(), bar_h), u.get_status_color())

func _draw_hex_fill(hex: Vector2i, color: Color) -> void :
    var center = _hex_screen_pos(hex)
    var corners = HexUtil.hex_corners(center, HEX_SIZE * cam_zoom)
    for i in range(1, corners.size() - 1):
        draw_colored_polygon(PackedVector2Array([corners[0], corners[i], corners[i + 1]]), color)

func _draw_hex_outline(hex: Vector2i, color: Color, width: float = 1.0) -> void :
    var center = _hex_screen_pos(hex)
    var corners = HexUtil.hex_corners(center, HEX_SIZE * cam_zoom)
    for i in corners.size():
        draw_line(corners[i], corners[(i + 1) % corners.size()], color, width)

func _draw_unit_list() -> void :
    var r = unit_list_rect
    draw_rect(r, UI_BG)
    draw_rect(r, UI_BORDER, false, 1.0)
    var font = ThemeDB.fallback_font
    draw_string(font, r.position + Vector2(8, 22), "SQUAD", HORIZONTAL_ALIGNMENT_LEFT, 160, 14, UI_ACCENT)
    for i in player_units.size():
        var u = player_units[i]
        var y = r.position.y + 30 + i * 48.0
        var row_color = Color(0.15, 0.2, 0.3, 0.8) if u == selected_unit else Color(0.1, 0.1, 0.15, 0.5)
        draw_rect(Rect2(r.position.x + 4, y, r.size.x - 8, 44), row_color)

        var name_color = UI_TEXT if u.is_alive() else UI_DIM
        draw_string(font, Vector2(r.position.x + 10, y + 16), u.unit_name, HORIZONTAL_ALIGNMENT_LEFT, 120, 12, name_color)

        var status_str = "%s | AP:%d" % [u.get_status_string(), u.ap]
        draw_string(font, Vector2(r.position.x + 10, y + 34), status_str, HORIZONTAL_ALIGNMENT_LEFT, 160, 10, u.get_status_color())

        var bx = r.position.x + 140
        var bw: float = 30.0
        draw_rect(Rect2(bx, y + 8, bw, 6), Color(0.2, 0.0, 0.0))
        draw_rect(Rect2(bx, y + 8, bw * u.get_hp_pct(), 6), u.get_status_color())

func _draw_info_panel() -> void :
    var r = info_panel_rect
    draw_rect(r, UI_BG)
    draw_rect(r, UI_BORDER, false, 1.0)
    var font = ThemeDB.fallback_font
    if not selected_unit:
        draw_string(font, r.position + Vector2(10, 30), "Select a unit", HORIZONTAL_ALIGNMENT_LEFT, 260, 14, UI_DIM)
        return
    var u = selected_unit
    var y = r.position.y + 10
    var x = r.position.x + 10
    var w = r.size.x - 20

    draw_string(font, Vector2(x, y + 18), u.unit_name, HORIZONTAL_ALIGNMENT_LEFT, w, 16, UI_ACCENT)
    y += 28

    draw_string(font, Vector2(x, y + 14), "Status: %s" % u.get_status_string(), HORIZONTAL_ALIGNMENT_LEFT, w, 12, u.get_status_color())
    y += 20

    draw_string(font, Vector2(x, y + 14), "HP: %d / %d" % [int(u.hp), int(u.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_TEXT)
    y += 18
    draw_rect(Rect2(x, y, w, 8), Color(0.2, 0.0, 0.0))
    draw_rect(Rect2(x, y, w * u.get_hp_pct(), 8), u.get_status_color())
    y += 14

    draw_string(font, Vector2(x, y + 14), "AP: %d / %d" % [u.ap, u.ap_max], HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_ACCENT)
    y += 20
    draw_rect(Rect2(x, y, w, 6), Color(0.1, 0.1, 0.2))
    draw_rect(Rect2(x, y, w * (float(u.ap) / float(maxi(u.ap_max, 1))), 6), UI_ACCENT)
    y += 14

    var wname = _weapon_name(u.active_weapon)
    var ammo_str = ""
    if u.ammo.has(u.active_weapon):
        var wdef = weapon_data.get(u.active_weapon, {})
        ammo_str = " [%d/%d]" % [u.ammo[u.active_weapon], int(wdef.get("ammo_max", 0))]
    draw_string(font, Vector2(x, y + 14), "Weapon: %s%s" % [wname, ammo_str], HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_TEXT)
    y += 20

    draw_string(font, Vector2(x, y + 14), "Armor: %d" % u.armor, HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_TEXT)
    y += 20

    draw_string(font, Vector2(x, y + 14), "Accuracy: +%d" % u.accuracy_bonus, HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_TEXT)
    y += 20

    draw_string(font, Vector2(x, y + 14), "Dodge: %d%%" % u.dodge, HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_TEXT)
    y += 24

    if not u.items.is_empty():
        draw_string(font, Vector2(x, y + 14), "Items:", HORIZONTAL_ALIGNMENT_LEFT, w, 12, UI_ACCENT)
        y += 18
        for ii in u.items.size():
            var item = u.items[ii]
            var idef = item_data.get(item.get("id", ""), {})
            var iname = idef.get("name", item.get("id", "?"))
            draw_string(font, Vector2(x + 8, y + 14), "%d. %s (x%d)" % [ii + 1, iname, item.get("count", 1)], HORIZONTAL_ALIGNMENT_LEFT, w - 8, 11, UI_TEXT)
            y += 16


    if combat_map and combat_map.has_cell(hover_hex):
        y += 10
        draw_line(Vector2(x, y), Vector2(x + w, y), UI_BORDER, 1.0)
        y += 6
        var ttype = combat_map.get_tile(hover_hex)
        draw_string(font, Vector2(x, y + 14), "Tile: %s" % ttype, HORIZONTAL_ALIGNMENT_LEFT, w, 11, UI_DIM)
        y += 16
        var cover = combat_map.get_cover(hover_hex)
        if cover > 0:
            draw_string(font, Vector2(x, y + 14), "Cover: %d" % cover, HORIZONTAL_ALIGNMENT_LEFT, w, 11, UI_DIM)
            y += 16
        var eu = _get_enemy_at(hover_hex)
        if eu:
            draw_string(font, Vector2(x, y + 14), "%s HP: %d/%d" % [eu.unit_name, int(eu.hp), int(eu.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, w, 11, UI_DANGER)
            y += 16
            if selected_unit:

                var wdef = selected_unit.get_active_weapon_data(weapon_data)
                var dist = HexUtil.hex_distance(selected_unit.hex_pos, hover_hex)
                @warning_ignore("integer_division")
                var w_range = int(wdef.get("range", 6))
                var base_acc = int(wdef.get("accuracy", 60))
                @warning_ignore("integer_division")
                var range_pen = maxi(0, (dist - w_range / 2) * 5)
                var cover_pen = combat_map.get_cover_vs(eu.hex_pos, selected_unit.hex_pos)
                var hit = clampi(base_acc + selected_unit.accuracy_bonus - range_pen - cover_pen - eu.dodge, 5, 95)
                draw_string(font, Vector2(x, y + 14), "Hit chance: %d%%" % hit, HORIZONTAL_ALIGNMENT_LEFT, w, 11, Color(0.9, 0.7, 0.3))

func _draw_action_bar() -> void :
    var r = action_bar_rect
    draw_rect(r, UI_BG)
    draw_rect(r, UI_BORDER, false, 1.0)
    if not selected_unit or not selected_unit.is_active():
        return
    var font = ThemeDB.fallback_font
    var btn_w: float = 100.0
    var btn_h: float = 40.0
    var gap: float = 8.0
    var bx = r.position.x + 10
    var by = r.position.y + 10

    var wdef = selected_unit.get_active_weapon_data(weapon_data)
    var buttons: Array = [
        {"label": "Move (1AP)", "enabled": selected_unit.ap >= 1}, 
        {"label": "Shoot (%dAP)" % int(wdef.get("ap_cost", 4)), "enabled": selected_unit.ap >= int(wdef.get("ap_cost", 4)) and not selected_unit.needs_reload()}, 
        {"label": "Aimed (%dAP)" % int(wdef.get("ap_aimed", 6)), "enabled": selected_unit.ap >= int(wdef.get("ap_aimed", 6)) and int(wdef.get("ap_aimed", 0)) > 0 and not selected_unit.needs_reload()}, 
        {"label": "Quick (%dAP)" % int(wdef.get("ap_quick", 3)), "enabled": selected_unit.ap >= int(wdef.get("ap_quick", 3)) and int(wdef.get("ap_quick", 0)) > 0 and not selected_unit.needs_reload()}, 
        {"label": "Reload [R]", "enabled": selected_unit.needs_reload() and selected_unit.ap >= int(wdef.get("reload_ap", 2))}, 
        {"label": "Swap [W]", "enabled": selected_unit.weapon_secondary != ""}, 
    ]

    for ii in selected_unit.items.size():
        var item = selected_unit.items[ii]
        var idef = item_data.get(item.get("id", ""), {})
        var ilabel = idef.get("name", "Item")
        var icost = int(idef.get("ap_cost", 4))
        buttons.append({"label": "%s (%dAP)" % [ilabel, icost], "enabled": selected_unit.ap >= icost})

    for i in buttons.size():
        var btn = buttons[i]
        var br = Rect2(bx + i * (btn_w + gap), by, btn_w, btn_h)
        if br.position.x + btn_w > r.position.x + r.size.x:
            break
        var bg = Color(0.15, 0.2, 0.3) if btn["enabled"] else Color(0.1, 0.1, 0.12)

        if btn["enabled"] and br.has_point(get_local_mouse_position()):
            bg = Color(0.2, 0.3, 0.45)
        draw_rect(br, bg)
        draw_rect(br, UI_BORDER, false, 1.0)
        var tc = UI_TEXT if btn["enabled"] else UI_DIM
        draw_string(font, br.position + Vector2(6, 26), btn["label"], HORIZONTAL_ALIGNMENT_LEFT, btn_w - 12, 10, tc)

func _draw_log_panel() -> void :
    var r = log_panel_rect
    draw_rect(r, UI_BG)
    draw_rect(r, UI_BORDER, false, 1.0)
    var font = ThemeDB.fallback_font
    draw_string(font, r.position + Vector2(8, 16), "COMBAT LOG", HORIZONTAL_ALIGNMENT_LEFT, 260, 11, UI_DIM)
    for i in action_log.size():
        var entry = action_log[i]
        var y = r.position.y + 24 + i * 14
        if y + 14 > r.position.y + r.size.y:
            break
        draw_string(font, Vector2(r.position.x + 8, y + 12), entry["text"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 10, entry["color"])

func _draw_end_turn_button() -> void :
    var hover = end_turn_rect.has_point(get_local_mouse_position())
    var bg = Color(0.2, 0.35, 0.5) if hover else Color(0.12, 0.18, 0.28)
    if phase == Phase.COMBAT_OVER:
        bg = Color(0.2, 0.4, 0.2) if hover else Color(0.15, 0.3, 0.15)
    draw_rect(end_turn_rect, bg)
    draw_rect(end_turn_rect, UI_BORDER, false, 1.0)
    var font = ThemeDB.fallback_font
    var label = "END TURN" if phase == Phase.PLAYER_PHASE else ("CLOSE" if phase == Phase.COMBAT_OVER else "ENEMY...")
    draw_string(font, end_turn_rect.position + Vector2(12, 30), label, HORIZONTAL_ALIGNMENT_LEFT, 100, 14, UI_TEXT)

func _draw_phase_banner() -> void :
    if phase == Phase.ENEMY_PHASE:
        var font = ThemeDB.fallback_font
        var banner_y = size.y * 0.15
        draw_string(font, Vector2(size.x * 0.3, banner_y), "ENEMY TURN", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.4, 28, Color(0.9, 0.3, 0.2, 0.7))
    elif phase == Phase.COMBAT_OVER:
        var font = ThemeDB.fallback_font
        var banner_y = size.y * 0.15
        var victory = _combat_result.get("victory", false)
        var text = "VICTORY!" if victory else "DEFEAT"
        var color = Color(0.3, 0.9, 0.4, 0.8) if victory else Color(0.9, 0.2, 0.15, 0.8)
        draw_string(font, Vector2(size.x * 0.25, banner_y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5, 36, color)

        if victory:
            var xp = _combat_result.get("xp_earned", 0)
            draw_string(font, Vector2(size.x * 0.3, banner_y + 40), "XP Earned: %d" % xp, HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.4, 18, UI_TEXT)
        draw_string(font, Vector2(size.x * 0.3, banner_y + 70), "Press ESC or click CLOSE", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.4, 14, UI_DIM)

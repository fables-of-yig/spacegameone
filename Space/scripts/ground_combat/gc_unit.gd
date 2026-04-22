extends RefCounted




const WOUNDED_THRESHOLD: float = 0.5
const CRITICAL_THRESHOLD: float = 0.2
const BLEEDOUT_TURNS: int = 3


var unit_id = 0
var unit_name: String = ""
var is_player: bool = true
var crew_ref: Dictionary = {}
var hex_pos: Vector2i = Vector2i.ZERO


var hp: float = 100.0
var max_hp: float = 100.0
var armor: int = 0
var ap: int = 10
var ap_max: int = 10
var accuracy_bonus: int = 0
var dodge: int = 0
var sight_range: int = 8
var combat_skill: int = 5


var weapon_primary: String = ""
var weapon_secondary: String = ""
var armor_type: String = "none"
var active_weapon: String = ""
var ammo: Dictionary = {}
var items: Array = []


enum Status{HEALTHY, WOUNDED, CRITICAL, INCAPACITATED, DEAD}
var status: int = Status.HEALTHY
var bleeding: bool = false
var bleedout_timer: int = 0
var suppression: int = 0
var hunkered: bool = false
var overwatch: bool = false
var overwatch_ap: int = 0
var cooldowns: Dictionary = {}
var xp_value: int = 10
var behavior: String = "balanced"


var abilities: Array = []


func init_from_crew(crew: Dictionary, loadout: Dictionary, weapon_data: Dictionary, armor_data: Dictionary, ability_data: Dictionary) -> void :
    is_player = true
    crew_ref = crew
    unit_id = crew.get("id", 0)
    unit_name = crew.get("name", "Unknown")


    var skills = crew.get("skills", {})
    combat_skill = int(skills.get("combat", 3))
    var _medical_skill = int(skills.get("medical", 0))
    var piloting_skill = int(skills.get("piloting", 0))
    var gunnery_skill = int(skills.get("gunnery", 0))
    var _entertainment_skill = int(skills.get("entertainment", 0))


    @warning_ignore("integer_division")
    ap_max = 10 + (combat_skill - 5) / 2 if combat_skill > 5 else 10
    accuracy_bonus = combat_skill * 4
    dodge = mini(piloting_skill * 2, 20)
    @warning_ignore("integer_division")
    sight_range = 8 + gunnery_skill / 3


    max_hp = float(crew.get("max_health", 100))
    hp = float(crew.get("health", max_hp))


    weapon_primary = loadout.get("weapon_primary", "assault_rifle")
    weapon_secondary = loadout.get("weapon_secondary", "combat_knife")
    armor_type = loadout.get("armor", "standard_vest")
    active_weapon = weapon_primary


    var ar = armor_data.get(armor_type, {})
    armor = int(ar.get("armor", 0))
    dodge += int(ar.get("dodge_bonus", 0))
    ap_max -= int(ar.get("ap_penalty", 0))


    _init_ammo(weapon_data)


    items.clear()
    for slot in ["item_1", "item_2", "item_3"]:
        var item_id = loadout.get(slot, "")
        if item_id != "":
            items.append({"id": item_id, "count": 1})


    abilities.clear()
    for aid in ability_data:
        var ab = ability_data[aid]
        var req_skill = ab.get("skill", "combat")
        var req_level = int(ab.get("skill_req", 0))
        var unit_skill_val = int(skills.get(req_skill, 0))
        if unit_skill_val >= req_level:
            abilities.append(aid)

    ap = ap_max
    _update_status()


func init_from_template(template: Dictionary, uid: int, weapon_data: Dictionary) -> void :
    is_player = false
    unit_id = uid
    unit_name = template.get("name", "Enemy")
    max_hp = float(template.get("max_hp", 80))
    hp = float(template.get("hp", max_hp))
    armor = int(template.get("armor", 0))
    combat_skill = int(template.get("combat_skill", 3))
    ap_max = int(template.get("ap_max", 10))
    xp_value = int(template.get("xp_value", 10))
    behavior = template.get("behavior", "balanced")


    accuracy_bonus = combat_skill * 4
    dodge = 0
    sight_range = 8

    weapon_primary = template.get("weapon", "assault_rifle")
    weapon_secondary = template.get("secondary", "")
    armor_type = template.get("armor_type", "none")
    active_weapon = weapon_primary

    _init_ammo(weapon_data)


    abilities = ["overwatch", "hunker_down"]

    ap = ap_max
    _update_status()

func _init_ammo(weapon_data: Dictionary) -> void :
    ammo.clear()
    for wid in [weapon_primary, weapon_secondary]:
        if wid == "":
            continue
        var wdef = weapon_data.get(wid, {})
        var max_ammo = int(wdef.get("ammo_max", -1))
        if max_ammo > 0:
            ammo[wid] = max_ammo


func begin_turn() -> void :
    ap = ap_max

    if suppression > 0:
        ap = maxi(ap - suppression, 2)
        suppression = 0

    if status == Status.WOUNDED:
        ap = maxi(ap - 2, 2)
    elif status == Status.CRITICAL:
        ap = maxi(ap - 4, 1)
    elif status == Status.INCAPACITATED:
        ap = 0
        bleedout_timer -= 1
        if bleedout_timer <= 0:
            status = Status.DEAD

    if bleeding and status != Status.INCAPACITATED and status != Status.DEAD:
        take_damage(5.0)

    hunkered = false
    overwatch = false
    overwatch_ap = 0

    var expired: Array = []
    for aid in cooldowns:
        cooldowns[aid] -= 1
        if cooldowns[aid] <= 0:
            expired.append(aid)
    for aid in expired:
        cooldowns.erase(aid)


func spend_ap(cost: int) -> bool:
    if ap < cost:
        return false
    ap -= cost
    return true


func take_damage(raw_damage: float) -> float:
    var effective = maxf(raw_damage - float(armor), raw_damage * 0.1)
    hp = maxf(hp - effective, 0.0)
    _update_status()
    return effective


func heal(amount: float) -> void :
    hp = minf(hp + amount, max_hp)
    if bleeding and hp > max_hp * CRITICAL_THRESHOLD:
        bleeding = false
    _update_status()


func stabilize() -> void :
    if status == Status.INCAPACITATED:
        bleedout_timer = 99
        bleeding = false

func _update_status() -> void :
    if hp <= 0:
        if status != Status.DEAD:
            status = Status.INCAPACITATED
            bleedout_timer = BLEEDOUT_TURNS
            bleeding = true
            ap = 0
    elif hp < max_hp * CRITICAL_THRESHOLD:
        status = Status.CRITICAL
        bleeding = true
    elif hp < max_hp * WOUNDED_THRESHOLD:
        status = Status.WOUNDED
    else:
        status = Status.HEALTHY

func is_alive() -> bool:
    return status != Status.DEAD and status != Status.INCAPACITATED

func is_active() -> bool:
    return is_alive() and ap > 0

func get_hp_pct() -> float:
    if max_hp <= 0:
        return 0.0
    return hp / max_hp


func get_active_weapon_data(weapon_data: Dictionary) -> Dictionary:
    return weapon_data.get(active_weapon, {})


func needs_reload() -> bool:
    if not ammo.has(active_weapon):
        return false
    return ammo[active_weapon] <= 0


func reload(weapon_data: Dictionary) -> bool:
    var wdef = weapon_data.get(active_weapon, {})
    var max_ammo = int(wdef.get("ammo_max", -1))
    if max_ammo <= 0:
        return false
    var cost = int(wdef.get("reload_ap", 2))
    if not spend_ap(cost):
        return false
    ammo[active_weapon] = max_ammo
    return true


func consume_ammo() -> bool:
    if not ammo.has(active_weapon):
        return true
    if ammo[active_weapon] <= 0:
        return false
    ammo[active_weapon] -= 1
    return true


func swap_weapon() -> void :
    if active_weapon == weapon_primary and weapon_secondary != "":
        active_weapon = weapon_secondary
    elif weapon_primary != "":
        active_weapon = weapon_primary


func use_item(item_idx: int) -> Dictionary:
    if item_idx < 0 or item_idx >= items.size():
        return {}
    var item = items[item_idx]
    item["count"] = item.get("count", 1) - 1
    if item["count"] <= 0:
        items.remove_at(item_idx)
    return item


func get_status_string() -> String:
    match status:
        Status.HEALTHY: return "Healthy"
        Status.WOUNDED: return "Wounded"
        Status.CRITICAL: return "Critical"
        Status.INCAPACITATED: return "Down"
        Status.DEAD: return "Dead"
    return "Unknown"


func get_status_color() -> Color:
    match status:
        Status.HEALTHY: return Color(0.3, 0.9, 0.3)
        Status.WOUNDED: return Color(0.9, 0.8, 0.2)
        Status.CRITICAL: return Color(0.9, 0.3, 0.1)
        Status.INCAPACITATED: return Color(0.5, 0.1, 0.1)
        Status.DEAD: return Color(0.3, 0.3, 0.3)
    return Color.WHITE

extends Node

const PedIO := preload("res://Space/scripts/shared/ped/ped_io.gd")
const _StationGenerator := preload("res://Space/scripts/autoload/station_generator.gd")
const _InputSetup := preload("res://Space/scripts/autoload/input_setup.gd")
const _ModuleSprites := preload("res://Space/scripts/autoload/module_sprites.gd")

enum GameState{FLYING, COMBAT, SHIP_BUILDER, STAR_MAP, DIALOGUE, PAUSED}
var state: GameState = GameState.FLYING
const INVALID_POS: = Vector3i(-9999, -9999, -9999)


var ship_modules: Array = []
var module_inventory: Dictionary = {}
var equipped_core: String = "core_pod"
var ship_color_primary: Color = Color(0.3, 0.55, 0.8)
var ship_color_secondary: Color = Color(0.15, 0.25, 0.45)
var _module_sprite_cache: Dictionary = {}

func get_module_sprite(sprite_name: String) -> Texture2D:
    return _ModuleSprites.get_sprite(sprite_name, _module_sprite_cache, ship_color_primary, ship_color_secondary)

func invalidate_module_sprites():
    _module_sprite_cache.clear()


var current_system: String = ""
var near_star: bool = false
var docked_at_station: bool = false
var builder_open: bool = false
var visited_systems: Array = []
var discovered_pois: Dictionary = {}
const DETECTION_RANGE_MULT: float = 3.0
var _loaded_from_save: bool = false
var _last_template_combat_style: String = "standard"
var skip_main_menu: bool = false
var auto_test_fly: bool = false
var start_template_path: String = "res://Space/data/npc_templates/noblefox.json"


var kill_count: int = 0
var total_kills: int = 0



var credits: int = 1000



var ship_crew: Array = []
var max_crew: int = 0
var food_supply: float = 0.0
var food_capacity: float = 0.0
var command_mode: bool = false
var active_ship_id: String = ""
var mutiny_active: bool = false
var mutiny_target: String = ""
var cargo_capacity: int = 0
var cargo_hold: Array = []
var prisoners: Array = []
var prisoner_capacity: int = 0
var active_research: String = ""
var research_progress: float = 0.0
var RESEARCH_PROJECTS: Dictionary = {}
var active_missions: Array = []
var crew_warnings: Array = []
var morale_event_log: Array = []
var ship_modules_version: int = 0
var hull_walkable: Array = []
var work_orders: Array = []
var crafting_orders: Array = []
var fleet_ships: Array = []
var fleet_id_counter: int = 0
var crew_id_counter: int = 0
var room_detection_dirty: bool = false
var colonies: Array = []
var station_populations: Dictionary = {}


var in_combat: bool = false
var consumed_pois: Array = []
# sys_id -> Array[String] of poi.id values that have been unlocked at runtime.
# A POI authored with `hidden: true` is skipped during spawn until its id
# appears in this map; the unlock_poi trigger action writes here.
var unlocked_pois: Dictionary = {}
var killed_placed_npcs: Dictionary = {}


var fuel: float = 50.0
var fuel_capacity: float = 100.0


var resources: Dictionary = {}
var resource_capacity: int = 20


var npc_ships: Dictionary = {}
var npc_id_counter: int = 0







const STATION_ECONOMY_PROFILES: Dictionary = {
    "trade": {
        "produces": {"polymer": 2, "alloy": 1, "circuits": 1}, 
        "consumes": {"ore": 2, "carbon": 1, "metals": 1}, 
        "food_per_pop": 0.5, 
        "credit_income": 50, 
        "starting_credits": 10000, 
        "starting_resources": {"ore": 15, "metals": 10, "polymer": 8, "alloy": 5, "carbon": 8, "circuits": 5, "alcohol": 5}, 
    }, 
    "military": {
        "produces": {}, 
        "consumes": {"metals": 2, "alloy": 1, "polymer": 1}, 
        "food_per_pop": 0.8, 
        "credit_income": 20, 
        "starting_credits": 8000, 
        "starting_resources": {"metals": 25, "alloy": 15, "polymer": 10, "ore": 10}, 
    }, 
    "pirate": {
        "produces": {"alcohol": 2}, 
        "consumes": {"carbon": 1}, 
        "food_per_pop": 0.6, 
        "credit_income": 10, 
        "starting_credits": 3000, 
        "starting_resources": {"alcohol": 15, "carbon": 5, "metals": 5}, 
    }, 
    "science": {
        "produces": {"circuits": 2, "rare_earth": 1}, 
        "consumes": {"crystals": 2, "gas": 1}, 
        "food_per_pop": 0.4, 
        "credit_income": 30, 
        "starting_credits": 6000, 
        "starting_resources": {"crystals": 15, "gas": 10, "circuits": 10, "rare_earth": 5}, 
    }, 
    "gateway": {
        "produces": {"polymer": 1}, 
        "consumes": {"ore": 1, "metals": 1}, 
        "food_per_pop": 0.6, 
        "credit_income": 80, 
        "starting_credits": 15000, 
        "starting_resources": {"ore": 20, "metals": 15, "polymer": 10, "alloy": 10, "carbon": 10, "circuits": 8}, 
    }, 
}


const TRADE_RESOURCES: Array = ["ore", "crystals", "metals", "rare_earth", "gas", "carbon", "copper_ore", "titanium_ore", "circuits", "alloy", "polymer", "alcohol"]


const FACTION_BUILD_SHIP_COST: Dictionary = {"metals": 50, "alloy": 25}


var faction_reputation: Dictionary = {}




var debug_mode: bool = false


var conduit_power_radius: int = 1











const MODULE_BASE_HP: Dictionary = {
    "reactor": {"hp": 80, "armor": 5}, 
    "engine": {"hp": 60, "armor": 3}, 
    "weapon": {"hp": 50, "armor": 2}, 
    "shield": {"hp": 40, "armor": 1}, 
    "armor": {"hp": 120, "armor": 10}, 
    "sensor": {"hp": 30, "armor": 1}, 
    "cargo": {"hp": 60, "armor": 2}, 
    "quarters": {"hp": 50, "armor": 2}, 
    "fuel_tank": {"hp": 50, "armor": 2}, 
    "life_support": {"hp": 60, "armor": 3}, 
    "conduit": {"hp": 30, "armor": 1}, 
    "hallway": {"hp": 30, "armor": 1}, 
    "airlock": {"hp": 40, "armor": 3}, 
    "structural": {"hp": 40, "armor": 5}, 
    "bridge": {"hp": 60, "armor": 4}, 
    "medbay": {"hp": 50, "armor": 2}, 
    "construction_hangar": {"hp": 80, "armor": 4}, 
    "basic_workshop": {"hp": 50, "armor": 2}, 
    "farmers_workshop": {"hp": 50, "armor": 2}, 
    "solar_field": {"hp": 30, "armor": 1}, 
    "hydroponics": {"hp": 40, "armor": 1}, 
    "mining": {"hp": 50, "armor": 3}, 
    "research_lab": {"hp": 50, "armor": 2}, 
    "brig": {"hp": 50, "armor": 3}, 
    "hangar": {"hp": 60, "armor": 3}, 
    "rec_room": {"hp": 40, "armor": 2}, 
    "mess": {"hp": 40, "armor": 2}, 
    "armory": {"hp": 60, "armor": 4}, 
    "fleet_comm": {"hp": 40, "armor": 2}, 
    "fuel_scoop": {"hp": 40, "armor": 2}, 
    "colony_spear": {"hp": 80, "armor": 5}, 
    "docking_collar": {"hp": 100, "armor": 6}, 
    "ladder": {"hp": 25, "armor": 1}, 
    "point_defense": {"hp": 45, "armor": 3}, 
    "smelter": {"hp": 60, "armor": 3}, 
    "kitchen": {"hp": 40, "armor": 2}, 
    "brewery": {"hp": 40, "armor": 2}, 
    "fabricator": {"hp": 50, "armor": 3}, 
    "animal_pen": {"hp": 80, "armor": 2}, 
    "aquaculture_tank": {"hp": 60, "armor": 1},
    "shield_supercharger": {"hp": 45, "armor": 3},
}

const TIER_HP_MULT: Dictionary = {
    "makeshift": 0.6, 
    "standard": 1.0, 
    "advanced": 1.4, 
    "military": 1.8, 
    "cruiser": 2.2, 
}

func init_module_hp(mod: Dictionary) -> void :

    if mod.has("hp") and mod.has("max_hp"):
        return
    var data: Dictionary = mod.get("data", {})
    var mtype: String = data.get("type", "structural")
    var defaults: Dictionary = MODULE_BASE_HP.get(mtype, {"hp": 40, "armor": 2})
    var tier: String = data.get("tier", "standard")

    if tier == "standard" and data.has("min_hull"):
        var mh: String = data.get("min_hull", "")
        if mh == "cruiser":
            tier = "cruiser"
        elif mh == "frigate":
            tier = "advanced"
    var tier_mult: float = TIER_HP_MULT.get(tier, 1.0)

    var stats: Dictionary = data.get("stats", {})
    var base_hp: float = float(stats.get("module_hp", defaults["hp"])) * tier_mult
    var base_armor: float = float(stats.get("module_armor", defaults["armor"]))
    mod["max_hp"] = base_hp
    mod["armor"] = base_armor

    if mod.get("damaged", false):
        mod["hp"] = base_hp * 0.4
    else:
        mod["hp"] = base_hp

func damage_module(mod: Dictionary, amount: float) -> float:

    var hp: float = mod.get("hp", 0)
    if hp <= 0:
        return 0.0
    var armor: float = mod.get("armor", 0)
    var effective: float = maxf(amount - armor, amount * 0.15)
    mod["hp"] = maxf(hp - effective, 0)

    if mod["hp"] < mod.get("max_hp", 1.0) * 0.5:
        mod["damaged"] = true
    if mod["hp"] <= 0:
        mod["destroyed"] = true
        mod["damaged"] = true
    return minf(effective, hp)

func repair_module(mod: Dictionary) -> void :

    mod["hp"] = mod.get("max_hp", 40.0)
    mod["damaged"] = false
    mod.erase("destroyed")

func get_total_ship_hp() -> Array:

    var current: float = 0.0
    var maximum: float = 0.0
    for mod in ship_modules:
        if not mod.has("max_hp"):
            init_module_hp(mod)
        maximum += mod.get("max_hp", 0.0)
        current += maxf(mod.get("hp", mod.get("max_hp", 0.0)), 0.0)
    return [current, maximum]

func damage_ship_at_cell(hex_cell: Vector2i, amount: float) -> float:

    for mod in ship_modules:
        var cells = get_mod_hex_cells(mod)
        if hex_cell in cells:
            return damage_module(mod, amount)

    # No module at exact cell — find nearest alive module to the hit
    return _damage_nearest_module(hex_cell, amount, ship_modules)

func damage_random_module(amount: float) -> float:
    # Fallback for hits with no position data at all (e.g. harpoon stress damage)
    var alive_mods: Array = []
    for mod in ship_modules:
        if mod.get("hp", 1.0) > 0:
            alive_mods.append(mod)
    if alive_mods.is_empty():
        return 0.0
    var target = alive_mods[randi() % alive_mods.size()]
    return damage_module(target, amount)

func _damage_nearest_module(hex_cell: Vector2i, amount: float, modules: Array) -> float:
    var best_mod: Dictionary = {}
    var best_dist: float = INF
    for mod in modules:
        if mod.get("hp", 1.0) <= 0:
            continue
        for cell in get_mod_hex_cells(mod):
            var dx = hex_cell.x - cell.x
            var dy = hex_cell.y - cell.y
            var d = dx * dx + dy * dy
            if d < best_dist:
                best_dist = d
                best_mod = mod
    if best_mod.is_empty():
        return 0.0
    return damage_module(best_mod, amount)




var persistent_stations: Dictionary = {}





var linked_sections: Array = []


const SECONDS_PER_GAME_HOUR: float = 10.0
const HOURS_PER_DAY: int = 24
const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12
var game_hour: int = 6
var game_day: int = 1
var game_month: int = 1
var game_year: int = 1
var game_clock_accumulator: float = 0.0
var total_game_hours: int = 0
signal hour_changed(hour: int, day: int, month: int, year: int)
signal day_changed(day: int, month: int, year: int)


const RESOURCE_TYPES: Dictionary = {
    "ore": {"name": "Iron Ore", "color": [0.6, 0.45, 0.3], "sell_price": 3, "weight": 40}, 
    "crystals": {"name": "Crystals", "color": [0.5, 0.7, 0.95], "sell_price": 8, "weight": 15}, 
    "metals": {"name": "Refined Metals", "color": [0.7, 0.7, 0.75], "sell_price": 5, "weight": 25}, 
    "rare_earth": {"name": "Rare Elements", "color": [0.8, 0.5, 0.9], "sell_price": 15, "weight": 10}, 
    "gas": {"name": "Noble Gas", "color": [0.3, 0.8, 0.7], "sell_price": 6, "weight": 20}, 
    "carbon": {"name": "Carbon Compounds", "color": [0.35, 0.35, 0.4], "sell_price": 4, "weight": 30}, 
    "copper_ore": {"name": "Copper Ore", "color": [0.75, 0.5, 0.3], "sell_price": 4, "weight": 35}, 
    "titanium_ore": {"name": "Titanium Ore", "color": [0.55, 0.6, 0.65], "sell_price": 5, "weight": 30}, 
    "circuits": {"name": "Circuits", "color": [0.3, 0.7, 0.3], "sell_price": 10, "weight": 8}, 
    "alloy": {"name": "Alloy Bars", "color": [0.6, 0.65, 0.75], "sell_price": 8, "weight": 18}, 
    "polymer": {"name": "Polymer Sheets", "color": [0.4, 0.5, 0.6], "sell_price": 7, "weight": 12}, 
    "alcohol": {"name": "Alcohol", "color": [0.7, 0.5, 0.2], "sell_price": 6, "weight": 10}, 
}






const CRAFTING_RECIPES: Dictionary = {

    "conduit_mk1": {"ore": 2, "metals": 1}, 
    "deck_plate": {"metals": 1}, 
    "hallway_mk1": {"metals": 1}, 
    "hallway_long": {"metals": 3}, 
    "deck_ladder_mk1": {"metals": 2, "ore": 1}, 
    "deck_lift_mk1": {"metals": 4, "crystals": 2}, 
    "airlock_mk1": {"metals": 4, "crystals": 2}, 
    "blast_door_mk1": {"metals": 5, "crystals": 1}, 
    "storage_locker_mk1": {"metals": 2}, 
    "officer_cabin_mk1": {"metals": 3, "crystals": 2}, 
    "common_room_mk1": {"metals": 6, "crystals": 3, "polymer": 2}, 
    "observation_deck_mk1": {"metals": 3, "crystals": 3}, 
    "armor_plate_mk1": {"ore": 4, "metals": 2}, 
    "crew_quarters_mk1": {"ore": 3, "metals": 2}, 
    "mess_hall_mk1": {"ore": 2, "metals": 1, "carbon": 1}, 
    "life_support_mk1": {"metals": 2, "gas": 1}, 
    "cargo_bay_mk1": {"ore": 3, "metals": 2}, 
    "brig_mk1": {"ore": 2, "metals": 2}, 
    "research_lab_mk1": {"metals": 5, "crystals": 4, "rare_earth": 2}, 
    "rec_room_mk1": {"ore": 2, "carbon": 1}, 

    "pulse_laser_mk1": {"metals": 3, "crystals": 2}, 
    "autocannon_mk1": {"metals": 4, "ore": 2}, 
    "shield_gen_mk1": {"metals": 3, "crystals": 3}, 
    "sensor_mk1": {"crystals": 3, "metals": 1}, 
    "armory_mk1": {"metals": 3, "ore": 2}, 

    "thruster_mk1": {"metals": 2, "ore": 2, "gas": 1}, 
    "engine_block_mk1": {"metals": 3, "ore": 2}, 
    "micro_reactor": {"metals": 3, "crystals": 1}, 
    "reactor_mk1": {"metals": 5, "crystals": 3, "rare_earth": 1}, 
    "fuel_scoop_mk1": {"metals": 3, "gas": 2}, 
    "mining_laser_mk1": {"metals": 3, "crystals": 2, "ore": 2}, 
    "construction_hangar_mk1": {"metals": 8, "ore": 6, "crystals": 4, "rare_earth": 2}, 
    "basic_workshop": {"metals": 3, "ore": 2, "carbon": 1}, 
    "fabricator_mk1": {"metals": 4, "ore": 3, "carbon": 2, "weaponsmith_tools": 1}, 
    "medbay_mk1": {"metals": 2, "crystals": 2, "carbon": 2}, 
    "hangar_bay_mk1": {"metals": 5, "ore": 3}, 
    "hydroponics_mk1": {"metals": 2, "carbon": 2, "mycelium": 3}, 
    "bridge_mk1": {"metals": 4, "crystals": 3, "rare_earth": 1}, 

    "animal_pen_mk1": {"metals": 3, "ore": 2, "carbon": 1}, 
    "animal_pen_mk2": {"metals": 5, "ore": 3, "carbon": 2, "rare_earth": 1}, 
    "aquaculture_tank": {"metals": 4, "crystals": 2, "carbon": 2}, 
    "cargo_bay_wide_mk1": {"ore": 3, "metals": 2}, 

    "pulse_laser_mk2": {"metals": 5, "crystals": 4, "rare_earth": 1}, 
    "autocannon_mk2": {"metals": 6, "ore": 3, "rare_earth": 1}, 
    "shield_gen_mk2": {"metals": 5, "crystals": 5, "rare_earth": 2}, 
    "thruster_mk2": {"metals": 4, "ore": 3, "gas": 2, "rare_earth": 1}, 
    "ion_thruster_cluster_mk2": {"metals": 5, "ore": 4, "gas": 2, "rare_earth": 1}, 
    "engine_block_mk2": {"metals": 5, "ore": 4, "gas": 1, "rare_earth": 1}, 
    "reactor_mk2": {"metals": 6, "crystals": 4, "rare_earth": 3}, 
    "sensor_mk2": {"crystals": 5, "metals": 2, "rare_earth": 1}, 
    "fuel_scoop_mk2": {"metals": 5, "gas": 4, "rare_earth": 1}, 
    "mining_laser_mk2": {"metals": 5, "crystals": 4, "ore": 3, "rare_earth": 1}, 
    "armor_plate_mk2": {"ore": 6, "metals": 4, "rare_earth": 1}, 
    "armor_plate_array_mk2": {"ore": 8, "metals": 6, "rare_earth": 2}, 
    "repair_module_mk1": {"metals": 4, "crystals": 3, "carbon": 2}, 
    "fabricator_mk2": {"metals": 6, "ore": 4, "carbon": 2, "weaponsmith_tools": 1, "rare_earth": 1}, 
    "warp_thruster_mk1": {"metals": 6, "ore": 4, "gas": 3, "rare_earth": 2}, 
    "warp_thruster_mk2": {"metals": 8, "ore": 6, "gas": 4, "rare_earth": 3}, 
    "mobius_thruster": {"metals": 10, "ore": 8, "gas": 5, "crystals": 3, "rare_earth": 5}, 

    "beam_emitter_mk1": {"metals": 4, "crystals": 5, "rare_earth": 2}, 
    "missile_rack_mk1": {"metals": 5, "ore": 4, "crystals": 2}, 
    "point_defense_mk1": {"metals": 4, "crystals": 3, "rare_earth": 1}, 
    "ecm_jammer_mk1": {"crystals": 5, "rare_earth": 2}, 
    "afterburner_mk1": {"metals": 3, "gas": 4, "rare_earth": 1}, 

    "crew_quarters_mk2": {"ore": 5, "metals": 3, "rare_earth": 1}, 
    "crew_quarters_mk3": {"ore": 7, "metals": 5, "rare_earth": 2}, 
    "mess_hall_mk2": {"ore": 3, "metals": 2, "carbon": 2, "rare_earth": 1}, 
    "medbay_mk2": {"metals": 4, "crystals": 4, "carbon": 3, "rare_earth": 1}, 
    "cargo_bay_mk2": {"ore": 5, "metals": 4, "rare_earth": 1}, 

    "core_pod": {"metals": 4, "ore": 3}, 
    "core_scout": {"metals": 8, "ore": 6}, 
    "core_corvette": {"metals": 14, "ore": 10, "rare_earth": 2}, 
    "core_frigate": {"metals": 20, "ore": 16, "rare_earth": 4, "crystals": 4}, 
    "core_cruiser": {"metals": 40, "ore": 30, "rare_earth": 8, "crystals": 10}, 

    "smelter_mk1": {"metals": 5, "ore": 4, "warpsmith_tools": 1}, 
    "kitchen_mk1": {"metals": 3, "carbon": 2, "cookware": 1}, 
    "brewery_mk1": {"metals": 3, "carbon": 2, "brewers_tools": 1}, 
    "farmers_workshop": {"metals": 3, "carbon": 4, "farming_tools": 1}, 
    "solar_field": {"metals": 4, "crystals": 3, "mycelium": 5}, 

    "makeshift_reactor": {"metals": 2, "warpsmith_tools": 1}, 
    "makeshift_engine": {"metals": 2, "ore": 1}, 
    "makeshift_life_support": {"metals": 1, "carbon": 1}, 
    "makeshift_bridge": {"metals": 2, "warpsmith_tools": 1}, 

    "macro_cannon_mk1": {"metals": 8, "ore": 5, "weaponsmith_tools": 1, "rare_earth": 1}, 
    "lance_battery_mk1": {"metals": 6, "crystals": 6, "weaponsmith_tools": 1, "rare_earth": 3}, 
    "railgun_mk1": {"metals": 10, "crystals": 5, "weaponsmith_tools": 1, "rare_earth": 4}, 
    "torpedo_launcher_mk1": {"metals": 7, "ore": 5, "weaponsmith_tools": 1, "rare_earth": 2}, 
    "hornet_battery_mk1": {"metals": 8, "crystals": 8, "weaponsmith_tools": 1, "rare_earth": 5}, 
}


var pending_barks: Array = []


# Global trigger tags now live on `MvTriggerEngine.global_tags`; use the
# engine's set_global_tag/get_global_tag API. Save/restore hooks in this
# file forward to snapshot_global_tags/restore_global_tags.
var fired_triggers: Array = []
var visited_events: Dictionary = {}


var pending_events: Array = []

const SAVE_DIR: String = "user://saves/"
const MAX_SAVE_SLOTS: int = 5
var current_save_slot: int = 1


func _ready():
    _InputSetup.install()
    var settings_manager := get_node_or_null("/root/SettingsManager")
    if settings_manager != null and settings_manager.has_method("register_input_defaults"):
        settings_manager.call("register_input_defaults")
    _init_starter_inventory()
    _migrate_old_save()

func _input(event: InputEvent):
    detect_input_device(event)

func reset_to_new_game():

    current_system = ""
    visited_systems = []
    discovered_pois = {}
    in_combat = false
    _loaded_from_save = false
    kill_count = 0
    total_kills = 0
    var tuning := _load_tuning()
    credits = int(tuning.get("starting_credits", 1000))
    game_hour = 6
    game_day = 1
    game_month = 1
    game_year = 1
    game_clock_accumulator = 0.0
    total_game_hours = 0
    EncounterManager.reset()
    fuel = float(tuning.get("starting_fuel", 50.0))
    fuel_capacity = float(tuning.get("fuel_capacity", 100.0))
    resources = {}
    resource_capacity = int(tuning.get("resource_capacity", 20))
    debug_mode = false
    npc_ships = {}
    npc_id_counter = 0
    _station_cache.clear()
    faction_reputation = {}
    MvTriggerEngine.clear_global_tags()
    fired_triggers = []
    visited_events = {}
    pending_events = []
    consumed_pois = []
    unlocked_pois = {}
    killed_placed_npcs = {}
    ship_modules = []
    module_inventory = {}
    persistent_stations = {}
    linked_sections = []
    _init_starter_inventory()

func _init_starter_inventory():
    if not module_inventory.is_empty() or not ship_modules.is_empty():
        return
    var mods = DataManager.modules
    if mods.is_empty():
        _init_starter_inventory.call_deferred()
        return
    if start_template_path != "":
        var tmpl_path = start_template_path
        start_template_path = ""
        var result = import_ship(tmpl_path)
        if result.get("ok", false):
            return
        print("[GameManager] Template import failed: ", result.get("error", "unknown"))
    ship_modules = [
        {"id": "conduit_mk1", "grid_pos": Vector2i(0, -1), "deck": 0, "data": mods.get("conduit_mk1", {})}, 
        {"id": "makeshift_reactor", "grid_pos": Vector2i(0, -2), "deck": 0, "data": mods.get("makeshift_reactor", {})}, 
        {"id": "makeshift_life_support", "grid_pos": Vector2i(1, -3), "deck": 0, "data": mods.get("makeshift_life_support", {})}, 
        {"id": "makeshift_bridge", "grid_pos": Vector2i(0, -3), "deck": 0, "data": mods.get("makeshift_bridge", {})}, 
        {"id": "crew_quarters_mk1", "grid_pos": Vector2i(1, -1), "deck": 0, "data": mods.get("crew_quarters_mk1", {}), "rotation": 4}, 
        {"id": "airlock_mk1", "grid_pos": Vector2i(1, 1), "deck": 0, "data": mods.get("airlock_mk1", {})}, 
        {"id": "mess_hall_mk1", "grid_pos": Vector2i(-1, -1), "deck": 0, "data": mods.get("mess_hall_mk1", {}), "rotation": 4}, 
        {"id": "cargo_bay_mk1", "grid_pos": Vector2i(-1, 1), "deck": 0, "data": mods.get("cargo_bay_mk1", {}), "rotation": 4}, 
        {"id": "sensor_mk1", "grid_pos": Vector2i(1, 0), "deck": 0, "data": mods.get("sensor_mk1", {})}, 
        {"id": "makeshift_reactor", "grid_pos": Vector2i(0, 1), "deck": 0, "data": mods.get("makeshift_reactor", {})}, 
        {"id": "makeshift_engine", "grid_pos": Vector2i(0, 2), "deck": 0, "data": mods.get("makeshift_engine", {}), "damaged": true}, 
    ]
    module_inventory = {}
    for mod in ship_modules:
        init_module_hp(mod)
    update_resource_capacity()

var using_controller: bool = false
var controller_aim: Vector2 = Vector2.ZERO
const STICK_DEADZONE: float = 0.15

# When true, UICoordinator hides the legacy combat HUD and shows the new
# Tactical HUD (SCS Meridian re-skin). F10 flips this at runtime; see
# main.gd `_unhandled_input` and UICoordinator.toggle_tactical_hud().
var use_tactical_hud: bool = false



func detect_input_device(event: InputEvent):
    if event is InputEventJoypadButton or event is InputEventJoypadMotion:
        if not using_controller:
            using_controller = true
            Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
    elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
        if using_controller:
            using_controller = false
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func poll_right_stick() -> Vector2:
    var rx = Input.get_action_strength("controller_aim_right") - Input.get_action_strength("controller_aim_left")
    var ry = Input.get_action_strength("controller_aim_down") - Input.get_action_strength("controller_aim_up")
    var raw = Vector2(rx, ry)
    if raw.length() < STICK_DEADZONE:
        return Vector2.ZERO

    var magnitude = (raw.length() - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
    controller_aim = raw.normalized() * clampf(magnitude, 0, 1)
    return controller_aim


func poll_left_stick() -> Vector2:
    var lx = Input.get_action_strength("controller_move_right") - Input.get_action_strength("controller_move_left")
    var ly = Input.get_action_strength("controller_move_down") - Input.get_action_strength("controller_move_up")
    var raw = Vector2(lx, ly)
    if raw.length() < STICK_DEADZONE:
        return Vector2.ZERO
    var magnitude = (raw.length() - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
    return raw.normalized() * clampf(magnitude, 0, 1)


func get_button_prompt(action_name: String) -> String:
    return _InputSetup.format_action_prompt(action_name, using_controller, action_name)







func tick_game_clock(delta: float):


    game_clock_accumulator += delta
    while game_clock_accumulator >= SECONDS_PER_GAME_HOUR:
        game_clock_accumulator -= SECONDS_PER_GAME_HOUR
        game_hour += 1
        total_game_hours += 1
        var new_day = false
        if game_hour >= HOURS_PER_DAY:
            game_hour = 0
            game_day += 1
            new_day = true
            if game_day > DAYS_PER_MONTH:
                game_day = 1
                game_month += 1
                if game_month > MONTHS_PER_YEAR:
                    game_month = 1
                    game_year += 1
        hour_changed.emit(game_hour, game_day, game_month, game_year)
        if new_day:
            day_changed.emit(game_day, game_month, game_year)




func get_clock_string() -> String:

    return "%02d:00 — Day %d, Month %d, Year %d" % [game_hour, game_day, game_month, game_year]

func get_short_clock() -> String:

    return "D%d M%d Y%d %02d:00" % [game_day, game_month, game_year, game_hour]

func _has_placed_module_type(mtype: String) -> bool:
    for mod in ship_modules:
        if mod.get("damaged", false):
            continue
        if mod.get("data", {}).get("type", "") == mtype:
            return true
    return false

func has_construction_hangar() -> bool:

    return _has_placed_module_type("construction_hangar")

func has_docking_collar() -> bool:

    return _has_placed_module_type("docking_collar")

func has_airlock() -> bool:

    return _has_placed_module_type("airlock")

func has_shield_supercharger() -> bool:
    return _has_placed_module_type("shield_supercharger")

func has_sensor() -> bool:
    return _has_placed_module_type("sensor")

func is_module_damaged(mod: Dictionary) -> bool:
    if not mod.has("max_hp"):
        init_module_hp(mod)
    return mod.get("hp", 0) < mod.get("max_hp", 1.0)

func get_damaged_modules() -> Array:
    var result: Array = []
    for mod in ship_modules:
        if not mod.has("max_hp"):
            init_module_hp(mod)
        if mod.get("hp", 0) < mod.get("max_hp", 1.0):
            result.append(mod)
    return result

func get_destroyed_modules() -> Array:
    var result: Array = []
    for mod in ship_modules:
        if mod.get("destroyed", false) or mod.get("hp", 1.0) <= 0:
            result.append(mod)
    return result

func has_hangar() -> bool:
    return _has_placed_module_type("hangar")








@warning_ignore("unused_private_class_variable")
var _occ_cache: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _occ_cache_ids: Dictionary = {}


func buy_module(mod_id: String) -> bool:
    var mod_data = DataManager.modules.get(mod_id, {})
    if mod_data.is_empty():
        return false
    var price: int = int(mod_data.get("buy_price", 0) * get_station_price_mult())
    if price <= 0 or credits < price:
        return false
    credits -= price
    if not module_inventory.has(mod_id):
        module_inventory[mod_id] = 0
    module_inventory[mod_id] += 1
    return true

func sell_module(mod_id: String) -> bool:
    if not module_inventory.has(mod_id) or module_inventory[mod_id] <= 0:
        return false
    var mod_data = DataManager.modules.get(mod_id, {})
    var price: int = int(mod_data.get("sell_price", 0))
    module_inventory[mod_id] -= 1
    if module_inventory[mod_id] <= 0:
        module_inventory.erase(mod_id)
    credits += price
    return true

func add_module(mod_id: String, count: int = 1):
    if not module_inventory.has(mod_id):
        module_inventory[mod_id] = 0
    module_inventory[mod_id] += count

func remove_module(mod_id: String, count: int = 1) -> bool:
    if not module_inventory.has(mod_id) or module_inventory[mod_id] < count:
        return false
    module_inventory[mod_id] -= count
    if module_inventory[mod_id] <= 0:
        module_inventory.erase(mod_id)
    return true



func buy_fuel(amount: float, price: int) -> bool:
    if credits < price:
        return false
    credits -= price
    fuel = minf(fuel + amount, fuel_capacity)
    return true

func consume_fuel(amount: float):
    fuel = maxf(fuel - amount, 0)



func get_total_resources() -> int:
    var total: int = 0
    for r in resources.values():
        total += int(r)
    return total

func add_resource(res_type: String, amount: int) -> int:

    var space = resource_capacity - get_total_resources()
    var added = mini(amount, space)
    if added <= 0:
        return 0
    resources[res_type] = resources.get(res_type, 0) + added
    return added

func remove_resource(res_type: String, amount: int) -> bool:
    if resources.get(res_type, 0) < amount:
        return false
    resources[res_type] -= amount
    if resources[res_type] <= 0:
        resources.erase(res_type)
    return true

func sell_resource(res_type: String, amount: int, station_key: String = "") -> bool:
    var price_per: int
    if station_key != "":
        price_per = get_station_resource_price(station_key, res_type, false)
    else:
        price_per = int(RESOURCE_TYPES.get(res_type, {}).get("sell_price", 1))
    if not remove_resource(res_type, amount):
        return false
    credits += price_per * amount

    if station_key != "":
        station_add_resource(station_key, res_type, amount)
        var econ = get_station_economy(station_key)
        econ["credits"] = maxi(int(econ.get("credits", 0)) - price_per * amount, 0)
    return true

func sell_all_resources(station_key: String = "") -> int:
    var total_earned: int = 0
    for res_type in resources.keys():
        var amount: int = int(resources[res_type])
        var price_per: int
        if station_key != "":
            price_per = get_station_resource_price(station_key, res_type, false)
        else:
            price_per = int(RESOURCE_TYPES.get(res_type, {}).get("sell_price", 1))
        total_earned += price_per * amount
        if station_key != "":
            station_add_resource(station_key, res_type, amount)
    resources.clear()
    if station_key != "":
        var econ = get_station_economy(station_key)
        econ["credits"] = maxi(int(econ.get("credits", 0)) - total_earned, 0)
    credits += total_earned
    return total_earned

func update_resource_capacity():
    resource_capacity = 40
    for mod in ship_modules:
        var data = mod.get("data", {})
        if data.get("type", "") == "cargo":
            resource_capacity += data.get("stats", {}).get("cargo_capacity", 0) * 12





func can_craft(mod_id: String) -> bool:
    if debug_mode:
        return CRAFTING_RECIPES.has(mod_id) or DataManager.modules.has(mod_id)
    var recipe = CRAFTING_RECIPES.get(mod_id, {})
    if recipe.is_empty():
        return false
    for res_type in recipe:
        if resources.get(res_type, 0) < int(recipe[res_type]):
            return false
    return true

func craft_module(mod_id: String) -> bool:
    if not can_craft(mod_id):
        return false
    if not debug_mode:
        var recipe = CRAFTING_RECIPES.get(mod_id, {})
        for res_type in recipe:
            remove_resource(res_type, int(recipe[res_type]))
    add_module(mod_id)
    return true

func get_scoop_rate() -> float:
    var rate: float = 0.0
    for mod in ship_modules:
        var data = mod.get("data", {})
        if data.get("type", "") == "fuel_scoop":
            rate += data.get("stats", {}).get("scoop_rate", 0)
    return rate

func get_mod_hex_size(mod: Dictionary) -> int:

    return int(mod.get("data", {}).get("hex_size", 1))

func get_mod_hex_shape(mod: Dictionary) -> Array:

    var data = mod.get("data", {})
    var hs: int = data.get("hex_size", 1)
    var shape: Array = data.get("hex_shape", HexUtil.default_shape(hs))
    var rot: int = int(mod.get("rotation", 0)) % 6
    if rot > 0:
        for _i in rot:
            shape = HexUtil.rotate_shape_cw(shape)
    return shape

func get_mod_hex_cells(mod: Dictionary) -> Array:

    var gp_raw = mod.get("grid_pos", Vector2i.ZERO)
    var gp: Vector2i
    if gp_raw is Array:
        gp = Vector2i(int(gp_raw[0]), int(gp_raw[1]))
    elif gp_raw is Vector2i:
        gp = gp_raw
    else:
        gp = Vector2i.ZERO
    var shape = get_mod_hex_shape(mod)
    var cells: Array = []
    for offset in shape:
        cells.append(Vector2i(gp.x + offset[0], gp.y + offset[1]))
    return cells

func get_mod_hex_cells_3d(mod: Dictionary) -> Array:

    var cells_2d = get_mod_hex_cells(mod)
    var deck: int = get_mod_deck(mod)
    var cells: Array = []
    for c in cells_2d:
        cells.append(Vector3i(c.x, c.y, deck))
    return cells

func is_pos_on_module(pos: Vector3i, mod: Dictionary) -> bool:

    if pos.z != get_mod_deck(mod):
        return false
    var pos2d = Vector2i(pos.x, pos.y)
    for c in get_mod_hex_cells(mod):
        if c == pos2d:
            return true
    return false

func is_pos_on_or_adjacent_to_module(pos: Vector3i, mod: Dictionary) -> bool:

    if pos.z != get_mod_deck(mod):
        return false
    var pos2d = Vector2i(pos.x, pos.y)
    for c in get_mod_hex_cells(mod):
        if HexUtil.is_same_or_neighbor(pos2d, c):
            return true
    return false






func get_mod_sub_footprint(mod: Dictionary) -> Array:

    var data = mod.get("data", {})

    var custom = data.get("sub_footprint", [])
    if not custom.is_empty():
        return custom
    var mtype: String = data.get("type", "structural")
    return HexUtil.get_sub_footprint(mtype)

func get_mod_open_sub_slots(mod: Dictionary) -> Array:

    var filled = get_mod_sub_footprint(mod)
    var sub_items: Dictionary = mod.get("sub_items", {})
    var open: Array = []
    for i in HexUtil.SUB_HEX_COUNT:
        if i not in filled and not sub_items.has(i) and not sub_items.has(str(i)):
            open.append(i)
    return open

func get_mod_sub_item(mod: Dictionary, sub_index: int) -> Dictionary:

    var sub_items: Dictionary = mod.get("sub_items", {})

    if sub_items.has(sub_index):
        return sub_items[sub_index]
    if sub_items.has(str(sub_index)):
        return sub_items[str(sub_index)]
    return {}

func set_mod_sub_item(mod: Dictionary, sub_index: int, item: Dictionary) -> bool:

    var filled = get_mod_sub_footprint(mod)
    if sub_index in filled:
        return false
    if not mod.has("sub_items"):
        mod["sub_items"] = {}
    mod["sub_items"][sub_index] = item
    return true

func remove_mod_sub_item(mod: Dictionary, sub_index: int) -> Dictionary:

    var sub_items: Dictionary = mod.get("sub_items", {})
    var item: Dictionary = {}
    if sub_items.has(sub_index):
        item = sub_items[sub_index]
        sub_items.erase(sub_index)
    elif sub_items.has(str(sub_index)):
        item = sub_items[str(sub_index)]
        sub_items.erase(str(sub_index))
    return item

func get_all_sub_items_in_cell(mod: Dictionary) -> Array:

    var sub_items: Dictionary = mod.get("sub_items", {})
    var items: Array = []
    for key in sub_items:
        items.append({"sub_index": int(key), "item": sub_items[key]})
    return items

func get_mod_deck(mod: Dictionary) -> int:

    return int(mod.get("deck", 0))

func get_mod_key(mod: Dictionary) -> String:

    return mod.get("id", "") + "@" + str(mod.get("grid_pos", Vector2i.ZERO)) + ":" + str(get_mod_deck(mod))

func get_deck_count() -> int:

    var core_data = DataManager.modules.get(equipped_core, {})
    return int(core_data.get("deck_count", 1))

func get_mine_rate() -> float:
    var rate: float = 0.0
    for mod in ship_modules:
        var data = mod.get("data", {})
        if data.get("type", "") == "mining":
            rate += data.get("stats", {}).get("mine_rate", 0)
    return rate



var _station_cache: Dictionary = {}

func generate_station_data(station_type: String, seed_val: int = 0) -> Dictionary:
    var cache_key = "%s_%d" % [station_type, seed_val]
    if _station_cache.has(cache_key):
        return _station_cache[cache_key]
    var result: Dictionary = _StationGenerator.generate(station_type, seed_val)
    _station_cache[cache_key] = result
    return result

enum FleetOrder{HOLD, ORBIT, PATROL, ESCORT, MINE, SCOOP, TRANSPORT}

@warning_ignore("unused_signal")
signal ship_switched(new_ship_id: String)

func _get_save_path(slot: int) -> String:
    return SAVE_DIR + "save_%d.json" % slot

func delete_save(slot: int) -> bool:
    var path = _get_save_path(slot)
    if not FileAccess.file_exists(path):
        return false
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    return true

func _migrate_old_save():

    var old_path = "user://save_game.json"
    if FileAccess.file_exists(old_path) and not has_save_slot(1):
        DirAccess.make_dir_recursive_absolute(SAVE_DIR)
        var file = FileAccess.open(old_path, FileAccess.READ)
        if file:
            var text = file.get_as_text()
            file.close()
            var new_file = FileAccess.open(_get_save_path(1), FileAccess.WRITE)
            if new_file:
                new_file.store_string(text)
                new_file.close()

func has_save_slot(slot: int) -> bool:
    return FileAccess.file_exists(_get_save_path(slot))

func get_save_info(slot: int) -> Dictionary:

    var path = _get_save_path(slot)
    if not FileAccess.file_exists(path):
        return {}
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        return {}
    var text = file.get_as_text()
    file.close()
    var json = JSON.new()
    if json.parse(text) != OK:
        return {}
    return json.data.get("slot_info", {})





func get_reputation(faction_id: String) -> float:
    return faction_reputation.get(faction_id, 0.0)

func modify_reputation(faction_id: String, amount: float):
    var current = faction_reputation.get(faction_id, 0.0)
    faction_reputation[faction_id] = clampf(current + amount, -100.0, 100.0)

func get_faction_disposition(faction_id: String) -> String:

    var rep = get_reputation(faction_id)
    var factions = DataManager.galaxy_data.get("factions", {})
    var base = factions.get(faction_id, {}).get("disposition", "neutral")

    if rep <= -50:
        return "hostile"
    elif rep >= 50:
        return "friendly"
    return base

func get_faction_ship_colors(faction_id: String) -> Dictionary:
    var factions = DataManager.galaxy_data.get("factions", {})
    var fc = factions.get(faction_id, {}).get("color", [0.5, 0.5, 0.55])
    var base = Color(fc[0], fc[1], fc[2])
    return {
        "primary": [base.r, base.g, base.b],
        "secondary": [base.r * 0.6, base.g * 0.6, base.b * 0.6],
    }

func get_station_price_mult() -> float:


    var sys = DataManager.systems.get(current_system, {})
    var faction_id = sys.get("faction", "independent")
    var disposition = get_faction_disposition(faction_id)
    match disposition:
        "friendly": return 0.9
        "hostile": return 1.2
        _: return 1.0

func init_faction_reputation():

    var factions = DataManager.galaxy_data.get("factions", {})
    for fid in factions:
        if faction_reputation.has(fid):
            continue
        var entry: Dictionary = factions[fid]
        # Authored player_rep_start wins when present (new factions.json
        # schema); fall back to disposition-based default for back-compat
        # with the original hardcoded HUMAN_FACTIONS shape.
        if entry.has("player_rep_start"):
            faction_reputation[fid] = float(entry["player_rep_start"])
            continue
        var base = entry.get("disposition_to_player", entry.get("disposition", "neutral"))
        match base:
            "friendly": faction_reputation[fid] = 25.0
            "hostile": faction_reputation[fid] = -25.0
            _: faction_reputation[fid] = 0.0





const NPC_SHIP_SHAPES: Dictionary = {
    "trader": "freighter", 
    "patrol": "chevron", 
    "wanderer": "dart", 
    "pirate": "dart", 
    "science": "science_vessel", 
}

const BUILTIN_NPC_TEMPLATES: = {
    "argyste_annihilator": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [-1, 4, "thruster_mk1"], [-2, 5, "thruster_mk1"], [0, 3, "thruster_mk1"], [1, 3, "thruster_mk1"], [2, 3, "thruster_mk1"], 
        [1, 2, "reactor_mk1"], [-2, 3, "reactor_mk1"], [0, 2, "sensor_mk1"], [1, 0, "crew_quarters_mk1"], [-1, 1, "crew_quarters_mk1"], 
        [1, -1, "macro_cannon_mk1"], [2, -1, "macro_cannon_mk1"], [3, -1, "macro_cannon_mk1"], [4, -1, "macro_cannon_mk1"], 
        [5, -1, "macro_cannon_mk1"], [6, -1, "macro_cannon_mk1"], [7, -1, "macro_cannon_mk1"], 
        [3, 1, "antimatter_reactor"], [5, 1, "antimatter_reactor"], [-3, 4, "antimatter_reactor"], [-5, 6, "antimatter_reactor"], 
        [-7, 7, "antimatter_reactor"], [8, 0, "antimatter_reactor"], 
        [8, -2, "macro_cannon_mk1"], [0, -1, "macro_cannon_mk1"], [-1, 0, "macro_cannon_mk1"], [-2, 1, "macro_cannon_mk1"], 
        [-3, 2, "macro_cannon_mk1"], [-4, 3, "macro_cannon_mk1"], [-5, 4, "macro_cannon_mk1"], [-6, 5, "macro_cannon_mk1"], 
        [-7, 6, "macro_cannon_mk1"], [-8, 6, "macro_cannon_mk1"], 
        [7, -3, "macro_cannon_mk1"], [5, -3, "macro_cannon_mk1"], [3, -3, "macro_cannon_mk1"], 
        [1, -4, "macro_cannon_mk1"], [-1, -3, "macro_cannon_mk1"], 
        [-7, 4, "macro_cannon_mk1"], [-5, 2, "macro_cannon_mk1"], [-3, 0, "macro_cannon_mk1"], 
        [-1, -4, "macro_cannon_mk1"], [1, -5, "macro_cannon_mk1"], [1, -7, "macro_cannon_mk1"], [-1, -6, "macro_cannon_mk1"], 
        [-2, -2, "macro_cannon_mk1"], [-4, 0, "macro_cannon_mk1"], [-6, 2, "macro_cannon_mk1"], [-8, 4, "macro_cannon_mk1"], 
        [3, -4, "macro_cannon_mk1"], [5, -4, "macro_cannon_mk1"], [7, -4, "macro_cannon_mk1"], 
        [8, -5, "macro_cannon_mk1"], [8, -7, "macro_cannon_mk1"], [-8, 1, "macro_cannon_mk1"], 
        [-3, 5, "thruster_mk2"], [-4, 6, "thruster_mk2"], [-5, 7, "thruster_mk2"], [-6, 8, "thruster_mk2"], 
        [3, 2, "thruster_mk2"], [5, 2, "thruster_mk2"], [4, 2, "thruster_mk2"], [6, 2, "thruster_mk2"], 
    ]}, 
    "cyvral_canine": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [-1, 4, "thruster_mk1"], [-2, 5, "thruster_mk1"], [-3, 6, "thruster_mk1"], [-4, 7, "thruster_mk1"], [-5, 8, "thruster_mk1"], 
        [0, 3, "thruster_mk1"], [1, 3, "thruster_mk1"], [2, 3, "thruster_mk1"], [3, 3, "thruster_mk1"], [4, 3, "thruster_mk1"], [5, 3, "thruster_mk1"], 
        [1, 2, "reactor_mk1"], [3, 2, "reactor_mk1"], [5, 2, "reactor_mk1"], [-2, 3, "reactor_mk1"], [-4, 5, "reactor_mk1"], [-6, 7, "reactor_mk1"], 
        [7, 1, "afterburner_mk1"], [8, 0, "afterburner_mk1"], [-7, 8, "afterburner_mk1"], [-8, 8, "afterburner_mk1"], 
        [-7, 7, "shield_gen_mk2"], [7, 0, "shield_gen_mk2"], [6, 0, "shield_gen_mk2"], [-6, 6, "shield_gen_mk2"], 
        [0, 2, "sensor_mk1"], [1, 0, "crew_quarters_mk1"], [-1, 1, "crew_quarters_mk1"], 
        [3, 0, "life_support_mk1"], [-3, 3, "life_support_mk1"], [5, 0, "medbay_mk1"], [-5, 5, "medbay_mk1"], 
        [7, -1, "railgun_mk1"], [5, -1, "railgun_mk1"], [3, -1, "railgun_mk1"], [1, -1, "railgun_mk1"], 
        [-8, 7, "railgun_mk1"], [-6, 5, "railgun_mk1"], [-4, 3, "railgun_mk1"], [-2, 1, "railgun_mk1"], 
        [3, -3, "railgun_mk1"], [-3, 0, "railgun_mk1"], 
    ]}, 
    "escape_pod": {"core_id": "core_pod", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [0, -1, "conduit_mk1"], [0, -2, "makeshift_reactor"], [1, -3, "makeshift_life_support"], [0, -3, "makeshift_bridge"], 
        [1, -1, "crew_quarters_mk1"], [1, 1, "airlock_mk1"], [-1, -1, "mess_hall_mk1"], [-1, 1, "cargo_bay_mk1"], 
        [1, 0, "sensor_mk1"], [0, 1, "makeshift_reactor"], [0, 2, "makeshift_engine"], 
    ]}, 
    "fastasfuck": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [-1, 4, "thruster_mk1"], [-2, 5, "thruster_mk1"], [-3, 6, "thruster_mk1"], [-4, 7, "thruster_mk1"], [-5, 8, "thruster_mk1"], 
        [0, 3, "thruster_mk1"], [1, 3, "thruster_mk1"], [2, 3, "thruster_mk1"], [3, 3, "thruster_mk1"], [4, 3, "thruster_mk1"], [5, 3, "thruster_mk1"], 
        [1, 2, "reactor_mk1"], [3, 2, "reactor_mk1"], [5, 2, "reactor_mk1"], [-2, 3, "reactor_mk1"], [-4, 5, "reactor_mk1"], [-6, 7, "reactor_mk1"], 
        [7, 1, "afterburner_mk1"], [8, 0, "afterburner_mk1"], [-7, 8, "afterburner_mk1"], [-8, 8, "afterburner_mk1"], 
        [-7, 7, "shield_gen_mk2"], [7, 0, "shield_gen_mk2"], [6, 0, "shield_gen_mk2"], [-6, 6, "shield_gen_mk2"], 
        [0, 2, "sensor_mk1"], [1, 0, "crew_quarters_mk1"], [-1, 1, "crew_quarters_mk1"], 
        [3, 0, "life_support_mk1"], [-3, 3, "life_support_mk1"], [5, 0, "medbay_mk1"], [-5, 5, "medbay_mk1"], 
    ]}, 
    "scouter": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [1, 1, "micro_reactor"], [-1, 2, "micro_reactor"], [0, 2, "micro_reactor"], 
        [1, 0, "crew_quarters_mk1"], [-1, 1, "mess_hall_mk1"], [0, -1, "medbay_mk1"], 
        [1, -2, "life_support_mk1"], [-1, -1, "brig_mk1"], 
        [-2, 0, "pulse_laser_mk1"], [2, -2, "pulse_laser_mk1"], 
        [-2, -1, "armor_plate_mk1"], [-1, -2, "armor_plate_mk1"], [0, -3, "armor_plate_mk1"], [1, -3, "armor_plate_mk1"], 
        [2, -3, "armor_plate_mk1"], [-3, 0, "armor_plate_mk1"], [3, -3, "armor_plate_mk1"], [-3, 1, "armor_plate_mk1"], 
        [-2, 1, "armor_plate_mk1"], [-2, 2, "armor_plate_mk1"], [2, 0, "armor_plate_mk1"], [2, -1, "armor_plate_mk1"], 
        [3, -2, "armor_plate_mk1"], 
        [0, 3, "thruster_mk1"], [1, 2, "sensor_mk1"], 
    ]}, 
    "scoutship": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [0, 2, "common_room_mk1"], [1, 0, "crew_quarters_mk1"], [2, 1, "life_support_mk1"], 
        [-2, 3, "crew_quarters_mk1"], [-3, 3, "medbay_mk1"], [-3, 1, "mess_hall_mk1"], 
        [-2, 4, "micro_reactor"], [2, 2, "micro_reactor"], [-1, 1, "micro_reactor"], 
        [-1, 4, "conduit_mk1"], [1, 3, "conduit_mk1"], [3, 1, "conduit_mk1"], [-3, 4, "conduit_mk1"], 
        [-1, 0, "conduit_mk1"], [0, -1, "conduit_mk1"], [1, -1, "conduit_mk1"], 
        [-2, 0, "sensor_mk1"], [1, -2, "hangar_bay_mk1"], [4, -1, "airlock_mk1"], [2, 0, "cargo_bay_mk1"], 
        [3, -1, "conduit_mk1"], [2, -2, "conduit_mk1"], [3, -2, "conduit_mk1"], [3, -3, "conduit_mk1"], 
        [-1, -1, "conduit_mk1"], [-2, -1, "conduit_mk1"], [0, -3, "bridge_mk1"], [-3, 0, "shield_gen_mk1"], 
        [-1, -2, "conduit_mk1"], 
        [4, -2, "armor_plate_mk1"], [4, -3, "armor_plate_mk1"], [4, -4, "armor_plate_mk1"], 
        [3, -4, "armor_plate_mk1"], [2, -4, "armor_plate_mk1"], [1, -4, "armor_plate_mk1"], [0, -4, "armor_plate_mk1"], 
        [-1, -3, "armor_plate_mk1"], [-2, -2, "armor_plate_mk1"], [-3, -1, "armor_plate_mk1"], 
        [-4, 0, "armor_plate_mk1"], [-4, 1, "armor_plate_mk1"], [-4, 2, "armor_plate_mk1"], [-4, 3, "armor_plate_mk1"], 
        [0, 4, "thruster_mk1"], [4, 0, "thruster_mk1"], [-4, 4, "thruster_mk1"], 
    ]}, 
    "startship": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [1, 1, "micro_reactor"], [-1, 2, "micro_reactor"], [0, 2, "micro_reactor"], 
        [1, 0, "crew_quarters_mk1"], [-1, 1, "mess_hall_mk1"], [0, -1, "medbay_mk1"], 
        [1, -2, "life_support_mk1"], [-1, -1, "brig_mk1"], 
        [-2, 0, "pulse_laser_mk1"], [2, -2, "pulse_laser_mk1"], 
        [-2, -1, "armor_plate_mk1"], [-1, -2, "armor_plate_mk1"], [0, -3, "armor_plate_mk1"], [1, -3, "armor_plate_mk1"], 
        [2, -3, "armor_plate_mk1"], [-3, 0, "armor_plate_mk1"], [3, -3, "armor_plate_mk1"], [-3, 1, "armor_plate_mk1"], 
        [-2, 1, "armor_plate_mk1"], [-2, 2, "armor_plate_mk1"], [2, 0, "armor_plate_mk1"], [2, -1, "armor_plate_mk1"], 
        [3, -2, "armor_plate_mk1"], 
        [1, 2, "sensor_mk1"], [-1, 3, "shield_gen_mk1"], 
        [-1, 4, "thruster_mk1"], [1, 3, "thruster_mk1"], 
        [-2, 3, "armor_plate_mk1"], [2, 1, "armor_plate_mk1"], 
    ]}, 
    "synvic_canine": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [-1, 4, "thruster_mk1"], [-2, 5, "thruster_mk1"], [-3, 6, "thruster_mk1"], [-4, 7, "thruster_mk1"], [-5, 8, "thruster_mk1"], 
        [0, 3, "thruster_mk1"], [1, 3, "thruster_mk1"], [2, 3, "thruster_mk1"], [3, 3, "thruster_mk1"], [4, 3, "thruster_mk1"], [5, 3, "thruster_mk1"], 
        [1, 2, "reactor_mk1"], [3, 2, "reactor_mk1"], [5, 2, "reactor_mk1"], [-2, 3, "reactor_mk1"], [-4, 5, "reactor_mk1"], [-6, 7, "reactor_mk1"], 
        [7, 1, "afterburner_mk1"], [8, 0, "afterburner_mk1"], [-7, 8, "afterburner_mk1"], [-8, 8, "afterburner_mk1"], 
        [-7, 7, "shield_gen_mk2"], [7, 0, "shield_gen_mk2"], [6, 0, "shield_gen_mk2"], [-6, 6, "shield_gen_mk2"], 
        [0, 2, "sensor_mk1"], [1, 0, "crew_quarters_mk1"], [-1, 1, "crew_quarters_mk1"], 
        [3, 0, "life_support_mk1"], [-3, 3, "life_support_mk1"], [5, 0, "medbay_mk1"], [-5, 5, "medbay_mk1"], 
        [7, -1, "railgun_mk1"], [5, -1, "railgun_mk1"], [3, -1, "railgun_mk1"], [1, -1, "railgun_mk1"], 
        [-8, 7, "railgun_mk1"], [-6, 5, "railgun_mk1"], [-4, 3, "railgun_mk1"], [-2, 1, "railgun_mk1"], 
        [-1, -1, "macro_cannon_mk1"], [0, -2, "macro_cannon_mk1"], 
    ]}, 
    "testing1": {"core_id": "core_scout", "combat_style": "standard", "colors": {"primary": [0.3, 0.55, 0.8], "secondary": [0.15, 0.25, 0.45]}, "modules": [
        [1, 1, "micro_reactor"], [-1, 2, "micro_reactor"], [0, 2, "micro_reactor"], 
        [1, 0, "crew_quarters_mk1"], [-1, 1, "mess_hall_mk1"], [0, -1, "medbay_mk1"], 
        [1, -2, "life_support_mk1"], [-1, -1, "brig_mk1"], 
    ]}, 
}

const NPC_TYPE_STATS: Dictionary = {
    "trader": {"max_health": 80, "max_shields": 20, "max_speed": 160, "ship_size": 18}, 
    "patrol": {"max_health": 100, "max_shields": 40, "max_speed": 300, "ship_size": 15}, 
    "wanderer": {"max_health": 50, "max_shields": 10, "max_speed": 280, "ship_size": 12}, 
    "pirate": {"max_health": 70, "max_shields": 20, "max_speed": 360, "ship_size": 14}, 
    "science": {"max_health": 60, "max_shields": 30, "max_speed": 180, "ship_size": 16}, 
}

func generate_npc_ships_for_system(sys_id: String) -> Array:

    if npc_ships.has(sys_id):
        return npc_ships[sys_id]
    var sys_data = DataManager.systems.get(sys_id, {})
    if sys_data.is_empty():
        return []
    var threat = int(sys_data.get("threat_level", 1))
    if threat <= 0:
        npc_ships[sys_id] = []
        return []
    var faction = sys_data.get("faction", "independent")
    var rng = RandomNumberGenerator.new()
    rng.seed = sys_id.hash() + 7777


    var base_count = 3
    if threat <= 1:
        base_count = rng.randi_range(10, 20)
    elif threat <= 3:
        base_count = rng.randi_range(6, 12)
    else:
        base_count = rng.randi_range(3, 6)


    var pois = sys_data.get("pois", [])
    var poi_positions: Array = []
    for poi in pois:
        var orbit_dist = poi.get("orbit_dist", 500)
        var orbit_angle_deg = poi.get("orbit_angle", 0)
        var angle_rad = deg_to_rad(orbit_angle_deg)
        poi_positions.append(Vector2(cos(angle_rad) * orbit_dist, sin(angle_rad) * orbit_dist))

    var ships: Array = []
    var factions_data = DataManager.galaxy_data.get("factions", {})

    for i in base_count:
        npc_id_counter += 1
        var npc_type = _pick_npc_type(rng, threat, faction)
        var ship_faction = _pick_npc_faction(rng, faction, npc_type, factions_data)
        var stats = NPC_TYPE_STATS.get(npc_type, NPC_TYPE_STATS["wanderer"])
        var fc = factions_data.get(ship_faction, {}).get("color", [0.5, 0.5, 0.55])

        var r = clampf(fc[0] + rng.randf_range(-0.08, 0.08), 0.1, 1.0)
        var g = clampf(fc[1] + rng.randf_range(-0.08, 0.08), 0.1, 1.0)
        var b = clampf(fc[2] + rng.randf_range(-0.08, 0.08), 0.1, 1.0)


        var route = _generate_npc_route(rng, npc_type, poi_positions)

        var start_pos = route[0] if not route.is_empty() else Vector2(rng.randf_range(-5000, 5000), rng.randf_range(-5000, 5000))

        var ship_name = _generate_npc_ship_name(rng, npc_type, ship_faction, factions_data)
        var is_hostile = npc_type == "pirate" or factions_data.get(ship_faction, {}).get("disposition", "neutral") == "hostile"

        var ship: Dictionary = {
            "id": "npc_%d" % npc_id_counter, 
            "name": ship_name, 
            "faction": ship_faction, 
            "npc_type": npc_type, 
            "shape": NPC_SHIP_SHAPES.get(npc_type, "chevron"), 
            "color": [r, g, b], 
            "max_health": stats["max_health"], 
            "health": stats["max_health"], 
            "max_shields": stats["max_shields"], 
            "shields": stats["max_shields"], 
            "max_speed": stats["max_speed"], 
            "ship_size": stats["ship_size"], 
            "hostile": is_hostile, 
            "world_pos": [start_pos.x, start_pos.y], 
            "rotation": rng.randf() * TAU, 
            "route": [], 
            "route_index": 0, 
            "system": sys_id, 
            "alive": true, 
        }

        for rp in route:
            ship["route"].append([rp.x, rp.y])
        ships.append(ship)

        ship["modules"] = _generate_npc_modules(rng, npc_type)
        ship["combat_style"] = _last_template_combat_style

        var faction_info = factions_data.get(ship_faction, {})
        ship["ship_style"] = faction_info.get("ship_style", "")

        ship["crew"] = generate_npc_ship_crew(rng, npc_type, ship_faction)

        var job_type: int
        match npc_type:
            "trader": job_type = NpcJob.HAULING
            "patrol": job_type = NpcJob.PATROL
            "pirate": job_type = NpcJob.BOUNTY_HUNT
            "science": job_type = NpcJob.EXPLORING
            _: job_type = NpcJob.IDLE
        ship["job"] = job_type
        ship["job_target"] = ""
        ship["cargo"] = {}
        ship["credits"] = rng.randi_range(50, 500)


    var sys_faction = sys_data.get("faction", "independent")
    var is_isd_system = sys_faction == "isd"
    var is_safe = threat <= 1
    if is_isd_system or is_safe:
        var patrol_count_isd = 2 if is_safe else 3
        if is_isd_system:
            patrol_count_isd = rng.randi_range(3, 5)
        var isd_fc = factions_data.get("isd", {}).get("color", [0.7, 0.2, 0.2])
        for _pi in patrol_count_isd:
            npc_id_counter += 1
            var p_stats = NPC_TYPE_STATS.get("patrol", NPC_TYPE_STATS["wanderer"])
            var pr = clampf(isd_fc[0] + rng.randf_range(-0.05, 0.05), 0.1, 1.0)
            var pg = clampf(isd_fc[1] + rng.randf_range(-0.05, 0.05), 0.1, 1.0)
            var pb = clampf(isd_fc[2] + rng.randf_range(-0.05, 0.05), 0.1, 1.0)
            var p_route = _generate_npc_route(rng, "patrol", poi_positions)
            var p_start = p_route[0] if not p_route.is_empty() else Vector2(rng.randf_range(-4000, 4000), rng.randf_range(-4000, 4000))
            var p_ship: Dictionary = {
                "id": "npc_%d" % npc_id_counter, 
                "name": "ISD %s" % ["Enforcer", "Sentinel", "Warden", "Guardian", "Vanguard"][rng.randi() % 5], 
                "faction": "isd", 
                "npc_type": "patrol", 
                "shape": NPC_SHIP_SHAPES.get("patrol", "chevron"), 
                "color": [pr, pg, pb], 
                "max_health": p_stats["max_health"] * 1.5, 
                "health": p_stats["max_health"] * 1.5, 
                "max_shields": p_stats["max_shields"] * 1.5, 
                "shields": p_stats["max_shields"] * 1.5, 
                "max_speed": p_stats["max_speed"], 
                "ship_size": p_stats["ship_size"] + 2.0, 
                "hostile": false, 
                "is_law_enforcement": true, 
                "world_pos": [p_start.x, p_start.y], 
                "rotation": rng.randf() * TAU, 
                "route": [], 
                "route_index": 0, 
                "system": sys_id, 
                "alive": true, 
            }
            for rp in p_route:
                p_ship["route"].append([rp.x, rp.y])
            p_ship["modules"] = _generate_npc_modules(rng, "patrol")
            p_ship["ship_style"] = factions_data.get("isd", {}).get("ship_style", "")
            p_ship["crew"] = generate_npc_ship_crew(rng, "patrol", "isd")
            p_ship["job"] = NpcJob.PATROL
            p_ship["job_target"] = ""
            p_ship["cargo"] = {}
            p_ship["credits"] = rng.randi_range(100, 300)
            ships.append(p_ship)

    npc_ships[sys_id] = ships
    return ships



func _get_system_station_keys(sys_id: String) -> Array:

    var keys: Array = []
    for sk in persistent_stations:
        if sk.begins_with(sys_id + "_"):
            keys.append(sk)
    return keys

func _find_best_npc_trade(_sys_id: String) -> Dictionary:


    var best: Dictionary = {}
    var best_profit: int = 0
    var all_keys: Array = []
    for sk in persistent_stations:
        all_keys.append(sk)
    for source_key in all_keys:
        var s_econ = get_station_economy(source_key)
        var s_res = s_econ.get("resources", {})
        for rt in TRADE_RESOURCES:
            var stock = int(s_res.get(rt, 0))
            if stock < 3:
                continue
            var buy_price = get_station_resource_price(source_key, rt, true)
            for dest_key in all_keys:
                if dest_key == source_key:
                    continue
                var sell_price = get_station_resource_price(dest_key, rt, false)
                var profit = sell_price - buy_price
                if profit > best_profit:
                    best_profit = profit
                    best = {"source": source_key, "dest": dest_key, "resource": rt, "buy_price": buy_price, "sell_price": sell_price, "profit": profit}
    return best

func tick_npc_jobs_hourly():


    for sys_id in npc_ships:
        var ships: Array = npc_ships[sys_id]
        var sys_station_keys = _get_system_station_keys(sys_id)

        for ship in ships:
            if not ship.get("alive", true):
                continue
            var job: int = int(ship.get("job", NpcJob.IDLE))
            var crew: Array = ship.get("crew", [])
            var cargo: Dictionary = ship.get("cargo", {})


            if job != NpcJob.IDLE and job != NpcJob.DOCKED:
                ship["fuel"] = maxf(ship.get("fuel", 50.0) - 1.0, 0)
                if ship.get("fuel", 0) <= 0:
                    ship["job"] = NpcJob.DOCKED


            for c in crew:
                var needs = c.get("needs", {})
                needs["morale"] = maxf(float(needs.get("morale", 100)) - 0.5, 10)
                needs["hunger"] = maxf(float(needs.get("hunger", 100)) - 2.0, 10)
                c["needs"] = needs


            match job:
                NpcJob.HAULING:

                    var total_cargo: int = 0
                    for rk in cargo:
                        total_cargo += int(cargo[rk])
                    var cargo_cap: int = 20
                    var trade_dest: String = ship.get("trade_dest", "")
                    var trade_res: String = ship.get("trade_resource", "")
                    var travel_hrs: int = int(ship.get("travel_hours", 0))

                    if total_cargo <= 0 and trade_dest == "":

                        var route = _find_best_npc_trade(sys_id)
                        if not route.is_empty():
                            ship["trade_dest"] = route["dest"]
                            ship["trade_resource"] = route["resource"]
                            ship["job_target"] = route["source"]
                            ship["travel_hours"] = 0

                        elif not sys_station_keys.is_empty():
                            var sk = sys_station_keys[randi() % sys_station_keys.size()]
                            var s_econ = get_station_economy(sk)
                            var s_res = s_econ.get("resources", {})
                            for rt in TRADE_RESOURCES:
                                if int(s_res.get(rt, 0)) > 5:
                                    var taken = station_remove_resource(sk, rt, randi_range(2, 4))
                                    if taken > 0:
                                        cargo[rt] = int(cargo.get(rt, 0)) + taken
                                        ship["cargo"] = cargo
                                    break
                    elif total_cargo <= 0 and trade_dest != "":

                        ship["travel_hours"] = travel_hrs + 1
                        if travel_hrs >= 2:

                            var source_key = ship.get("job_target", "")
                            if source_key != "" and persistent_stations.has(source_key):
                                var buy_amount = mini(cargo_cap, int(get_station_economy(source_key).get("resources", {}).get(trade_res, 0)))
                                if buy_amount > 0:
                                    var taken = station_remove_resource(source_key, trade_res, buy_amount)
                                    cargo[trade_res] = int(cargo.get(trade_res, 0)) + taken
                                    ship["cargo"] = cargo

                                    var price = get_station_resource_price(source_key, trade_res, true)
                                    var cost = price * taken
                                    var econ_s = get_station_economy(source_key)
                                    econ_s["credits"] = int(econ_s.get("credits", 0)) + mini(cost, int(ship.get("credits", 0)))
                                    ship["credits"] = maxi(int(ship.get("credits", 0)) - cost, 0)
                                ship["travel_hours"] = 0
                    elif total_cargo > 0:

                        ship["travel_hours"] = travel_hrs + 1
                        if travel_hrs >= 3:

                            var dest_key = trade_dest if trade_dest != "" else (sys_station_keys[randi() % sys_station_keys.size()] if not sys_station_keys.is_empty() else "")
                            var earned: int = 0
                            if dest_key != "" and persistent_stations.has(dest_key):
                                for rk in cargo:
                                    var sell_p = get_station_resource_price(dest_key, rk, false)
                                    earned += int(cargo[rk]) * sell_p
                                    station_add_resource(dest_key, rk, int(cargo[rk]))
                                var d_econ = get_station_economy(dest_key)
                                d_econ["credits"] = maxi(int(d_econ.get("credits", 0)) - earned, 0)
                            else:

                                for rk in cargo:
                                    earned += int(cargo[rk]) * int(RESOURCE_TYPES.get(rk, {}).get("sell_price", 2))
                            ship["credits"] = int(ship.get("credits", 0)) + earned
                            ship["cargo"] = {}
                            ship["trade_dest"] = ""
                            ship["trade_resource"] = ""
                            ship["travel_hours"] = 0

                NpcJob.MINING:

                    var total_cargo: int = 0
                    for rk in cargo:
                        total_cargo += int(cargo[rk])
                    if total_cargo < 15:
                        if randf() < 0.8:
                            var mine_types = ["ore", "crystals", "carbon", "rare_earth", "copper_ore", "titanium_ore"]
                            var rt = mine_types[randi() % mine_types.size()]
                            cargo[rt] = int(cargo.get(rt, 0)) + 1
                            ship["cargo"] = cargo
                    else:

                        var earned: int = 0
                        var dest_key = sys_station_keys[randi() % sys_station_keys.size()] if not sys_station_keys.is_empty() else ""
                        for rk in cargo:
                            if dest_key != "":
                                var sell_p = get_station_resource_price(dest_key, rk, false)
                                earned += int(cargo[rk]) * sell_p
                                station_add_resource(dest_key, rk, int(cargo[rk]))
                            else:
                                earned += int(cargo[rk]) * int(RESOURCE_TYPES.get(rk, {}).get("sell_price", 2))
                        if dest_key != "":
                            var m_econ = get_station_economy(dest_key)
                            m_econ["credits"] = maxi(int(m_econ.get("credits", 0)) - earned, 0)
                        ship["credits"] = int(ship.get("credits", 0)) + earned
                        ship["cargo"] = {}

                NpcJob.PATROL:

                    var pay: int = 2
                    if not sys_station_keys.is_empty():
                        var patrol_sk = sys_station_keys[randi() % sys_station_keys.size()]
                        var p_econ = get_station_economy(patrol_sk)
                        if int(p_econ.get("credits", 0)) >= pay:
                            p_econ["credits"] = int(p_econ.get("credits", 0)) - pay
                            ship["credits"] = int(ship.get("credits", 0)) + pay
                    else:
                        ship["credits"] = int(ship.get("credits", 0)) + pay

                NpcJob.BOUNTY_HUNT:

                    if randf() < 0.15:

                        var stolen_value: int = 0
                        for other in ships:
                            if other == ship or int(other.get("job", -1)) != NpcJob.HAULING:
                                continue
                            var other_cargo = other.get("cargo", {})
                            if other_cargo.is_empty():
                                continue

                            for rk in other_cargo:
                                var steal_amt = maxi(int(int(other_cargo[rk]) * randf_range(0.3, 0.5)), 1)
                                other_cargo[rk] = maxi(int(other_cargo[rk]) - steal_amt, 0)
                                cargo[rk] = int(cargo.get(rk, 0)) + steal_amt
                                stolen_value += steal_amt * int(RESOURCE_TYPES.get(rk, {}).get("sell_price", 2))
                                break
                            ship["cargo"] = cargo
                            break
                        if stolen_value <= 0:
                            ship["credits"] = int(ship.get("credits", 0)) + randi_range(5, 20)

                    var pirate_cargo_total: int = 0
                    for rk in cargo:
                        pirate_cargo_total += int(cargo[rk])
                    if pirate_cargo_total >= 10:
                        var pirate_sk = ""
                        for sk in sys_station_keys:
                            if persistent_stations[sk].get("station_type", "") == "pirate":
                                pirate_sk = sk
                                break
                        var p_earned: int = 0
                        for rk in cargo:
                            if pirate_sk != "":
                                p_earned += int(cargo[rk]) * get_station_resource_price(pirate_sk, rk, false)
                                station_add_resource(pirate_sk, rk, int(cargo[rk]))
                            else:
                                p_earned += int(cargo[rk]) * int(RESOURCE_TYPES.get(rk, {}).get("sell_price", 2))
                        ship["credits"] = int(ship.get("credits", 0)) + p_earned
                        ship["cargo"] = {}

                NpcJob.EXPLORING:

                    ship["credits"] = int(ship.get("credits", 0)) + 1

                NpcJob.DOCKED:

                    if int(ship.get("credits", 0)) >= 20:
                        ship["fuel"] = 50.0
                        ship["credits"] = int(ship.get("credits", 0)) - 20
                        var npc_type = ship.get("npc_type", "wanderer")
                        match npc_type:
                            "trader": ship["job"] = NpcJob.HAULING
                            "patrol": ship["job"] = NpcJob.PATROL
                            "pirate": ship["job"] = NpcJob.BOUNTY_HUNT
                            "science": ship["job"] = NpcJob.EXPLORING
                            _: ship["job"] = NpcJob.IDLE
                    for c in crew:
                        var needs = c.get("needs", {})
                        needs["morale"] = minf(float(needs.get("morale", 50)) + 2.0, 100)
                        needs["hunger"] = minf(float(needs.get("hunger", 50)) + 5.0, 100)
                        c["needs"] = needs


            if job != NpcJob.DOCKED and ship.get("fuel", 50.0) < 5.0 and int(ship.get("credits", 0)) >= 20:
                ship["fuel"] = 50.0
                ship["credits"] = int(ship.get("credits", 0)) - 20


var _npc_template_cache: Dictionary = {}
var _npc_templates_loaded: bool = false

func _load_npc_templates() -> Array:

    if _npc_templates_loaded:
        return _npc_template_cache.values()
    _npc_templates_loaded = true
    _npc_template_cache.clear()

    for tname in BUILTIN_NPC_TEMPLATES:
        var bt = BUILTIN_NPC_TEMPLATES[tname]

        var modules: Array = []
        for entry in bt["modules"]:
            modules.append({"id": entry[2], "grid_pos": [entry[0], entry[1]], "deck": 0})
        _npc_template_cache[tname] = {
            "name": tname, 
            "core_id": bt.get("core_id", "core_scout"), 
            "combat_style": bt.get("combat_style", "standard"), 
            "colors": bt.get("colors", {}), 
            "modules": modules, 
        }

    for tdir in ["res://Space/data/npc_templates/", "user://npc_templates/"]:
        var dir = DirAccess.open(tdir)
        if not dir:
            continue
        dir.list_dir_begin()
        var fname = dir.get_next()
        while fname != "":
            if fname.ends_with(".json") and fname != "_manifest.json" and not fname.ends_with("_recording.json"):
                var file = FileAccess.open(tdir + fname, FileAccess.READ)
                if file:
                    var json = JSON.new()
                    if json.parse(file.get_as_text()) == OK:
                        var data = json.data
                        if data is Dictionary and data.has("modules"):
                            var base = fname.get_basename()
                            # Check for an associated AI recording
                            var rec_path = _find_template_recording(base)
                            if rec_path != "":
                                data["recording_path"] = rec_path
                            _npc_template_cache[base] = data
                    file.close()
            fname = dir.get_next()
    print("[GameManager] Loaded %d NPC templates (%d built-in)" % [_npc_template_cache.size(), BUILTIN_NPC_TEMPLATES.size()])
    return _npc_template_cache.values()

func reload_npc_templates():

    _npc_templates_loaded = false
    _load_npc_templates()

func get_builtin_template_names() -> Array:

    return BUILTIN_NPC_TEMPLATES.keys()

func get_template_by_name(tname: String) -> Dictionary:

    _load_npc_templates()
    return _npc_template_cache.get(tname, {})

func _find_template_recording(base_name: String) -> String:
    # Check combat_recordings dir first, then npc_templates dir
    var paths = [
        "user://combat_recordings/%s.json" % base_name,
        "res://Space/data/npc_templates/%s_recording.json" % base_name,
    ]
    for p in paths:
        if FileAccess.file_exists(p):
            return p
    return ""

func load_template_recording(template_name: String) -> CombatRecording:
    var safe_name = template_name.replace(" ", "_").to_lower()
    var tmpl = get_template_by_name(safe_name)
    var rec_path = tmpl.get("recording_path", "")
    if rec_path == "":
        rec_path = _find_template_recording(safe_name)
    if rec_path == "":
        return null
    var rec = CombatRecording.new()
    if rec.load_from_file(rec_path):
        return rec
    return null

func get_template_list() -> Array:

    var result: Array = []

    for dir_path in ["user://npc_templates/", SHIP_EXPORT_DIR]:
        var dir = DirAccess.open(dir_path)
        if not dir:
            continue
        dir.list_dir_begin()
        var fname = dir.get_next()
        while fname != "":
            if fname.ends_with(".json"):
                var file = FileAccess.open(dir_path + fname, FileAccess.READ)
                if file:
                    var json = JSON.new()
                    if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
                        var d: Dictionary = json.data
                        if d.has("modules"):
                            result.append({
                                "name": d.get("name", fname.get_basename()), 
                                "filename": fname, 
                                "path": dir_path + fname, 
                                "core_id": d.get("core_id", "core_pod"), 
                                "module_count": d.get("modules", []).size(), 
                            })
                    file.close()
            fname = dir.get_next()
    return result

func _generate_npc_modules(rng: RandomNumberGenerator, npc_type: String) -> Array:






    _last_template_combat_style = "standard"


    var saved = _load_npc_templates()
    if not saved.is_empty():
        var pick = saved[rng.randi() % saved.size()]
        _last_template_combat_style = pick.get("combat_style", "standard")
        var tmpl_modules: Array = []
        for i in pick["modules"].size():
            var entry = pick["modules"][i]
            var gp = entry.get("grid_pos", [0, 0])

            var mod_id = entry.get("id", "")
            var mod_data = DataManager.modules.get(mod_id, {})
            var mod_type = mod_data.get("type", entry.get("type", "armor"))
            tmpl_modules.append({
                "id": "npc_mod_%d" % i, 
                "grid_pos": [gp[0], gp[1]], 
                "deck": 0, 
                "data": mod_data.duplicate() if not mod_data.is_empty() else {"type": mod_type, "hex_size": 1}, 
            })
        return tmpl_modules










    var layout: Array = []

    match npc_type:
        "trader":


            match rng.randi() % 3:
                0:
                    layout = [

                        [0, 0, "reactor"], 

                        [0, -1, "quarters"], [1, -1, "cargo"], 
                        [1, 0, "cargo"], [-1, 0, "cargo"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 

                        [0, -2, "cargo"], [1, -2, "cargo"], [2, -2, "cargo"], 
                        [2, -1, "fuel_tank"], [2, 0, "cargo"], 
                        [-2, 0, "cargo"], [-2, 1, "cargo"], 
                        [-2, 2, "fuel_tank"], [-1, 2, "engine"], [0, 2, "engine"], 
                        [1, 1, "cargo"], [-1, -1, "cargo"], 
                    ]
                1:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "cargo"], [1, -1, "quarters"], 
                        [1, 0, "cargo"], [-1, 0, "cargo"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                        [0, -2, "cargo"], [1, -2, "cargo"], [2, -2, "fuel_tank"], 
                        [2, -1, "cargo"], [2, 0, "cargo"], 
                        [-2, 0, "cargo"], [-2, 1, "fuel_tank"], 
                        [-2, 2, "cargo"], [-1, 2, "engine"], [0, 2, "engine"], 
                        [1, 1, "cargo"], [-1, -1, "cargo"], 
                    ]
                2:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "cargo"], [1, -1, "cargo"], 
                        [1, 0, "cargo"], [-1, 0, "quarters"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                        [0, -2, "fuel_tank"], [1, -2, "cargo"], [2, -2, "cargo"], 
                        [2, -1, "cargo"], [2, 0, "cargo"], 
                        [-2, 0, "cargo"], [-2, 1, "cargo"], 
                        [-2, 2, "engine"], [-1, 2, "engine"], [0, 2, "fuel_tank"], 
                        [1, 1, "cargo"], [-1, -1, "cargo"], 
                    ]
        "patrol":

            match rng.randi() % 3:
                0:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "weapon"], [1, -1, "weapon"], 
                        [1, 0, "shield"], [-1, 0, "armor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                1:
                    layout = [
                        [0, 0, "shield"], 
                        [0, -1, "weapon"], [1, -1, "weapon"], 
                        [1, 0, "armor"], [-1, 0, "reactor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                2:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "weapon"], [1, -1, "shield"], 
                        [1, 0, "weapon"], [-1, 0, "armor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
        "wanderer":

            match rng.randi() % 3:
                0:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "cargo"], [1, -1, "fuel_tank"], 
                        [1, 0, "cargo"], [-1, 0, "cargo"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                1:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "fuel_tank"], [1, -1, "cargo"], 
                        [1, 0, "cargo"], [-1, 0, "quarters"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                2:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "cargo"], [1, -1, "cargo"], 
                        [1, 0, "fuel_tank"], [-1, 0, "cargo"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
        "pirate":

            match rng.randi() % 3:
                0:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "weapon"], [1, -1, "weapon"], 
                        [1, 0, "armor"], [-1, 0, "armor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                1:
                    layout = [
                        [0, 0, "armor"], 
                        [0, -1, "weapon"], [1, -1, "weapon"], 
                        [1, 0, "reactor"], [-1, 0, "weapon"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                2:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "weapon"], [1, -1, "armor"], 
                        [1, 0, "weapon"], [-1, 0, "weapon"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
        "science":

            match rng.randi() % 3:
                0:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "sensor"], [1, -1, "sensor"], 
                        [1, 0, "sensor"], [-1, 0, "quarters"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                1:
                    layout = [
                        [0, 0, "sensor"], 
                        [0, -1, "sensor"], [1, -1, "quarters"], 
                        [1, 0, "reactor"], [-1, 0, "sensor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]
                2:
                    layout = [
                        [0, 0, "reactor"], 
                        [0, -1, "sensor"], [1, -1, "sensor"], 
                        [1, 0, "quarters"], [-1, 0, "sensor"], 
                        [0, 1, "engine"], [-1, 1, "engine"], 
                    ]


    var weapon_pool: Array
    match npc_type:
        "pirate":
            weapon_pool = ["pulse_laser_mk1", "autocannon_mk1", "pulse_laser_mk2", "autocannon_mk1"]
        "patrol":
            weapon_pool = ["pulse_laser_mk1", "autocannon_mk1", "pulse_laser_mk1"]
        _:
            weapon_pool = ["pulse_laser_mk1"]

    var modules: Array = []
    for i in layout.size():
        var entry = layout[i]
        var entry_type = entry[2]

        if entry_type == "weapon":
            entry_type = weapon_pool[rng.randi() % weapon_pool.size()]

        var mod_data = DataManager.modules.get(entry_type, {})
        if not mod_data.is_empty():
            modules.append({
                "id": entry_type, 
                "grid_pos": [entry[0], entry[1]], 
                "deck": 0, 
                "data": mod_data.duplicate(), 
            })
        else:
            modules.append({
                "id": "npc_mod_%d" % i, 
                "grid_pos": [entry[0], entry[1]], 
                "deck": 0, 
                "data": {"type": entry_type, "hex_size": 1}, 
            })
    return modules

func _pick_npc_type(rng: RandomNumberGenerator, threat: int, _faction: String) -> String:
    var roll = rng.randf()
    if threat >= 4:

        if roll < 0.5: return "pirate"
        elif roll < 0.7: return "patrol"
        elif roll < 0.85: return "wanderer"
        else: return "trader"
    elif threat >= 2:
        if roll < 0.15: return "pirate"
        elif roll < 0.35: return "patrol"
        elif roll < 0.55: return "trader"
        elif roll < 0.75: return "wanderer"
        else: return "science"
    elif threat >= 1:

        if roll < 0.35: return "trader"
        elif roll < 0.6: return "patrol"
        elif roll < 0.8: return "wanderer"
        else: return "science"
    else:

        if roll < 0.4: return "trader"
        elif roll < 0.7: return "patrol"
        elif roll < 0.85: return "science"
        else: return "wanderer"

func _pick_npc_faction(rng: RandomNumberGenerator, sys_faction: String, npc_type: String, factions: Dictionary) -> String:
    if npc_type == "pirate":

        return "fringe"

    if rng.randf() < 0.6:
        return sys_faction
    var keys = factions.keys()
    if keys.is_empty():
        return sys_faction
    return keys[rng.randi() % keys.size()]

func _generate_npc_route(rng: RandomNumberGenerator, npc_type: String, poi_positions: Array) -> Array:
    var route: Array = []
    match npc_type:
        "trader":

            if poi_positions.size() >= 2:
                var shuffled = poi_positions.duplicate()
                shuffled.shuffle()
                for i in mini(shuffled.size(), 3):
                    route.append(shuffled[i] + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300)))
            else:
                for i in 3:
                    route.append(Vector2(rng.randf_range(-5000, 5000), rng.randf_range(-5000, 5000)))
        "patrol":

            var center = poi_positions[0] if not poi_positions.is_empty() else Vector2.ZERO
            for i in 4:
                var angle = i * TAU / 4.0 + rng.randf_range(-0.3, 0.3)
                var dist = rng.randf_range(1200, 3000)
                route.append(center + Vector2.from_angle(angle) * dist)
        "pirate":

            for i in 3:
                var angle = rng.randf() * TAU
                var dist = rng.randf_range(4000, 8000)
                route.append(Vector2.from_angle(angle) * dist)

            route.append(Vector2(rng.randf_range(-1500, 1500), rng.randf_range(-1500, 1500)))
        "science":

            if not poi_positions.is_empty():
                var target = poi_positions[rng.randi() % poi_positions.size()]
                for i in 4:
                    var angle = i * TAU / 4.0
                    route.append(target + Vector2.from_angle(angle) * rng.randf_range(500, 1200))
            else:
                for i in 3:
                    route.append(Vector2(rng.randf_range(-3000, 3000), rng.randf_range(-3000, 3000)))
        _:
            for i in 4:
                var angle = rng.randf() * TAU
                var dist = rng.randf_range(2000, 7000)
                route.append(Vector2.from_angle(angle) * dist)
    return route

const NPC_SHIP_PREFIXES: Array = ["ISS", "CSV", "MV", "TCS", "RSV", "SS", "HSS", "FV", 
    "RV", "DSV", "ACS", "PSV", "GSV", "CRV", "MSV", "KSV", 
]
const NPC_SHIP_NAMES: Array = [
    "Wanderer", "Horizon", "Venture", "Prospect", "Dawn Treader", 
    "Iron Wake", "Star Drifter", "Long Haul", "Quiet Storm", "Deep Current", 
    "Nimbus", "Outreach", "Far Sight", "Relay", "Steadfast", 
    "Pilgrim", "Salvage King", "Black Fin", "Red Keel", "Silver Thread", 
    "Dustrunner", "Nebula Chaser", "Meridian", "Apex", "Crosswind", 
    "Sundog", "Icebreaker", "Anvil", "Whisper", "Bulwark", 
    "Starfall", "Tempest", "Vagabond", "Iron Maiden", "Profit Margin", 
    "Last Chance", "Paper Tiger", "Dead Reckoning", "Hard Bargain", "Rough Cut", 
    "Cold Comfort", "Tall Order", "Razor's Edge", "Low Orbit", "Scrap Heap", 
    "Turncoat", "Bottom Line", "Clean Sweep", "Blind Spot", "Dark Horse", 
    "Long Shot", "Free Agent", "Tin Can", "Dry Dock", "Clear Sky", 
    "Bolt Cutter", "Split Decision", "Heavy Lifter", "Cargo King", "Hull Breach", 
]

func _generate_npc_ship_name(rng: RandomNumberGenerator, _npc_type: String, _faction: String, _factions: Dictionary) -> String:
    var prefix = NPC_SHIP_PREFIXES[rng.randi() % NPC_SHIP_PREFIXES.size()]
    var ship_name = NPC_SHIP_NAMES[rng.randi() % NPC_SHIP_NAMES.size()]
    return "%s %s" % [prefix, ship_name]

func get_npc_ships_in_system(sys_id: String) -> Array:
    return npc_ships.get(sys_id, [])

func remove_npc_ship(npc_id: String, sys_id: String):
    if not npc_ships.has(sys_id):
        return
    for i in range(npc_ships[sys_id].size() - 1, -1, -1):
        if npc_ships[sys_id][i].get("id") == npc_id:
            npc_ships[sys_id].remove_at(i)
            break

func save_game(slot: int = -1) -> bool:
    if slot < 0:
        slot = current_save_slot
    current_save_slot = slot
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)
    var hull_data = DataManager.modules.get(equipped_core, {})
    var sys_data = DataManager.systems.get(current_system, {})
    var save_data = {
        "ship_modules": _serialize_modules(), 
        "module_inventory": module_inventory, 
        "current_system": current_system, 
        "visited_systems": visited_systems, 
        "active_pack_id": MvPackLoader.current_pack.pack_id if MvPackLoader.current_pack != null else "",
        "planetary_state": PlanetaryInterface.snapshot_all() if PlanetaryInterface != null and PlanetaryInterface.has_method("snapshot_all") else {},
        "discovered_pois": discovered_pois, 
        "kill_count": kill_count, 
        "total_kills": total_kills, 
        "credits": credits, 
        "ship_color_primary": [ship_color_primary.r, ship_color_primary.g, ship_color_primary.b],
        "ship_color_secondary": [ship_color_secondary.r, ship_color_secondary.g, ship_color_secondary.b],
        "tags": MvTriggerEngine.snapshot_global_tags(),
        "fired_triggers": fired_triggers, 
        "visited_events": visited_events, 
        "pending_events": pending_events, 
        "equipped_core": equipped_core, 
        "fuel": fuel, 
        "resources": resources, 
        "debug_mode": debug_mode, 
        "npc_ships": npc_ships, 
        "npc_id_counter": npc_id_counter, 
        "faction_reputation": faction_reputation, 
        "consumed_pois": consumed_pois,
        "unlocked_pois": unlocked_pois,
        "killed_placed_npcs": killed_placed_npcs,
        "game_hour": game_hour,
        "game_day": game_day, 
        "game_month": game_month, 
        "game_year": game_year, 
        "total_game_hours": total_game_hours, 
        "galaxy_seed": DataManager.galaxy_seed, 
        "galaxy_size": DataManager.galaxy_size, 
        "save_time": Time.get_unix_time_from_system(), 
        "encounter_state": EncounterManager.get_save_data(),
        "persistent_stations": persistent_stations, 
        "linked_sections": _serialize_linked_sections(), 
        "save_version": 3, 
        "save_slot": slot, 
        "slot_info": {
            "hull_name": hull_data.get("name", "Unknown"), 
            "system_name": sys_data.get("name", "Unknown"), 
            "credits": credits, 
            "crew_count": 0, 
        }, 
    }
    var file = FileAccess.open(_get_save_path(slot), FileAccess.WRITE)
    if not file:
        push_error("Failed to open save file for writing")
        return false
    file.store_string(JSON.stringify(save_data, "\t"))
    file.close()
    return true

func load_game(slot: int = -1) -> bool:
    if slot < 0:
        slot = current_save_slot
    var path = _get_save_path(slot)
    if not FileAccess.file_exists(path):
        return false
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        return false
    var text = file.get_as_text()
    file.close()
    var json = JSON.new()
    if json.parse(text) != OK:
        push_error("Save file parse error: " + json.get_error_message())
        return false
    current_save_slot = slot
    var data: Dictionary = json.data
    ship_modules = _deserialize_modules(data.get("ship_modules", []))
    module_inventory = data.get("module_inventory", {})
    current_system = data.get("current_system", "")
    visited_systems = data.get("visited_systems", [])
    if PlanetaryInterface != null and PlanetaryInterface.has_method("restore_all"):
        var planetary_state_v: Variant = data.get("planetary_state", {})
        if typeof(planetary_state_v) == TYPE_DICTIONARY:
            PlanetaryInterface.restore_all(planetary_state_v)
    discovered_pois = data.get("discovered_pois", {})
    kill_count = data.get("kill_count", 0)
    total_kills = data.get("total_kills", 0)
    credits = data.get("credits", 500)
    var pc = data.get("ship_color_primary", [0.3, 0.55, 0.8])
    ship_color_primary = Color(pc[0], pc[1], pc[2])
    var sc = data.get("ship_color_secondary", [0.15, 0.25, 0.45])
    ship_color_secondary = Color(sc[0], sc[1], sc[2])
    invalidate_module_sprites()
    MvTriggerEngine.restore_global_tags(data.get("tags", {}))
    fired_triggers = data.get("fired_triggers", [])
    visited_events = data.get("visited_events", {})
    pending_events = data.get("pending_events", [])
    equipped_core = data.get("equipped_core", "core_pod")
    consumed_pois = data.get("consumed_pois", [])
    var loaded_unlocked_v: Variant = data.get("unlocked_pois", {})
    unlocked_pois = loaded_unlocked_v if typeof(loaded_unlocked_v) == TYPE_DICTIONARY else {}
    killed_placed_npcs = data.get("killed_placed_npcs", {})
    game_hour = data.get("game_hour", 6)
    game_day = data.get("game_day", 1)
    game_month = data.get("game_month", 1)
    game_year = data.get("game_year", 1)
    total_game_hours = data.get("total_game_hours", 0)
    game_clock_accumulator = 0.0
    EncounterManager.load_save_data(data.get("encounter_state", {}))
    fuel = data.get("fuel", 100.0)
    resources = data.get("resources", {})

    var save_time: float = data.get("save_time", 0.0)
    if save_time > 0:
        var elapsed_sec = clampf(Time.get_unix_time_from_system() - save_time, 0.0, 86400.0)
        var elapsed_hours = int(elapsed_sec / SECONDS_PER_GAME_HOUR)
        elapsed_hours = mini(elapsed_hours, 720)
        for _h in elapsed_hours:
            game_hour += 1
            total_game_hours += 1
            if game_hour >= HOURS_PER_DAY:
                game_hour = 0
                game_day += 1

                if game_day > DAYS_PER_MONTH:
                    game_day = 1
                    game_month += 1
                    if game_month > MONTHS_PER_YEAR:
                        game_month = 1
                        game_year += 1

            tick_npc_jobs_hourly()

    debug_mode = data.get("debug_mode", false)
    npc_ships = data.get("npc_ships", {})
    npc_id_counter = data.get("npc_id_counter", 0)
    faction_reputation = data.get("faction_reputation", {})

    # Procedural saves used to call DataManager.generate_new_galaxy here
    # to reconstitute the seeded galaxy. With procedural deleted, saves
    # are pack-based; the active pack's authored systems are loaded by
    # MvPackLoader at boot, so nothing needs to be regenerated. Old
    # procedural saves are unloadable.
    persistent_stations = data.get("persistent_stations", {})

    for sk in persistent_stations:
        _ensure_station_economy(sk)
    linked_sections = _deserialize_linked_sections(data.get("linked_sections", []))

    for mod in ship_modules:
        if not mod.has("max_hp"):
            init_module_hp(mod)
    update_resource_capacity()
    _loaded_from_save = true
    return true

func has_save() -> bool:

    for i in range(1, MAX_SAVE_SLOTS + 1):
        if has_save_slot(i):
            return true
    return false

func _serialize_modules() -> Array:
    var result: Array = []
    for mod in ship_modules:
        var gp = mod.get("grid_pos", Vector2i(0, 0))
        var entry = {
            "id": mod.get("id", ""), 
            "grid_pos": [gp.x, gp.y], 
            "deck": get_mod_deck(mod), 
        }
        if mod.get("damaged", false):
            entry["damaged"] = true
        if mod.get("destroyed", false):
            entry["destroyed"] = true

        if mod.has("hp"):
            entry["hp"] = mod["hp"]
        if mod.has("max_hp"):
            entry["max_hp"] = mod["max_hp"]
        if mod.has("armor"):
            entry["armor"] = mod["armor"]
        var rot = int(mod.get("rotation", 0))
        if rot > 0:
            entry["rotation"] = rot

        var sub_items: Dictionary = mod.get("sub_items", {})
        if not sub_items.is_empty():
            var si_out: Dictionary = {}
            for key in sub_items:
                si_out[str(key)] = {"id": sub_items[key].get("id", "")}
            entry["sub_items"] = si_out
        result.append(entry)
    return result

func _deserialize_modules(data: Array) -> Array:
    var result: Array = []
    for entry in data:
        var id: String = entry.get("id", "")
        var gp = entry.get("grid_pos", [0, 0])
        var mod = {
            "id": id, 
            "grid_pos": Vector2i(int(gp[0]), int(gp[1])), 
            "deck": int(entry.get("deck", 0)), 
            "data": DataManager.modules.get(id, {}), 
        }
        if entry.get("damaged", false):
            mod["damaged"] = true
        if entry.get("destroyed", false):
            mod["destroyed"] = true

        if entry.has("hp") and entry.has("max_hp"):
            mod["hp"] = float(entry["hp"])
            mod["max_hp"] = float(entry["max_hp"])
            mod["armor"] = float(entry.get("armor", 0))
        else:
            init_module_hp(mod)

        var rot = int(entry.get("rotation", 0))
        if rot == 0 and entry.get("rotated", false):
            rot = 1
        if rot > 0:
            mod["rotation"] = rot

        var si_saved: Dictionary = entry.get("sub_items", {})
        if not si_saved.is_empty():
            var si: Dictionary = {}
            for key in si_saved:
                var item_id: String = si_saved[key].get("id", "") if si_saved[key] is Dictionary else str(si_saved[key])
                if item_id != "" and DataManager.modules.has(item_id):
                    si[int(key)] = {"id": item_id, "data": DataManager.modules[item_id]}
            if not si.is_empty():
                mod["sub_items"] = si
        result.append(mod)
    return result

const SHIP_EXPORT_DIR: String = "user://ship_exports/"

func export_ship(filename: String) -> String:

    DirAccess.make_dir_recursive_absolute(SHIP_EXPORT_DIR)
    var safe_name = filename.strip_edges().replace(" ", "_").to_lower()
    if safe_name.is_empty():
        safe_name = "ship_export"
    if not safe_name.ends_with(".json"):
        safe_name += ".json"
    var export_data = {
        "export_version": 1, 
        "name": filename.strip_edges(), 
        "core_id": equipped_core, 
        "modules": _serialize_modules(), 
        "colors": {
            "primary": [ship_color_primary.r, ship_color_primary.g, ship_color_primary.b],
            "secondary": [ship_color_secondary.r, ship_color_secondary.g, ship_color_secondary.b],
        },
    }
    var path = SHIP_EXPORT_DIR + safe_name
    var file = FileAccess.open(path, FileAccess.WRITE)
    if not file:
        push_error("[ShipExport] Failed to write: " + path)
        return ""
    file.store_string(JSON.stringify(export_data, "\t"))
    file.close()
    print("[ShipExport] Exported ship to: ", path)
    return path

func import_ship(path: String) -> Dictionary:

    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "File not found: " + path}
    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        return {"ok": false, "error": "Cannot open file: " + path}
    var json = JSON.new()
    var err = json.parse(file.get_as_text())
    file.close()
    if err != OK:
        return {"ok": false, "error": "JSON parse error: " + json.get_error_message()}
    var data: Dictionary = json.data
    if not data is Dictionary or not data.has("modules"):
        return {"ok": false, "error": "Invalid ship file (missing modules)"}
    var version = int(data.get("export_version", 0))
    var core_id: String = data.get("core_id", "")
    if core_id == "" or not DataManager.modules.has(core_id):
        return {"ok": false, "error": "Unknown core: " + core_id}
    equipped_core = core_id
    ship_modules = _deserialize_modules(data.get("modules", []))
    var colors = data.get("colors", {})
    if not colors.is_empty():
        var pc = colors.get("primary", [ship_color_primary.r, ship_color_primary.g, ship_color_primary.b])
        ship_color_primary = Color(pc[0], pc[1], pc[2])
        var sc = colors.get("secondary", [ship_color_secondary.r, ship_color_secondary.g, ship_color_secondary.b])
        ship_color_secondary = Color(sc[0], sc[1], sc[2])

    if version == 0:
        if data.has("primary_color"):
            var pc = data["primary_color"]
            ship_color_primary = Color(pc[0], pc[1], pc[2])
        if data.has("secondary_color"):
            var sc = data["secondary_color"]
            ship_color_secondary = Color(sc[0], sc[1], sc[2])
    invalidate_module_sprites()
    update_resource_capacity()
    print("[ShipImport] Imported ship '%s' (v%d): %d modules, core=%s" % [data.get("name", "?"), version, ship_modules.size(), core_id])
    return {"ok": true, "name": data.get("name", ""), "module_count": ship_modules.size()}





func get_or_create_station(station_key: String, station_type: String, seed_val: int) -> Dictionary:

    if persistent_stations.has(station_key):
        return persistent_stations[station_key]

    var data = generate_station_data(station_type, seed_val)
    data["station_key"] = station_key
    data["station_type"] = station_type
    data["faction"] = _get_station_faction(station_key)
    data["hostile"] = false

    for mod in data.get("modules", []):
        if not mod.has("data"):
            mod["data"] = DataManager.modules.get(mod.get("id", ""), {"type": "structural"})
        init_module_hp(mod)

    _compute_station_stats(data)

    _init_station_economy(data)
    persistent_stations[station_key] = data
    return data

func _get_station_faction(station_key: String) -> String:

    for sys_id in DataManager.systems:
        var sys = DataManager.systems[sys_id]
        for poi in sys.get("pois", []):
            var key = "%s_%s" % [poi.get("type", ""), poi.get("name", "")]
            if key == station_key or poi.get("name", "") in station_key:
                return sys.get("faction", "independent")
    return "independent"

func _init_station_economy(data: Dictionary):

    if data.has("economy"):
        return
    var stype = data.get("station_type", "trade")
    var profile = STATION_ECONOMY_PROFILES.get(stype, STATION_ECONOMY_PROFILES["trade"])
    var pop_size = 8
    data["economy"] = {
        "credits": int(profile.get("starting_credits", 5000)), 
        "resources": profile.get("starting_resources", {}).duplicate(true), 
        "food": float(pop_size * 10), 
        "demand": {}, 
        "supply": {}, 
    }

func _ensure_station_economy(station_key: String):

    if not persistent_stations.has(station_key):
        return
    var data = persistent_stations[station_key]
    if not data.has("economy"):
        _init_station_economy(data)

func tick_station_economies_hourly():

    for station_key in persistent_stations:
        var data = persistent_stations[station_key]
        _ensure_station_economy(station_key)
        var econ: Dictionary = data.get("economy", {})
        var stype = data.get("station_type", "trade")
        var profile = STATION_ECONOMY_PROFILES.get(stype, STATION_ECONOMY_PROFILES["trade"])
        var res: Dictionary = econ.get("resources", {})


        var produces: Dictionary = profile.get("produces", {})
        for rt in produces:
            res[rt] = int(res.get(rt, 0)) + int(produces[rt])


        var consumes: Dictionary = profile.get("consumes", {})
        for rt in consumes:
            res[rt] = maxi(int(res.get(rt, 0)) - int(consumes[rt]), 0)


        var pop_size = 8
        var food_drain = float(pop_size) * profile.get("food_per_pop", 0.5)
        econ["food"] = maxf(float(econ.get("food", 0)) - food_drain, 0)


        econ["credits"] = int(econ.get("credits", 0)) + int(profile.get("credit_income", 20))



        var demand: Dictionary = econ.get("demand", {})
        var supply: Dictionary = econ.get("supply", {})
        for rt in TRADE_RESOURCES:
            var stock = int(res.get(rt, 0))
            var is_consumed = consumes.has(rt)
            var is_produced = produces.has(rt)

            var threshold: float = 20.0
            if is_consumed:
                threshold = 30.0

            var raw_demand = clampf(1.0 + (threshold - stock) / threshold, 0.5, 2.5)
            if is_consumed and stock < 5:
                raw_demand = minf(raw_demand + 0.5, 3.0)

            var raw_supply = clampf(1.0 + (stock - threshold) / threshold, 0.5, 2.5)
            if is_produced:
                raw_supply = minf(raw_supply + 0.3, 2.5)

            demand[rt] = lerpf(float(demand.get(rt, 1.0)), raw_demand, 0.3)
            supply[rt] = lerpf(float(supply.get(rt, 1.0)), raw_supply, 0.3)
        econ["demand"] = demand
        econ["supply"] = supply
        econ["resources"] = res

func get_station_resource_price(station_key: String, resource_type: String, is_buy: bool) -> int:

    var base_info = RESOURCE_TYPES.get(resource_type, {})
    var base_price = float(base_info.get("sell_price", 3))
    _ensure_station_economy(station_key)
    var econ = persistent_stations.get(station_key, {}).get("economy", {})
    var demand_mult = float(econ.get("demand", {}).get(resource_type, 1.0))
    var supply_mult = float(econ.get("supply", {}).get(resource_type, 1.0))
    var dynamic = base_price * demand_mult / maxf(supply_mult, 0.3)
    var faction_mult = get_station_price_mult()
    if is_buy:
        return maxi(int(ceilf(dynamic * 1.2 * faction_mult)), 1)
    else:
        return maxi(int(floorf(dynamic * 0.85 * faction_mult)), 1)

func get_station_economy(station_key: String) -> Dictionary:

    _ensure_station_economy(station_key)
    return persistent_stations.get(station_key, {}).get("economy", {})

func station_add_resource(station_key: String, resource_type: String, amount: int):

    _ensure_station_economy(station_key)
    var econ = persistent_stations.get(station_key, {}).get("economy", {})
    var res = econ.get("resources", {})
    res[resource_type] = int(res.get(resource_type, 0)) + amount
    econ["resources"] = res

func station_remove_resource(station_key: String, resource_type: String, amount: int) -> int:

    _ensure_station_economy(station_key)
    var econ = persistent_stations.get(station_key, {}).get("economy", {})
    var res = econ.get("resources", {})
    var have = int(res.get(resource_type, 0))
    var taken = mini(have, amount)
    res[resource_type] = have - taken
    econ["resources"] = res
    return taken

func _compute_station_stats(data: Dictionary) -> void :

    var total_hp: float = 0.0
    var max_hp: float = 0.0
    var total_shields: float = 0.0
    var weapon_count: int = 0
    for mod in data.get("modules", []):
        var mdata = mod.get("data", {})
        max_hp += mod.get("max_hp", 40.0)
        total_hp += mod.get("hp", mod.get("max_hp", 40.0))
        if mdata.get("type", "") == "shield":
            total_shields += mdata.get("stats", {}).get("shield_capacity", 30.0)
        if mdata.get("type", "") == "weapon":
            weapon_count += 1
    data["health"] = total_hp
    data["max_health"] = max_hp
    data["shields"] = total_shields
    data["max_shields"] = total_shields
    data["weapon_count"] = weapon_count

func damage_station_module(station_key: String, hex_cell: Vector2i, amount: float) -> float:

    if not persistent_stations.has(station_key):
        return 0.0
    var sdata = persistent_stations[station_key]
    for mod in sdata.get("modules", []):
        var cells = get_mod_hex_cells(mod)
        if hex_cell in cells:
            var dealt = damage_module(mod, amount)
            _compute_station_stats(sdata)
            return dealt

    var alive: Array = []
    for mod in sdata.get("modules", []):
        if mod.get("hp", 1.0) > 0:
            alive.append(mod)
    if not alive.is_empty():
        var dealt = damage_module(alive[randi() % alive.size()], amount)
        _compute_station_stats(sdata)
        return dealt
    return 0.0

func is_station_destroyed(station_key: String) -> bool:
    if not persistent_stations.has(station_key):
        return false
    var sdata = persistent_stations[station_key]
    return sdata.get("health", 1.0) <= 0


# True when a hidden POI has been unlocked at runtime by an unlock_poi
# trigger action. Compared against the POI's `id` field (stable identifier
# authored in systems.json).
func is_poi_unlocked(sys_id: String, poi_id: String) -> bool:
    if sys_id.is_empty() or poi_id.is_empty():
        return false
    var arr_v: Variant = unlocked_pois.get(sys_id, null)
    if typeof(arr_v) != TYPE_ARRAY:
        return false
    return poi_id in (arr_v as Array)


# Append `poi_id` to unlocked_pois[sys_id] if not already present. The
# system re-renders this on next entry (spawn_system_pois reads the map
# when iterating each POI), so an active session won't see the change
# until the player jumps out and back into the system.
func unlock_poi(sys_id: String, poi_id: String) -> void:
    if sys_id.is_empty() or poi_id.is_empty():
        return
    var arr_v: Variant = unlocked_pois.get(sys_id, [])
    var arr: Array = arr_v if typeof(arr_v) == TYPE_ARRAY else []
    if poi_id in arr:
        return
    arr.append(poi_id)
    unlocked_pois[sys_id] = arr





func link_fleet_ship(_fleet_id: String) -> bool:

    return false

func detach_section(section_idx: int) -> bool:

    if section_idx < 0 or section_idx >= linked_sections.size():
        return false
    var section = linked_sections[section_idx]
    var section_mods: Array = section.get("modules", [])
    for smod in section_mods:
        var smod_gp = smod.get("grid_pos", Vector2i.ZERO)
        for i in range(ship_modules.size() - 1, -1, -1):
            if ship_modules[i].get("grid_pos", Vector2i(-999, -999)) == smod_gp:
                ship_modules.remove_at(i)
                break
    linked_sections.remove_at(section_idx)
    update_resource_capacity()
    return true

func promote_to_flagship(_fleet_ship_id: String) -> bool:

    return false


func _serialize_linked_sections() -> Array:
    var result: Array = []
    for sec in linked_sections:
        var entry = {"offset": sec.get("offset", [0, 0]), "source_id": sec.get("source_id", "")}
        var mods: Array = []
        for mod in sec.get("modules", []):
            var gp = mod.get("grid_pos", Vector2i.ZERO)
            var m = {"id": mod.get("id", ""), "grid_pos": [gp.x, gp.y], "deck": get_mod_deck(mod)}
            if mod.has("hp"):
                m["hp"] = mod["hp"]
            if mod.has("max_hp"):
                m["max_hp"] = mod["max_hp"]
            if mod.has("armor"):
                m["armor"] = mod["armor"]
            if mod.get("rotation", 0) > 0:
                m["rotation"] = mod["rotation"]
            mods.append(m)
        entry["modules"] = mods
        result.append(entry)
    return result

func _deserialize_linked_sections(data: Array) -> Array:
    var result: Array = []
    for entry in data:
        var sec = {"offset": entry.get("offset", [0, 0]), "source_id": entry.get("source_id", "")}
        var mods: Array = []
        for m in entry.get("modules", []):
            var gp = m.get("grid_pos", [0, 0])
            var mod = {
                "id": m.get("id", ""), 
                "grid_pos": Vector2i(int(gp[0]), int(gp[1])), 
                "deck": int(m.get("deck", 0)), 
                "data": DataManager.modules.get(m.get("id", ""), {}), 
            }
            if m.has("hp") and m.has("max_hp"):
                mod["hp"] = float(m["hp"])
                mod["max_hp"] = float(m["max_hp"])
                mod["armor"] = float(m.get("armor", 0))
            else:
                init_module_hp(mod)
            if m.get("rotation", 0) > 0:
                mod["rotation"] = m["rotation"]
            mods.append(mod)
        sec["modules"] = mods
        result.append(sec)
    return result





func is_controlling_fleet_ship() -> bool:
    return false

func get_active_modules() -> Array:
    return ship_modules

func get_active_core_id() -> String:
    return equipped_core

func get_cargo_space_free() -> int:
    return 999

func generate_npc_ship_crew(_rng: RandomNumberGenerator, _npc_type: String, _faction_id: String = "") -> Array:
    return []

func generate_station_population(_station_key: String, _station_type: String, _seed_val: int, _station_faction: String = "") -> Array:
    return []

func get_station_population(_station_key: String) -> Array:
    return []

func update_crew_capacity():
    pass

func rebuild_walkable_cells():
    pass

func auto_assign_crew():
    pass

func pos3_arr(pos: Vector3i) -> Array:
    return [pos.x, pos.y, pos.z]

func repair_module_at(grid_pos: Vector2i) -> bool:
    for mod in ship_modules:
        if mod.get("grid_pos") == grid_pos and is_module_damaged(mod):
            repair_module(mod)
            return true
    return false

func repair_all_damaged():
    for mod in ship_modules:
        repair_module(mod)

func queue_event(_event_id: String, _delay_min: float, _delay_max: float, _extra_tags: Dictionary = {}):
    pass

func tick_pending_events(_delta: float) -> String:
    return ""

func substitute_tags(text: String) -> String:
    var result = text
    var tags_snap: Dictionary = MvTriggerEngine.snapshot_global_tags()
    for key in tags_snap:
        result = result.replace("{%s}" % key, str(tags_snap[key]))
    return result

func has_pilot_at_bridge() -> bool:

    return true

func crew_pos(_crew: Dictionary) -> Vector3i:

    return INVALID_POS

func get_crew_skill(_crew: Dictionary, _skill_name: String) -> int:

    return 0

func grant_skill_xp(_crew: Dictionary, _skill_name: String, _amount: float = 1.0):

    pass

func get_skill_for_module_type(_module_type: String) -> String:

    return ""

func get_research_bonus(_bonus_name: String) -> float:

    return 0.0

func get_crew_daily_wage(_crew: Dictionary) -> int:

    return 0

func tick_shore_leave_events() -> Array:

    return []

func tick_crew_movement(_delta: float):

    pass

func tick_crew_needs(_delta: float):

    pass

func tick_crew_ai(_delta: float):

    pass

func tick_crew_relationships(_delta: float):

    pass

func tick_morale_events(_delta: float):

    pass

func supply_colony(_colony_id: String, _food: float) -> float:

    return 0.0

func get_active_ship_data() -> Dictionary:

    return {}

func update_cargo_capacity():

    pass

func get_fleet_ships_in_system(_sys_id: String) -> Array:

    return []

func get_fleet_ship(_fleet_id: String) -> Dictionary:

    return {}

func remove_fleet_ship(_fleet_id: String):

    pass

func generate_crew(_role: String = "") -> Dictionary:

    return {}

func compute_fleet_ship_stats(_ship: Dictionary):

    pass

func calculate_ship_attraction() -> float:

    return 0.0

func _get_module_grid_pos_from_assignment(_assignment: String) -> Vector3i:

    return INVALID_POS

func get_work_order(_order_id: String) -> Dictionary:

    return {}

func _get_module_at_grid(_pos: Vector3i) -> Dictionary:

    return {}

func hire_spacer_from_station(_station_key: String, _spacer_id: String) -> Dictionary:

    return {}

func get_colony(_colony_id: String) -> Dictionary:

    return {}

func tick_colony_production(_delta: float):

    pass






func add_crew_member(_crew_data: Dictionary): pass
func get_active_crew() -> Array: return []
func count_crew_for_type(_mtype: String) -> int: return 0
func get_crew_repairing(_grid_pos) -> Dictionary: return {}
func send_nearest_crew_to_repair(_grid_pos): pass
func get_crew_mood_reasons(_crew: Dictionary) -> Array: return []
func get_best_skill(_crew: Dictionary) -> String: return ""
func get_relationship_label(_val: float) -> String: return ""
func log_crew_bark(_text: String, _crew_id: String = ""): pass
func get_preference_bark(_crew: Dictionary) -> String: return ""
func _get_crew_spawn_pos() -> Vector3i: return INVALID_POS
func _find_path_bfs(_from: Vector3i, _to: Vector3i) -> Array: return []
func get_pilot_evasion_impulse() -> Vector2: return Vector2.ZERO
func pay_daily_wages(): pass
func hire_crew(_station_key: String, _spacer_id: String) -> bool: return false
func buy_food(_amount: int, _cost: int) -> bool: return false
var crew_bark_log: Array = []
var crew_relationships: Dictionary = {}
var crew_target: String = ""
var jailed_crew: Array = []
var MOOD_COLORS: Dictionary = {}
@warning_ignore("unused_private_class_variable")
var _docked_station_key: String = ""


func accept_mission(_mission_data: Dictionary) -> bool: return false
func check_mission_progress(): pass
func complete_mission(_mission_id: String) -> bool: return false
func record_kill_for_missions(_faction: String): pass
func record_poi_visit_for_missions(_poi_name: String): pass
var completed_missions: Array = []


func can_research(_project_id: String) -> bool: return false
func start_research(_project_id: String): pass
func tick_research(_delta: float): pass
func _has_research_lab() -> bool: return false
var completed_research: Array = []
var CORE_RESEARCH_REQS: Dictionary = {}


func create_ground_colony(_sys_id: String, _poi_name: String, _planet_data: Dictionary) -> String: return ""
func deploy_colony(_fleet_id: String, _planet_data: Dictionary) -> String: return ""
func abandon_colony(_colony_id: String): pass
func collect_from_colony(_colony_id: String) -> Dictionary: return {}
func get_colonies_in_system(_sys_id: String) -> Array: return []
func get_colony_for_planet(_sys_id: String, _poi_name: String) -> String: return ""
func get_colony_tier_name(_colony: Dictionary) -> String: return ""
func generate_colony_layout(_colony: Dictionary): pass
func get_colony_modules(_colony_id: String) -> Array: return []
func get_colony_cosmetics(_colony_id: String) -> Array: return []
func set_colony_modules(_colony_id: String, _modules: Array): pass
func set_colony_cosmetics(_colony_id: String, _cosmetics: Array): pass
func tick_colonies(_delta: float): pass
func tick_npc_colonies(): pass
var active_colony_id: String = ""
var npc_colonies: Dictionary = {}
var COLONY_TIER_NAMES: Array = ["Outpost", "Settlement", "Colony", "City"]
var COLONY_TIER_POP: Array = [0, 10, 30, 80]
var COLONY_FOOD_PER_POP: float = 0.5


func create_fleet_ship(_data: Dictionary) -> String: return ""
func collect_from_fleet_ship(_fleet_id: String) -> Dictionary: return {}
func transfer_crew_to_fleet(_fleet_id: String, _crew_ids: Array): pass
func transfer_crew_from_fleet(_fleet_id: String, _crew_ids: Array): pass
func set_fleet_order(_fleet_id: String, _order: int, _target: String = ""): pass
func set_transport_route(_fleet_id: String, _stops: Array): pass
func get_transport_stop_name(_stop: Dictionary) -> String: return ""
func switch_to_fleet_ship(_fleet_id: String): pass
func switch_to_player_ship(): pass
func tick_fleet(_delta: float): pass
enum NpcJob{IDLE, HAULING, MINING, PATROL, BOUNTY_HUNT, EXPLORING, DOCKED}


func create_work_order(_data: Dictionary) -> String: return ""
func cancel_work_order(_order_id: String): pass
func _work_order_materials_ready(_order: Dictionary) -> bool: return false
func station_install_cost_total() -> int: return 0
func station_instant_install_all(): pass
func create_crafting_order(_recipe_id: String) -> bool: return false
func cancel_crafting_order(_order_idx: int): pass
func tick_construction(_delta: float): pass
func tick_crafting(_delta: float): pass
func tick_hauling(_delta: float): pass


func tick_production_hourly(): pass
func tick_livestock_hourly(): pass
func tick_ship_visitors(): pass
func tick_engineer_maintenance(_delta: float): pass
func tick_maintenance(_delta: float): pass
func tick_npc_daily_wages(): pass
func tick_npc_contracts(): pass
func tick_npc_population_movement(): pass
var ship_visitor_count: int = 0
var ship_visitor_income: float = 0.0
var pending_shore_dilemmas: Array = []
var detected_rooms: Array = []


func add_prisoner(_crew_data: Dictionary): pass
func has_brig_space() -> bool: return false


func _load_tuning() -> Dictionary:
    var pack_id := ""
    if MvPackLoader.current_pack != null:
        pack_id = MvPackLoader.current_pack.pack_id
    if pack_id.is_empty():
        pack_id = "demo"
    for path in [
        PedIO.user_file(pack_id, "GameTuning", "tuning.json"),
        PedIO.shipped_file(pack_id, "GameTuning", "tuning.json"),
        PedIO.demo_file("GameTuning", "tuning.json"),
    ]:
        if FileAccess.file_exists(path):
            var f := FileAccess.open(path, FileAccess.READ)
            if f == null:
                continue
            var raw = JSON.parse_string(f.get_as_text())
            f.close()
            if typeof(raw) == TYPE_DICTIONARY:
                return raw
    return {}

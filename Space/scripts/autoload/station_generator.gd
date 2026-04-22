class_name StationGenerator
extends RefCounted

# Procedural station layout generator. Extracted from GameManager.
# The _station_cache stays on GameManager because it is session state
# written through save/load; GM wraps generate() with caching.

static func generate(station_type: String, seed_val: int = 0) -> Dictionary:
    var cache_key = "%s_%d" % [station_type, seed_val]
    var rng = RandomNumberGenerator.new()
    rng.seed = seed_val if seed_val != 0 else rng.randi()
    var hull_radius: int
    match station_type:
        "gateway": hull_radius = 10
        "military", "science": hull_radius = 8
        "pirate": hull_radius = 6
        _: hull_radius = 7
    var hull_cells: Array = HexUtil.generate_hex_disc(hull_radius)
    var modules: Array = []
    var cosmetics: Array = []
    var npcs: Array = []
    var hull_set: Dictionary = {}
    for c in hull_cells:
        hull_set[c] = true
    var claimed: Dictionary = {}
    var room_label_data: Dictionary = {}


    var core_mods: Dictionary = {Vector2i(0, 0): "micro_reactor", Vector2i(1, 0): "life_support_mk1", Vector2i(-1, 0): "life_support_mk1"}
    for pos in core_mods:
        claimed[pos] = "core"
        modules.append({"id": core_mods[pos], "grid_pos": pos, "data": DataManager.modules.get(core_mods[pos], {}), "deck": 0})


    var spawn_point: Vector2i = Vector2i(0, hull_radius)
    if not hull_set.has(spawn_point):
        spawn_point = Vector2i(0, hull_radius - 1)
    claimed[spawn_point] = "dock"
    modules.append({"id": "airlock_mk1", "grid_pos": spawn_point, "data": DataManager.modules.get("airlock_mk1", {}), "deck": 0})
    for n in HexUtil.NEIGHBORS:
        var dc: Vector2i = spawn_point + n
        if hull_set.has(dc) and not claimed.has(dc) and dc.y >= hull_radius - 1:
            claimed[dc] = "dock"
            modules.append({"id": "deck_plate", "grid_pos": dc, "data": DataManager.modules.get("deck_plate", {}), "deck": 0})



    for r in range(hull_radius - 1, 0, -1):
        for q in [0, -1]:
            var pos: Vector2i = Vector2i(q, r)
            if hull_set.has(pos) and not claimed.has(pos):
                claimed[pos] = "corridor"

    @warning_ignore("integer_division")
    var cross_r: int = maxi(hull_radius / 3, 2)
    for q in range( - hull_radius + 1, hull_radius):
        for r_off in [cross_r, cross_r - 1]:
            var pos: Vector2i = Vector2i(q, r_off)
            if hull_set.has(pos) and not claimed.has(pos):
                claimed[pos] = "corridor"

    if hull_radius >= 7:
        @warning_ignore("integer_division")
        var cross_r2: int = - maxi(hull_radius / 3, 2)
        for q in range( - hull_radius + 1, hull_radius):
            for r_off in [cross_r2, cross_r2 + 1]:
                var pos: Vector2i = Vector2i(q, r_off)
                if hull_set.has(pos) and not claimed.has(pos):
                    claimed[pos] = "corridor"

    if hull_radius >= 9:
        @warning_ignore("integer_division")
        var cross_r3: int = hull_radius * 2 / 3
        for q in range( - hull_radius + 1, hull_radius):
            var pos: Vector2i = Vector2i(q, cross_r3)
            if hull_set.has(pos) and not claimed.has(pos):
                claimed[pos] = "corridor"
    for pos in claimed.keys():
        if claimed[pos] == "corridor":
            modules.append({"id": "deck_plate", "grid_pos": pos, "data": DataManager.modules.get("deck_plate", {}), "deck": 0})


    var room_plans: Array = _get_station_room_plans(station_type)
    var corridor_cells: Array = []
    for pos in claimed:
        if claimed[pos] == "corridor":
            corridor_cells.append(pos)
    for plan in room_plans:
        var anchor: Vector2i = _find_room_anchor(corridor_cells, hull_set, claimed, rng)
        if anchor == Vector2i(-999, -999):
            continue
        var cluster: Array = _grow_room_cluster(anchor, hull_set, claimed, plan.get("size", 4), rng)
        if cluster.is_empty():
            continue
        for c in cluster:
            claimed[c] = "room"
            modules.append({"id": "deck_plate", "grid_pos": c, "data": DataManager.modules.get("deck_plate", {}), "deck": 0})
        var tiles: Array = plan.get("tiles", [])
        var cat: String = plan.get("category", "")
        for j in mini(tiles.size(), cluster.size()):
            var tile: Dictionary = tiles[j]
            cosmetics.append({"id": "int_" + tile.get("subtype", ""), "grid_pos": cluster[j], "data": {"type": "interior", "subtype": tile.get("subtype", ""), "category": cat, "name": tile.get("name", "")}, "deck": 0})
        var sum: Vector2i = Vector2i.ZERO
        for c in cluster:
            sum += c
        @warning_ignore("integer_division")
        room_label_data[Vector2i(sum.x / cluster.size(), sum.y / cluster.size())] = plan.get("name", "Room")
        var npc_def: Dictionary = plan.get("npc", {})
        if not npc_def.is_empty() and not cluster.is_empty():
            npcs.append({"name": npc_def.get("name", "NPC"), "role": npc_def.get("role", "civilian"), "hex": cluster[0], "stationary": true})


    var station_key: String = cache_key
    var population: Array = []
    var pop_idx: int = 0
    for ni in npcs.size():
        if pop_idx >= population.size():
            break
        if npcs[ni].get("stationary", false):
            var spacer = population[pop_idx]
            npcs[ni]["name"] = spacer.get("name", "NPC")
            npcs[ni]["spacer_id"] = spacer.get("id", "")
            pop_idx += 1
    var walk_cells: Array = []
    for pos in claimed:
        walk_cells.append(pos)
    while pop_idx < population.size():
        var spacer = population[pop_idx]
        var whex = walk_cells[rng.randi() % walk_cells.size()]
        npcs.append({"name": spacer.get("name", "Spacer"), "role": spacer.get("role", "deckhand"), "hex": whex, "stationary": false, "spacer_id": spacer.get("id", "")})
        pop_idx += 1
    return {"modules": modules, "cosmetics": cosmetics, "npcs": npcs, "spawn_point": spawn_point, "station_key": station_key, "room_labels": room_label_data, "hull_radius": hull_radius}


static func _find_room_anchor(corridor_cells: Array, hull_set: Dictionary, claimed: Dictionary, rng: RandomNumberGenerator) -> Vector2i:

    var candidates: Array = []
    for pos in corridor_cells:
        for n in HexUtil.NEIGHBORS:
            var nb: Vector2i = pos + n
            if not hull_set.has(nb) or claimed.has(nb):
                continue
            var too_close: bool = false

            for n2 in HexUtil.NEIGHBORS:
                var adj1: Vector2i = nb + n2
                if claimed.has(adj1) and claimed[adj1] == "room":
                    too_close = true
                    break
                if not too_close:
                    for n3 in HexUtil.NEIGHBORS:
                        var adj2: Vector2i = adj1 + n3
                        if claimed.has(adj2) and claimed[adj2] == "room":
                            too_close = true
                            break
                if too_close:
                    break
            if not too_close:
                candidates.append(nb)
    if candidates.is_empty():

        for pos in corridor_cells:
            for n in HexUtil.NEIGHBORS:
                var nb: Vector2i = pos + n
                if not hull_set.has(nb) or claimed.has(nb):
                    continue
                var near_room: bool = false
                for n2 in HexUtil.NEIGHBORS:
                    if claimed.has(nb + n2) and claimed[nb + n2] == "room":
                        near_room = true
                        break
                if not near_room:
                    candidates.append(nb)
    if candidates.is_empty():

        for pos in corridor_cells:
            for n in HexUtil.NEIGHBORS:
                var nb: Vector2i = pos + n
                if hull_set.has(nb) and not claimed.has(nb):
                    candidates.append(nb)
    if candidates.is_empty():
        return Vector2i(-999, -999)
    return candidates[rng.randi() % candidates.size()]


static func _grow_room_cluster(start: Vector2i, hull_set: Dictionary, claimed: Dictionary, target_size: int, rng: RandomNumberGenerator) -> Array:

    var cluster: Array = [start]
    var frontier: Array = [start]
    while cluster.size() < target_size and not frontier.is_empty():
        var idx: int = rng.randi() % frontier.size()
        var cur: Vector2i = frontier[idx]
        var grew: bool = false
        var dirs: Array = HexUtil.NEIGHBORS.duplicate()
        for i in range(dirs.size() - 1, 0, -1):
            var j: int = rng.randi() % (i + 1)
            var tmp = dirs[i]
            dirs[i] = dirs[j]
            dirs[j] = tmp
        for d in dirs:
            if cluster.size() >= target_size:
                break
            var nb: Vector2i = cur + d
            if not hull_set.has(nb) or claimed.has(nb) or nb in cluster:
                continue

            var adj_room: bool = false
            for n2 in HexUtil.NEIGHBORS:
                var adj: Vector2i = nb + n2
                if adj in cluster:
                    continue
                if claimed.has(adj) and claimed[adj] == "room":
                    adj_room = true
                    break
            if adj_room:
                continue
            cluster.append(nb)
            frontier.append(nb)
            grew = true
        if not grew:
            frontier.remove_at(idx)
    return cluster


static func _get_station_room_plans(station_type: String) -> Array:

    var plans: Array = []
    match station_type:
        "trade":
            plans = [
                {"name": "Market", "category": "commerce", "size": 12, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Shop Counter", "subtype": "shop_counter"},
                    {"name": "Display Cases", "subtype": "display_case"}, {"name": "Display Cases", "subtype": "display_case"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Vendor Machine", "subtype": "vending_machine"}, {"name": "Vendor Machine", "subtype": "vending_machine"}],
                 "npc": {"name": "Shopkeeper", "role": "shopkeeper"}},
                {"name": "Cantina", "category": "cantina", "size": 10, "tiles": [
                    {"name": "Bar Top", "subtype": "bar_counter"}, {"name": "Bar Top", "subtype": "bar_counter"},
                    {"name": "Seating", "subtype": "booth_seat"}, {"name": "Seating", "subtype": "booth_seat"},
                    {"name": "Drink Taps", "subtype": "bar_taps"}, {"name": "Stage", "subtype": "stage"},
                    {"name": "Neon Sign", "subtype": "neon_sign"}],
                 "npc": {"name": "Bartender", "role": "bartender"}},
                {"name": "Quarters", "category": "quarters", "size": 8, "tiles": [
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Lockers", "subtype": "locker"},
                    {"name": "Lockers", "subtype": "locker"}, {"name": "Personal Terminal", "subtype": "desk_terminal"}]},
                {"name": "Medbay", "category": "medical", "size": 7, "tiles": [
                    {"name": "Medical Bed", "subtype": "med_bed"}, {"name": "Medical Bed", "subtype": "med_bed"},
                    {"name": "Medical Supplies", "subtype": "medicine_cabinet"}, {"name": "Body Scanner", "subtype": "body_scanner"}],
                 "npc": {"name": "Medic", "role": "worker"}},
                {"name": "Cargo Bay", "category": "cargo", "size": 8, "tiles": [
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}]},
            ]
        "military":
            plans = [
                {"name": "Armory", "category": "workshop", "size": 10, "tiles": [
                    {"name": "Weapon Racks", "subtype": "tool_rack"}, {"name": "Weapon Racks", "subtype": "tool_rack"},
                    {"name": "Equipment Storage", "subtype": "parts_bin"}, {"name": "Equipment Storage", "subtype": "parts_bin"},
                    {"name": "Workbench", "subtype": "workbench"}, {"name": "Lockers", "subtype": "locker"},
                    {"name": "Lockers", "subtype": "locker"}],
                 "npc": {"name": "Quartermaster", "role": "military"}},
                {"name": "Command", "category": "command", "size": 10, "tiles": [
                    {"name": "Command Console", "subtype": "command_terminal"}, {"name": "Command Console", "subtype": "command_terminal"},
                    {"name": "Holographic Table", "subtype": "holotable"}, {"name": "Comms Array", "subtype": "comms_console"},
                    {"name": "Nav Charts", "subtype": "nav_charts"}, {"name": "Nav Charts", "subtype": "nav_charts"}],
                 "npc": {"name": "Commander", "role": "military"}},
                {"name": "Brig", "category": "brig", "size": 6, "tiles": [
                    {"name": "Cell Bunk", "subtype": "bunk"}, {"name": "Cell Bunk", "subtype": "bunk"},
                    {"name": "Floor Grating", "subtype": "grating"}, {"name": "Floor Grating", "subtype": "grating"},
                    {"name": "Blast Door", "subtype": "blast_door"}]},
                {"name": "Medbay", "category": "medical", "size": 8, "tiles": [
                    {"name": "Medical Bed", "subtype": "med_bed"}, {"name": "Medical Bed", "subtype": "med_bed"},
                    {"name": "Medical Supplies", "subtype": "medicine_cabinet"}, {"name": "Body Scanner", "subtype": "body_scanner"},
                    {"name": "Body Scanner", "subtype": "body_scanner"}],
                 "npc": {"name": "Medic", "role": "worker"}},
                {"name": "Mess Hall", "category": "mess", "size": 10, "tiles": [
                    {"name": "Dining Tables", "subtype": "dining_table_lg"}, {"name": "Dining Tables", "subtype": "dining_table_lg"},
                    {"name": "Bench Seating", "subtype": "bench"}, {"name": "Bench Seating", "subtype": "bench"},
                    {"name": "Serving Counter", "subtype": "serving_counter"}, {"name": "Food Prep", "subtype": "cooking_station"}]},
                {"name": "Supply Depot", "category": "commerce", "size": 8, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Shop Counter", "subtype": "shop_counter"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Display Cases", "subtype": "display_case"}],
                 "npc": {"name": "Supply Officer", "role": "shopkeeper"}},
            ]
        "pirate":
            plans = [
                {"name": "Black Market", "category": "commerce", "size": 8, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Display Cases", "subtype": "display_case"}],
                 "npc": {"name": "Fence", "role": "shopkeeper"}},
                {"name": "Dive Bar", "category": "cantina", "size": 10, "tiles": [
                    {"name": "Bar Top", "subtype": "bar_counter"}, {"name": "Bar Top", "subtype": "bar_counter"},
                    {"name": "Seating", "subtype": "booth_seat"}, {"name": "Seating", "subtype": "booth_seat"},
                    {"name": "Drink Taps", "subtype": "bar_taps"}, {"name": "Bottle Shelf", "subtype": "bottle_shelf"},
                    {"name": "Neon Sign", "subtype": "neon_sign"}],
                 "npc": {"name": "Barkeep", "role": "bartender"}},
                {"name": "Bunks", "category": "quarters", "size": 6, "tiles": [
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Floor Grating", "subtype": "grating"}]},
                {"name": "Fighting Pit", "category": "recreation", "size": 6, "tiles": [
                    {"name": "Sparring Mat", "subtype": "sparring_mat"}, {"name": "Sparring Mat", "subtype": "sparring_mat"},
                    {"name": "Training Gear", "subtype": "exercise_equip"}, {"name": "Floor Grating", "subtype": "grating"}]},
            ]
        "science":
            plans = [
                {"name": "Research Lab", "category": "command", "size": 12, "tiles": [
                    {"name": "Command Console", "subtype": "command_terminal"}, {"name": "Command Console", "subtype": "command_terminal"},
                    {"name": "Holographic Table", "subtype": "holotable"}, {"name": "Body Scanner", "subtype": "body_scanner"},
                    {"name": "Body Scanner", "subtype": "body_scanner"}, {"name": "Personal Terminal", "subtype": "desk_terminal"},
                    {"name": "Personal Terminal", "subtype": "desk_terminal"}],
                 "npc": {"name": "Lead Scientist", "role": "worker"}},
                {"name": "Medbay", "category": "medical", "size": 8, "tiles": [
                    {"name": "Medical Bed", "subtype": "med_bed"}, {"name": "Medical Bed", "subtype": "med_bed"},
                    {"name": "Medical Supplies", "subtype": "medicine_cabinet"}, {"name": "Body Scanner", "subtype": "body_scanner"}],
                 "npc": {"name": "Doctor", "role": "worker"}},
                {"name": "Quarters", "category": "quarters", "size": 8, "tiles": [
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Personal Terminal", "subtype": "desk_terminal"}, {"name": "Bookshelf", "subtype": "bookshelf"},
                    {"name": "Bookshelf", "subtype": "bookshelf"}]},
                {"name": "Cafeteria", "category": "mess", "size": 8, "tiles": [
                    {"name": "Dining Tables", "subtype": "dining_table_lg"}, {"name": "Dining Tables", "subtype": "dining_table_lg"},
                    {"name": "Food Prep", "subtype": "cooking_station"}, {"name": "Vendor Machine", "subtype": "vending_machine"}]},
                {"name": "Supply", "category": "commerce", "size": 6, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Display Cases", "subtype": "display_case"}],
                 "npc": {"name": "Requisitions", "role": "shopkeeper"}},
            ]
        "gateway":
            plans = [
                {"name": "Grand Market", "category": "commerce", "size": 16, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Shop Counter", "subtype": "shop_counter"},
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Display Cases", "subtype": "display_case"},
                    {"name": "Display Cases", "subtype": "display_case"}, {"name": "Display Cases", "subtype": "display_case"},
                    {"name": "Cargo Storage", "subtype": "cargo_crate"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Vendor Machine", "subtype": "vending_machine"}, {"name": "Vendor Machine", "subtype": "vending_machine"}],
                 "npc": {"name": "Station Merchant", "role": "shopkeeper"}},
                {"name": "Cantina", "category": "cantina", "size": 14, "tiles": [
                    {"name": "Bar Top", "subtype": "bar_counter"}, {"name": "Bar Top", "subtype": "bar_counter"},
                    {"name": "Seating", "subtype": "booth_seat"}, {"name": "Seating", "subtype": "booth_seat"},
                    {"name": "Seating", "subtype": "booth_seat"}, {"name": "Drink Taps", "subtype": "bar_taps"},
                    {"name": "Stage", "subtype": "stage"}, {"name": "Stage", "subtype": "stage"},
                    {"name": "Neon Sign", "subtype": "neon_sign"}],
                 "npc": {"name": "Bartender", "role": "bartender"}},
                {"name": "Command Center", "category": "command", "size": 10, "tiles": [
                    {"name": "Command Console", "subtype": "command_terminal"}, {"name": "Command Console", "subtype": "command_terminal"},
                    {"name": "Holographic Table", "subtype": "holotable"}, {"name": "Comms Array", "subtype": "comms_console"},
                    {"name": "Nav Charts", "subtype": "nav_charts"}, {"name": "Nav Charts", "subtype": "nav_charts"}],
                 "npc": {"name": "Station Commander", "role": "military"}},
                {"name": "Medical Wing", "category": "medical", "size": 10, "tiles": [
                    {"name": "Medical Bed", "subtype": "med_bed"}, {"name": "Medical Bed", "subtype": "med_bed"},
                    {"name": "Medical Bed", "subtype": "med_bed"}, {"name": "Medical Supplies", "subtype": "medicine_cabinet"},
                    {"name": "Body Scanner", "subtype": "body_scanner"}, {"name": "Body Scanner", "subtype": "body_scanner"}],
                 "npc": {"name": "Chief Medic", "role": "worker"}},
                {"name": "Quarters", "category": "quarters", "size": 10, "tiles": [
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Lockers", "subtype": "locker"}, {"name": "Lockers", "subtype": "locker"},
                    {"name": "Personal Terminal", "subtype": "desk_terminal"}]},
                {"name": "Recreation", "category": "recreation", "size": 8, "tiles": [
                    {"name": "Game Table", "subtype": "game_table"}, {"name": "Game Table", "subtype": "game_table"},
                    {"name": "Seating", "subtype": "couch"}, {"name": "Seating", "subtype": "couch"},
                    {"name": "Viewport", "subtype": "viewport"}, {"name": "Viewport", "subtype": "viewport"}]},
            ]
        _:
            plans = [
                {"name": "Shop", "category": "commerce", "size": 8, "tiles": [
                    {"name": "Shop Counter", "subtype": "shop_counter"}, {"name": "Shop Counter", "subtype": "shop_counter"},
                    {"name": "Display Cases", "subtype": "display_case"}, {"name": "Cargo Storage", "subtype": "cargo_crate"},
                    {"name": "Vendor Machine", "subtype": "vending_machine"}],
                 "npc": {"name": "Shopkeeper", "role": "shopkeeper"}},
                {"name": "Bar", "category": "cantina", "size": 8, "tiles": [
                    {"name": "Bar Top", "subtype": "bar_counter"}, {"name": "Bar Top", "subtype": "bar_counter"},
                    {"name": "Seating", "subtype": "booth_seat"}, {"name": "Seating", "subtype": "booth_seat"},
                    {"name": "Drink Taps", "subtype": "bar_taps"}, {"name": "Neon Sign", "subtype": "neon_sign"}],
                 "npc": {"name": "Bartender", "role": "bartender"}},
                {"name": "Bunks", "category": "quarters", "size": 6, "tiles": [
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Bunks", "subtype": "bunk"},
                    {"name": "Bunks", "subtype": "bunk"}, {"name": "Lockers", "subtype": "locker"}]},
            ]
    return plans

extends RefCounted




const TILE_DEFS: Dictionary = {
    "open": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 0, "move_cost": 1, "destructible": false}, 
    "rough": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 0, "move_cost": 2, "destructible": false}, 
    "wall": {"walkable": false, "cover": 0, "blocks_los": true, "hp": 0, "move_cost": 99, "destructible": false}, 
    "destructible_wall": {"walkable": false, "cover": 0, "blocks_los": true, "hp": 80, "move_cost": 99, "destructible": true}, 
    "half_cover": {"walkable": true, "cover": 20, "blocks_los": false, "hp": 50, "move_cost": 1, "destructible": true}, 
    "full_cover": {"walkable": true, "cover": 40, "blocks_los": false, "hp": 80, "move_cost": 1, "destructible": true}, 
    "door": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 40, "move_cost": 1, "destructible": true}, 
    "water": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 0, "move_cost": 3, "destructible": false}, 
    "vegetation": {"walkable": true, "cover": 10, "blocks_los": false, "hp": 30, "move_cost": 1, "destructible": true}, 
    "elevation": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 0, "move_cost": 2, "destructible": false}, 
    "objective": {"walkable": true, "cover": 0, "blocks_los": false, "hp": 0, "move_cost": 1, "destructible": false}, 
    "rubble": {"walkable": true, "cover": 5, "blocks_los": false, "hp": 0, "move_cost": 2, "destructible": false}, 
}


var tiles: Dictionary = {}
var tile_hp: Dictionary = {}
var smoke_tiles: Dictionary = {}
var map_name: String = ""
var fire_support_allowed: bool = false
var biome: String = "station"
var spawn_zones: Dictionary = {}
var objectives: Array = []
var enemy_squad: Array = []
var enemy_templates: Dictionary = {}

func load_map(map_data: Dictionary) -> void :
    tiles.clear()
    tile_hp.clear()
    smoke_tiles.clear()
    map_name = map_data.get("name", "Unknown")
    fire_support_allowed = map_data.get("fire_support_allowed", false)
    biome = map_data.get("biome", "station")
    objectives = map_data.get("objectives", [])
    enemy_squad = map_data.get("enemy_squad", [])
    enemy_templates = map_data.get("enemy_templates", {})


    var raw_tiles = map_data.get("tiles", {})
    for key in raw_tiles:
        var parts = key.split(",")
        if parts.size() == 2:
            var pos = Vector2i(int(parts[0]), int(parts[1]))
            var ttype: String = raw_tiles[key]
            tiles[pos] = ttype

            var tdef = TILE_DEFS.get(ttype, {})
            if tdef.get("destructible", false) and tdef.get("hp", 0) > 0:
                tile_hp[pos] = tdef["hp"]


    spawn_zones.clear()
    var raw_spawns = map_data.get("spawn_zones", {})
    for zone_name in raw_spawns:
        var zone_cells: Array = []
        for cell in raw_spawns[zone_name]:
            zone_cells.append(Vector2i(int(cell[0]), int(cell[1])))
        spawn_zones[zone_name] = zone_cells

func get_tile(pos: Vector2i) -> String:
    return tiles.get(pos, "")

func get_tile_def(pos: Vector2i) -> Dictionary:
    var ttype = tiles.get(pos, "")
    if ttype == "":
        return {}
    return TILE_DEFS.get(ttype, {})

func is_walkable(pos: Vector2i) -> bool:
    var ttype = tiles.get(pos, "")
    if ttype == "":
        return false
    return TILE_DEFS.get(ttype, {}).get("walkable", false)

func get_move_cost(pos: Vector2i) -> int:
    var tdef = get_tile_def(pos)
    return tdef.get("move_cost", 99)

func get_cover(pos: Vector2i) -> int:
    var tdef = get_tile_def(pos)
    return tdef.get("cover", 0)

func blocks_los(pos: Vector2i) -> bool:
    var ttype = tiles.get(pos, "")
    if ttype == "":
        return true
    if smoke_tiles.has(pos) and smoke_tiles[pos] > 0:
        return true
    return TILE_DEFS.get(ttype, {}).get("blocks_los", true)


func damage_tile(pos: Vector2i, amount: float) -> bool:
    if not tile_hp.has(pos):
        return false
    tile_hp[pos] -= amount
    if tile_hp[pos] <= 0:
        tile_hp.erase(pos)

        tiles[pos] = "rubble"
        return true
    return false


func tick_smoke() -> void :
    var expired: Array = []
    for pos in smoke_tiles:
        smoke_tiles[pos] -= 1
        if smoke_tiles[pos] <= 0:
            expired.append(pos)
    for pos in expired:
        smoke_tiles.erase(pos)


func add_smoke(center: Vector2i, radius: int, duration: int) -> void :
    var cells = HexUtil.hexes_in_radius(center, radius)
    for c in cells:
        if tiles.has(c):
            smoke_tiles[c] = duration






func find_path(start: Vector2i, goal: Vector2i, occupied_cells: Dictionary = {}) -> Array:
    if start == goal:
        return []
    if not is_walkable(goal) or occupied_cells.has(goal):
        return []

    var open_set: Array = [[0, start]]
    var came_from: Dictionary = {}
    var cost_so_far: Dictionary = {start: 0}
    came_from[start] = null
    while not open_set.is_empty():

        var best_idx: int = 0
        for i in range(1, open_set.size()):
            if open_set[i][0] < open_set[best_idx][0]:
                best_idx = i
        var current_entry = open_set[best_idx]
        open_set.remove_at(best_idx)
        var current_cost: int = current_entry[0]
        var current: Vector2i = current_entry[1]
        if current == goal:
            break
        for nb in HexUtil.get_neighbors(current):
            if not is_walkable(nb):
                continue
            if nb != goal and occupied_cells.has(nb):
                continue
            var move_c = get_move_cost(nb)
            var new_cost = current_cost + move_c
            if not cost_so_far.has(nb) or new_cost < cost_so_far[nb]:
                cost_so_far[nb] = new_cost
                came_from[nb] = current
                open_set.append([new_cost, nb])

    if not came_from.has(goal):
        return []
    var path: Array = []
    var step = goal
    while step != null and step != start:
        path.append(step)
        step = came_from.get(step)
    path.reverse()
    return path



func get_reachable(start: Vector2i, max_ap: int, occupied_cells: Dictionary = {}) -> Dictionary:
    var reachable: Dictionary = {start: 0}
    var open_set: Array = [[0, start]]
    while not open_set.is_empty():
        var best_idx: int = 0
        for i in range(1, open_set.size()):
            if open_set[i][0] < open_set[best_idx][0]:
                best_idx = i
        var entry = open_set[best_idx]
        open_set.remove_at(best_idx)
        var current_cost: int = entry[0]
        var current: Vector2i = entry[1]
        for nb in HexUtil.get_neighbors(current):
            if not is_walkable(nb):
                continue
            if nb != start and occupied_cells.has(nb):
                continue
            var move_c = get_move_cost(nb)
            var new_cost = current_cost + move_c
            if new_cost > max_ap:
                continue
            if not reachable.has(nb) or new_cost < reachable[nb]:
                reachable[nb] = new_cost
                open_set.append([new_cost, nb])
    return reachable





func has_los(a: Vector2i, b: Vector2i) -> bool:
    if a == b:
        return true
    var line = hex_line(a, b)

    for i in range(1, line.size() - 1):
        if blocks_los(line[i]):
            return false
    return true


func hex_line(a: Vector2i, b: Vector2i) -> Array:
    var dist = HexUtil.hex_distance(a, b)
    if dist == 0:
        return [a]

    var a_cube = _axial_to_cube(a)
    var b_cube = _axial_to_cube(b)
    var results: Array = []
    for i in range(dist + 1):
        var t = float(i) / float(dist)
        var cx = lerpf(a_cube[0], b_cube[0], t)
        var cy = lerpf(a_cube[1], b_cube[1], t)
        var cz = lerpf(a_cube[2], b_cube[2], t)
        results.append(_cube_round_to_axial(cx, cy, cz))
    return results

func _axial_to_cube(h: Vector2i) -> Array:
    return [float(h.x), float(h.y), float( - h.x - h.y)]

func _cube_round_to_axial(x: float, y: float, z: float) -> Vector2i:
    var rx = roundi(x)
    var ry = roundi(y)
    var rz = roundi(z)
    var dx = absf(float(rx) - x)
    var dy = absf(float(ry) - y)
    var dz = absf(float(rz) - z)
    if dx > dy and dx > dz:
        rx = - ry - rz
    elif dy > dz:
        ry = - rx - rz
    return Vector2i(rx, ry)


func get_all_cells() -> Array:
    return tiles.keys()


func has_cell(pos: Vector2i) -> bool:
    return tiles.has(pos)



func get_cover_vs(defender_pos: Vector2i, attacker_pos: Vector2i) -> int:

    var own_cover = get_cover(defender_pos)

    var best = own_cover
    for nb in HexUtil.get_neighbors(defender_pos):

        var d_to_att = HexUtil.hex_distance(nb, attacker_pos)
        var d_def_att = HexUtil.hex_distance(defender_pos, attacker_pos)
        if d_to_att < d_def_att:
            var nb_def = get_tile_def(nb)
            if nb_def.get("blocks_los", false) or nb_def.get("cover", 0) > 0:
                var c = nb_def.get("cover", 0)
                if nb_def.get("blocks_los", false):
                    c = 40
                best = maxi(best, c)
    return best

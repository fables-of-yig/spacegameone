extends Node















const NEIGHBORS: Array = [
    Vector2i(1, 0), 
    Vector2i(-1, 0), 
    Vector2i(0, 1), 
    Vector2i(0, -1), 
    Vector2i(1, -1), 
    Vector2i(-1, 1), 
]



func offset_to_axial(col: int, row: int) -> Vector2i:

    @warning_ignore("integer_division")
    var q = col - (row - (row & 1)) / 2
    return Vector2i(q, row)

func axial_to_offset(q: int, r: int) -> Vector2i:

    @warning_ignore("integer_division")
    var col = q + (r - (r & 1)) / 2
    return Vector2i(col, r)



func get_neighbors(hex: Vector2i) -> Array:

    var result: Array = []
    for n in NEIGHBORS:
        result.append(hex + n)
    return result

func are_neighbors(a: Vector2i, b: Vector2i) -> bool:

    var diff = b - a
    return diff in NEIGHBORS

func hex_distance(a: Vector2i, b: Vector2i) -> int:

    var dq = b.x - a.x
    var dr = b.y - a.y
    @warning_ignore("integer_division")
    return (absi(dq) + absi(dq + dr) + absi(dr)) / 2

func is_same_or_neighbor(a: Vector2i, b: Vector2i) -> bool:

    return a == b or are_neighbors(a, b)

func hexes_in_radius(center: Vector2i, radius: int) -> Array:

    var cells: Array = []
    for q in range( - radius, radius + 1):
        var r1 = maxi( - radius, - q - radius)
        var r2 = mini(radius, - q + radius)
        for r in range(r1, r2 + 1):
            cells.append(center + Vector2i(q, r))
    return cells

func hex_distance_3d(a: Vector3i, b: Vector3i) -> int:

    return hex_distance(Vector2i(a.x, a.y), Vector2i(b.x, b.y)) + absi(a.z - b.z) * 100



func hex_to_pixel(hex: Vector2i, hex_size: float) -> Vector2:

    var x = hex_size * 1.5 * float(hex.x)
    var y = hex_size * sqrt(3.0) * (float(hex.y) + float(hex.x) * 0.5)
    return Vector2(x, y)

func pixel_to_hex(pixel: Vector2, hex_size: float) -> Vector2i:

    var q_frac = pixel.x * 2.0 / 3.0 / hex_size
    var r_frac = ( - pixel.x / 3.0 + pixel.y * sqrt(3.0) / 3.0) / hex_size
    return axial_round(q_frac, r_frac)

func axial_round(q_frac: float, r_frac: float) -> Vector2i:

    var s_frac = - q_frac - r_frac
    var q_int = roundi(q_frac)
    var r_int = roundi(r_frac)
    var s_int = roundi(s_frac)
    var q_diff = absf(float(q_int) - q_frac)
    var r_diff = absf(float(r_int) - r_frac)
    var s_diff = absf(float(s_int) - s_frac)
    if q_diff > r_diff and q_diff > s_diff:
        q_int = - r_int - s_int
    elif r_diff > s_diff:
        r_int = - q_int - s_int
    return Vector2i(q_int, r_int)



func hex_corners(center: Vector2, hex_size: float) -> PackedVector2Array:

    var corners = PackedVector2Array()
    for i in 6:
        var angle = deg_to_rad(60.0 * float(i))
        corners.append(center + Vector2(cos(angle), sin(angle)) * hex_size)
    return corners

func hex_corner(center: Vector2, hex_size: float, i: int) -> Vector2:

    var angle = deg_to_rad(60.0 * float(i))
    return center + Vector2(cos(angle), sin(angle)) * hex_size



func rotate_cw(offset: Vector2i) -> Vector2i:


    return Vector2i( - offset.y, offset.x + offset.y)

func rotate_ccw(offset: Vector2i) -> Vector2i:


    return Vector2i(offset.x + offset.y, - offset.x)

func rotate_hex(hex: Vector2i, rotations: int) -> Vector2i:

    var h = hex
    var r = rotations % 6
    if r < 0:
        r += 6
    for _i in r:
        h = rotate_cw(h)
    return h

func rotate_shape_cw(shape: Array) -> Array:

    var rotated: Array = []
    for cell in shape:
        var v = Vector2i(cell[0], cell[1])
        var r = rotate_cw(v)
        rotated.append([r.x, r.y])
    return rotated

func rotate_shape_ccw(shape: Array) -> Array:

    var rotated: Array = []
    for cell in shape:
        var v = Vector2i(cell[0], cell[1])
        var r = rotate_ccw(v)
        rotated.append([r.x, r.y])
    return rotated



func generate_hex_disc(radius: int) -> Array:



    var cells: Array = []
    for q in range( - radius, radius + 1):
        var r1 = maxi( - radius, - q - radius)
        var r2 = mini(radius, - q + radius)
        for r in range(r1, r2 + 1):
            cells.append(Vector2i(q, r))
    return cells



func parse_hull_pattern(pattern: Array) -> Array:



    var cells: Array = []
    for row in pattern.size():
        var line: String = pattern[row]
        for col in line.length():
            if line[col] == "X":
                cells.append(offset_to_axial(col, row))
    return cells

func find_engine_edge(cells: Array) -> Array:


    var edge: Array = []
    var cell_set: Dictionary = {}
    for c in cells:
        cell_set[c] = true
    for c in cells:

        if not cell_set.has(c + Vector2i(0, 1)):
            edge.append(c)
    return edge



func default_shape(hex_size: int) -> Array:

    match hex_size:
        1:
            return [[0, 0]]
        2:
            return [[0, 0], [1, 0]]
        3:
            return [[0, 0], [1, 0], [0, 1]]
        4:
            return [[0, 0], [1, 0], [0, 1], [1, -1]]
        5:
            return [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]
        6:
            return [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, -1]]
        7:

            return [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1], [1, -1], [-1, 1]]
        _:

            var shape: Array = [[0, 0]]
            var ring = 1
            while shape.size() < hex_size:
                for dir_i in 6:
                    var h = Vector2i(0, 0)

                    for _s in ring:
                        h += NEIGHBORS[4]
                    for side in 6:
                        var d = NEIGHBORS[(side + 2) % 6]
                        for _step in ring:
                            if shape.size() >= hex_size:
                                break
                            if not _shape_has(shape, h):
                                shape.append([h.x, h.y])
                            h += d
                ring += 1
            return shape

func _shape_has(shape: Array, hex: Vector2i) -> bool:
    for c in shape:
        if c[0] == hex.x and c[1] == hex.y:
            return true
    return false







const SUB_HEX_COUNT: int = 7
const SUB_HEX_CENTER: int = 0



const SUB_HEX_OFFSETS: Array = [
    Vector2i(0, 0), 
    Vector2i(1, 0), 
    Vector2i(-1, 0), 
    Vector2i(0, 1), 
    Vector2i(0, -1), 
    Vector2i(1, -1), 
    Vector2i(-1, 1), 
]




const SUB_FOOTPRINT_DEFAULTS: Dictionary = {
    "weapon": [0, 1, 2, 4, 5], 
    "shield": [0, 1, 2, 5, 6], 
    "engine": [0, 1, 2, 3, 6], 
    "reactor": [0, 1, 2, 3, 5], 
    "sensor": [0, 1, 4, 5, 6], 
    "cargo": [0, 1, 2, 3, 6], 
    "quarters": [0, 3, 4, 5, 6], 
    "medbay": [0, 1, 2, 4, 5], 
    "bridge": [0, 1, 2, 4, 5], 
    "armor": [0, 1, 2, 3, 4, 5, 6], 
    "structural": [0], 
    "hallway": [], 
    "conduit": [0, 1], 
    "airlock": [0, 1, 2], 
    "core": [0, 1, 2, 3, 4, 5, 6], 
    "life_support": [0, 1, 2, 3, 5], 
    "fuel_tank": [0, 1, 2, 3, 4, 5], 
    "mess_hall": [0, 3, 6], 
    "brig": [0, 1, 2, 5], 
    "mining": [0, 1, 2, 3, 5], 
    "construction_hangar": [0, 1, 2, 3, 4, 5], 
    "basic_workshop": [0, 1, 2, 3], 
    "farmers_workshop": [0, 1, 2, 3], 
    "solar_field": [0, 1, 2, 3, 4, 5, 6], 
    "docking_collar": [0, 1, 2], 
    "common_room": [0, 3], 
    "animal_pen": [0, 1, 3, 6], 
    "aquaculture_tank": [0, 1, 2, 3, 4, 5], 
}

func get_sub_footprint(module_type: String) -> Array:

    return SUB_FOOTPRINT_DEFAULTS.get(module_type, [0, 1, 2, 4, 5])

func get_open_sub_slots(module_type: String) -> Array:

    var filled = get_sub_footprint(module_type)
    var open: Array = []
    for i in SUB_HEX_COUNT:
        if i not in filled:
            open.append(i)
    return open

func sub_hex_pixel_offset(sub_index: int, main_hex_size: float) -> Vector2:


    if sub_index < 0 or sub_index >= SUB_HEX_OFFSETS.size():
        return Vector2.ZERO
    var sub_size = main_hex_size / 3.0
    return hex_to_pixel(SUB_HEX_OFFSETS[sub_index], sub_size)

func sub_hex_size(main_hex_size: float) -> float:

    return main_hex_size / 3.0



func cells_adjacent(cells_a: Array, cells_b: Array) -> bool:


    for a in cells_a:
        var av = Vector2i(a[0], a[1]) if a is Array else a
        for b in cells_b:
            var bv = Vector2i(b[0], b[1]) if b is Array else b
            if are_neighbors(av, bv):
                return true
    return false

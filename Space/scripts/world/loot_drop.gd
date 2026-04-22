extends Area2D




var module_id: String = ""
var module_name: String = ""
var module_type: String = ""
var pickup_radius: float = 60.0
var lifetime: float = 30.0
var spin_time: float = 0.0
var bob_time: float = 0.0
var collected: bool = false
var scanned: bool = false

signal picked_up(module_id: String)

var type_colors: Dictionary = {
    "weapon": Color(0.9, 0.3, 0.25), 
    "shield": Color(0.3, 0.5, 1.0), 
    "engine": Color(1.0, 0.6, 0.2), 
    "reactor": Color(0.95, 0.82, 0.2), 
    "armor": Color(0.5, 0.55, 0.6), 
    "sensor": Color(0.25, 0.85, 0.45), 
    "conduit": Color(0.6, 0.5, 0.2), 
}

func _ready():
    process_mode = PROCESS_MODE_PAUSABLE
    add_to_group("loot")
    var shape = CircleShape2D.new()
    shape.radius = pickup_radius
    var col = CollisionShape2D.new()
    col.shape = shape
    add_child(col)

    spin_time = randf() * TAU
    bob_time = randf() * TAU

func setup(mod_id: String):
    module_id = mod_id
    var mod_data = DataManager.modules.get(mod_id, {})
    module_name = mod_data.get("name", mod_id)
    module_type = mod_data.get("type", "")

func _process(delta: float):
    if collected:
        return
    spin_time += delta * 2.0
    bob_time += delta * 1.5
    lifetime -= delta
    if lifetime <= 0:
        queue_free()
        return


    var players = get_tree().get_nodes_in_group("player")
    if not players.is_empty():
        var p = players[0]
        if global_position.distance_to(p.global_position) < pickup_radius:
            _collect()

    queue_redraw()

func _collect():
    if collected:
        return
    collected = true
    picked_up.emit(module_id)
    queue_free()

func _draw():
    if collected:
        return

    var base_color = type_colors.get(module_type, Color(0.5, 0.5, 0.5))
    var bob_offset = sin(bob_time) * 3.0


    var glow_alpha = 0.15 + sin(spin_time) * 0.05
    draw_circle(Vector2(0, bob_offset), 18, Color(base_color, glow_alpha))


    var r = 8.0
    var pts = PackedVector2Array()
    for i in 4:
        var angle = spin_time + TAU * i / 4.0
        var stretch_x = cos(spin_time * 0.7) * 0.4 + 0.6
        pts.append(Vector2(cos(angle) * r * stretch_x, sin(angle) * r + bob_offset))
    draw_colored_polygon(pts, base_color * 0.8)
    draw_polyline(pts, base_color * 1.3, 1.5)


    draw_circle(Vector2(0, bob_offset), 2.5, base_color * 1.5)


    var players = get_tree().get_nodes_in_group("player")
    var show_label = scanned
    if not players.is_empty():
        if global_position.distance_to(players[0].global_position) < pickup_radius * 1.5:
            show_label = true

    if show_label:
        var font = ThemeDB.fallback_font
        draw_string(font, Vector2( - module_name.length() * 3, -20 + bob_offset), module_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(base_color, 0.8))


    if lifetime < 5.0:
        modulate.a = clampf(lifetime / 5.0, 0.2, 1.0)

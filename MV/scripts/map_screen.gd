extends CanvasLayer

# Pause-screen map. Tracks visited rooms and renders them as rectangles
# connected by door links. Auto-layouts rooms by BFS from the start room
# using door target connections.

const UIPanels := preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")
const VISITED_COLOR: Color = Color(0.25, 0.45, 0.7, 0.8)
const CURRENT_COLOR: Color = Color(0.4, 0.85, 0.4, 0.9)
const UNVISITED_COLOR: Color = Color(0.2, 0.2, 0.25, 0.4)
const DOOR_COLOR: Color = Color(0.6, 0.6, 0.7, 0.5)
const CELL_SIZE: float = 12.0
const MARGIN: int = 32

var _panel: Control = null
var _canvas: Control = null
var _active: bool = false
var _visited: Dictionary = {}
var _room_positions: Dictionary = {}
var _camera_offset: Vector2 = Vector2.ZERO
var _authored_screen: Control = null
var _authored_pack_id: String = ""

static var _singleton = null


static func instance():
    return _singleton


func _ready() -> void:
    _singleton = self
    layer = 96
    _build_ui()
    visible = false
    _authored_screen = Control.new()
    _authored_screen.set_script(AuthoredScreenRuntime)
    _authored_screen.visible = false
    add_child(_authored_screen)
    _authored_screen.action_requested.connect(_on_authored_action)


func _process(delta: float) -> void:
    if not _mv_runtime_available():
        if _active:
            close()
        return
    if MvDialogueRunner != null and MvDialogueRunner.has_method("is_active") and MvDialogueRunner.is_active():
        return
    if Input.is_action_just_pressed("map"):
        if _active:
            close()
        else:
            open()
    if _active:
        var scroll := Vector2.ZERO
        if Input.is_action_pressed("move_left"):
            scroll.x -= 200.0 * delta
        if Input.is_action_pressed("move_right"):
            scroll.x += 200.0 * delta
        if Input.is_action_pressed("aim_up"):
            scroll.y -= 200.0 * delta
        if Input.is_action_pressed("crouch"):
            scroll.y += 200.0 * delta
        if scroll != Vector2.ZERO:
            _camera_offset += scroll
            _canvas.queue_redraw()


func mark_visited(room_addr: String) -> void:
    _visited[room_addr] = true


func visited_snapshot() -> Dictionary:
    return _visited.duplicate()


func restore_visited(data: Dictionary) -> void:
    _visited = data.duplicate()


func clear() -> void:
    _visited.clear()


func current_map_rooms() -> Array:
    var out: Array = []
    for addr in _room_positions.keys():
        out.append({
            "addr": str(addr),
            "visited": _visited.has(addr),
            "grid": _room_positions[addr],
        })
    return out


func open() -> void:
    if not _mv_runtime_available():
        return
    if _active:
        return
    _active = true
    visible = true
    MvGame.simulation_paused = true
    _refresh_authored_screen()
    _compute_layout()
    _canvas.queue_redraw()


func close() -> void:
    _active = false
    visible = false
    MvGame.simulation_paused = false


func _build_ui() -> void:
    _panel = Control.new()
    _panel.anchor_right = 1.0
    _panel.anchor_bottom = 1.0
    _panel.draw.connect(_draw_bg)

    _canvas = Control.new()
    _canvas.anchor_right = 1.0
    _canvas.anchor_bottom = 1.0
    _canvas.draw.connect(_draw_map)
    _panel.add_child(_canvas)

    add_child(_panel)


func _draw_bg() -> void:
    UIPanels.draw_dim(_panel, Rect2(Vector2.ZERO, _panel.size))


func _compute_layout() -> void:
    _room_positions.clear()
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null or not room_mgr.has_method("rooms"):
        return

    var all_rooms: Dictionary = room_mgr.rooms()
    if all_rooms.is_empty():
        return

    var start_addr: String = ""
    if room_mgr.has_method("current_room"):
        var cur: Dictionary = room_mgr.current_room()
        start_addr = str(cur.get("addr", ""))
    if start_addr.is_empty():
        start_addr = all_rooms.keys()[0]

    _room_positions[start_addr] = Vector2i.ZERO

    var queue: Array = [start_addr]
    var visited_set: Dictionary = { start_addr: true }
    while not queue.is_empty():
        var addr: String = queue.pop_front()
        var info: Dictionary = all_rooms.get(addr, {})
        var doors: Array = info.get("doors", [])
        var base: Vector2i = _room_positions[addr]
        var w_screens: int = maxi(info.get("width_screens", 1), 1)
        var h_screens: int = maxi(info.get("height_screens", 1), 1)

        for door in doors:
            var target: String = str(door.get("target", ""))
            if target.is_empty() or visited_set.has(target):
                continue
            var dir: String = str(door.get("direction", ""))
            var dir_offset := Vector2i.ZERO
            match dir:
                "right":
                    dir_offset = Vector2i(w_screens, 0)
                "left":
                    dir_offset = Vector2i(-maxi(all_rooms.get(target, {}).get("width_screens", 1), 1), 0)
                "down":
                    dir_offset = Vector2i(0, h_screens)
                "up":
                    dir_offset = Vector2i(0, -maxi(all_rooms.get(target, {}).get("height_screens", 1), 1))
            _room_positions[target] = base + dir_offset
            visited_set[target] = true
            queue.append(target)


func _draw_map() -> void:
    if _has_authored_screen():
        return
    var room_mgr: Node = MvGame.room_manager
    if room_mgr == null or not room_mgr.has_method("rooms"):
        return
    var all_rooms: Dictionary = room_mgr.rooms()
    var current_addr: String = ""
    if room_mgr.has_method("current_room"):
        current_addr = str(room_mgr.current_room().get("addr", ""))

    var center := _canvas.size / 2.0 - _camera_offset

    for addr in _room_positions:
        var grid_pos: Vector2i = _room_positions[addr]
        var info: Dictionary = all_rooms.get(addr, {})
        var w: int = maxi(info.get("width_screens", 1), 1)
        var h: int = maxi(info.get("height_screens", 1), 1)

        var rect_pos := center + Vector2(grid_pos.x, grid_pos.y) * CELL_SIZE
        var rect_size := Vector2(w, h) * CELL_SIZE

        var color: Color
        if addr == current_addr:
            color = CURRENT_COLOR
        elif _visited.has(addr):
            color = VISITED_COLOR
        else:
            color = UNVISITED_COLOR

        _canvas.draw_rect(Rect2(rect_pos, rect_size), color)
        _canvas.draw_rect(Rect2(rect_pos, rect_size), color.lightened(0.3), false, 1.0)


func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    return "demo"


func _has_authored_screen() -> bool:
    return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
    if _authored_screen == null:
        return
    var pack_id := _current_pack_id()
    if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "map"):
        _authored_pack_id = ""
        _authored_screen.call("clear_screen")
        _canvas.visible = true
        return
    if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
        _authored_pack_id = pack_id
        var data: Dictionary = UIIo.load_screen(pack_id, "map")
        _authored_screen.call("load_screen", "map", data, HudDataSource.new(null, null))
    _authored_screen.visible = true
    _canvas.visible = false


func _on_authored_action(action_id: String, _action_args: String, _element_id: String) -> void:
    _emit_ui_button_event(action_id, _action_args, _element_id)
    match action_id:
        "close_screen", "resume":
            close()
        "open_screen":
            _open_authored_screen(_action_args)
        "fire_event":
            UiHostActions.fire_authored_event("map", "map_screen", _action_args, _element_id)
        "play_sfx":
            UiHostActions.play_authored_sfx(_action_args)
        _:
            UiHostActions.warn_unhandled_action("map_screen", action_id)


func _open_authored_screen(target: String) -> void:
    match target:
        "", "map":
            return
        "boss_intro", "cinematic":
            UiHostActions.open_cinematic(_current_pack_id(), "map_screen", target)
        "inventory":
            close()
            MvInventoryScreen.open()
        _:
            push_warning("MvMapScreen: open_screen target '%s' is not supported here" % target)


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
    UiHostActions.emit_ui_button_event("map", "map_screen", action_id, action_args, element_id)


func _mv_runtime_available() -> bool:
    return PlanetaryInterface.hosted or MvGame.main != null

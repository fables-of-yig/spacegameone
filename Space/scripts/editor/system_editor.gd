extends Control


const RegIO = preload("res://Space/scripts/shared/reg/reg_io.gd")
const SystemIO = preload("res://Space/scripts/shared/system_io.gd")
const PackAssetIndex = preload("res://Space/scripts/shared/pack_asset_index.gd")
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")
const PsgPanel = preload("res://Space/scripts/editor/psg/psg_panel.gd")
const PsgIO = preload("res://Space/scripts/editor/psg/psg_io.gd")
const FactionsIO = preload("res://Space/scripts/shared/factions_io.gd")

signal closed
signal systems_saved(pack_id: String, systems: Dictionary)
signal region_edit_requested(pack_id: String, region_id: String)


var systems: Dictionary = {}
var _pack_id: String = "demo"
var selected_id: String = ""
var dragging_id: String = ""
var drag_offset: Vector2 = Vector2.ZERO
var connect_mode: bool = false
var connect_from: String = ""
var selected_poi: int = -1
var scroll_y: float = 0.0
var status_text: String = ""
var status_timer: float = 0.0


var dragging_poi: int = -1
var inset_rect: Rect2 = Rect2()
var inset_center: Vector2 = Vector2.ZERO
var inset_scale: float = 1.0

var selected_npc: int = -1
var dragging_npc: int = -1
var drawing_route: bool = false
var template_picker_open: bool = false
var template_list: Array = []
var template_picker_scroll: float = 0.0
var template_picker_rect: Rect2 = Rect2()
var template_picker_rows: Array = []

var sprite_picker_target: String = ""
var sprite_file_dialog: FileDialog = null

var edit_line: LineEdit = null
var editing_key: String = ""
var editing_rect: Rect2 = Rect2()


var field_rects: Array = []
var button_rects: Array = []
var _psg_panel: Control = null
var _psg_target_kind: String = ""  # "poi" or "system_star"
var _psg_target_system_id: String = ""
var _psg_target_poi_index: int = -1

var _undo: RefCounted = null

const PANEL_W: float = 380.0
const TOOLBAR_H: float = 42.0
const NODE_R: float = 18.0

const _FIELD_TIPS: Dictionary = {
    "system_id": "Stable system id used as the key in systems.json. Connections and pack start_system reference this, not the display name.",
    "name": "Display name for this solar system. Shown on the galaxy map and in travel prompts.",
    "star_class": "Star classification string (e.g. G, M, K). Cosmetic — used for flavor in event text and HUD readouts.",
    "faction": "Controlling faction id. Cross-references the faction table in galaxy_data.json; drives hostility defaults for NPCs placed here.",
    "threat_level": "Integer 1+. Controls enemy spawn difficulty and which loot table tier rolls when encounters trigger. Shown as pips under the star on the map.",
    "description": "Free-form flavor text shown to the player when they scan or enter the system.",
    "star_r": "Star color red channel, 0.0–1.0. Previewed in the color swatch on the right.",
    "star_g": "Star color green channel, 0.0–1.0. Previewed in the color swatch on the right.",
    "star_b": "Star color blue channel, 0.0–1.0. Previewed in the color swatch on the right.",
    "star_size": "Radius of the star's visual in pixels when inside this system.",
    "star_sprite": "Optional PNG for the star. Click to open the native file picker in this pack's star art folder. Picking a file from outside that folder copies it in. Right-click clears.",
    "background_image": "Optional PNG tiled behind this system's procedural starfield. Click to open the native file picker in this pack's system background folder. Picking a file from outside that folder copies it in. Right-click clears.",
    "star_anim_frames": "If the star sprite is a horizontal strip, set how many frames it contains. 1 = static sprite.",
    "star_anim_fps": "Frames per second for the custom star strip animation. 0 = static.",
    "star_gravity": "Gravity-well radius in pixels. Pulls the ship toward the star within this range; 0 disables.",
    "poi_id": "Stable POI id used for snapshot keying and trigger lookups. Auto-derived from the name if blank. Should be unique within this system.",
    "poi_name": "POI display name. Appears on the system map and in hail/scan prompts.",
    "poi_type": "POI category: station, hostile_station, salvage, resource, anomaly, ruin, planet. Drives the pip color on the map and which default interactions apply.",
    "poi_desc": "Flavor text shown when the player scans or docks at this POI.",
    "poi_event": "Optional event id fired on arrival. Red ! warning = the event doesn't exist (check the Events tab).",
    "poi_orbit_dist": "Orbital radius in pixels from the star. Larger = further out.",
    "poi_orbit_angle": "Orbital angle in degrees (0 = east, 90 = south). Drag the pip on the inset map to set this visually.",
    "poi_sprite": "Optional PNG for the POI. Click to open the native file picker in this pack's POI art folder. Picking a file from outside that folder copies it in. Right-click clears.",
    "poi_scale": "Visual scale multiplier for the POI sprite. 1.0 = native size.",
    "poi_anim_frames": "If the POI sprite is a horizontal strip, set how many frames it contains. 1 = static sprite.",
    "poi_anim_fps": "Frames per second for the POI strip animation. 0 = static.",
    "poi_gravity": "Gravity-well radius around this POI in pixels. 0 disables.",
    "poi_hidden": "When true, this POI is skipped during spawn until an unlock_poi trigger action records its `id`. Use for gated landings revealed by quests, dialogue, or scanning beacons. Requires the POI to have a stable `id` — if `id` is blank, the POI cannot be unlocked at runtime.",
    "planet_pack": "Optional pack override for cross-pack travel. Leave blank to land inside this campaign pack.",
    # Per-system spawn triggers used to live here; they're authored in the
    # Triggers tab now as ECA rules with event=space_proximity_band /
    # space_system_enter / space_station_destroyed plus the
    # spawn_space_enemies action. See dlg/eca_schema.gd.
    "region_id": "Stable region id (folder name under Content/<pack>/Regions/). Renaming here renames the region on disk and rewrites POI links.",
    "region_name": "Display name for this region. Shown in the landing prompt.",
    "region_spawn_room": "Room address inside this region the player spawns in when landing here. Must exist in the region's rooms.json. The exact spawn position inside the room comes from that room's player_spawn entity.",
    "npc_id": "Unique NPC id within this system. Used by dialogue and event effects to reference this specific NPC.",
    "npc_name": "NPC display name shown in hails and on the HUD.",
    "npc_template": "Template id from the NPC templates library. Applies a default ship + stat block. Click to open the picker.",
    "npc_static_hull": "Optional static hull PNG for this placed NPC. Click to open the native file picker in this pack's ship-art folder. Picking a file from outside that folder copies it in. Right-click clears.",
    "npc_faction": "Faction id. Drives color on the inset map and default hostility toward the player.",
    "npc_hostile": "true = attacks on sight; false = passive/dockable (unless factional rules override).",
    "npc_type": "Behavior archetype: patrol, guard, trader, wanderer. Determines waypoint interpretation.",
    "npc_combat_style": "Combat AI variant. Affects weapon preference, engagement range, and retreat behavior.",
    "npc_hail_event": "Event id fired when the player hails this NPC. Red ! warning = the event doesn't exist.",
    "npc_orbit_dist": "Starting orbital distance from the star in pixels.",
    "npc_orbit_angle": "Starting orbital angle in degrees. Drag the NPC diamond on the inset to set visually.",
    "npc_beh_mode": "Active behavior mode: patrol (follow waypoints), guard (hold position), wander (random roam).",
    "npc_beh_aggro": "Distance in pixels at which the NPC notices and engages the player.",
    "npc_beh_flee": "HP ratio 0.0–1.0 below which the NPC attempts to flee. 0 disables.",
    "npc_beh_respawn": "true = NPC respawns after being destroyed.",
    "npc_beh_respawn_hrs": "In-game hours before respawn. 0 = instant on system re-entry.",
}

const _BUTTON_TIPS: Dictionary = {
    "back_to_campaign": "Close Systems + Planets and return to the campaign editor hub.",
    "add_system": "Create a new solar system node on the galaxy map. Drag it to position after creation.",
    "delete_system": "Delete the currently selected system. Removes it from routes and triggers.",
    "connect_mode": "Toggle connect mode. Click two systems to create a travel route between them.",
    "save": "Save systems and all child data to the active pack on disk.",
    "add_poi": "Add a new point of interest inside the selected system. Drag on the inset map to position.",
    "remove_poi": "Remove the selected POI from this system.",
    "select_poi": "Click to select this POI; shows its fields below and highlights it on the inset map.",
    "add_npc": "Place a new NPC in this system. Drag the diamond on the inset map to position.",
    "remove_npc": "Remove the selected NPC from this system.",
    "select_npc": "Click to select this NPC; shows its fields, behavior, and patrol route below.",
    "add_waypoint": "Add a waypoint to the selected NPC's patrol route at their current position.",
    "remove_wp": "Remove this waypoint from the patrol route.",
    "toggle_draw_route": "Toggle draw-route mode. While active, click the inset map to add waypoints in order; right-click to finish.",
    "open_planet_generator": "Open the planet shader generator. Pick a body type, scrub seed + params, then bake a rotation strip PNG into the active pack and assign it as the POI's sprite.",
    "open_star_generator": "Open the planet shader generator scoped to the system's central star. Bakes into Systems/AstralBodies/Stars and sets star_sprite + star_anim_frames + star_anim_fps.",
    "add_region": "Append a new landable region to this POI. Creates a fresh on-disk region (Content/<pack>/Regions/<id>/) with a starter room and adds an entry to this POI's regions[] list.",
    "region_edit_rooms": "Open the region editor for this region. Use it to author rooms, doors, tiles, entities, and zones.",
    "region_delete": "Remove this region entry from the POI's regions[] list. The on-disk region (Content/<pack>/Regions/<id>/) is left alone — delete it from the file system or with the region editor if you want it gone for good.",
}

func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    _load_systems()
    _undo = EditorUndo.new(_capture_state, _apply_state)
    edit_line = LineEdit.new()
    edit_line.visible = false
    var sb = StyleBoxFlat.new()
    sb.bg_color = Color(0.1, 0.1, 0.14)
    sb.border_color = Color(0.4, 0.6, 1.0)
    sb.set_border_width_all(1)
    sb.set_content_margin_all(3)
    edit_line.add_theme_stylebox_override("normal", sb)
    edit_line.add_theme_stylebox_override("focus", sb)
    edit_line.add_theme_color_override("font_color", Color(1, 1, 0.9))
    edit_line.add_theme_font_size_override("font_size", 13)
    add_child(edit_line)
    edit_line.text_submitted.connect(_on_field_submitted)
    edit_line.focus_exited.connect(_on_edit_focus_lost)

    sprite_file_dialog = FileDialog.new()
    sprite_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    sprite_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    sprite_file_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
    sprite_file_dialog.title = "Pick sprite PNG"
    _enable_native_file_dialog(sprite_file_dialog)
    sprite_file_dialog.file_selected.connect(_on_sprite_file_selected)
    sprite_file_dialog.canceled.connect(_on_sprite_file_dialog_canceled)
    add_child(sprite_file_dialog)

    _psg_panel = Control.new()
    _psg_panel.set_script(PsgPanel)
    _psg_panel.visible = false
    add_child(_psg_panel)
    _psg_panel.cancelled.connect(_on_psg_panel_cancelled)
    _psg_panel.applied.connect(_on_psg_panel_applied)


func open_editor(p_pack_id: String = "") -> void:
    _pack_id = p_pack_id.strip_edges()
    if _pack_id.is_empty():
        _pack_id = "demo"
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    refresh()


func _capture_state() -> Dictionary:
    return {
        "systems": systems.duplicate(true),
        "selected_id": selected_id,
        "selected_poi": selected_poi,
        "selected_npc": selected_npc,
    }


func _apply_state(snap: Dictionary) -> void:
    var s_v: Variant = snap.get("systems", null)
    if typeof(s_v) == TYPE_DICTIONARY:
        systems = s_v
    selected_id = str(snap.get("selected_id", ""))
    selected_poi = int(snap.get("selected_poi", -1))
    selected_npc = int(snap.get("selected_npc", -1))


func refresh():
    _load_systems()
    selected_id = ""
    selected_poi = -1
    selected_npc = -1
    template_picker_open = false
    sprite_picker_target = ""
    drawing_route = false
    if _undo != null:
        _undo.clear()
    queue_redraw()

func _load_systems():
    systems = SystemIO.load_or_init(_pack_id)

func _process(delta: float):
    if status_timer > 0:
        status_timer -= delta
        if status_timer <= 0:
            status_text = ""
    if is_visible_in_tree():
        _update_tooltips()
    queue_redraw()


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    for entry in field_rects:
        var r: Rect2 = entry.get("rect", Rect2())
        if r.has_point(mp):
            var key: String = str(entry.get("key", ""))
            var tip: String = str(_FIELD_TIPS.get(key, ""))
            if tip == "":
                # Strip trailing _<index> for list-row fields (region rows).
                var stripped := key
                var under := key.rfind("_")
                if under > 0 and key.substr(under + 1).is_valid_int():
                    stripped = key.substr(0, under)
                tip = str(_FIELD_TIPS.get(stripped, ""))
            if tip != "":
                EditorTooltip.show_text(tip)
            return
    for entry in button_rects:
        var r: Rect2 = entry.get("rect", Rect2())
        if r.has_point(mp):
            var bid: String = str(entry.get("id", ""))
            var tip: String = str(_BUTTON_TIPS.get(bid, ""))
            if tip == "":
                # Strip trailing _<index> for list-item buttons.
                var stripped := bid
                var under := bid.rfind("_")
                if under > 0 and bid.substr(under + 1).is_valid_int():
                    stripped = bid.substr(0, under)
                tip = str(_BUTTON_TIPS.get(stripped, ""))
            if tip != "":
                EditorTooltip.show_text(tip)
            return



func _canvas_w() -> float:
    return size.x - PANEL_W

func _map_to_screen(map_pos: Array) -> Vector2:
    var cw = _canvas_w()
    var ch = size.y - TOOLBAR_H
    return Vector2(
        map_pos[0] / 1000.0 * (cw - 80) + 40, 
        map_pos[1] / 1000.0 * (ch - 80) + 40
    )

func _screen_to_map(spos: Vector2) -> Array:
    var cw = _canvas_w()
    var ch = size.y - TOOLBAR_H
    return [
        clampf((spos.x - 40) / (cw - 80) * 1000.0, 0, 1000), 
        clampf((spos.y - 40) / (ch - 80) * 1000.0, 0, 1000)
    ]

func _find_system_at(pos: Vector2) -> String:
    for sid in systems:
        var spos = _map_to_screen(systems[sid].get("position", [500, 500]))
        if pos.distance_to(spos) < NODE_R + 6:
            return sid
    return ""



func _draw():
    var font = ThemeDB.fallback_font
    field_rects.clear()
    button_rects.clear()


    var cw = _canvas_w()
    draw_rect(Rect2(0, 0, cw, size.y - TOOLBAR_H), Color(0.04, 0.04, 0.06))


    for gx in range(0, int(cw), 50):
        for gy in range(0, int(size.y - TOOLBAR_H), 50):
            draw_circle(Vector2(gx, gy), 1.0, Color(0.12, 0.12, 0.15))


    for sid in systems:
        var sys = systems[sid]
        var from_pos = _map_to_screen(sys.get("position", [500, 500]))
        for conn_id in sys.get("connections", []):
            if systems.has(conn_id):
                var to_pos = _map_to_screen(systems[conn_id].get("position", [500, 500]))
                var lcol = Color(0.25, 0.35, 0.5, 0.6)
                if sid == selected_id or conn_id == selected_id:
                    lcol = Color(0.4, 0.55, 0.8, 0.8)
                draw_line(from_pos, to_pos, lcol, 1.5)


    for sid in systems:
        var sys = systems[sid]
        var spos = _map_to_screen(sys.get("position", [500, 500]))
        var sc = sys.get("star_color", [1, 1, 1])
        var col = Color(sc[0], sc[1], sc[2])
        var is_selected = (sid == selected_id)


        draw_circle(spos, NODE_R + 6, Color(col, 0.08))

        draw_circle(spos, NODE_R, col if is_selected else col * 0.7)

        if is_selected:
            draw_arc(spos, NODE_R + 4, 0, TAU, 24, Color(0.4, 0.7, 1.0, 0.8), 2.0)

        var threat = sys.get("threat_level", 1)
        for i in threat:
            draw_circle(spos + Vector2( - threat * 3.0 + i * 6.0 + 3, NODE_R + 10), 2.5, Color(1, 0.4, 0.2))

        draw_string(font, spos + Vector2(-30, - NODE_R - 6), sys.get("name", sid), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.9))


    if connect_mode:
        var hint = "CONNECT MODE: Click a system"
        if connect_from != "":
            hint = "CONNECT MODE: Click target system (or same to cancel)"
        draw_string(font, Vector2(10, size.y - TOOLBAR_H - 10), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.3, 0.9, 0.5))


    if selected_id != "" and systems.has(selected_id):
        _draw_system_map_inset(font)


    _draw_toolbar(font)


    _draw_panel(font)


    if drawing_route:
        draw_string(font, Vector2(10, size.y - TOOLBAR_H - 30), "DRAW ROUTE: Click inset to add waypoints, Right-click to finish", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 0.6, 0.2))

    if template_picker_open:
        _draw_template_picker(font)

    if status_text != "":
        draw_string(font, Vector2(cw * 0.5 - 60, size.y - TOOLBAR_H - 10), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.3, 0.9, 0.4))

func _draw_system_map_inset(font: Font):

    var sys = systems[selected_id]
    var pois: Array = sys.get("pois", [])
    var cw = _canvas_w()
    var inset_size: float = minf(cw * 0.4, 200.0)
    var inset_x = cw - inset_size - 10
    var inset_y = 10.0
    var center = Vector2(inset_x + inset_size * 0.5, inset_y + inset_size * 0.5)


    inset_rect = Rect2(inset_x, inset_y, inset_size, inset_size)
    inset_center = center
    draw_rect(inset_rect, Color(0.02, 0.02, 0.04, 0.9))
    draw_rect(inset_rect, Color(0.2, 0.25, 0.35, 0.5), false, 1.0)


    var max_dist: float = 800.0
    for poi in pois:
        var od: float = poi.get("orbit_dist", 500)
        if od > max_dist:
            max_dist = od
    var placed_npcs: Array = sys.get("placed_npcs", [])
    for npc in placed_npcs:
        var od: float = npc.get("orbit_dist", 500)
        if od > max_dist:
            max_dist = od
    var inset_scale_val = (inset_size * 0.4) / max_dist
    inset_scale = inset_scale_val


    var sc = sys.get("star_color", [1, 1, 1])
    var star_col = Color(sc[0], sc[1], sc[2])
    draw_circle(center, 6, Color(star_col, 0.3))
    draw_circle(center, 4, star_col)


    var type_colors: Dictionary = {
        "station": Color(0.3, 0.85, 0.4), 
        "hostile_station": Color(0.95, 0.3, 0.2), 
        "salvage": Color(0.85, 0.75, 0.3), 
        "resource": Color(0.4, 0.7, 0.95), 
        "anomaly": Color(0.7, 0.4, 1.0), 
        "ruin": Color(0.2, 0.85, 0.95), 
        "planet": Color(0.3, 0.7, 0.3), 
    }
    for i in pois.size():
        var poi = pois[i]
        var od: float = poi.get("orbit_dist", 500)
        var oa: float = deg_to_rad(poi.get("orbit_angle", 0))
        var r = od * inset_scale_val

        draw_arc(center, r, 0, TAU, 24, Color(0.15, 0.18, 0.25, 0.3), 0.5)

        var pp = center + Vector2(cos(oa), sin(oa)) * r
        var pt: String = poi.get("type", "anomaly")
        var pc = type_colors.get(pt, Color(0.5, 0.5, 0.5))
        var pip_r = 4.0 if (i == selected_poi) else 3.0
        if i == selected_poi:
            draw_circle(pp, pip_r + 2, Color(1.0, 1.0, 1.0, 0.3))
        draw_circle(pp, pip_r, pc)

        var name_str: String = poi.get("name", "?")
        if name_str.length() > 10:
            name_str = name_str.substr(0, 8) + ".."
        draw_string(font, pp + Vector2(pip_r + 2, 4), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(pc, 0.7))

        var grav = poi.get("gravity_radius", 0)
        if grav > 0:
            var grav_r_inset = grav * inset_scale_val
            draw_arc(pp, grav_r_inset, 0, TAU, 24, Color(pc, 0.15), 1.0)

    # Star gravity well in inset
    var star_grav: float = sys.get("star_gravity", 0)
    if star_grav > 0:
        var sgr = star_grav * inset_scale_val
        draw_arc(center, sgr, 0, TAU, 32, Color(star_col, 0.15), 1.0)

    _draw_npc_pips_on_inset(font, center, inset_scale_val, placed_npcs)

    if dragging_poi >= 0 or dragging_npc >= 0:
        draw_string(font, Vector2(inset_x + 4, inset_y + 12), "Dragging...", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.8, 0.5))

    draw_string(font, Vector2(inset_x + 4, inset_y + inset_size - 4), "SYSTEM MAP (drag POIs/NPCs)", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.45, 0.5))

func _draw_npc_pips_on_inset(font: Font, center: Vector2, sc: float, npcs: Array):
    var factions = DataManager.galaxy_data.get("factions", {})
    for i in npcs.size():
        var npc = npcs[i]
        var od: float = npc.get("orbit_dist", 500)
        var oa: float = deg_to_rad(npc.get("orbit_angle", 0))
        var pp = center + Vector2(cos(oa), sin(oa)) * od * sc
        var fid: String = npc.get("faction", "independent")
        var fc = factions.get(fid, {}).get("color", [0.5, 0.5, 0.55])
        var ncol = Color(fc[0], fc[1], fc[2])
        var pip_s = 5.0 if (i == selected_npc) else 4.0
        if i == selected_npc:
            draw_circle(pp, pip_s + 2, Color(1.0, 1.0, 1.0, 0.4))
        var pts = PackedVector2Array([
            pp + Vector2(0, -pip_s), pp + Vector2(pip_s, 0),
            pp + Vector2(0, pip_s), pp + Vector2(-pip_s, 0)
        ])
        draw_colored_polygon(pts, ncol)
        draw_polyline(pts + PackedVector2Array([pts[0]]), ncol * 1.3, 1.0)
        var npc_name: String = npc.get("name", "?")
        if npc_name.length() > 8:
            npc_name = npc_name.substr(0, 6) + ".."
        draw_string(font, pp + Vector2(pip_s + 2, 4), npc_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(ncol, 0.7))

        var route: Array = npc.get("patrol_route", [])
        if not route.is_empty():
            var prev_wp = pp
            for wi in route.size():
                var wp = route[wi]
                var wd: float = wp.get("dist", 500)
                var wa: float = deg_to_rad(wp.get("angle", 0))
                var wp_pos = center + Vector2(cos(wa), sin(wa)) * wd * sc
                draw_line(prev_wp, wp_pos, Color(ncol, 0.4), 1.0)
                draw_circle(wp_pos, 2.0, Color(ncol, 0.6))
                draw_string(font, wp_pos + Vector2(3, -2), str(wi + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(ncol, 0.5))
                prev_wp = wp_pos

func _draw_toolbar(font: Font):
    var ty = size.y - TOOLBAR_H
    var cw = _canvas_w()
    draw_rect(Rect2(0, ty, cw, TOOLBAR_H), Color(0.08, 0.08, 0.1))

    var btns = [
        {"id": "back_to_campaign", "label": "Back to Campaign"},
        {"id": "add_system", "label": "+ Add System"}, 
        {"id": "delete_system", "label": "- Delete"}, 
        {"id": "connect_mode", "label": "Connect" if not connect_mode else "Cancel Connect"}, 
        {"id": "save", "label": "Save to Disk"}, 
    ]
    var bx = 10.0
    for btn in btns:
        var bw = btn.label.length() * 8.0 + 20
        var r = Rect2(bx, ty + 6, bw, TOOLBAR_H - 12)
        var hover = r.has_point(get_local_mouse_position())
        draw_rect(r, Color(0.2, 0.25, 0.35) if hover else Color(0.14, 0.14, 0.18))
        draw_rect(r, Color(0.35, 0.4, 0.5), false, 1.0)
        draw_string(font, Vector2(bx + 10, ty + TOOLBAR_H - 14), btn.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.9))
        button_rects.append({"id": btn.id, "rect": r})
        bx += bw + 8

func _draw_panel(font: Font):
    var px = _canvas_w()
    var pw = PANEL_W
    draw_rect(Rect2(px, 0, pw, size.y), Color(0.07, 0.07, 0.09))
    draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.2, 0.25, 0.3), 1.0)

    if selected_id == "" or not systems.has(selected_id):
        draw_string(font, Vector2(px + 16, 30), "Select a system on the map", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.4, 0.45))
        return

    var sys = systems[selected_id]
    var x = px + 12.0
    var y = 8.0 - scroll_y


    y = _draw_section("SYSTEM: " + selected_id, x, y, font)
    draw_string(font, Vector2(x + 4, y + 14), "Pack: " + _pack_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.38, 0.46, 0.56))
    y += 18
    y = _draw_field("system_id", "ID", selected_id, x, y, font)
    y = _draw_field("name", "Name", str(sys.get("name", "")), x, y, font)
    y = _draw_field("star_class", "Class", str(sys.get("star_class", "")), x, y, font)
    y = _draw_field("faction", "Faction", str(sys.get("faction", "")), x, y, font)
    var _sys_faction := str(sys.get("faction", "")).strip_edges()
    if not _sys_faction.is_empty() and not _faction_id_exists(_sys_faction):
        _draw_warning(field_rects.back().rect, font)
    y = _draw_field("threat_level", "Threat", str(sys.get("threat_level", 1)), x, y, font)
    y = _draw_field("description", "Desc", str(sys.get("description", "")), x, y, font)
    var _bg = sys.get("background_image", "")
    y = _draw_field("background_image", "Background", _sprite_field_display("background_image", _bg), x, y, font)


    y += 8
    y = _draw_section("STAR COLOR", x, y, font)
    var sc = sys.get("star_color", [1, 1, 1])
    y = _draw_field("star_r", "R", "%.2f" % sc[0], x, y, font)
    y = _draw_field("star_g", "G", "%.2f" % sc[1], x, y, font)
    y = _draw_field("star_b", "B", "%.2f" % sc[2], x, y, font)
    y = _draw_field("star_size", "Star Size", str(int(sys.get("star_size", 60))), x, y, font)
    var _ss = sys.get("star_sprite", "")
    y = _draw_field("star_sprite", "Star Sprite", _sprite_field_display("star_sprite", _ss), x, y, font)
    y = _draw_generate_star_button(x, y, font)
    y = _draw_field("star_anim_frames", "Star Frames", str(int(sys.get("star_anim_frames", 1))), x, y, font)
    y = _draw_field("star_anim_fps", "Star FPS", "%.2f" % float(sys.get("star_anim_fps", 0.0)), x, y, font)
    y = _draw_field("star_gravity", "Gravity R", str(int(sys.get("star_gravity", 0))), x, y, font)

    draw_rect(Rect2(x + PANEL_W - 80, y - 80, 50, 50), Color(sc[0], sc[1], sc[2]))


    y += 8
    y = _draw_section("CONNECTIONS", x, y, font)
    var conns: Array = sys.get("connections", [])
    for c in conns:
        draw_string(font, Vector2(x + 8, y + 14), "- " + c, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.7, 0.8))
        y += 18
    if conns.is_empty():
        draw_string(font, Vector2(x + 8, y + 14), "(none)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.35, 0.4))
        y += 18


    y += 8
    y = _draw_section("POINTS OF INTEREST", x, y, font)
    var pois: Array = sys.get("pois", [])
    for i in pois.size():
        var poi = pois[i]
        var is_sel = (i == selected_poi)
        var py = y
        var pr = Rect2(x + 4, py, PANEL_W - 36, 22)
        draw_rect(pr, Color(0.14, 0.18, 0.25) if is_sel else Color(0.08, 0.08, 0.1))
        if is_sel:
            draw_rect(pr, Color(0.4, 0.6, 0.9), false, 1.0)
        draw_string(font, Vector2(x + 10, py + 16), poi.get("name", "unnamed"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 
            Color(0.85, 0.85, 0.9) if is_sel else Color(0.55, 0.55, 0.6))
        draw_string(font, Vector2(x + 180, py + 16), poi.get("type", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4, 0.5, 0.6))
        button_rects.append({"id": "select_poi_%d" % i, "rect": pr})
        y += 24


    var poi_btn_y = y + 4
    var add_r = Rect2(x + 4, poi_btn_y, 70, 22)
    var rem_r = Rect2(x + 80, poi_btn_y, 70, 22)
    draw_rect(add_r, Color(0.15, 0.2, 0.15))
    draw_rect(add_r, Color(0.3, 0.5, 0.3), false, 1.0)
    draw_string(font, Vector2(x + 14, poi_btn_y + 16), "+ POI", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.85, 0.5))
    button_rects.append({"id": "add_poi", "rect": add_r})
    draw_rect(rem_r, Color(0.2, 0.12, 0.12))
    draw_rect(rem_r, Color(0.5, 0.3, 0.3), false, 1.0)
    draw_string(font, Vector2(x + 90, poi_btn_y + 16), "- POI", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.4, 0.4))
    button_rects.append({"id": "remove_poi", "rect": rem_r})
    y = poi_btn_y + 28


    if selected_poi >= 0 and selected_poi < pois.size():
        y += 4
        y = _draw_section("POI DETAILS", x, y, font)
        var poi = pois[selected_poi]
        y = _draw_field("poi_id", "ID", str(poi.get("id", "")), x, y, font)
        y = _draw_field("poi_name", "Name", str(poi.get("name", "")), x, y, font)
        y = _draw_field("poi_type", "Type", str(poi.get("type", "")), x, y, font)
        y = _draw_field("poi_desc", "Desc", str(poi.get("description", "")), x, y, font)
        y = _draw_field("poi_event", "Event ID", str(poi.get("event_id", "")), x, y, font)
        var _poi_eid = poi.get("event_id", "")
        if _poi_eid != "" and not DataManager.events.has(_poi_eid):
            _draw_warning(field_rects.back().rect, font)
        y = _draw_field("poi_orbit_dist", "Orbit Dist", str(int(poi.get("orbit_dist", 500))), x, y, font)
        y = _draw_field("poi_orbit_angle", "Orbit Angle", str(int(poi.get("orbit_angle", 0))), x, y, font)
        var _ps = poi.get("sprite", "")
        y = _draw_field("poi_sprite", "Sprite", _sprite_field_display("poi_sprite", _ps), x, y, font)
        var _poi_type_str := str(poi.get("type", ""))
        if _poi_type_str == "planet" or _poi_type_str == "star":
            y = _draw_generate_planet_button(x, y, font)
        y = _draw_field("poi_scale", "Scale", "%.2f" % poi.get("visual_scale", 1.0), x, y, font)
        y = _draw_field("poi_anim_frames", "Anim Frames", str(int(poi.get("anim_frames", 1))), x, y, font)
        y = _draw_field("poi_anim_fps", "Anim FPS", "%.2f" % float(poi.get("anim_fps", 0.0)), x, y, font)
        y = _draw_field("poi_gravity", "Gravity R", str(int(poi.get("gravity_radius", 0))), x, y, font)
        y = _draw_field("poi_hidden", "Hidden", str(bool(poi.get("hidden", false))), x, y, font)
        if str(poi.get("type", "")) == "planet":
            var planet_data: Dictionary = _ensure_planet_data(poi)
            y += 4
            y = _draw_section("LANDING TARGET", x, y, font)
            y = _draw_field("planet_pack", "Pack Override", str(planet_data.get("pack_id", _pack_id)), x, y, font)
            y = _draw_regions_list(x, y, font, planet_data)


    # Per-system spawn triggers used to live here as a bespoke stub. They
    # are now authored as ECA rules in the Triggers tab (event
    # space_proximity_band / space_system_enter / space_station_destroyed
    # + action spawn_space_enemies), so the runtime keeps a single
    # condition/action vocabulary across the whole pack.

    y += 8
    y = _draw_section("PLACED NPCs", x, y, font)
    var placed_npcs: Array = sys.get("placed_npcs", [])
    for ni in placed_npcs.size():
        var npc = placed_npcs[ni]
        var is_nsel = (ni == selected_npc)
        var nr = Rect2(x + 4, y, PANEL_W - 36, 22)
        draw_rect(nr, Color(0.18, 0.16, 0.12) if is_nsel else Color(0.08, 0.08, 0.1))
        if is_nsel:
            draw_rect(nr, Color(0.9, 0.7, 0.3), false, 1.0)
        var nlabel = npc.get("name", "NPC %d" % ni)
        var ntype = npc.get("npc_type", "patrol")
        draw_string(font, Vector2(x + 10, y + 16), nlabel, HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
            Color(0.85, 0.85, 0.9) if is_nsel else Color(0.55, 0.55, 0.6))
        draw_string(font, Vector2(x + 180, y + 16), ntype, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.45, 0.35))
        button_rects.append({"id": "select_npc_%d" % ni, "rect": nr})
        y += 24

    var npc_btn_y = y + 4
    var nadd_r = Rect2(x + 4, npc_btn_y, 70, 22)
    var nrem_r = Rect2(x + 80, npc_btn_y, 70, 22)
    draw_rect(nadd_r, Color(0.18, 0.16, 0.1))
    draw_rect(nadd_r, Color(0.6, 0.5, 0.2), false, 1.0)
    draw_string(font, Vector2(x + 14, npc_btn_y + 16), "+ NPC", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.7, 0.3))
    button_rects.append({"id": "add_npc", "rect": nadd_r})
    draw_rect(nrem_r, Color(0.2, 0.12, 0.1))
    draw_rect(nrem_r, Color(0.5, 0.3, 0.2), false, 1.0)
    draw_string(font, Vector2(x + 90, npc_btn_y + 16), "- NPC", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.4, 0.3))
    button_rects.append({"id": "remove_npc", "rect": nrem_r})
    y = npc_btn_y + 28

    if selected_npc >= 0 and selected_npc < placed_npcs.size():
        y += 4
        y = _draw_section("NPC DETAILS", x, y, font)
        var npc = placed_npcs[selected_npc]
        y = _draw_field("npc_id", "ID", str(npc.get("id", "")), x, y, font)
        y = _draw_field("npc_name", "Name", str(npc.get("name", "")), x, y, font)
        y = _draw_field("npc_template", "Template", str(npc.get("template", "(click to pick)")), x, y, font)
        var hull_path: String = str(npc.get("static_hull_path", ""))
        y = _draw_field("npc_static_hull", "Static Hull", _sprite_field_display("npc_static_hull", hull_path), x, y, font)
        y = _draw_field("npc_faction", "Faction", str(npc.get("faction", "independent")), x, y, font)
        var _npc_faction := str(npc.get("faction", "")).strip_edges()
        if not _npc_faction.is_empty() and not _faction_id_exists(_npc_faction):
            _draw_warning(field_rects.back().rect, font)
        y = _draw_field("npc_hostile", "Hostile", str(npc.get("hostile", false)), x, y, font)
        y = _draw_field("npc_type", "Type", str(npc.get("npc_type", "patrol")), x, y, font)
        y = _draw_field("npc_combat_style", "Combat Style", str(npc.get("combat_style", "standard")), x, y, font)
        y = _draw_field("npc_hail_event", "Hail Event", str(npc.get("hail_event_id", "")), x, y, font)
        var _npc_heid = npc.get("hail_event_id", "")
        if _npc_heid != "" and not DataManager.events.has(_npc_heid):
            _draw_warning(field_rects.back().rect, font)
        y = _draw_field("npc_orbit_dist", "Orbit Dist", str(int(npc.get("orbit_dist", 2000))), x, y, font)
        y = _draw_field("npc_orbit_angle", "Orbit Angle", str(int(npc.get("orbit_angle", 0))), x, y, font)

        y += 4
        y = _draw_section("BEHAVIOR", x, y, font)
        var beh: Dictionary = npc.get("behavior", {})
        y = _draw_field("npc_beh_mode", "Mode", str(beh.get("mode", "patrol")), x, y, font)
        y = _draw_field("npc_beh_aggro", "Aggro Range", str(int(beh.get("aggro_range", 1200))), x, y, font)
        y = _draw_field("npc_beh_flee", "Flee Thresh", "%.2f" % beh.get("flee_threshold", 0.2), x, y, font)
        y = _draw_field("npc_beh_respawn", "Respawn", str(beh.get("respawn", false)), x, y, font)
        y = _draw_field("npc_beh_respawn_hrs", "Respawn Hrs", str(int(beh.get("respawn_hours", 0))), x, y, font)

        y += 4
        y = _draw_section("PATROL ROUTE", x, y, font)
        var route: Array = npc.get("patrol_route", [])
        for wi in route.size():
            var wp = route[wi]
            var wp_label = "WP%d: d=%d a=%d" % [wi + 1, int(wp.get("dist", 0)), int(wp.get("angle", 0))]
            draw_string(font, Vector2(x + 8, y + 14), wp_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.55, 0.5))
            var wp_del_r = Rect2(x + PANEL_W - 60, y, 20, 18)
            draw_string(font, Vector2(x + PANEL_W - 56, y + 14), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.4, 0.3))
            button_rects.append({"id": "remove_wp_%d" % wi, "rect": wp_del_r})
            y += 18
        if route.is_empty():
            draw_string(font, Vector2(x + 8, y + 14), "(no waypoints)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.35, 0.35, 0.4))
            y += 18
        var wp_btn_y = y + 4
        var wpadd_r = Rect2(x + 4, wp_btn_y, 60, 22)
        var wpdraw_r = Rect2(x + 70, wp_btn_y, 80, 22)
        draw_rect(wpadd_r, Color(0.15, 0.15, 0.12))
        draw_rect(wpadd_r, Color(0.5, 0.5, 0.3), false, 1.0)
        draw_string(font, Vector2(x + 14, wp_btn_y + 16), "+ WP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.4))
        button_rects.append({"id": "add_waypoint", "rect": wpadd_r})
        var draw_label = "Stop Draw" if drawing_route else "Draw Route"
        draw_rect(wpdraw_r, Color(0.2, 0.15, 0.1) if drawing_route else Color(0.15, 0.12, 0.1))
        draw_rect(wpdraw_r, Color(0.8, 0.5, 0.2) if drawing_route else Color(0.5, 0.4, 0.2), false, 1.0)
        draw_string(font, Vector2(x + 78, wp_btn_y + 16), draw_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.9, 0.6, 0.2))
        button_rects.append({"id": "toggle_draw_route", "rect": wpdraw_r})
        y = wp_btn_y + 28

func _draw_section(title: String, x: float, y: float, font: Font) -> float:
    draw_line(Vector2(x, y + 6), Vector2(x + PANEL_W - 30, y + 6), Color(0.2, 0.25, 0.3), 1.0)
    draw_string(font, Vector2(x + 4, y + 20), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.6, 0.75))
    return y + 26

func _draw_field(key: String, label: String, value: String, x: float, y: float, font: Font) -> float:
    var label_w: float = 80.0
    var val_x = x + label_w
    var val_w = PANEL_W - label_w - 36
    draw_string(font, Vector2(x + 4, y + 15), label + ":", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.55))

    var vr = Rect2(val_x, y + 1, val_w, 18)
    var is_editing = (editing_key == key and edit_line.visible)
    if not is_editing:
        draw_rect(vr, Color(0.1, 0.1, 0.13))

        var display = value
        if display.length() > 35:
            display = display.substr(0, 32) + "..."
        draw_string(font, Vector2(val_x + 4, y + 15), display, HORIZONTAL_ALIGNMENT_LEFT, int(val_w - 8), 12, Color(0.85, 0.85, 0.9))
    field_rects.append({"key": key, "rect": vr, "value": value})
    return y + 22

func _draw_warning(rect: Rect2, font: Font):
    draw_rect(rect, Color(0.9, 0.2, 0.1, 0.25), false, 1.0)
    draw_string(font, Vector2(rect.position.x + rect.size.x - 14, rect.position.y + 14), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.3, 0.2))


# Lightweight existence check used by the inline faction-field warning
# indicator. Loads factions.json on every paint — not free, but the
# system_editor only paints when the panel is dirty, and packs have a
# handful of factions at most. Swap for a cached map if it ever shows up
# in profiles.
func _faction_id_exists(fid: String) -> bool:
    if fid.is_empty():
        return false
    var factions := FactionsIO.load_or_empty(_pack_id)
    return factions.has(fid)



func _draw_template_picker(font: Font):
    var px = _canvas_w() + 20
    var py = 100.0
    var pw = PANEL_W - 40
    var ph = 300.0
    template_picker_rect = Rect2(px, py, pw, ph)
    draw_rect(template_picker_rect, Color(0.06, 0.06, 0.08, 0.95))
    draw_rect(template_picker_rect, Color(0.5, 0.5, 0.3), false, 1.0)
    draw_string(font, Vector2(px + 8, py + 16), "SELECT TEMPLATE (Esc to close)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.5))
    template_picker_rows.clear()
    var row_y = py + 24.0 - template_picker_scroll
    for i in template_list.size():
        var t = template_list[i]
        if row_y + 22 < py + 24 or row_y > py + ph:
            row_y += 22
            continue
        var rr = Rect2(px + 4, row_y, pw - 8, 20)
        var hover = rr.has_point(get_local_mouse_position())
        draw_rect(rr, Color(0.15, 0.15, 0.1) if hover else Color(0.08, 0.08, 0.06))
        var tname: String = t.get("name", "?")
        var tcore: String = t.get("core_id", "?")
        var tmods: int = t.get("module_count", 0)
        draw_string(font, Vector2(px + 10, row_y + 15), tname, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.85, 0.7))
        draw_string(font, Vector2(px + pw - 110, row_y + 15), tcore, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.45))
        draw_string(font, Vector2(px + pw - 40, row_y + 15), "%dm" % tmods, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.45, 0.5, 0.45))
        template_picker_rows.append({"index": i, "rect": rr})
        row_y += 22

func _input(event):
    if not visible:
        return
    if edit_line != null and edit_line.has_focus():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            queue_redraw()


func _gui_input(event: InputEvent):
    if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        if template_picker_open:
            template_picker_open = false
            queue_redraw()
            accept_event()
            return
        if drawing_route:
            drawing_route = false
            queue_redraw()
            accept_event()
            return
        if edit_line != null and edit_line.visible:
            _on_field_submitted(edit_line.text)
            accept_event()
            return
        _request_close()
        accept_event()
        return

    if event is InputEventMouseButton:
        if event.pressed:
            match event.button_index:
                MOUSE_BUTTON_LEFT:
                    _handle_left_click(event.position)
                MOUSE_BUTTON_RIGHT:
                    if drawing_route:
                        drawing_route = false
                        queue_redraw()
                        accept_event()
                    elif template_picker_open:
                        template_picker_open = false
                        queue_redraw()
                        accept_event()
                    elif _try_clear_sprite_field_at(event.position):
                        accept_event()
                MOUSE_BUTTON_WHEEL_UP:
                    if template_picker_open and template_picker_rect.has_point(event.position):
                        template_picker_scroll = maxf(template_picker_scroll - 22, 0)
                        queue_redraw()
                        accept_event()
                    elif event.position.x > _canvas_w():
                        scroll_y = maxf(scroll_y - 30, 0)
                        queue_redraw()
                        accept_event()
                MOUSE_BUTTON_WHEEL_DOWN:
                    if template_picker_open and template_picker_rect.has_point(event.position):
                        template_picker_scroll += 22
                        queue_redraw()
                        accept_event()
                    elif event.position.x > _canvas_w():
                        scroll_y += 30
                        queue_redraw()
                        accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            if dragging_npc >= 0:
                dragging_npc = -1
                if _undo != null:
                    _undo.commit("move npc")
                accept_event()
            elif dragging_poi >= 0:
                dragging_poi = -1
                if _undo != null:
                    _undo.commit("move poi")
                accept_event()
            elif dragging_id != "":
                dragging_id = ""
                if _undo != null:
                    _undo.commit("move system")
                accept_event()

    elif event is InputEventMouseMotion:
        if dragging_npc >= 0 and selected_id != "" and systems.has(selected_id):
            _drag_npc_in_inset(event.position)
            queue_redraw()
            accept_event()
        elif dragging_poi >= 0 and selected_id != "" and systems.has(selected_id):
            _drag_poi_in_inset(event.position)
            queue_redraw()
            accept_event()
        elif dragging_id != "" and systems.has(dragging_id):
            var new_pos = _screen_to_map(event.position - drag_offset)
            systems[dragging_id]["position"] = new_pos
            queue_redraw()
            accept_event()

func _handle_left_click(pos: Vector2):
    if template_picker_open:
        for row in template_picker_rows:
            if row.rect.has_point(pos):
                _select_template(row.index)
                accept_event()
                return
        if not template_picker_rect.has_point(pos):
            template_picker_open = false
            queue_redraw()
        accept_event()
        return

    if edit_line.visible:
        _on_field_submitted(edit_line.text)


    for btn in button_rects:
        if btn.rect.has_point(pos):
            _handle_button(btn.id)
            accept_event()
            return


    for fr in field_rects:
        if fr.rect.has_point(pos):
            if fr.key == "npc_template":
                _open_template_picker()
                accept_event()
                return
            if fr.key in ["poi_sprite", "star_sprite", "npc_static_hull", "background_image"]:
                _open_sprite_picker(fr.key)
                accept_event()
                return
            _start_editing(fr.key, fr.value, fr.rect)
            accept_event()
            return


    if selected_id != "" and systems.has(selected_id) and inset_rect.has_point(pos):
        if drawing_route:
            _add_waypoint_at_inset(pos)
            queue_redraw()
            accept_event()
            return
        var best_npc = _find_npc_at_inset(pos)
        if best_npc >= 0:
            selected_npc = best_npc
            dragging_npc = best_npc
            if _undo != null:
                _undo.begin()
            queue_redraw()
            accept_event()
            return
        var best_i = _find_poi_at_inset(pos)
        if best_i >= 0:
            selected_poi = best_i
            dragging_poi = best_i
            if _undo != null:
                _undo.begin()
        queue_redraw()
        accept_event()
        return


    if pos.x < _canvas_w() and pos.y < size.y - TOOLBAR_H:
        var sid = _find_system_at(pos)
        if connect_mode:
            _handle_connect_click(sid)
        elif sid != "":
            selected_id = sid
            selected_poi = -1
            selected_npc = -1
            scroll_y = 0

            var spos = _map_to_screen(systems[sid].get("position", [500, 500]))
            drag_offset = pos - spos
            dragging_id = sid
            if _undo != null:
                _undo.begin()
        else:
            selected_id = ""
            selected_poi = -1
            selected_npc = -1
        queue_redraw()
        accept_event()

func _handle_button(btn_id: String):
    if btn_id == "back_to_campaign":
        _request_close()
    elif btn_id == "add_system":
        _add_system()
    elif btn_id == "delete_system":
        _delete_system()
    elif btn_id == "connect_mode":
        connect_mode = not connect_mode
        connect_from = ""
    elif btn_id == "save":
        _save_systems()
    elif btn_id == "add_poi":
        _add_poi()
    elif btn_id == "remove_poi":
        _remove_poi()
    elif btn_id.begins_with("select_poi_"):
        selected_poi = int(btn_id.replace("select_poi_", ""))
    elif btn_id == "add_npc":
        _add_npc()
    elif btn_id == "remove_npc":
        _remove_npc()
    elif btn_id.begins_with("select_npc_"):
        selected_npc = int(btn_id.replace("select_npc_", ""))
    elif btn_id == "add_waypoint":
        _add_waypoint()
    elif btn_id == "toggle_draw_route":
        drawing_route = not drawing_route
    elif btn_id.begins_with("remove_wp_"):
        _remove_waypoint_at(int(btn_id.replace("remove_wp_", "")))
    elif btn_id == "open_planet_generator":
        _open_planet_generator()
    elif btn_id == "open_star_generator":
        _open_star_generator()
    elif btn_id == "add_region":
        _add_region_to_selected_poi()
    elif btn_id.begins_with("region_edit_rooms_"):
        _open_region_editor_for_row(int(btn_id.replace("region_edit_rooms_", "")))
    elif btn_id.begins_with("region_delete_"):
        _delete_region_row(int(btn_id.replace("region_delete_", "")))
    queue_redraw()


func _selected_poi_dict() -> Dictionary:
    if selected_id == "" or not systems.has(selected_id) or selected_poi < 0:
        return {}
    var pois: Array = systems[selected_id].get("pois", [])
    if selected_poi >= pois.size():
        return {}
    if typeof(pois[selected_poi]) != TYPE_DICTIONARY:
        return {}
    return pois[selected_poi]


func _add_region_to_selected_poi() -> void:
    var poi: Dictionary = _selected_poi_dict()
    if poi.is_empty():
        return
    var planet_data: Dictionary = _ensure_planet_data(poi)
    var pack_target: String = str(planet_data.get("pack_id", _pack_id)).strip_edges()
    if pack_target.is_empty():
        pack_target = _pack_id
    var regions_v: Variant = planet_data.get("regions", [])
    if typeof(regions_v) != TYPE_ARRAY:
        planet_data["regions"] = []
        regions_v = planet_data["regions"]
    var regions: Array = regions_v
    var used: Dictionary = {}
    for entry_v in regions:
        if typeof(entry_v) == TYPE_DICTIONARY:
            used[str((entry_v as Dictionary).get("id", ""))] = true
    if pack_target == _pack_id:
        # Also exclude region ids already on disk so we don't collide with
        # another POI's existing folder.
        for existing_v in RegIO.list_regions(_pack_id):
            if typeof(existing_v) == TYPE_DICTIONARY:
                used[str((existing_v as Dictionary).get("id", ""))] = true
    var base_name: String = "Region %d" % (regions.size() + 1)
    var new_id: String = RegIO.unique_content_id(base_name, used, "region")

    if _undo != null:
        _undo.begin()

    var new_entry: Dictionary = {
        "id": new_id,
        "name": base_name,
        "spawn_room": "start",
    }
    regions.append(new_entry)
    planet_data["regions"] = regions

    # Create the on-disk region so the entry is immediately editable.
    if pack_target == _pack_id:
        RegIO.create_region(_pack_id, new_id, base_name)

    if _undo != null:
        _undo.commit("add region")
    _set_status("Added region: %s" % new_id)


func _delete_region_row(idx: int) -> void:
    var poi: Dictionary = _selected_poi_dict()
    if poi.is_empty():
        return
    var planet_data: Dictionary = _ensure_planet_data(poi)
    var regions_v: Variant = planet_data.get("regions", [])
    if typeof(regions_v) != TYPE_ARRAY:
        return
    var regions: Array = regions_v
    if idx < 0 or idx >= regions.size() or regions.size() <= 1:
        return
    if _undo != null:
        _undo.begin()
    var removed: String = ""
    if typeof(regions[idx]) == TYPE_DICTIONARY:
        removed = str((regions[idx] as Dictionary).get("id", ""))
    regions.remove_at(idx)
    planet_data["regions"] = regions
    if _undo != null:
        _undo.commit("remove region")
    if not removed.is_empty():
        _set_status("Removed region link: %s (region folder kept)" % removed)


func _open_region_editor_for_row(idx: int) -> void:
    var poi: Dictionary = _selected_poi_dict()
    if poi.is_empty():
        return
    var planet_data: Dictionary = _ensure_planet_data(poi)
    var regions_v: Variant = planet_data.get("regions", [])
    if typeof(regions_v) != TYPE_ARRAY:
        return
    var regions: Array = regions_v
    if idx < 0 or idx >= regions.size():
        return
    if typeof(regions[idx]) != TYPE_DICTIONARY:
        return
    var entry: Dictionary = regions[idx]
    var region_id: String = str(entry.get("id", "")).strip_edges()
    if region_id.is_empty():
        return
    var pack_target: String = str(planet_data.get("pack_id", _pack_id)).strip_edges()
    if pack_target.is_empty():
        pack_target = _pack_id
    # Author edits only the local pack's regions; cross-pack overrides are
    # browsed in their own campaign session.
    if pack_target != _pack_id:
        _set_status("Cannot edit cross-pack region '%s' from this campaign." % region_id)
        return
    region_edit_requested.emit(pack_target, region_id)


func _draw_generate_planet_button(x: float, y: float, font: Font) -> float:
    var btn_h: float = 24.0
    var btn_w: float = PANEL_W - 36.0
    var rect := Rect2(x + 4, y, btn_w, btn_h)
    draw_rect(rect, Color(0.16, 0.22, 0.32))
    draw_rect(rect, Color(0.4, 0.7, 0.95), false, 1.0)
    draw_string(font, Vector2(x + 14, y + 17),
        "Generate planet sprite...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(0.78, 0.9, 1.0))
    button_rects.append({"id": "open_planet_generator", "rect": rect})
    return y + btn_h + 4.0


func _draw_generate_star_button(x: float, y: float, font: Font) -> float:
    var btn_h: float = 24.0
    var btn_w: float = PANEL_W - 36.0
    var rect := Rect2(x + 4, y, btn_w, btn_h)
    draw_rect(rect, Color(0.28, 0.22, 0.14))
    draw_rect(rect, Color(0.96, 0.78, 0.36), false, 1.0)
    draw_string(font, Vector2(x + 14, y + 17),
        "Generate star sprite...", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1.0, 0.9, 0.65))
    button_rects.append({"id": "open_star_generator", "rect": rect})
    return y + btn_h + 4.0


func _open_planet_generator() -> void:
    if _psg_panel == null:
        return
    if selected_id == "" or not systems.has(selected_id) or selected_poi < 0:
        _set_status("Select a planet/star POI first.")
        return
    var pois: Array = systems[selected_id].get("pois", [])
    if selected_poi >= pois.size():
        return
    var poi: Dictionary = pois[selected_poi]
    var poi_type := str(poi.get("type", ""))
    var initial_type: String = "Star" if poi_type == "star" else "GasPlanet"

    var target_dir: String = _sprite_target_dir("poi_sprite")
    var poi_name: String = str(poi.get("name", ""))
    var stem: String = _planetgen_file_stem("poi", selected_id, poi_name, selected_poi)
    var existing_sprite: String = str(poi.get("sprite", ""))
    var sidecar: String = ""
    if not existing_sprite.is_empty():
        var candidate: String = PsgIO.sidecar_path_for(existing_sprite)
        if not candidate.is_empty() and FileAccess.file_exists(candidate):
            sidecar = candidate

    _psg_target_kind = "poi"
    _psg_target_system_id = selected_id
    _psg_target_poi_index = selected_poi

    _psg_panel.position = Vector2.ZERO
    _psg_panel.size = size
    _psg_panel.open(initial_type, randi() % 10000, target_dir, stem, sidecar)


func _open_star_generator() -> void:
    if _psg_panel == null:
        return
    if selected_id == "" or not systems.has(selected_id):
        _set_status("Select a system first.")
        return
    var sys: Dictionary = systems[selected_id]

    var target_dir: String = _sprite_target_dir("star_sprite")
    var stem: String = _planetgen_file_stem("star", selected_id, "", -1)
    var existing_sprite: String = str(sys.get("star_sprite", ""))
    var sidecar: String = ""
    if not existing_sprite.is_empty():
        var candidate: String = PsgIO.sidecar_path_for(existing_sprite)
        if not candidate.is_empty() and FileAccess.file_exists(candidate):
            sidecar = candidate

    _psg_target_kind = "system_star"
    _psg_target_system_id = selected_id
    _psg_target_poi_index = -1

    _psg_panel.position = Vector2.ZERO
    _psg_panel.size = size
    _psg_panel.open("Star", randi() % 10000, target_dir, stem, sidecar)


func _planetgen_file_stem(kind: String, system_id: String, name_hint: String, poi_index: int) -> String:
    var system_part: String = _sanitize_stem(system_id)
    if system_part.is_empty():
        system_part = "system"
    if kind == "star":
        return "%s_star" % system_part
    var name_part: String = _sanitize_stem(name_hint)
    if name_part.is_empty():
        name_part = "poi_%d" % max(0, poi_index)
    return "%s_%s" % [system_part, name_part]


func _sanitize_stem(raw: String) -> String:
    var lower: String = raw.strip_edges().to_lower()
    var out: String = ""
    for i in range(lower.length()):
        var ch: String = lower.substr(i, 1)
        var code: int = ch.unicode_at(0)
        var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
        out += ch if ok else "_"
    while out.find("__") >= 0:
        out = out.replace("__", "_")
    return out.trim_prefix("_").trim_suffix("_")


func _on_psg_panel_cancelled() -> void:
    _psg_target_kind = ""
    _psg_target_system_id = ""
    _psg_target_poi_index = -1
    queue_redraw()


func _on_psg_panel_applied(sprite_path: String, anim_frames: int, anim_fps: float, _sidecar_path: String) -> void:
    if _psg_target_kind == "poi":
        if not systems.has(_psg_target_system_id):
            _psg_target_kind = ""
            return
        var pois: Array = systems[_psg_target_system_id].get("pois", [])
        if _psg_target_poi_index < 0 or _psg_target_poi_index >= pois.size():
            _psg_target_kind = ""
            return
        if _undo != null:
            _undo.begin()
        var poi: Dictionary = pois[_psg_target_poi_index]
        poi["sprite"] = sprite_path
        poi["anim_frames"] = anim_frames
        poi["anim_fps"] = anim_fps
        if _undo != null:
            _undo.commit("bake planet sprite")
        _set_status("Baked: " + sprite_path.get_file())
    elif _psg_target_kind == "system_star":
        if not systems.has(_psg_target_system_id):
            _psg_target_kind = ""
            return
        if _undo != null:
            _undo.begin()
        var sys: Dictionary = systems[_psg_target_system_id]
        sys["star_sprite"] = sprite_path
        sys["star_anim_frames"] = anim_frames
        sys["star_anim_fps"] = anim_fps
        if _undo != null:
            _undo.commit("bake star sprite")
        _set_status("Baked star: " + sprite_path.get_file())
    _psg_target_kind = ""
    _psg_target_system_id = ""
    _psg_target_poi_index = -1
    queue_redraw()

func _handle_connect_click(sid: String):
    if sid == "":
        return
    if connect_from == "":
        connect_from = sid
        _set_status("Selected: " + sid + " — now click target")
    elif connect_from == sid:
        connect_mode = false
        connect_from = ""
    else:
        if _undo != null:
            _undo.begin()
        var sys_a = systems[connect_from]
        var sys_b = systems[sid]
        var conns_a: Array = sys_a.get("connections", [])
        var conns_b: Array = sys_b.get("connections", [])
        if sid in conns_a:
            conns_a.erase(sid)
            conns_b.erase(connect_from)
            _set_status("Disconnected %s <-> %s" % [connect_from, sid])
        else:
            conns_a.append(sid)
            conns_b.append(connect_from)
            _set_status("Connected %s <-> %s" % [connect_from, sid])
        sys_a["connections"] = conns_a
        sys_b["connections"] = conns_b
        connect_mode = false
        connect_from = ""
        if _undo != null:
            _undo.commit("toggle connection")



func _start_editing(key: String, value: String, rect: Rect2):
    editing_key = key
    editing_rect = rect
    edit_line.text = value
    edit_line.position = rect.position
    edit_line.size = rect.size
    edit_line.visible = true
    edit_line.grab_focus()
    edit_line.select_all()

func _on_edit_focus_lost() -> void:
    if edit_line != null and edit_line.visible:
        _on_field_submitted(edit_line.text)

func _rename_selected_system_id(raw_text: String) -> void:
    var old_id := selected_id
    var new_id := raw_text.strip_edges()
    if old_id.is_empty() or not systems.has(old_id):
        return
    if new_id.is_empty():
        _set_status("ERROR: System ID cannot be empty.")
        return
    if new_id == old_id:
        return
    if systems.has(new_id):
        _set_status("ERROR: System ID '%s' already exists." % new_id)
        return

    var sys: Dictionary = systems[old_id]
    systems.erase(old_id)
    systems[new_id] = sys

    for sid_v in systems.keys():
        var sid := str(sid_v)
        var other: Dictionary = systems[sid]
        var conns_v: Variant = other.get("connections", [])
        if typeof(conns_v) != TYPE_ARRAY:
            continue
        var conns: Array = conns_v
        for i in range(conns.size()):
            if str(conns[i]) == old_id:
                conns[i] = new_id
        other["connections"] = conns

    if dragging_id == old_id:
        dragging_id = new_id
    if connect_from == old_id:
        connect_from = new_id
    selected_id = new_id
    _update_manifest_start_system(old_id, new_id)
    _set_status("Renamed system ID: %s -> %s" % [old_id, new_id])

func _update_manifest_start_system(old_id: String, new_id: String) -> void:
    if _pack_id.is_empty():
        return
    var path := PackPaths.writable_pack_file(_pack_id, "Pack.json")
    if not FileAccess.file_exists(path):
        return
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var manifest: Dictionary = parsed
    if str(manifest.get("start_system", "")).strip_edges() != old_id:
        return
    manifest["start_system"] = new_id
    file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        _set_status("WARNING: renamed system, but could not update Pack.json start_system.")
        return
    file.store_string(JSON.stringify(manifest, "\t"))
    file.close()

func _on_field_submitted(text: String):
    if editing_key == "" or selected_id == "" or not systems.has(selected_id):
        edit_line.visible = false
        editing_key = ""
        return

    var sys = systems[selected_id]
    var key = editing_key
    edit_line.visible = false
    editing_key = ""

    if _undo != null:
        _undo.begin()

    match key:
        "system_id":
            _rename_selected_system_id(text)
        "name":
            sys["name"] = text
        "star_class":
            sys["star_class"] = text
        "faction":
            sys["faction"] = text
        "description":
            sys["description"] = text
        "threat_level":
            sys["threat_level"] = clampi(int(text), 1, 10)
        "star_r":
            var sc = sys.get("star_color", [1, 1, 1])
            sc[0] = clampf(float(text), 0, 1)
            sys["star_color"] = sc
        "star_g":
            var sc = sys.get("star_color", [1, 1, 1])
            sc[1] = clampf(float(text), 0, 1)
            sys["star_color"] = sc
        "star_b":
            var sc = sys.get("star_color", [1, 1, 1])
            sc[2] = clampf(float(text), 0, 1)
            sys["star_color"] = sc
        "star_size":
            sys["star_size"] = clampi(int(text), 10, 200)
        "star_anim_frames":
            sys["star_anim_frames"] = maxi(int(text), 1)
        "star_anim_fps":
            sys["star_anim_fps"] = maxf(float(text), 0.0)
        "star_gravity":
            sys["star_gravity"] = maxi(int(text), 0)
        "poi_id":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    var trimmed_id: String = text.strip_edges()
                    pois[selected_poi]["id"] = trimmed_id
                    var planet_data: Dictionary = _ensure_planet_data(pois[selected_poi])
                    planet_data["poi_id"] = trimmed_id
        "poi_name":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["name"] = text
                    if str(pois[selected_poi].get("type", "")) == "planet":
                        var planet_data: Dictionary = _ensure_planet_data(pois[selected_poi])
                        planet_data["name"] = text
        "poi_type":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["type"] = text
                    if text == "planet":
                        var planet_data: Dictionary = _ensure_planet_data(pois[selected_poi])
                        if str(planet_data.get("pack_id", "")).strip_edges().is_empty():
                            planet_data["pack_id"] = _pack_id
                        if str(planet_data.get("name", "")).strip_edges().is_empty():
                            planet_data["name"] = str(pois[selected_poi].get("name", "Planet"))
        "poi_desc":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["description"] = text
        "poi_event":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["event_id"] = text
        "poi_orbit_dist":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["orbit_dist"] = maxf(float(text), 100)
        "poi_orbit_angle":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["orbit_angle"] = fmod(float(text), 360.0)
        "poi_scale":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["visual_scale"] = clampf(float(text), 0.1, 10.0)
        "poi_anim_frames":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["anim_frames"] = maxi(int(text), 1)
        "poi_anim_fps":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["anim_fps"] = maxf(float(text), 0.0)
        "poi_gravity":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    pois[selected_poi]["gravity_radius"] = maxi(int(text), 0)
        "poi_hidden":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    var trimmed := text.strip_edges().to_lower()
                    pois[selected_poi]["hidden"] = trimmed == "true" or trimmed == "1" or trimmed == "yes"
        "planet_pack":
            if selected_poi >= 0:
                var pois: Array = sys.get("pois", [])
                if selected_poi < pois.size():
                    var planet_data: Dictionary = _ensure_planet_data(pois[selected_poi])
                    planet_data["pack_id"] = text.strip_edges()
        _:
            if key.begins_with("npc_"):
                _apply_npc_field(sys, key, text)
            elif key.begins_with("region_"):
                _apply_region_field(sys, key, text)

    if _undo != null:
        _undo.commit("edit " + key)
    queue_redraw()


func _add_system():
    if _undo != null:
        _undo.begin()
    var base_id = "new_system"
    var idx = 1
    while systems.has(base_id + "_" + str(idx)):
        idx += 1
    var sid = base_id + "_" + str(idx)
    systems[sid] = {
        "name": "New System",
        "position": [500, 500],
        "star_class": "G",
        "star_color": [1.0, 1.0, 0.8],
        "star_size": 60,
        "star_sprite": "",
        "star_anim_frames": 1,
        "star_anim_fps": 0.0,
        "star_gravity": 0,
        "background_image": "",
        "description": "",
        "threat_level": 1,
        "faction": "independent",
        "connections": [],
        "pois": [],
        "placed_npcs": []
    }
    selected_id = sid
    selected_poi = -1
    _set_status("Added system: " + sid)
    if _undo != null:
        _undo.commit("add system")

func _delete_system():
    if selected_id == "":
        return
    if _undo != null:
        _undo.begin()
    for sid in systems:
        var conns: Array = systems[sid].get("connections", [])
        conns.erase(selected_id)
    systems.erase(selected_id)
    _set_status("Deleted: " + selected_id)
    selected_id = ""
    selected_poi = -1
    if _undo != null:
        _undo.commit("delete system")

func _add_poi():
    if selected_id == "" or not systems.has(selected_id):
        return
    if _undo != null:
        _undo.begin()
    var pois: Array = systems[selected_id].get("pois", [])
    var angle = pois.size() * 60.0
    var used_ids: Dictionary = {}
    for existing_v in pois:
        if typeof(existing_v) == TYPE_DICTIONARY:
            used_ids[str((existing_v as Dictionary).get("id", ""))] = true
    var new_poi_id: String = RegIO.unique_content_id("poi_%d" % (pois.size() + 1), used_ids, "poi")
    pois.append({
        "id": new_poi_id,
        "name": "New POI",
        "type": "anomaly",
        "description": "",
        "event_id": "",
        "orbit_dist": 800,
        "orbit_angle": angle,
        "sprite": "",
        "visual_scale": 1.0,
        "anim_frames": 1,
        "anim_fps": 0.0,
        "gravity_radius": 0,
        "planet_data": {"poi_id": new_poi_id, "regions": []},
    })
    systems[selected_id]["pois"] = pois
    selected_poi = pois.size() - 1
    if _undo != null:
        _undo.commit("add poi")

func _remove_poi():
    if selected_id == "" or selected_poi < 0:
        return
    var pois: Array = systems[selected_id].get("pois", [])
    if selected_poi < pois.size():
        if _undo != null:
            _undo.begin()
        pois.remove_at(selected_poi)
        selected_poi = mini(selected_poi, pois.size() - 1)
        if _undo != null:
            _undo.commit("remove poi")

func _save_systems():
    DataManager.systems = systems.duplicate(true)
    if SystemIO.save(_pack_id, systems):
        systems_saved.emit(_pack_id, systems.duplicate(true))
        _set_status("Saved systems for pack '%s'." % _pack_id)
    else:
        _set_status("ERROR: Could not write systems for '%s'!" % _pack_id)

func _find_poi_at_inset(pos: Vector2) -> int:

    if selected_id == "" or not systems.has(selected_id):
        return -1
    var pois: Array = systems[selected_id].get("pois", [])
    var best: int = -1
    var best_dist: float = 12.0
    for i in pois.size():
        var poi = pois[i]
        var od: float = poi.get("orbit_dist", 500)
        var oa: float = deg_to_rad(poi.get("orbit_angle", 0))
        var pp = inset_center + Vector2(cos(oa), sin(oa)) * od * inset_scale
        var d = pos.distance_to(pp)
        if d < best_dist:
            best_dist = d
            best = i
    return best

func _drag_poi_in_inset(pos: Vector2):

    if dragging_poi < 0 or selected_id == "" or not systems.has(selected_id):
        return
    var pois: Array = systems[selected_id].get("pois", [])
    if dragging_poi >= pois.size():
        dragging_poi = -1
        return
    var offset = pos - inset_center
    var dist = offset.length() / maxf(inset_scale, 0.001)
    var angle = rad_to_deg(atan2(offset.y, offset.x))
    if angle < 0:
        angle += 360.0
    pois[dragging_poi]["orbit_dist"] = maxf(dist, 100)
    pois[dragging_poi]["orbit_angle"] = fmod(angle, 360.0)

func _add_npc():
    if selected_id == "" or not systems.has(selected_id):
        return
    if _undo != null:
        _undo.begin()
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    var npc_num = npcs.size() + 1
    var nid = "%s_npc_%d" % [selected_id, npc_num]
    npcs.append({
        "id": nid,
        "name": "NPC %d" % npc_num,
        "template": "",
        "static_hull_path": "",
        "faction": systems[selected_id].get("faction", "independent"),
        "hostile": false,
        "npc_type": "patrol",
        "combat_style": "standard",
        "orbit_dist": 2000,
        "orbit_angle": npcs.size() * 45,
        "hail_event_id": "",
        "patrol_route": [],
        "behavior": {
            "mode": "patrol",
            "aggro_range": 1200,
            "flee_threshold": 0.2,
            "respawn": false,
            "respawn_hours": 0,
            "conditions": {}
        }
    })
    systems[selected_id]["placed_npcs"] = npcs
    selected_npc = npcs.size() - 1
    _set_status("Added NPC: " + nid)
    if _undo != null:
        _undo.commit("add npc")

func _remove_npc():
    if selected_id == "" or selected_npc < 0:
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if selected_npc < npcs.size():
        if _undo != null:
            _undo.begin()
        npcs.remove_at(selected_npc)
        selected_npc = mini(selected_npc, npcs.size() - 1)
        drawing_route = false
        if _undo != null:
            _undo.commit("remove npc")
    else:
        drawing_route = false

func _open_template_picker():
    template_list = GameManager.get_template_list()
    template_picker_scroll = 0.0
    template_picker_open = true
    template_picker_rows.clear()

func _select_template(idx: int):
    if idx < 0 or idx >= template_list.size():
        return
    if selected_id == "" or selected_npc < 0:
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if selected_npc < npcs.size():
        if _undo != null:
            _undo.begin()
        npcs[selected_npc]["template"] = template_list[idx].get("name", "")
        if _undo != null:
            _undo.commit("select template")
    template_picker_open = false

func _add_waypoint():
    if selected_id == "" or selected_npc < 0:
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if selected_npc >= npcs.size():
        return
    if _undo != null:
        _undo.begin()
    var npc = npcs[selected_npc]
    var route: Array = npc.get("patrol_route", [])
    var angle = route.size() * 60
    route.append({"dist": npc.get("orbit_dist", 2000), "angle": angle})
    npc["patrol_route"] = route
    if _undo != null:
        _undo.commit("add waypoint")

func _remove_waypoint_at(idx: int):
    if selected_id == "" or selected_npc < 0:
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if selected_npc >= npcs.size():
        return
    var route: Array = npcs[selected_npc].get("patrol_route", [])
    if idx >= 0 and idx < route.size():
        if _undo != null:
            _undo.begin()
        route.remove_at(idx)
        if _undo != null:
            _undo.commit("remove waypoint")

func _add_waypoint_at_inset(pos: Vector2):
    if selected_id == "" or selected_npc < 0:
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if selected_npc >= npcs.size():
        return
    if _undo != null:
        _undo.begin()
    var offset = pos - inset_center
    var dist = offset.length() / maxf(inset_scale, 0.001)
    var angle = rad_to_deg(atan2(offset.y, offset.x))
    if angle < 0:
        angle += 360.0
    var route: Array = npcs[selected_npc].get("patrol_route", [])
    route.append({"dist": maxf(dist, 100), "angle": fmod(angle, 360.0)})
    npcs[selected_npc]["patrol_route"] = route
    if _undo != null:
        _undo.commit("add waypoint")

func _find_npc_at_inset(pos: Vector2) -> int:
    if selected_id == "" or not systems.has(selected_id):
        return -1
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    var best: int = -1
    var best_dist: float = 12.0
    for i in npcs.size():
        var npc = npcs[i]
        var od: float = npc.get("orbit_dist", 500)
        var oa: float = deg_to_rad(npc.get("orbit_angle", 0))
        var pp = inset_center + Vector2(cos(oa), sin(oa)) * od * inset_scale
        var d = pos.distance_to(pp)
        if d < best_dist:
            best_dist = d
            best = i
    return best

func _drag_npc_in_inset(pos: Vector2):
    if dragging_npc < 0 or selected_id == "" or not systems.has(selected_id):
        return
    var npcs: Array = systems[selected_id].get("placed_npcs", [])
    if dragging_npc >= npcs.size():
        dragging_npc = -1
        return
    var offset = pos - inset_center
    var dist = offset.length() / maxf(inset_scale, 0.001)
    var angle = rad_to_deg(atan2(offset.y, offset.x))
    if angle < 0:
        angle += 360.0
    npcs[dragging_npc]["orbit_dist"] = maxf(dist, 100)
    npcs[dragging_npc]["orbit_angle"] = fmod(angle, 360.0)

func _apply_npc_field(sys: Dictionary, key: String, text: String):
    if selected_npc < 0:
        return
    var npcs: Array = sys.get("placed_npcs", [])
    if selected_npc >= npcs.size():
        return
    var npc = npcs[selected_npc]
    match key:
        "npc_id":
            npc["id"] = text
        "npc_name":
            npc["name"] = text
        "npc_faction":
            npc["faction"] = text
        "npc_hostile":
            npc["hostile"] = (text.to_lower() == "true")
        "npc_type":
            npc["npc_type"] = text
        "npc_combat_style":
            npc["combat_style"] = text
        "npc_hail_event":
            npc["hail_event_id"] = text
        "npc_orbit_dist":
            npc["orbit_dist"] = maxf(float(text), 100)
        "npc_orbit_angle":
            npc["orbit_angle"] = fmod(float(text), 360.0)
        "npc_beh_mode":
            npc.get("behavior", {})["mode"] = text
        "npc_beh_aggro":
            npc.get("behavior", {})["aggro_range"] = maxf(float(text), 0)
        "npc_beh_flee":
            npc.get("behavior", {})["flee_threshold"] = clampf(float(text), 0.0, 1.0)
        "npc_beh_respawn":
            npc.get("behavior", {})["respawn"] = (text.to_lower() == "true")
        "npc_beh_respawn_hrs":
            npc.get("behavior", {})["respawn_hours"] = maxi(int(text), 0)


# Per-region field writes. key shape: "region_<field>_<index>".
func _apply_region_field(sys: Dictionary, key: String, text: String) -> void:
    if selected_poi < 0:
        return
    var pois: Array = sys.get("pois", [])
    if selected_poi >= pois.size():
        return
    var poi: Dictionary = pois[selected_poi]
    var planet_data: Dictionary = _ensure_planet_data(poi)
    var regions_v: Variant = planet_data.get("regions", [])
    if typeof(regions_v) != TYPE_ARRAY:
        return
    var regions: Array = regions_v
    var under: int = key.rfind("_")
    if under <= 0:
        return
    var suffix: String = key.substr(under + 1)
    if not suffix.is_valid_int():
        return
    var idx: int = int(suffix)
    if idx < 0 or idx >= regions.size():
        return
    if typeof(regions[idx]) != TYPE_DICTIONARY:
        return
    var entry: Dictionary = regions[idx]
    var base_key: String = key.substr(0, under)
    var pack_target: String = str(planet_data.get("pack_id", _pack_id)).strip_edges()
    if pack_target.is_empty():
        pack_target = _pack_id
    match base_key:
        "region_id":
            var raw_id: String = text.strip_edges()
            if raw_id.is_empty():
                return
            var sanitized: String = RegIO.sanitize_content_id(raw_id, "region")
            var old_id: String = str(entry.get("id", "")).strip_edges()
            entry["id"] = sanitized
            # Reflect the change on disk only inside this campaign pack.
            if pack_target == _pack_id and not old_id.is_empty() and old_id != sanitized:
                RegIO.rename_region(_pack_id, old_id, sanitized, str(entry.get("name", sanitized)))
        "region_name":
            var trimmed_name: String = text.strip_edges()
            entry["name"] = trimmed_name
            var region_id: String = str(entry.get("id", "")).strip_edges()
            if pack_target == _pack_id and not region_id.is_empty() and not trimmed_name.is_empty():
                var meta: Dictionary = RegIO.load_region(_pack_id, region_id)
                meta["name"] = trimmed_name
                RegIO.save_region_meta(_pack_id, region_id, meta)
        "region_spawn_room":
            entry["spawn_room"] = text.strip_edges()


func _set_status(text: String):
    status_text = text
    status_timer = 3.0


func _open_sprite_picker(target: String):
    sprite_picker_target = target
    if sprite_file_dialog == null:
        return
    var target_dir: String = _sprite_target_dir(target)
    if target_dir.is_empty():
        return
    sprite_file_dialog.title = _sprite_picker_title(target)
    _ensure_directory_exists(target_dir)
    var global_target_dir: String = ProjectSettings.globalize_path(target_dir)
    if DirAccess.dir_exists_absolute(global_target_dir):
        sprite_file_dialog.current_dir = global_target_dir
    else:
        sprite_file_dialog.current_dir = ProjectSettings.globalize_path("res://")
    sprite_file_dialog.popup_centered_ratio(0.8)


func _on_sprite_file_selected(selected_path: String) -> void:
    var target: String = sprite_picker_target
    sprite_picker_target = ""
    if target.is_empty():
        return
    var final_path: String = _prepare_sprite_path_for_target(target, selected_path)
    if final_path.is_empty():
        _set_status("Sprite pick failed")
        return
    if _assign_sprite_path(target, final_path):
        _set_status("Sprite: " + final_path.get_file())


func _on_sprite_file_dialog_canceled() -> void:
    sprite_picker_target = ""


func _assign_sprite_path(target: String, path: String) -> bool:
    if _undo != null:
        _undo.begin()
    var did: bool = false
    if target == "poi_sprite":
        if selected_id != "" and systems.has(selected_id) and selected_poi >= 0:
            var pois: Array = systems[selected_id].get("pois", [])
            if selected_poi < pois.size():
                pois[selected_poi]["sprite"] = path
                did = true
    elif target == "npc_static_hull":
        if selected_id != "" and systems.has(selected_id) and selected_npc >= 0:
            var npcs: Array = systems[selected_id].get("placed_npcs", [])
            if selected_npc < npcs.size():
                npcs[selected_npc]["static_hull_path"] = path
                did = true
    elif target == "star_sprite":
        if selected_id != "" and systems.has(selected_id):
            systems[selected_id]["star_sprite"] = path
            did = true
    elif target == "background_image":
        if selected_id != "" and systems.has(selected_id):
            systems[selected_id]["background_image"] = path
            did = true
    if _undo != null:
        if did:
            _undo.commit("select sprite")
        else:
            _undo.discard()
    if did:
        queue_redraw()
    return did


func _try_clear_sprite_field_at(pos: Vector2) -> bool:
    for fr in field_rects:
        if not fr.rect.has_point(pos):
            continue
        var key: String = str(fr.key)
        if not ["poi_sprite", "star_sprite", "npc_static_hull", "background_image"].has(key):
            return false
        if _assign_sprite_path(key, ""):
            _set_status("Sprite cleared")
        return true
    return false


func _sprite_target_dir(target: String) -> String:
    match target:
        "star_sprite":
            return PackAssetIndex.user_pack_dir(_pack_id) + "Systems/AstralBodies/Stars"
        "poi_sprite":
            return PackAssetIndex.user_pack_dir(_pack_id) + "Systems/AstralBodies/Pois"
        "background_image":
            return PackAssetIndex.user_pack_dir(_pack_id) + "Systems/Backgrounds"
        "npc_static_hull":
            return "res://Space/art/ships/%s/Hulls" % _pack_id
        _:
            return ""


func _sprite_picker_title(target: String) -> String:
    match target:
        "star_sprite":
            return "Pick star sprite PNG"
        "poi_sprite":
            return "Pick POI sprite PNG"
        "background_image":
            return "Pick system background PNG"
        "npc_static_hull":
            return "Pick static hull PNG"
        _:
            return "Pick sprite PNG"


func _prepare_sprite_path_for_target(target: String, selected_path: String) -> String:
    var source_abs: String = selected_path.strip_edges()
    if source_abs.is_empty():
        return ""
    var source_local: String = ProjectSettings.localize_path(source_abs).replace("\\", "/")
    var target_dir: String = _sprite_target_dir(target)
    if target_dir.is_empty():
        return ""
    _ensure_directory_exists(target_dir)
    if _path_is_in_dir(source_local, target_dir):
        return source_local
    var dest_name: String = _sanitize_asset_file_name(source_abs.get_file(), _sprite_import_prefix(target))
    var dest_path: String = _next_available_import_path(target_dir, dest_name)
    if _copy_binary_file(source_abs, ProjectSettings.globalize_path(dest_path)):
        return dest_path
    return ""


func _next_available_import_path(target_dir: String, file_name: String) -> String:
    var clean_name: String = _sanitize_asset_file_name(file_name.get_file())
    var base_name: String = clean_name.get_basename().strip_edges()
    var ext: String = clean_name.get_extension().to_lower()
    var candidate: String = target_dir + "/" + clean_name
    var counter: int = 2
    while FileAccess.file_exists(candidate):
        candidate = "%s/%s_%d.%s" % [target_dir, base_name, counter, ext]
        counter += 1
    return candidate


func _sprite_import_prefix(target: String) -> String:
    match target:
        "star_sprite":
            return "star"
        "poi_sprite":
            return "poi"
        "background_image":
            return "background"
        "npc_static_hull":
            return "hull"
        _:
            return "sprite"


func _sanitize_asset_file_name(file_name: String, fallback_stem: String = "sprite") -> String:
    var trimmed: String = file_name.strip_edges()
    var ext: String = trimmed.get_extension().to_lower()
    if ext.is_empty():
        ext = "png"
    var base_name: String = trimmed.get_basename().to_lower()
    var out: String = ""
    for i in range(base_name.length()):
        var ch: String = base_name.substr(i, 1)
        var code: int = ch.unicode_at(0)
        var ok: bool = (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
        out += ch if ok else "_"
    while out.find("__") >= 0:
        out = out.replace("__", "_")
    out = out.trim_prefix("_").trim_suffix("_")
    if out.is_empty():
        out = fallback_stem
    return "%s.%s" % [out, ext]


func _sprite_field_display(target: String, raw_path: String) -> String:
    var path: String = raw_path.strip_edges()
    if path.is_empty():
        return "(none)"
    var target_dir: String = _sprite_target_dir(target).replace("\\", "/").trim_suffix("/")
    var clean_path: String = path.replace("\\", "/")
    if _path_is_in_dir(clean_path, target_dir):
        var rel: String = clean_path.trim_prefix(target_dir + "/")
        var dir_name: String = target_dir.get_file()
        return "%s/%s" % [dir_name, rel]
    var writable_root := PackPaths.writable_pack_dir(_pack_id)
    if clean_path.begins_with(writable_root):
        return clean_path.trim_prefix(writable_root)
    if clean_path.begins_with("res://"):
        return clean_path.trim_prefix("res://")
    return clean_path.get_file()


func _copy_binary_file(source_path: String, dest_path: String) -> bool:
    var src := FileAccess.open(source_path, FileAccess.READ)
    if src == null:
        return false
    var bytes := src.get_buffer(src.get_length())
    src.close()
    if bytes.is_empty():
        return false
    var dest_dir: String = dest_path.get_base_dir()
    if not dest_dir.is_empty():
        DirAccess.make_dir_recursive_absolute(dest_dir)
    var dst := FileAccess.open(dest_path, FileAccess.WRITE)
    if dst == null:
        return false
    dst.store_buffer(bytes)
    dst.close()
    return true


func _ensure_directory_exists(path: String) -> void:
    var global_path: String = ProjectSettings.globalize_path(path)
    if not global_path.is_empty():
        DirAccess.make_dir_recursive_absolute(global_path)


func _path_is_in_dir(path: String, dir_path: String) -> bool:
    var clean_path: String = path.replace("\\", "/").trim_suffix("/")
    var clean_dir: String = dir_path.replace("\\", "/").trim_suffix("/")
    return clean_path == clean_dir or clean_path.begins_with(clean_dir + "/")


func _ensure_planet_data(poi: Dictionary) -> Dictionary:
    var planet_data: Dictionary = poi.get("planet_data", {})
    if planet_data.is_empty():
        planet_data = {
            "name": str(poi.get("name", "Planet")),
            "pack_id": _pack_id,
            "poi_id": str(poi.get("id", "")).strip_edges(),
            "regions": [],
        }
        poi["planet_data"] = planet_data

    # Strip legacy realm fields if present from older saves.
    planet_data.erase("realm_id")
    planet_data.erase("region_id")
    planet_data.erase("spawn_room")
    planet_data.erase("spawn_pos")

    if str(planet_data.get("name", "")).strip_edges().is_empty():
        planet_data["name"] = str(poi.get("name", "Planet"))
    if str(planet_data.get("pack_id", "")).strip_edges().is_empty():
        planet_data["pack_id"] = _pack_id
    if str(planet_data.get("poi_id", "")).strip_edges().is_empty():
        planet_data["poi_id"] = str(poi.get("id", "")).strip_edges()

    var target_pack: String = str(planet_data.get("pack_id", _pack_id)).strip_edges()
    if target_pack.is_empty():
        target_pack = _pack_id

    var regions_v: Variant = planet_data.get("regions", null)
    if typeof(regions_v) != TYPE_ARRAY:
        planet_data["regions"] = []
        regions_v = planet_data["regions"]
    var regions: Array = regions_v

    # Seed a default region row if none exist so the panel is never empty
    # and the runtime landing always has something to spawn into.
    if regions.is_empty() and target_pack == _pack_id:
        var default_region: String = RegIO.default_region_id(target_pack)
        if not default_region.is_empty():
            var spawn_room: String = RegIO.get_region_start_room(target_pack, default_region)
            var bare_room: String = spawn_room
            var slash: int = spawn_room.find("/")
            if slash >= 0:
                bare_room = spawn_room.substr(slash + 1)
            regions.append({
                "id": default_region,
                "name": default_region.capitalize(),
                "spawn_room": bare_room if not bare_room.is_empty() else "start",
            })
            planet_data["regions"] = regions

    # Normalize every entry so the panel can render uniformly. Strip the
    # retired spawn_pos field if a prior save left one behind.
    for i in range(regions.size()):
        var entry_v: Variant = regions[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            regions[i] = {"id": "", "name": "", "spawn_room": "start"}
            continue
        var entry: Dictionary = entry_v
        if not entry.has("id"):
            entry["id"] = ""
        if not entry.has("name"):
            entry["name"] = str(entry.get("id", "")).capitalize()
        if not entry.has("spawn_room"):
            entry["spawn_room"] = "start"
        entry.erase("spawn_pos")

    return planet_data


# Renders the per-POI regions[] list. Each row exposes the region id, name,
# and spawn room, with an Edit Rooms button (opens the region editor through
# the host) and a Delete button (kept only when the list has more than one
# entry). The exact spawn position inside the room comes from that room's
# player_spawn entity at land time. Returns the next y cursor for the caller.
func _draw_regions_list(x: float, y: float, font: Font, planet_data: Dictionary) -> float:
    y += 4
    y = _draw_section("REGIONS", x, y, font)
    var regions_v: Variant = planet_data.get("regions", [])
    var regions: Array = regions_v if typeof(regions_v) == TYPE_ARRAY else []
    var row_w: float = PANEL_W - 36.0

    for i in range(regions.size()):
        var entry_v: Variant = regions[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v

        # Region header strip — keeps the row identifiable.
        var header_rect: Rect2 = Rect2(x + 4, y, row_w, 18)
        draw_rect(header_rect, Color(0.1, 0.16, 0.22))
        draw_rect(header_rect, Color(0.36, 0.52, 0.78, 0.85), false, 1.0)
        draw_string(font, Vector2(x + 10, y + 13),
            "Region #%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
            Color(0.78, 0.86, 0.96))
        y += 22

        y = _draw_field("region_id_%d" % i, "ID", str(entry.get("id", "")), x, y, font)
        y = _draw_field("region_name_%d" % i, "Name", str(entry.get("name", "")), x, y, font)
        y = _draw_field("region_spawn_room_%d" % i, "Spawn Room",
            str(entry.get("spawn_room", "")), x, y, font)

        # Edit Rooms + Delete row.
        var btn_y: float = y + 2
        var edit_w: float = 110.0
        var del_w: float = 70.0
        var edit_r: Rect2 = Rect2(x + 4, btn_y, edit_w, 22)
        draw_rect(edit_r, Color(0.14, 0.22, 0.32))
        draw_rect(edit_r, Color(0.36, 0.62, 0.95), false, 1.0)
        draw_string(font, Vector2(edit_r.position.x + 10, btn_y + 16),
            "Edit Rooms", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.78, 0.92, 1.0))
        button_rects.append({"id": "region_edit_rooms_%d" % i, "rect": edit_r})

        if regions.size() > 1:
            var del_r: Rect2 = Rect2(x + 4 + edit_w + 8.0, btn_y, del_w, 22)
            draw_rect(del_r, Color(0.22, 0.12, 0.14))
            draw_rect(del_r, Color(0.62, 0.32, 0.38), false, 1.0)
            draw_string(font, Vector2(del_r.position.x + 12, btn_y + 16),
                "Delete", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.95, 0.65, 0.65))
            button_rects.append({"id": "region_delete_%d" % i, "rect": del_r})
        y = btn_y + 28

    # Add region trailing button.
    var add_y: float = y + 4
    var add_r: Rect2 = Rect2(x + 4, add_y, row_w, 24)
    draw_rect(add_r, Color(0.12, 0.18, 0.12))
    draw_rect(add_r, Color(0.3, 0.62, 0.42), false, 1.0)
    draw_string(font, Vector2(add_r.position.x + 14, add_y + 17),
        "+ Add region", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(0.62, 0.92, 0.68))
    button_rects.append({"id": "add_region", "rect": add_r})
    return add_y + 30


func _request_close() -> void:
    visible = false
    closed.emit()

func _enable_native_file_dialog(dialog: FileDialog) -> void:
    for prop_v in dialog.get_property_list():
        if typeof(prop_v) != TYPE_DICTIONARY:
            continue
        var prop: Dictionary = prop_v
        if str(prop.get("name", "")) == "use_native_dialog":
            dialog.set("use_native_dialog", true)
            return

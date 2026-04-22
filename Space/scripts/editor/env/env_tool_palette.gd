extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const EnvTypes = preload("res://Space/scripts/editor/env/env_types.gd")

# Left-side tool palette: tool selection, dynamic tile-layer list with
# add/remove/reorder/speed controls, edit-mode switcher (collision/
# entities/doors), and overlay toggle. Each button dispatches to the
# parent editor and queues a redraw. The whole panel scrolls vertically
# when the tile_layers list grows beyond the visible area.

var editor: Node = null

const PAD_X: float = 16.0
const ROW_H_TOOL: float = 32.0
const ROW_H_LAYER: float = 28.0
const ROW_H_BTN: float = 26.0
const GAP_SM: float = 4.0
const GAP_LG: float = 14.0

var _tool_rects: Array = []
var _layer_rects: Array = []
var _layer_action_rects: Array = []  # up/down/×/speed/rename on active layer
var _add_rects: Array = []            # + BG / + FG
var _mode_rects: Array = []           # collision / entities / doors
var _overlay_rects: Array = []
var _collision_brush_rects: Array = []
var _slope_shape_rects: Array = []
var _slope_toggle_rects: Array = []

var _scroll_y: float = 0.0
var _content_h: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(_delta):
    queue_redraw()


func _gui_input(event):
    if editor == null:
        return

    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            var max_scroll := maxf(_content_h - size.y, 0.0)
            _scroll_y = minf(_scroll_y + 28.0, max_scroll)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll_y = maxf(_scroll_y - 28.0, 0.0)
            accept_event()
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            for entry in _tool_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    if entry.get("enabled", true):
                        editor.set_active_tool(int(entry["tool"]))
                    accept_event()
                    return
            for entry in _layer_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    editor.set_active_tile_layer(int(entry["idx"]))
                    accept_event()
                    return
            for entry in _layer_action_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    _dispatch_layer_action(str(entry["action"]))
                    accept_event()
                    return
            for entry in _add_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    editor.add_tile_layer(str(entry["role"]))
                    accept_event()
                    return
            for entry in _mode_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    editor.set_active_mode(int(entry["mode"]))
                    accept_event()
                    return
            for entry in _overlay_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    if str(entry["key"]) == "collision":
                        editor.show_collision = not editor.show_collision
                    accept_event()
                    return
            for entry in _collision_brush_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    editor.set_selected_collision_nibble(int(entry["nibble"]))
                    accept_event()
                    return
            for entry in _slope_shape_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    editor.set_selected_collision_nibble(EnvTypes.BT_SLOPE)
                    editor.set_selected_slope_shape(int(entry["shape"]))
                    accept_event()
                    return
            for entry in _slope_toggle_rects:
                if (entry["rect"] as Rect2).has_point(mb.position):
                    var key := str(entry["key"])
                    if key == "hflip":
                        editor.set_selected_collision_nibble(EnvTypes.BT_SLOPE)
                        editor.toggle_selected_slope_hflip()
                    elif key == "vflip":
                        editor.set_selected_collision_nibble(EnvTypes.BT_SLOPE)
                        editor.toggle_selected_slope_vflip()
                    elif key == "respawn":
                        editor.set_selected_collision_nibble(EnvTypes.BT_CRUMBLE)
                        editor.set_selected_crumble_reload_only(false)
                    elif key == "reload_only":
                        editor.set_selected_collision_nibble(EnvTypes.BT_CRUMBLE)
                        editor.set_selected_crumble_reload_only(true)
                    accept_event()
                    return


func _dispatch_layer_action(action: String) -> void:
    var idx: int = editor.active_tile_layer_idx
    match action:
        "up":
            editor.move_tile_layer(idx, -1)
        "down":
            editor.move_tile_layer(idx, 1)
        "remove":
            editor.remove_tile_layer(idx)
        "speed":
            _prompt_edit_speed(idx)
        "rename":
            _prompt_rename_layer(idx)


func _prompt_edit_speed(idx: int) -> void:
    @warning_ignore("unused_parameter")
    var _unused_idx := idx
    return


func _on_speed_submitted(text: String, idx: int) -> void:
    var parts := text.strip_edges().split(",")
    if parts.size() == 0:
        return
    var sx := float(parts[0])
    var sy := sx
    if parts.size() >= 2:
        sy = float(parts[1])
    editor.set_tile_layer_scroll(idx, sx, sy)


func _prompt_rename_layer(idx: int) -> void:
    var layers: Array = editor.get_tile_layers()
    if idx < 0 or idx >= layers.size():
        return
    var layer_v: Variant = layers[idx]
    if typeof(layer_v) != TYPE_DICTIONARY:
        return
    var current_name := str((layer_v as Dictionary).get("name", "Layer"))
    editor.show_text_modal("Rename layer", current_name,
        "New name for this tile layer.",
        Callable(self, "_on_rename_submitted").bind(idx))


func _on_rename_submitted(new_name: String, idx: int) -> void:
    var trimmed := new_name.strip_edges()
    if trimmed.is_empty():
        return
    editor.rename_tile_layer(idx, trimmed)


func _draw():
    UIPanels.draw_panel(self, Rect2(Vector2.ZERO, size),
        Color.WHITE, UIPanels.PanelVariant.DARK)

    if editor == null:
        return
    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    _tool_rects.clear()
    _layer_rects.clear()
    _layer_action_rects.clear()
    _add_rects.clear()
    _mode_rects.clear()
    _overlay_rects.clear()
    _collision_brush_rects.clear()
    _slope_shape_rects.clear()
    _slope_toggle_rects.clear()

    var btn_w: float = size.x - PAD_X * 2.0
    var y: float = 24.0 - _scroll_y

    # ─── TOOLS ───────────────────────────────────────────────────────────
    _draw_section_label(font, y, "TOOLS")
    y += 18.0
    var tool_defs := [
        {"tool": EnvTypes.TOOL_PAINT, "label": "PAINT", "tint": Color(0.45, 0.85, 0.55),
            "tip": "Paint tool — LMB places the selected tile on the active tile layer (or the selected brush in collision/entities/doors mode)."},
        {"tool": EnvTypes.TOOL_ERASE, "label": "ERASE", "tint": Color(0.9, 0.5, 0.45),
            "tip": "Erase tool — LMB clears tiles (or collision/entities/doors) on the active layer. RMB always erases regardless of selected tool."},
        {"tool": EnvTypes.TOOL_FILL, "label": "FILL", "tint": Color(0.6, 0.7, 1.0),
            "tip": "Flood fill — click to fill every connected matching tile with the selected tile. Respects the active tile layer."},
        {"tool": EnvTypes.TOOL_PICK, "label": "PICK", "tint": Color(0.95, 0.85, 0.4),
            "tip": "Eyedropper — click a tile on the canvas to adopt it as the active brush. Switches to PAINT automatically after picking."},
        {"tool": EnvTypes.TOOL_ANIMATE, "label": "ANIM", "tint": Color(0.7, 0.55, 0.95),
            "tip": "Animate — click a tile cell to open animation settings. Only available in TILE edit mode.",
            "tile_only": true},
    ]
    for def in tool_defs:
        var rect := Rect2(PAD_X, y, btn_w, ROW_H_TOOL)
        var tile_only: bool = def.get("tile_only", false)
        var enabled: bool = true
        if tile_only and editor.active_mode != EnvTypes.MODE_TILE:
            enabled = false
        _tool_rects.append({"tool": def["tool"], "rect": rect, "enabled": enabled})
        var is_active: bool = enabled and int(def["tool"]) == editor.active_tool
        var tint: Color = def["tint"]
        if not enabled:
            tint = Color(tint.r * 0.35, tint.g * 0.35, tint.b * 0.35, 1.0)
        elif not is_active:
            tint = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6, 1.0)
        var hover := rect.has_point(mouse_pos)
        UIPanels.draw_button_bg(self, rect, hover and enabled, tint)
        var label_col: Color
        if not enabled:
            label_col = Color(0.45, 0.5, 0.58, 1)
        elif is_active:
            label_col = Color(1, 1, 1, 1)
        else:
            label_col = Color(0.65, 0.72, 0.85, 1)
        draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 21),
            str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_col)
        if hover:
            if enabled:
                EditorTooltip.show_text(str(def["tip"]))
            else:
                EditorTooltip.show_text("ANIM is only available in TILE edit mode.")
        y += ROW_H_TOOL + GAP_SM

    y += GAP_LG

    # ─── TILE LAYERS ─────────────────────────────────────────────────────
    _draw_section_label(font, y, "TILE LAYERS")
    y += 18.0

    var tile_layers: Array = editor.get_tile_layers()
    var editing_tile: bool = editor.active_mode == EnvTypes.MODE_TILE
    var active_idx: int = editor.active_tile_layer_idx

    for i in tile_layers.size():
        var layer_v: Variant = tile_layers[i]
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = layer_v
        var rect := Rect2(PAD_X, y, btn_w, ROW_H_LAYER)
        _layer_rects.append({"idx": i, "rect": rect})
        var is_active: bool = editing_tile and i == active_idx
        var hover := rect.has_point(mouse_pos)
        var tint: Color
        if is_active:
            tint = Color(0.4, 0.7, 1.0, 1.0)
        else:
            tint = Color(0.3, 0.4, 0.55, 1.0)
        UIPanels.draw_button_bg(self, rect, hover, tint)

        var role := str(layer.get("role", EnvTypes.ROLE_MAIN))
        var role_col := EnvTypes.role_color(role)
        var badge_rect := Rect2(rect.position.x + 6, rect.position.y + 6, 14, 14)
        draw_rect(badge_rect, role_col)
        draw_rect(badge_rect, Color(0, 0, 0, 0.7), false, 1.0)

        var layer_name := str(layer.get("name", "Layer"))
        if layer_name.length() > 14:
            layer_name = layer_name.substr(0, 12) + "…"
        var name_col := Color(1, 1, 1, 1) if is_active else Color(0.75, 0.85, 0.95, 1)
        draw_string(font, Vector2(rect.position.x + 26, rect.position.y + 17),
            layer_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, name_col)

        var spd_text := "LOCK"
        draw_string(font, Vector2(rect.position.x + rect.size.x - 48, rect.position.y + 17),
            spd_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
            Color(0.85, 0.9, 1.0, 0.9) if is_active else Color(0.65, 0.72, 0.82, 0.8))

        if hover:
            EditorTooltip.show_text("Tile layer \"%s\" (role: %s). Click to make it the active paint target. Painted tile layers are world-locked so room art stays aligned with authored collision." % [str(layer.get("name", "Layer")), role])

        y += ROW_H_LAYER + 2.0

    y += GAP_SM

    # Layer action row: ↑ ↓ × NAME (operates on active layer)
    var action_defs := [
        {"action": "up", "label": "UP", "tint": Color(0.45, 0.7, 0.9),
            "tip": "Move the active tile layer one step up in the draw order. Higher in the list = drawn later = on top."},
        {"action": "down", "label": "DN", "tint": Color(0.45, 0.7, 0.9),
            "tip": "Move the active tile layer one step down in the draw order. Lower in the list = drawn earlier = behind other layers."},
        {"action": "remove", "label": "X", "tint": Color(0.9, 0.45, 0.45),
            "tip": "Delete the active tile layer and all of its painted tiles. There is no undo — save first if you're unsure."},
        {"action": "rename", "label": "NAM", "tint": Color(0.55, 0.8, 0.55),
            "tip": "Rename the active tile layer. Names are for your own organization — doesn't affect gameplay."},
    ]
    var active_role := ""
    if editing_tile and active_idx >= 0 and active_idx < tile_layers.size():
        var active_layer_v: Variant = tile_layers[active_idx]
        if typeof(active_layer_v) == TYPE_DICTIONARY:
            active_role = str((active_layer_v as Dictionary).get("role", EnvTypes.ROLE_MAIN))
    var action_count: int = action_defs.size()
    var action_btn_w: float = (btn_w - float(action_count - 1) * 2.0) / float(action_count)
    for i in action_count:
        var def: Dictionary = action_defs[i]
        var x_pos: float = PAD_X + float(i) * (action_btn_w + 2.0)
        var rect := Rect2(x_pos, y, action_btn_w, ROW_H_BTN)
        _layer_action_rects.append({"action": def["action"], "rect": rect})
        var hover := rect.has_point(mouse_pos)
        var enabled: bool = editing_tile and not tile_layers.is_empty()
        var tint: Color = def["tint"]
        if not enabled:
            tint = Color(tint.r * 0.45, tint.g * 0.45, tint.b * 0.45, 1.0)
        UIPanels.draw_button_bg(self, rect, hover and enabled, tint)
        var label_col := Color(1, 1, 1, 1) if enabled else Color(0.55, 0.6, 0.68, 1)
        var label_text := str(def["label"])
        var label_w := float(label_text.length()) * 5.5
        draw_string(font, Vector2(rect.position.x + (action_btn_w - label_w) * 0.5,
            rect.position.y + 17),
            label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, label_col)
        if hover:
            if enabled:
                EditorTooltip.show_text(str(def["tip"]))
            else:
                EditorTooltip.show_text("Layer actions are disabled. Switch to TILE edit mode and select a tile layer first.")
    y += ROW_H_BTN + GAP_SM

    # Add-layer row: + BG  + FG
    var add_defs := [
        {"role": EnvTypes.ROLE_BG, "label": "+ BG",
            "tip": "Add a new background tile layer. Background tile layers draw behind MAIN, but stay world-locked like every painted tile layer."},
        {"role": EnvTypes.ROLE_FG, "label": "+ FG",
            "tip": "Add a new foreground tile layer. Foreground tile layers draw in front of MAIN, but stay world-locked like every painted tile layer."},
    ]
    var add_btn_w: float = (btn_w - 4.0) * 0.5
    for i in add_defs.size():
        var def: Dictionary = add_defs[i]
        var x_pos: float = PAD_X + float(i) * (add_btn_w + 4.0)
        var rect := Rect2(x_pos, y, add_btn_w, ROW_H_BTN)
        _add_rects.append({"role": def["role"], "rect": rect})
        var hover := rect.has_point(mouse_pos)
        var role_tint: Color = EnvTypes.role_color(str(def["role"]))
        UIPanels.draw_button_bg(self, rect, hover,
            Color(role_tint.r * 0.85, role_tint.g * 0.85, role_tint.b * 0.85, 1.0))
        var label_text := str(def["label"])
        var label_w := float(label_text.length()) * 6.0
        draw_string(font, Vector2(rect.position.x + (add_btn_w - label_w) * 0.5,
            rect.position.y + 17),
            label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 1))
        if hover:
            EditorTooltip.show_text(str(def["tip"]))
    y += ROW_H_BTN + GAP_LG

    # ─── EDIT MODES ──────────────────────────────────────────────────────
    _draw_section_label(font, y, "EDIT MODE")
    y += 18.0
    var mode_defs := [
        {"mode": EnvTypes.MODE_COLLISION, "label": "COLLISION", "tint": Color(0.95, 0.45, 0.45),
            "tip": "Paint solid/non-solid collision cells. The player walks on SOLID tiles; everything else is empty. Independent from the tile art layer."},
        {"mode": EnvTypes.MODE_ENTITIES, "label": "ENTITIES", "tint": Color(0.45, 0.75, 1.0),
            "tip": "Place entities, NPCs, pickups, and named trigger zones from the entity picker. Click to place; right-click or ERASE to remove."},
        {"mode": EnvTypes.MODE_DOORS, "label": "DOORS", "tint": Color(0.45, 0.95, 0.6),
            "tip": "Drag-create door rectangles that link to other rooms. Doors define room transitions — paint a rect, then set its target room/door."},
    ]
    for def in mode_defs:
        var rect := Rect2(PAD_X, y, btn_w, ROW_H_LAYER)
        _mode_rects.append({"mode": def["mode"], "rect": rect})
        var is_active: bool = int(def["mode"]) == editor.active_mode
        var hover := rect.has_point(mouse_pos)
        var tint: Color = def["tint"]
        if not is_active:
            tint = Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5, 1.0)
        UIPanels.draw_button_bg(self, rect, hover, tint)
        var label_col := Color(1, 1, 1, 1) if is_active else Color(0.65, 0.72, 0.82, 1)
        draw_string(font, Vector2(rect.position.x + 12, rect.position.y + 19),
            str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_col)
        if hover:
            EditorTooltip.show_text(str(def["tip"]))
        y += ROW_H_LAYER + GAP_SM

    y += GAP_LG

    # ─── OVERLAYS ────────────────────────────────────────────────────────
    if editor.active_mode == EnvTypes.MODE_COLLISION:
        _draw_section_label(font, y, "COLLISION BRUSH")
        y += 18.0
        var collision_defs := [
            {"nibble": EnvTypes.BT_SOLID, "label": "SOLID", "tint": EnvTypes.block_type_color(EnvTypes.BT_SOLID),
                "tip": "Full solid block. Simple rectangular collision."},
            {"nibble": EnvTypes.BT_SLOPE, "label": "SLOPE", "tint": EnvTypes.block_type_color(EnvTypes.BT_SLOPE),
                "tip": "Slope collision. Use the slope controls below to pick direction and grade before painting."},
            {"nibble": EnvTypes.BT_CRUMBLE, "label": "CRUMBLE", "tint": EnvTypes.block_type_color(EnvTypes.BT_CRUMBLE),
                "tip": "Step-triggered crumble block. Configure whether it respawns after 4s or stays gone until room reload."},
            {"nibble": EnvTypes.BT_SHOOT_SOLID, "label": "SHOT", "tint": EnvTypes.block_type_color(EnvTypes.BT_SHOOT_SOLID),
                "tip": "Beam-break block. Use for tiles that only open to ranged shots."},
            {"nibble": EnvTypes.BT_BOMB_SOLID, "label": "BOMB", "tint": EnvTypes.block_type_color(EnvTypes.BT_BOMB_SOLID),
                "tip": "Bomb-break block. Only bomb/explosive interactions should clear it."},
            {"nibble": EnvTypes.BT_GRAPPLE_BLOCK, "label": "GRAPPLE", "tint": EnvTypes.block_type_color(EnvTypes.BT_GRAPPLE_BLOCK),
                "tip": "Grapple latch block. Keeps the grapple route authoring visible in the palette."},
            {"nibble": EnvTypes.BT_SPIKE, "label": "SPIKE", "tint": EnvTypes.block_type_color(EnvTypes.BT_SPIKE),
                "tip": "Hazard collision. Pick a painted spike cell to edit its damage/effect profile."},
            {"nibble": EnvTypes.BT_AIR, "label": "AIR", "tint": EnvTypes.block_type_color(EnvTypes.BT_AIR),
                "tip": "Paint empty space into the collision grid. Useful with fill when clearing large regions."},
        ]
        var brush_btn_w: float = (btn_w - 4.0) * 0.5
        for i in collision_defs.size():
            var def: Dictionary = collision_defs[i]
            var bx := PAD_X + float(i % 2) * (brush_btn_w + 4.0)
            var by := y + float(i / 2) * (ROW_H_BTN + 4.0)
            var rect := Rect2(bx, by, brush_btn_w, ROW_H_BTN)
            _collision_brush_rects.append({"nibble": def["nibble"], "rect": rect})
            var hover := rect.has_point(mouse_pos)
            var is_active: bool = int(def["nibble"]) == editor.selected_collision_nibble
            var tint: Color = def["tint"]
            if not is_active:
                tint = Color(tint.r * 0.7, tint.g * 0.7, tint.b * 0.7, 1.0)
            UIPanels.draw_button_bg(self, rect, hover, tint)
            draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 17),
                str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(1, 1, 1, 1) if is_active else Color(0.82, 0.88, 0.95, 1))
            if hover:
                EditorTooltip.show_text(str(def["tip"]))
        var collision_rows := int(ceil(float(collision_defs.size()) / 2.0))
        y += float(collision_rows) * (ROW_H_BTN + 4.0) + GAP_SM

        if editor.selected_collision_nibble == EnvTypes.BT_SLOPE and editor.has_method("get_selected_slope_info"):
            _draw_section_label(font, y, "SLOPE")
            y += 18.0
            var slope_info: Dictionary = editor.get_selected_slope_info()
            var preview_rect := Rect2(PAD_X, y, btn_w, 64.0)
            UIPanels.draw_panel(self, preview_rect, Color(0.3, 0.36, 0.5, 1.0), UIPanels.PanelVariant.DARK)
            _draw_slope_preview(preview_rect.grow(-8.0), slope_info, Color(0.55, 0.8, 1.0, 0.95), Color(0.3, 0.9, 1.0, 0.12))
            draw_string(font, Vector2(preview_rect.position.x + 72.0, preview_rect.position.y + 22.0),
                str(slope_info.get("label", "Slope")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.92, 0.96, 1.0, 1.0))
            draw_string(font, Vector2(preview_rect.position.x + 72.0, preview_rect.position.y + 42.0),
                str(slope_info.get("grade_label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.82, 0.98, 1.0))
            if preview_rect.has_point(mouse_pos):
                EditorTooltip.show_text("Selected slope: %s. %s" % [str(slope_info.get("label", "Slope")), str(slope_info.get("grade_label", ""))])
            y += preview_rect.size.y + GAP_SM

            var slope_shapes: Array = editor.get_slope_shapes()
            if slope_shapes.size() > 1:
                var shape_btn_w: float = (btn_w - 4.0) * 0.5
                for shape_idx in range(1, slope_shapes.size()):
                    var local_idx := shape_idx - 1
                    var sx := PAD_X + float(local_idx % 2) * (shape_btn_w + 4.0)
                    var sy := y + float(local_idx / 2) * (ROW_H_BTN + 4.0)
                    var rect := Rect2(sx, sy, shape_btn_w, ROW_H_BTN)
                    _slope_shape_rects.append({"shape": shape_idx, "rect": rect})
                    var hover := rect.has_point(mouse_pos)
                    var is_active: bool = shape_idx == int(editor.selected_slope_shape)
                    var tint := Color(0.38, 0.52, 0.86, 1.0) if is_active else Color(0.24, 0.3, 0.42, 1.0)
                    UIPanels.draw_button_bg(self, rect, hover, tint)
                    var shape_info: Dictionary = editor.get_slope_info(shape_idx, false, false)
                    draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 17),
                        "S%d  %s" % [shape_idx, _compact_slope_label(str(shape_info.get("label", "shape")))],
                        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.96, 1.0, 1.0))
                    if hover:
                        EditorTooltip.show_text("Base slope shape %d: %s. %s" % [shape_idx, str(shape_info.get("label", "Slope")), str(shape_info.get("grade_label", ""))])
                var shape_rows := int(ceil(float(maxi(slope_shapes.size() - 1, 0)) / 2.0))
                y += float(shape_rows) * (ROW_H_BTN + 4.0)

            var flip_defs := [
                {"key": "hflip", "label": "MIRROR X", "active": bool(editor.selected_slope_hflip),
                    "tip": "Mirror the slope horizontally. Flips which side rises."},
                {"key": "vflip", "label": "CEILING", "active": bool(editor.selected_slope_vflip),
                    "tip": "Flip the slope vertically to make it a ceiling instead of a floor."},
            ]
            var flip_btn_w: float = (btn_w - 4.0) * 0.5
            for i in flip_defs.size():
                var def: Dictionary = flip_defs[i]
                var rect := Rect2(PAD_X + float(i) * (flip_btn_w + 4.0), y, flip_btn_w, ROW_H_BTN)
                _slope_toggle_rects.append({"key": def["key"], "rect": rect})
                var hover := rect.has_point(mouse_pos)
                var active := bool(def["active"])
                var tint := Color(0.3, 0.78, 0.96, 1.0) if active else Color(0.26, 0.31, 0.4, 1.0)
                UIPanels.draw_button_bg(self, rect, hover, tint)
                draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 17),
                    str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                    Color(1, 1, 1, 1) if active else Color(0.78, 0.84, 0.92, 1))
                if hover:
                    EditorTooltip.show_text(str(def["tip"]))
            y += ROW_H_BTN + GAP_LG
        elif editor.selected_collision_nibble == EnvTypes.BT_CRUMBLE and editor.has_method("get_selected_crumble_info"):
            _draw_section_label(font, y, "CRUMBLE")
            y += 18.0
            var crumble_info: Dictionary = editor.get_selected_crumble_info()
            var preview_rect := Rect2(PAD_X, y, btn_w, 58.0)
            UIPanels.draw_panel(self, preview_rect, Color(0.38, 0.27, 0.12, 1.0), UIPanels.PanelVariant.DARK)
            draw_string(font, Vector2(preview_rect.position.x + 10, preview_rect.position.y + 22.0),
                "Mode: %s" % str(crumble_info.get("label", "Respawn")),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.92, 0.82, 1.0))
            draw_string(font, Vector2(preview_rect.position.x + 10, preview_rect.position.y + 42.0),
                str(crumble_info.get("desc", "")),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.78, 0.58, 1.0))
            if preview_rect.has_point(mouse_pos):
                EditorTooltip.show_text("Selected crumble mode: %s" % str(crumble_info.get("desc", "")))
            y += preview_rect.size.y + GAP_SM

            var crumble_defs := [
                {"key": "respawn", "label": "RESPAWN", "active": not bool(editor.selected_crumble_reload_only),
                    "tip": "Classic crumble. Fades out, stays gone about 4 seconds, then returns."},
                {"key": "reload_only", "label": "ROOM RELOAD", "active": bool(editor.selected_crumble_reload_only),
                    "tip": "One-shot crumble. Falls away and stays gone until you leave the room and come back."},
            ]
            var crumble_btn_w: float = (btn_w - 4.0) * 0.5
            for i in crumble_defs.size():
                var def: Dictionary = crumble_defs[i]
                var rect := Rect2(PAD_X + float(i) * (crumble_btn_w + 4.0), y, crumble_btn_w, ROW_H_BTN)
                _slope_toggle_rects.append({"key": def["key"], "rect": rect})
                var hover := rect.has_point(mouse_pos)
                var active := bool(def["active"])
                var tint := Color(0.88, 0.6, 0.24, 1.0) if active else Color(0.3, 0.24, 0.16, 1.0)
                UIPanels.draw_button_bg(self, rect, hover, tint)
                draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 17),
                    str(def["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                    Color(1, 1, 1, 1) if active else Color(0.9, 0.82, 0.72, 1))
                if hover:
                    EditorTooltip.show_text(str(def["tip"]))
            y += ROW_H_BTN + GAP_LG
        else:
            draw_string(font, Vector2(PAD_X, y + 12.0),
                "Current brush: %s" % EnvTypes.block_type_label(editor.selected_collision_nibble),
                HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.65, 0.72, 0.82, 1.0))
            y += 20.0

    _draw_section_label(font, y, "OVERLAYS")
    y += 18.0

    var coll_rect := Rect2(PAD_X, y, btn_w, ROW_H_LAYER)
    _overlay_rects.append({"key": "collision", "rect": coll_rect})
    var coll_hover := coll_rect.has_point(mouse_pos)
    var coll_tint: Color
    if editor.show_collision:
        coll_tint = Color(0.95, 0.45, 0.45, 1)
    else:
        coll_tint = Color(0.3, 0.35, 0.45, 1)
    UIPanels.draw_button_bg(self, coll_rect, coll_hover, coll_tint)
    var coll_label_col: Color
    if editor.show_collision:
        coll_label_col = Color(1, 1, 1, 1)
    else:
        coll_label_col = Color(0.6, 0.65, 0.72, 1)
    draw_string(font, Vector2(coll_rect.position.x + 12, coll_rect.position.y + 19),
        "COLLISION", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, coll_label_col)
    if coll_hover:
        EditorTooltip.show_text("Toggle the red collision overlay on top of the canvas. Useful for spotting gaps in collision while painting tiles.")
    y += ROW_H_LAYER + GAP_SM

    _content_h = y + _scroll_y + 36.0

    # Fixed hint footer (not affected by scroll)
    var hint := "MMB: pan  Wheel: zoom/scroll"
    draw_string(font, Vector2(PAD_X, size.y - 28),
        hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.7, 1))
    var hint2 := "LMB: tool   RMB: erase"
    draw_string(font, Vector2(PAD_X, size.y - 14),
        hint2, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.58, 0.7, 1))


func _draw_section_label(font: Font, y: float, text: String) -> void:
    draw_string(font, Vector2(PAD_X, y + 14),
        text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIPanels.TEXT_PANEL)


func _compact_slope_label(label: String) -> String:
    return label.replace("Floor ", "").replace("Ceiling ", "")


func _draw_slope_preview(rect: Rect2, slope_info: Dictionary, stroke: Color, fill: Color) -> void:
    var preview := Rect2(rect.position, Vector2(minf(rect.size.x, 54.0), rect.size.y))
    draw_rect(preview, Color(0.12, 0.16, 0.24, 0.95))
    draw_rect(preview, Color(0.38, 0.48, 0.66, 0.85), false, 1.0)
    if not bool(slope_info.get("valid", false)):
        return
    var left_y: float = float(int(slope_info.get("left_y", 16)))
    var right_y: float = float(int(slope_info.get("right_y", 16)))
    var x0 := preview.position.x + 6.0
    var x1 := preview.end.x - 6.0
    var y0 := lerpf(preview.position.y + 6.0, preview.end.y - 6.0, clampf(left_y / 16.0, 0.0, 1.0))
    var y1 := lerpf(preview.position.y + 6.0, preview.end.y - 6.0, clampf(right_y / 16.0, 0.0, 1.0))
    var p0 := Vector2(x0, y0)
    var p1 := Vector2(x1, y1)
    var is_ceiling := bool(slope_info.get("vflip", false))
    var poly := PackedVector2Array([p0, p1, Vector2(x1, preview.position.y if is_ceiling else preview.end.y), Vector2(x0, preview.position.y if is_ceiling else preview.end.y)])
    draw_colored_polygon(poly, fill)
    draw_line(p0, p1, stroke, 2.0)
    var arrow_dir := (p1 - p0).normalized()
    if arrow_dir.length_squared() > 0.01:
        var arrow_tip := p1
        var arrow_side := Vector2(-arrow_dir.y, arrow_dir.x) * 4.0
        draw_line(arrow_tip, arrow_tip - arrow_dir * 8.0 + arrow_side, stroke, 2.0)
        draw_line(arrow_tip, arrow_tip - arrow_dir * 8.0 - arrow_side, stroke, 2.0)

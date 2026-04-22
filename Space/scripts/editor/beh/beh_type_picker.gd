extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const BehTypes = preload("res://Space/scripts/editor/beh/beh_types.gd")

# Full-screen modal that lists every supported behavior node type,
# grouped by category (composites / decorators / leaves), and lets the
# user pick one. Fires `picked(type)` on selection; `cancelled` on Esc.

signal picked(type: String)
signal cancelled

const BOX_W: float = 520.0
const BOX_H: float = 540.0
const ROW_H: float = 28.0

var editor: Node = null

var _current_type: String = ""
var _rows: Array = []  # [{type, rect}]
var _cancel_rect: Rect2 = Rect2()
var _scroll: float = 0.0


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    visible = false
    set_process(true)


func _process(_delta):
    if visible:
        queue_redraw()


func open(current_type: String = "") -> void:
    _current_type = current_type
    _scroll = 0.0
    visible = true
    queue_redraw()


func close() -> void:
    visible = false


func _gui_input(event):
    if not visible:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
            if _cancel_rect.has_point(mb.position):
                _do_cancel()
                accept_event()
                return
            for row in _rows:
                if (row["rect"] as Rect2).has_point(mb.position):
                    _do_pick(str(row["type"]))
                    accept_event()
                    return
            var box := _box_rect()
            if not box.has_point(mb.position):
                _do_cancel()
                accept_event()
                return


func _input(event):
    if not visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            _do_cancel()
            get_viewport().set_input_as_handled()


func _do_pick(type: String) -> void:
    visible = false
    picked.emit(type)


func _do_cancel() -> void:
    visible = false
    cancelled.emit()


func _box_rect() -> Rect2:
    return Rect2((size.x - BOX_W) * 0.5, (size.y - BOX_H) * 0.5, BOX_W, BOX_H)


func _draw():
    if not visible:
        return

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.55)
    var box := _box_rect()
    UIPanels.draw_panel(self, box, Color.WHITE, UIPanels.PanelVariant.MAIN)

    var font := ThemeDB.fallback_font
    var mouse_pos := get_local_mouse_position()

    draw_string(font, box.position + Vector2(24, 36),
        "Pick node type", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UIPanels.TEXT_PANEL)

    _rows.clear()
    var list_x: float = box.position.x + 20
    var list_y: float = box.position.y + 60
    var list_w: float = box.size.x - 40

    var y: float = list_y
    y = _draw_group(font, mouse_pos, list_x, y, list_w,
        "COMPOSITES", BehTypes.COMPOSITE_TYPES,
        BehTypes.category_color(BehTypes.CAT_COMPOSITE))
    y += 8
    y = _draw_group(font, mouse_pos, list_x, y, list_w,
        "DECORATORS", BehTypes.DECORATOR_TYPES,
        BehTypes.category_color(BehTypes.CAT_DECORATOR))
    y += 8
    y = _draw_group(font, mouse_pos, list_x, y, list_w,
        "LEAVES", BehTypes.LEAF_TYPES,
        BehTypes.category_color(BehTypes.CAT_LEAF))

    # Cancel button.
    var btn_w: float = 110.0
    var btn_h: float = 32.0
    _cancel_rect = Rect2(box.position.x + box.size.x - btn_w - 20,
        box.position.y + box.size.y - btn_h - 16, btn_w, btn_h)
    var cancel_hover := _cancel_rect.has_point(mouse_pos)
    UIPanels.draw_button_bg(self, _cancel_rect, cancel_hover,
        Color(0.9, 0.45, 0.4, 1.0))
    var cancel_label := "CANCEL"
    var cancel_w := float(cancel_label.length()) * 6.0
    draw_string(font, Vector2(_cancel_rect.position.x + (btn_w - cancel_w) * 0.5,
        _cancel_rect.position.y + 21),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
        Color(1, 0.95, 0.95, 1) if cancel_hover else Color(0.8, 0.55, 0.55, 1))
    if cancel_hover:
        EditorTooltip.show_text("Close this picker without changing the node type. Esc or clicking outside the box does the same thing.")

    draw_string(font, box.position + Vector2(24, box.size.y - 12),
        "Click a type to apply.  Esc: cancel",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPanels.TEXT_PANEL_DIM)


func _draw_group(font: Font, mouse_pos: Vector2, x: float, y: float,
        w: float, header: String, types: Array, accent: Color) -> float:
    draw_string(font, Vector2(x + 4, y + 16),
        header, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, accent)
    y += 22
    for type_v in types:
        var t := str(type_v)
        var rect := Rect2(x, y, w, ROW_H - 2)
        var is_sel := t == _current_type
        var hover := rect.has_point(mouse_pos)

        var bg: Color
        if is_sel:
            bg = Color(0.3, 0.55, 0.42, 0.95)
        elif hover:
            bg = Color(0.18, 0.3, 0.22, 0.9)
        else:
            bg = Color(0.08, 0.16, 0.1, 0.8)
        draw_rect(rect, bg)
        draw_rect(rect, accent, false, 1.0)

        var swatch := Rect2(rect.position.x + 8, rect.position.y + 8, 10, 10)
        draw_rect(swatch, accent)

        var text_col: Color
        if is_sel:
            text_col = Color(1, 1, 1, 1)
        elif hover:
            text_col = Color(0.95, 1.0, 0.96, 1)
        else:
            text_col = Color(0.78, 0.92, 0.84, 1)
        draw_string(font, rect.position + Vector2(26, 18),
            t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_col)

        _rows.append({
            "type": t,
            "rect": rect,
        })

        if hover:
            EditorTooltip.show_text(_describe_type(t))

        y += ROW_H
    return y


func _describe_type(t: String) -> String:
    match t:
        "sequence":
            return "sequence — runs children in order. Returns SUCCESS only if every child succeeds; fails on the first failure. Like a logical AND."
        "selector":
            return "selector — runs children in order. Returns SUCCESS on the first child that succeeds; fails only if all fail. Like a logical OR / fallback chain."
        "simple_parallel":
            return "simple_parallel — ticks all children every frame. Success/failure policy depends on the configured threshold."
        "selector_random":
            return "selector_random — picks one child at random each tick. Useful for variety in idle animations or attack patterns."
        "sequence_reactive":
            return "sequence_reactive — like sequence, but re-evaluates earlier children each tick. Aborts if a previously-passing child fails."
        "sequence_star":
            return "sequence_star — like sequence, but remembers where it left off. Resumes from the last running child instead of restarting."
        "inverter":
            return "inverter — flips the child's result. SUCCESS becomes FAILURE and vice versa. Wrap a condition to negate it."
        "repeater":
            return "repeater — re-runs its child N times (or forever). Often used at the root of a behavior."
        "limiter":
            return "limiter — allows its child to run at most N times total. Returns FAILURE after the limit is reached."
        "until_fail":
            return "until_fail — re-ticks its child until it returns FAILURE, then itself returns SUCCESS."
        "cooldown":
            return "cooldown — runs its child, then refuses to run again for N seconds. Good for rate-limiting attacks."
        "delayer":
            return "delayer — waits N seconds before ticking its child the first time. Useful for telegraph windows."
        "action":
            return "action (leaf) — invokes a runtime action handler by name, e.g. walk_left, attack. Set the action name and any params on the right."
        "condition":
            return "condition (leaf) — queries a runtime condition handler by name, e.g. wall_ahead, see_player. Returns SUCCESS or FAILURE based on the world state."
        _:
            return "Behavior node type \"%s\". Click to apply." % t

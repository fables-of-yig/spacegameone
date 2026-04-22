extends CanvasLayer

# Global tooltip overlay used by the custom-drawn editor UIs. All editor
# panels immediate-mode draw their own rects and detect hover via
# Rect2.has_point(), so Godot's native Control.tooltip_text does not apply.
#
# Usage pattern inside a panel's _draw():
#     if my_btn_rect.has_point(mouse_pos):
#         EditorTooltip.show_text("Save all rooms and tilesets to disk.")
#
# Panels call show_text() every frame they're hovered; the overlay consumes
# the latest request each _process tick and draws it at the cursor. Toggled
# on/off by the TOOLTIPS button in each editor's topbar. State persists to
# user://editor_prefs.json so it sticks across sessions.
#
# NOTE: method is named show_text() (not show()) because CanvasLayer
# already defines a show() method — overriding it with a different
# signature is a parse error.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const TOGGLE_WIDTH := 130.0
const TOGGLE_LABEL := "TOOLTIPS"

const _PREFS_PATH := "user://editor_prefs.json"
const _MAX_WIDTH_PX := 380.0
const _FONT_SIZE := 12
const _LINE_PAD := 2.0
const _BOX_PAD_X := 10.0
const _BOX_PAD_Y := 7.0

var enabled: bool = false

var _pending_text: String = ""
var _current_text: String = ""
var _display: Control = null


func _ready() -> void:
    # Editors run while the tree is paused (main menu sets paused=true and
    # they sit under a PROCESS_MODE_ALWAYS CanvasLayer). We have to match
    # that or _process never ticks and _pending_text never flows to
    # _current_text — the symptom being "toggle does nothing, no tooltips
    # anywhere" in any editor reached from the main menu.
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 128
    _display = Control.new()
    _display.name = "TooltipDisplay"
    _display.set_anchors_preset(Control.PRESET_FULL_RECT)
    _display.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _display.process_mode = Node.PROCESS_MODE_ALWAYS
    _display.draw.connect(_on_display_draw)
    add_child(_display)
    set_process(true)
    _load_prefs()


func _process(_delta: float) -> void:
    # Snapshot the latest request from this frame and reset the slot so
    # panels that stop being hovered see their tooltip disappear next tick.
    _current_text = _pending_text
    _pending_text = ""
    _display.queue_redraw()


# ─── Public API ─────────────────────────────────────────────────────────

# Called from editor panel _draw() while the mouse is over a rect that has
# a tooltip. Safe to call every frame; only the last call of each frame
# wins. No-op when tooltips are disabled.
func show_text(text: String) -> void:
    if not enabled:
        return
    if text == null or text == "":
        return
    _pending_text = text


func set_enabled(value: bool) -> void:
    if enabled == value:
        return
    enabled = value
    if not enabled:
        _pending_text = ""
        _current_text = ""
    _save_prefs()


func toggle() -> void:
    set_enabled(not enabled)


# Draws a reusable "[✓] TOOLTIPS" toggle into `rect` on `canvas`. Topbars
# call this from _draw(); they own the click detection in _gui_input() and
# call toggle() when the rect is clicked. Forces its own tooltip visible
# on hover regardless of `enabled` so first-time discovery still works.
func draw_toggle(canvas: CanvasItem, rect: Rect2, mouse_pos: Vector2) -> void:
    var font: Font = ThemeDB.fallback_font
    var hover := rect.has_point(mouse_pos)
    var accent: Color
    if enabled:
        accent = Color(0.55, 0.9, 1.0, 1.0)
    else:
        accent = Color(0.45, 0.5, 0.6, 1.0)
    UIPanels.draw_button_bg(canvas, rect, hover, accent)

    var box_size: float = 16.0
    var box_pos := rect.position + Vector2(10.0, (rect.size.y - box_size) * 0.5)
    var box_rect := Rect2(box_pos, Vector2(box_size, box_size))
    canvas.draw_rect(box_rect, Color(0.08, 0.12, 0.18, 0.95))
    canvas.draw_rect(box_rect, Color(0.85, 0.92, 1.0, 0.95), false, 1.5)
    if enabled:
        canvas.draw_string(font, box_pos + Vector2(3.0, 13.0),
            "x", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.2, 1.0, 0.6, 1.0))

    var label_x := rect.position.x + box_size + 18.0
    var label_y := rect.position.y + 21.0
    var label_col: Color
    if hover:
        label_col = Color(1.0, 1.0, 1.0, 1.0)
    elif enabled:
        label_col = Color(0.95, 1.0, 1.0, 1.0)
    else:
        label_col = Color(0.75, 0.8, 0.88, 1.0)
    canvas.draw_string(font, Vector2(label_x, label_y), TOGGLE_LABEL,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 13, label_col)

    # The toggle itself needs to be self-explanatory even when tooltips
    # are OFF, so bypass the enabled gate by writing _pending_text directly.
    if hover:
        _pending_text = "Toggle mouseover tooltips. When ON, hover any button, field, or control in this editor to see what it does."


# ─── Rendering ──────────────────────────────────────────────────────────

func _on_display_draw() -> void:
    if _current_text == "":
        return
    var font: Font = ThemeDB.fallback_font
    if font == null:
        return

    var lines := _wrap_text(_current_text, font, _FONT_SIZE, _MAX_WIDTH_PX)
    if lines.is_empty():
        return

    var line_h := float(font.get_height(_FONT_SIZE)) + _LINE_PAD
    var max_w: float = 0.0
    for line in lines:
        var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE).x
        if w > max_w:
            max_w = w

    var box_size := Vector2(max_w + _BOX_PAD_X * 2.0,
        float(lines.size()) * line_h + _BOX_PAD_Y * 2.0)

    var mouse_pos := _display.get_local_mouse_position()
    var vp_size := _display.size
    # Offset below-right of cursor; flip sides if we'd overflow the viewport.
    var pos := mouse_pos + Vector2(16, 20)
    if pos.x + box_size.x > vp_size.x - 4.0:
        pos.x = mouse_pos.x - box_size.x - 8.0
    if pos.y + box_size.y > vp_size.y - 4.0:
        pos.y = mouse_pos.y - box_size.y - 8.0
    if pos.x < 4.0:
        pos.x = 4.0
    if pos.y < 4.0:
        pos.y = 4.0

    var box := Rect2(pos, box_size)
    # Drop shadow
    _display.draw_rect(Rect2(pos + Vector2(2, 2), box_size),
        Color(0, 0, 0, 0.45))
    _display.draw_rect(box, Color(0.07, 0.1, 0.17, 0.97))
    _display.draw_rect(box, Color(0.55, 0.78, 1.0, 0.95), false, 1.5)

    var text_col := Color(0.92, 0.96, 1.0, 1.0)
    for i in lines.size():
        var ty := pos.y + _BOX_PAD_Y + float(i + 1) * line_h - 4.0
        _display.draw_string(font,
            Vector2(pos.x + _BOX_PAD_X, ty),
            lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT_SIZE, text_col)


func _wrap_text(text: String, font: Font, size_px: int, max_px: float) -> Array:
    # Respects explicit newlines as hard breaks; soft-wraps long runs.
    var out: Array = []
    var hard_lines := text.split("\n")
    for hard in hard_lines:
        var words := hard.split(" ")
        var current := ""
        for w in words:
            var test := w if current == "" else current + " " + w
            var test_w := font.get_string_size(test,
                HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
            if test_w > max_px and current != "":
                out.append(current)
                current = w
            else:
                current = test
        if current != "":
            out.append(current)
    return out


# ─── Persistence ────────────────────────────────────────────────────────

func _load_prefs() -> void:
    if not FileAccess.file_exists(_PREFS_PATH):
        return
    var f := FileAccess.open(_PREFS_PATH, FileAccess.READ)
    if f == null:
        return
    var text := f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return
    var dict: Dictionary = parsed
    enabled = bool(dict.get("tooltips_enabled", false))


func _save_prefs() -> void:
    var dict := {"tooltips_enabled": enabled}
    var f := FileAccess.open(_PREFS_PATH, FileAccess.WRITE)
    if f == null:
        return
    f.store_string(JSON.stringify(dict))
    f.close()

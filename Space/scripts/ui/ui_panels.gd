extends RefCounted

const PackPaths = preload("res://Space/scripts/editor/pack_paths.gd")

# Intentionally NO `class_name UIPanels` — consumers use a `const UIPanels =
# preload(...)` so they work even before Godot's global script class cache
# has registered this script. Adding class_name back triggers
# SHADOWED_GLOBAL_IDENTIFIER warnings in every consumer.

# Static 9-slice panel + button helper + loadable theme store for the
# immediate-mode draw code scattered across the editors and menus.
#
# The active theme (panel/button art, 9-slice margins, text role colors,
# font sizes, modal dim alpha) lives in static vars that can be rewritten
# at runtime. This is what lets the in-game theme editor swap art and
# colors live for the active pack.
#
# Consumer API (unchanged from the pre-theme version):
#   UIPanels.draw_panel(self, my_rect)                        # MAIN variant
#   UIPanels.draw_panel(self, my_rect, Color.WHITE, UIPanels.PanelVariant.DARK)
#   UIPanels.draw_button(self, btn_rect, "OK", font, hovered, Color(0.4,0.7,1))
#   UIPanels.draw_button_bg(self, btn_rect, hovered, modulate, pressed)
#
# Theme loading:
#   UIPanels.load_default_theme()            # called once at game boot
#   UIPanels.load_pack_theme("demo")         # called on editor/pack open
#   UIPanels.apply_theme_dict(my_theme)      # direct apply (no IO)
#
# Fallbacks: if a texture path fails to load, `draw_panel` and
# `draw_button` degrade to plain draw_rect so early-bring-up still renders
# something legible.

enum PanelVariant { MAIN, ALT, DARK }

const PANEL_KEYS := ["main", "alt", "dark"]
const BUTTON_KEYS := ["normal", "hover", "pressed"]
const TEXT_ROLES := ["title", "body", "dim", "button", "button_hover", "error", "success"]
const FONT_ROLES := ["title_size", "body_size", "hint_size", "button_size"]

# Hard-coded fallback theme — used when no pack theme and no global default
# are present on disk. Shape matches the theme editor's JSON schema exactly.
const FALLBACK_THEME := {
    "panels": {
        "main": {"frame": "res://Assets/UI/ui_frame.png", "margin": [12, 12], "mode": "9slice"},
        "alt":  {"frame": "res://Assets/UI/ui_frame.png", "margin": [12, 12], "mode": "9slice"},
        "dark": {"frame": "res://Assets/UI/ui_frame.png", "margin": [12, 12], "mode": "9slice"},
    },
    "buttons": {
        "normal":  {"frame": "res://Space/art/ui/button_normal.png",  "margin": [14, 14], "mode": "9slice"},
        "hover":   {"frame": "res://Space/art/ui/button_hover.png",   "margin": [14, 14], "mode": "9slice"},
        "pressed": {"frame": "res://Space/art/ui/button_pressed.png", "margin": [14, 14], "mode": "9slice"},
    },
    "text": {
        "title":        "#ffeb40",
        "body":         "#ffeb40",
        "dim":          "#c7b82d",
        "button":       "#ffffff",
        "button_hover": "#ffffff",
        "error":        "#ff7070",
        "success":      "#70ff70",
    },
    "fonts": {
        "title_size":  16,
        "body_size":   12,
        "hint_size":   10,
        "button_size": 13,
    },
    "modal_dim_alpha": 0.55,
    "frame_stroke": "#6699ee99",
}

# Resolved runtime state. Keys match the FALLBACK_THEME shape exactly.
# Each panels[key] / buttons[key] entry is a Dictionary:
#   {"frame": String, "margin": Vector2i, "mode": String, "texture": Texture2D}
static var panels: Dictionary = {}
static var buttons: Dictionary = {}
static var text_colors: Dictionary = {}  # role -> Color
static var font_sizes: Dictionary = {}   # role -> int
static var modal_dim_alpha: float = 0.55
static var frame_stroke_color: Color = Color(0.4, 0.6, 0.9, 0.6)

# Backward-compat mirrors. Rewritten by apply_theme_dict so old callers
# that reference UIPanels.TEXT_PANEL / PANEL_MARGIN still work.
static var TEXT_PANEL: Color = Color(1.0, 0.92, 0.25, 1.0)
static var TEXT_PANEL_DIM: Color = Color(0.78, 0.72, 0.18, 1.0)
static var PANEL_MARGIN: Vector2i = Vector2i(12, 12)
static var BUTTON_MARGIN: Vector2i = Vector2i(14, 14)

static var _loaded: bool = false
static var _current_theme: Dictionary = {}
static var _current_pack_id: String = ""


# ─── Public theme API ────────────────────────────────────────────────────

static func current_theme() -> Dictionary:
    _ensure_loaded()
    return _current_theme.duplicate(true)

static func current_pack_id() -> String:
    return _current_pack_id

# Loads the global default theme from user://default_ui_theme.json, falling
# back to the hardcoded FALLBACK_THEME. Safe to call multiple times.
static func load_default_theme() -> void:
    var dict := _read_json_file("user://default_ui_theme.json")
    if dict.is_empty():
        dict = FALLBACK_THEME.duplicate(true)
    apply_theme_dict(dict)
    _current_pack_id = ""

# Loads a pack-specific theme from the writable Content/{pack_id}/UI/theme.json. If
# that file doesn't exist, falls back to res://Content/{pack_id}/UI/theme.json
# (shipped default), then to the global user default, then to FALLBACK_THEME.
static func load_pack_theme(pack_id: String) -> void:
    if pack_id == "":
        load_default_theme()
        return
    var user_path := PackPaths.writable_pack_file(pack_id, "UI/theme.json")
    var ship_path := "res://Content/%s/UI/theme.json" % pack_id
    var dict := _read_json_file(user_path)
    if dict.is_empty():
        dict = _read_json_file(ship_path)
    if dict.is_empty():
        dict = _read_json_file("user://default_ui_theme.json")
    if dict.is_empty():
        dict = FALLBACK_THEME.duplicate(true)
    apply_theme_dict(dict)
    _current_pack_id = pack_id

# Parses a theme dict into the static state. Loads textures, converts
# hex strings to Colors, normalizes missing keys against FALLBACK_THEME.
static func apply_theme_dict(theme_dict: Dictionary) -> void:
    var merged := _merge_with_fallback(theme_dict)
    _current_theme = merged.duplicate(true)

    panels.clear()
    var panels_raw: Dictionary = merged.get("panels", {})
    for k in PANEL_KEYS:
        var entry_v: Variant = panels_raw.get(k, {})
        var entry: Dictionary = entry_v if typeof(entry_v) == TYPE_DICTIONARY else {}
        var frame_path := str(entry.get("frame", FALLBACK_THEME["panels"][k]["frame"]))
        var margin := _as_vec2i(entry.get("margin", Vector2i(12, 12)))
        var mode := _normalize_frame_mode(str(entry.get("mode", FALLBACK_THEME["panels"][k]["mode"])))
        var tex: Texture2D = _load_texture_path(frame_path)
        panels[k] = {"frame": frame_path, "margin": margin, "mode": mode, "texture": tex}

    buttons.clear()
    var buttons_raw: Dictionary = merged.get("buttons", {})
    for k in BUTTON_KEYS:
        var entry_v: Variant = buttons_raw.get(k, {})
        var entry: Dictionary = entry_v if typeof(entry_v) == TYPE_DICTIONARY else {}
        var frame_path := str(entry.get("frame", FALLBACK_THEME["buttons"][k]["frame"]))
        var margin := _as_vec2i(entry.get("margin", Vector2i(14, 14)))
        var mode := _normalize_frame_mode(str(entry.get("mode", FALLBACK_THEME["buttons"][k]["mode"])))
        var tex: Texture2D = _load_texture_path(frame_path)
        buttons[k] = {"frame": frame_path, "margin": margin, "mode": mode, "texture": tex}

    text_colors.clear()
    var text_raw: Dictionary = merged.get("text", {})
    for role in TEXT_ROLES:
        var hex := str(text_raw.get(role, FALLBACK_THEME["text"][role]))
        text_colors[role] = _hex_to_color(hex)

    font_sizes.clear()
    var fonts_raw: Dictionary = merged.get("fonts", {})
    for role in FONT_ROLES:
        font_sizes[role] = int(fonts_raw.get(role, FALLBACK_THEME["fonts"][role]))

    modal_dim_alpha = float(merged.get("modal_dim_alpha", 0.55))
    frame_stroke_color = _hex_to_color(str(merged.get("frame_stroke", "#6699ee99")))

    # Update backward-compat mirrors so pre-theme callers keep working.
    TEXT_PANEL = text_colors.get("body", Color(1, 0.92, 0.25, 1))
    TEXT_PANEL_DIM = text_colors.get("dim", Color(0.78, 0.72, 0.18, 1))
    PANEL_MARGIN = (panels["main"] as Dictionary).get("margin", Vector2i(12, 12))
    BUTTON_MARGIN = (buttons["normal"] as Dictionary).get("margin", Vector2i(14, 14))

    _loaded = true

# Writes a theme dict to a pack's UI folder. Creates the folder if missing.
static func save_pack_theme(pack_id: String, theme_dict: Dictionary) -> bool:
    if pack_id == "":
        return false
    var dir_path := PackPaths.writable_pack_dir(pack_id) + "UI"
    DirAccess.make_dir_recursive_absolute(dir_path)
    var path := "%s/theme.json" % dir_path
    return _write_json_file(path, theme_dict)

# Writes a theme dict as the global default (user://default_ui_theme.json).
static func save_default_theme(theme_dict: Dictionary) -> bool:
    return _write_json_file("user://default_ui_theme.json", theme_dict)


# ─── Color / text role helpers ──────────────────────────────────────────

static func text_color(role: String) -> Color:
    _ensure_loaded()
    return text_colors.get(role, TEXT_PANEL)

static func font_size(role: String) -> int:
    _ensure_loaded()
    return int(font_sizes.get(role, 12))


# ─── Public draw API ────────────────────────────────────────────────────

# Draws a 9-slice panel into `rect` on `canvas`. Pass a Color via `modulate`
# to tint the panel art (default white = show native). Variant picks which
# of the main/alt/dark panel skins to draw.
static func draw_panel(canvas: CanvasItem, rect: Rect2,
        modulate: Color = Color.WHITE, variant: int = PanelVariant.MAIN) -> void:
    _ensure_loaded()
    var key := _panel_key_for_variant(variant)
    var entry: Dictionary = panels.get(key, {})
    var tex: Texture2D = entry.get("texture", null)
    if tex == null:
        canvas.draw_rect(rect, modulate * Color(0.06, 0.07, 0.11, 0.9))
        canvas.draw_rect(rect, modulate * Color(0.25, 0.3, 0.45, 0.6), false, 1.0)
        return
    _draw_framed_texture(canvas, rect, entry, tex, modulate, Vector2i(12, 12))

# Draws a 9-slice button with a centered label.
static func draw_button(canvas: CanvasItem, rect: Rect2, label: String, font: Font,
        hovered: bool = false, modulate: Color = Color.WHITE,
        pressed: bool = false, label_color: Color = Color(0.92, 0.95, 1.0)) -> void:
    _ensure_loaded()
    var key := "pressed" if pressed else ("hover" if hovered else "normal")
    var entry: Dictionary = buttons.get(key, {})
    var tex: Texture2D = entry.get("texture", null)
    if tex == null:
        var bg := modulate * Color(0.1, 0.15, 0.25, 0.9)
        if hovered: bg = bg.lerp(modulate * Color(0.3, 0.45, 0.65, 0.95), 0.6)
        canvas.draw_rect(rect, bg)
        canvas.draw_rect(rect, modulate * Color(0.4, 0.6, 0.85, 0.7), false, 1.5)
    else:
        _draw_framed_texture(canvas, rect, entry, tex, modulate, Vector2i(14, 14))
    # Center the label
    var text_w := float(label.length()) * 6.0
    var text_x := rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y := rect.position.y + rect.size.y * 0.5 + 5
    var col := label_color if hovered else label_color * Color(0.7, 0.75, 0.82, 1.0)
    canvas.draw_string(font, Vector2(text_x, text_y), label,
        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size("button_size"), col)

# Just the button 9-slice background (no label). Use this when you want to
# preserve custom label drawing.
static func draw_button_bg(canvas: CanvasItem, rect: Rect2,
        hovered: bool = false, modulate: Color = Color.WHITE,
        pressed: bool = false) -> void:
    _ensure_loaded()
    var key := "pressed" if pressed else ("hover" if hovered else "normal")
    var entry: Dictionary = buttons.get(key, {})
    var tex: Texture2D = entry.get("texture", null)
    if tex == null:
        var bg := modulate * Color(0.1, 0.15, 0.25, 0.9)
        if hovered: bg = bg.lerp(modulate * Color(0.3, 0.45, 0.65, 0.95), 0.6)
        canvas.draw_rect(rect, bg)
        canvas.draw_rect(rect, modulate * Color(0.4, 0.6, 0.85, 0.7), false, 1.5)
        return
    _draw_framed_texture(canvas, rect, entry, tex, modulate, Vector2i(14, 14))

# Just a frame stroke around `rect`, used for grouping headers / dividers.
static func draw_frame(canvas: CanvasItem, rect: Rect2, color: Color = Color(0, 0, 0, 0), thickness: float = 1.0) -> void:
    _ensure_loaded()
    var c := color if color.a > 0.0 else frame_stroke_color
    canvas.draw_rect(rect, c, false, thickness)

# Translucent background dim layer (e.g. modal backdrop). If alpha <= 0,
# uses the theme's modal_dim_alpha value.
static func draw_dim(canvas: CanvasItem, rect: Rect2, alpha: float = -1.0) -> void:
    _ensure_loaded()
    var a := alpha if alpha >= 0.0 else modal_dim_alpha
    canvas.draw_rect(rect, Color(0, 0, 0, a))


# ─── Internals ──────────────────────────────────────────────────────────

static func _ensure_loaded() -> void:
    if _loaded:
        return
    load_default_theme()

static func _panel_key_for_variant(variant: int) -> String:
    match variant:
        PanelVariant.ALT: return "alt"
        PanelVariant.DARK: return "dark"
        _: return "main"

static func _read_json_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var f := FileAccess.open(path, FileAccess.READ)
    if f == null:
        return {}
    var text := f.get_as_text()
    f.close()
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed

static func _write_json_file(path: String, data: Dictionary) -> bool:
    var text := JSON.stringify(data, "\t")
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(text)
    f.close()
    return true


static func _load_texture_path(path: String) -> Texture2D:
    if path.is_empty():
        return null
    if path.begins_with("res://"):
        return load(path) as Texture2D
    if path.begins_with("user://") or path.contains(":/") or path.begins_with("/"):
        if not FileAccess.file_exists(path):
            return null
        var file := FileAccess.open(path, FileAccess.READ)
        if file == null:
            return null
        var bytes := file.get_buffer(file.get_length())
        file.close()
        var image := Image.new()
        if image.load_png_from_buffer(bytes) != OK:
            return null
        return ImageTexture.create_from_image(image)
    return null


static func _normalize_frame_mode(mode: String) -> String:
    var clean := mode.strip_edges().to_lower()
    if clean == "stretch":
        return "stretch"
    return "9slice"

# Deep-merges `theme_dict` on top of FALLBACK_THEME so missing keys
# (e.g. the user only set panels.main.frame) are filled from fallback.
static func _merge_with_fallback(theme_dict: Dictionary) -> Dictionary:
    var out: Dictionary = FALLBACK_THEME.duplicate(true)
    _deep_merge(out, theme_dict)
    return out

static func _deep_merge(dst: Dictionary, src: Dictionary) -> void:
    for k in src.keys():
        var sv: Variant = src[k]
        if typeof(sv) == TYPE_DICTIONARY and typeof(dst.get(k, null)) == TYPE_DICTIONARY:
            _deep_merge(dst[k], sv)
        else:
            dst[k] = sv

static func _as_vec2i(v: Variant) -> Vector2i:
    if typeof(v) == TYPE_VECTOR2I:
        return v
    if typeof(v) == TYPE_VECTOR2:
        return Vector2i(int((v as Vector2).x), int((v as Vector2).y))
    if typeof(v) == TYPE_ARRAY:
        var a: Array = v
        if a.size() >= 2:
            return Vector2i(int(a[0]), int(a[1]))
    return Vector2i(12, 12)

# Accepts "#rrggbb", "#rrggbbaa", "rrggbb", or Godot color names. Returns
# white on parse failure so the theme still draws something legible.
static func _hex_to_color(hex: String) -> Color:
    var s := hex.strip_edges()
    if s == "":
        return Color.WHITE
    if s.begins_with("#"):
        s = s.substr(1)
    if s.length() == 6 or s.length() == 8:
        return Color.html(s)
    return Color.WHITE

static func color_to_hex(col: Color) -> String:
    return "#" + col.to_html(col.a < 1.0).to_lower()


# ─── 9-slice core ───────────────────────────────────────────────────────

# Manual 9-slice draw. Splits the source texture into 9 regions based on
# `margin` (corner size in pixels), then draws them into `rect`:
#   - 4 corners stay at original size (no scale)
#   - 4 edges stretch along one axis
#   - 1 center stretches both axes
# All draws go through a single modulate Color so palette-swap is uniform.
static func _draw_9slice(canvas: CanvasItem, tex: Texture2D, rect: Rect2,
        margin: Vector2i, modulate: Color) -> void:
    var ts: Vector2 = tex.get_size()
    if ts.x <= 0 or ts.y <= 0:
        canvas.draw_rect(rect, modulate * Color(0.1, 0.1, 0.15, 0.9))
        return
    var mx := float(margin.x)
    var my := float(margin.y)
    if mx * 2.0 > rect.size.x: mx = rect.size.x * 0.5
    if my * 2.0 > rect.size.y: my = rect.size.y * 0.5

    var inner_w := maxf(0.0, rect.size.x - mx * 2.0)
    var inner_h := maxf(0.0, rect.size.y - my * 2.0)
    var src_inner_w := maxf(1.0, ts.x - mx * 2.0)
    var src_inner_h := maxf(1.0, ts.y - my * 2.0)

    var rp := rect.position

    # Top-left corner
    canvas.draw_texture_rect_region(tex,
        Rect2(rp, Vector2(mx, my)),
        Rect2(0, 0, mx, my), modulate)
    # Top-right corner
    canvas.draw_texture_rect_region(tex,
        Rect2(rp + Vector2(rect.size.x - mx, 0), Vector2(mx, my)),
        Rect2(ts.x - mx, 0, mx, my), modulate)
    # Bottom-left corner
    canvas.draw_texture_rect_region(tex,
        Rect2(rp + Vector2(0, rect.size.y - my), Vector2(mx, my)),
        Rect2(0, ts.y - my, mx, my), modulate)
    # Bottom-right corner
    canvas.draw_texture_rect_region(tex,
        Rect2(rp + Vector2(rect.size.x - mx, rect.size.y - my), Vector2(mx, my)),
        Rect2(ts.x - mx, ts.y - my, mx, my), modulate)

    # Top edge
    if inner_w > 0:
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(mx, 0), Vector2(inner_w, my)),
            Rect2(mx, 0, src_inner_w, my), modulate)
        # Bottom edge
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(mx, rect.size.y - my), Vector2(inner_w, my)),
            Rect2(mx, ts.y - my, src_inner_w, my), modulate)
    # Left edge
    if inner_h > 0:
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(0, my), Vector2(mx, inner_h)),
            Rect2(0, my, mx, src_inner_h), modulate)
        # Right edge
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(rect.size.x - mx, my), Vector2(mx, inner_h)),
            Rect2(ts.x - mx, my, mx, src_inner_h), modulate)
    # Center
    if inner_w > 0 and inner_h > 0:
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(mx, my), Vector2(inner_w, inner_h)),
            Rect2(mx, my, src_inner_w, src_inner_h), modulate)


static func _draw_framed_texture(canvas: CanvasItem, rect: Rect2, entry: Dictionary,
        tex: Texture2D, modulate: Color, fallback_margin: Vector2i) -> void:
    var mode := _normalize_frame_mode(str(entry.get("mode", "9slice")))
    if mode == "stretch":
        canvas.draw_texture_rect(tex, rect, false, modulate)
        return
    var margin: Vector2i = entry.get("margin", fallback_margin)
    _draw_9slice(canvas, tex, rect, margin, modulate)


static func draw_authored_panel_sprite(canvas: CanvasItem, rect: Rect2, tex: Texture2D,
        props: Dictionary, modulate: Color = Color.WHITE, scale: float = 1.0) -> void:
    if tex == null:
        return
    var mode := _normalize_frame_mode(str(props.get("sprite_mode", "9slice")))
    if mode == "stretch":
        canvas.draw_texture_rect(tex, rect, false, modulate)
        return
    var raw_slice_x := float(props.get("sprite_slice_x", 0.0))
    var raw_slice_y := float(props.get("sprite_slice_y", 0.0))
    if raw_slice_x <= 0.0:
        raw_slice_x = floor(tex.get_width() / 3.0)
    if raw_slice_y <= 0.0:
        raw_slice_y = floor(tex.get_height() / 3.0)
    var src_margin := Vector2(
        maxf(raw_slice_x, 0.0),
        maxf(raw_slice_y, 0.0))
    _draw_tiled_9slice(canvas, tex, rect, src_margin, maxf(scale, 0.001), modulate)


static func _draw_tiled_9slice(canvas: CanvasItem, tex: Texture2D, rect: Rect2,
        src_margin: Vector2, scale: float, modulate: Color) -> void:
    var ts: Vector2 = tex.get_size()
    if ts.x <= 0.0 or ts.y <= 0.0:
        canvas.draw_rect(rect, modulate * Color(0.1, 0.1, 0.15, 0.9))
        return
    var src_mx := clampf(src_margin.x, 0.0, ts.x * 0.5)
    var src_my := clampf(src_margin.y, 0.0, ts.y * 0.5)
    var dst_mx := minf(src_mx * scale, rect.size.x * 0.5)
    var dst_my := minf(src_my * scale, rect.size.y * 0.5)
    var src_inner_w := maxf(0.0, ts.x - src_mx * 2.0)
    var src_inner_h := maxf(0.0, ts.y - src_my * 2.0)
    var dst_inner_w := maxf(0.0, rect.size.x - dst_mx * 2.0)
    var dst_inner_h := maxf(0.0, rect.size.y - dst_my * 2.0)
    var rp := rect.position

    if dst_mx > 0.0 and dst_my > 0.0:
        canvas.draw_texture_rect_region(tex,
            Rect2(rp, Vector2(dst_mx, dst_my)),
            Rect2(0.0, 0.0, src_mx, src_my), modulate)
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(rect.size.x - dst_mx, 0.0), Vector2(dst_mx, dst_my)),
            Rect2(ts.x - src_mx, 0.0, src_mx, src_my), modulate)
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(0.0, rect.size.y - dst_my), Vector2(dst_mx, dst_my)),
            Rect2(0.0, ts.y - src_my, src_mx, src_my), modulate)
        canvas.draw_texture_rect_region(tex,
            Rect2(rp + Vector2(rect.size.x - dst_mx, rect.size.y - dst_my), Vector2(dst_mx, dst_my)),
            Rect2(ts.x - src_mx, ts.y - src_my, src_mx, src_my), modulate)

    if dst_inner_w > 0.0 and dst_my > 0.0 and src_inner_w > 0.0 and src_my > 0.0:
        _tile_region(canvas, tex,
            Rect2(rp + Vector2(dst_mx, 0.0), Vector2(dst_inner_w, dst_my)),
            Rect2(src_mx, 0.0, src_inner_w, src_my),
            Vector2(src_inner_w * scale, dst_my), modulate)
        _tile_region(canvas, tex,
            Rect2(rp + Vector2(dst_mx, rect.size.y - dst_my), Vector2(dst_inner_w, dst_my)),
            Rect2(src_mx, ts.y - src_my, src_inner_w, src_my),
            Vector2(src_inner_w * scale, dst_my), modulate)
    if dst_inner_h > 0.0 and dst_mx > 0.0 and src_inner_h > 0.0 and src_mx > 0.0:
        _tile_region(canvas, tex,
            Rect2(rp + Vector2(0.0, dst_my), Vector2(dst_mx, dst_inner_h)),
            Rect2(0.0, src_my, src_mx, src_inner_h),
            Vector2(dst_mx, src_inner_h * scale), modulate)
        _tile_region(canvas, tex,
            Rect2(rp + Vector2(rect.size.x - dst_mx, dst_my), Vector2(dst_mx, dst_inner_h)),
            Rect2(ts.x - src_mx, src_my, src_mx, src_inner_h),
            Vector2(dst_mx, src_inner_h * scale), modulate)
    if dst_inner_w > 0.0 and dst_inner_h > 0.0 and src_inner_w > 0.0 and src_inner_h > 0.0:
        _tile_region(canvas, tex,
            Rect2(rp + Vector2(dst_mx, dst_my), Vector2(dst_inner_w, dst_inner_h)),
            Rect2(src_mx, src_my, src_inner_w, src_inner_h),
            Vector2(src_inner_w * scale, src_inner_h * scale), modulate)


static func _tile_region(canvas: CanvasItem, tex: Texture2D, dest_rect: Rect2,
        src_rect: Rect2, tile_size: Vector2, modulate: Color) -> void:
    var step_x := maxf(tile_size.x, 1.0)
    var step_y := maxf(tile_size.y, 1.0)
    var dx := 0.0
    while dx < dest_rect.size.x - 0.001:
        var draw_w := minf(step_x, dest_rect.size.x - dx)
        var src_w := src_rect.size.x * (draw_w / step_x)
        var dy := 0.0
        while dy < dest_rect.size.y - 0.001:
            var draw_h := minf(step_y, dest_rect.size.y - dy)
            var src_h := src_rect.size.y * (draw_h / step_y)
            canvas.draw_texture_rect_region(tex,
                Rect2(dest_rect.position + Vector2(dx, dy), Vector2(draw_w, draw_h)),
                Rect2(src_rect.position + Vector2.ZERO, Vector2(src_w, src_h)), modulate)
            dy += draw_h
        dx += draw_w


# ─── UI Builder draw helpers ────────────────────────────────────────────

static func draw_progress_bar(canvas: CanvasItem, rect: Rect2, fill_ratio: float,
        fill_color: Color, bg_color: Color, direction: String = "left_to_right",
        label_text: String = "", font: Font = null) -> void:
    canvas.draw_rect(rect, bg_color)
    var ratio := clampf(fill_ratio, 0.0, 1.0)
    var fill_rect: Rect2
    match direction:
        "right_to_left":
            var fw := rect.size.x * ratio
            fill_rect = Rect2(rect.position.x + rect.size.x - fw, rect.position.y, fw, rect.size.y)
        "bottom_to_top":
            var fh := rect.size.y * ratio
            fill_rect = Rect2(rect.position.x, rect.position.y + rect.size.y - fh, rect.size.x, fh)
        "top_to_bottom":
            fill_rect = Rect2(rect.position, Vector2(rect.size.x, rect.size.y * ratio))
        _:  # left_to_right
            fill_rect = Rect2(rect.position, Vector2(rect.size.x * ratio, rect.size.y))
    if ratio > 0.0:
        canvas.draw_rect(fill_rect, fill_color)
    if not label_text.is_empty() and font != null:
        var label_y := rect.position.y + rect.size.y * 0.5 + 4.0
        canvas.draw_string(font, Vector2(rect.position.x + 4, label_y),
            label_text, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 8),
            clampi(int(rect.size.y * 0.6), 8, 14), Color.WHITE)


static func draw_icon(canvas: CanvasItem, rect: Rect2, texture: Texture2D,
        src_rect: Rect2 = Rect2(), tint: Color = Color.WHITE) -> void:
    if texture == null:
        canvas.draw_rect(rect, Color(0.3, 0.3, 0.3, 0.5))
        return
    if src_rect.size.x <= 0 or src_rect.size.y <= 0:
        canvas.draw_texture_rect(texture, rect, false, tint)
    else:
        canvas.draw_texture_rect_region(texture, rect, src_rect, tint)


static func draw_separator(canvas: CanvasItem, rect: Rect2, color: Color = Color(0.5, 0.5, 0.5, 0.8),
        thickness: float = 1.0, orientation: String = "horizontal") -> void:
    if orientation == "vertical":
        var cx := rect.position.x + rect.size.x * 0.5
        canvas.draw_line(Vector2(cx, rect.position.y), Vector2(cx, rect.position.y + rect.size.y), color, thickness)
    else:
        var cy := rect.position.y + rect.size.y * 0.5
        canvas.draw_line(Vector2(rect.position.x, cy), Vector2(rect.position.x + rect.size.x, cy), color, thickness)


static func draw_tab_bar(canvas: CanvasItem, rect: Rect2, tabs: Array, active_idx: int,
        font: Font, active_color: Color = Color(0.4, 0.85, 1.0, 1.0),
        inactive_color: Color = Color(0.6, 0.65, 0.7, 1.0)) -> void:
    if tabs.is_empty():
        return
    var tab_w := rect.size.x / float(tabs.size())
    for i in tabs.size():
        var tab_rect := Rect2(rect.position.x + i * tab_w, rect.position.y, tab_w, rect.size.y)
        var is_active := i == active_idx
        var bg_col := Color(0.25, 0.35, 0.5, 0.9) if is_active else Color(0.2, 0.22, 0.3, 0.6)
        canvas.draw_rect(tab_rect, bg_col)
        var label: String = str(tabs[i]) if typeof(tabs[i]) != TYPE_DICTIONARY else str((tabs[i] as Dictionary).get("label", ""))
        var col := active_color if is_active else inactive_color
        if font != null:
            canvas.draw_string(font, tab_rect.position + Vector2(6, rect.size.y * 0.7),
                label, HORIZONTAL_ALIGNMENT_LEFT, int(tab_w - 12),
                clampi(int(rect.size.y * 0.55), 8, 14), col)

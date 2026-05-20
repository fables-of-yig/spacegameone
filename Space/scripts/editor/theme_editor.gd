extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo     = preload("res://Space/scripts/shared/ui/ui_io.gd")
const UITypes  = preload("res://Space/scripts/shared/ui/ui_types.gd")

# In-game theme editor main controller. Owns the working theme dict for
# the active pack and exposes mutator methods that every sub-panel/modal
# routes through. Mutators apply to UIPanels live so the preview pane
# (and the editor chrome itself) reflect every edit instantly.
#
# Child panels:
#   ui_topbar.gd        — pack label + SAVE / SET DEFAULT / LOAD DEFAULT / RESET / CLOSE
#   ui_field_panel.gd   — scrollable list of every editable field
#   ui_preview_panel.gd — live preview: panels, buttons, every text role, modal
#
# Modals:
#   ui_texture_picker.gd — full-screen 9-slice picker
#   ui_color_modal.gd    — hex + swatch grid
#   ui_number_modal.gd   — int/float input

signal closed

var pack_id: String = ""
var theme_data: Dictionary = {}
var dirty: bool = false

# Editor mode: 0 = theme styling, 1 = screen layout builder
var editor_mode: int = 0
var _active_screen_id: String = "hud_space"
var _screen_data: Dictionary = {}
var _screen_dirty: bool = false

var topbar: Control = null
var field_panel: Control = null
var preview_panel: Control = null
var texture_picker: Control = null
var color_modal: Control = null
var number_modal: Control = null
var screen_texture_import_dialog: FileDialog = null

# Screen editor panels (only visible in mode 1)
var screen_canvas: Control = null
var element_palette: Control = null
var property_panel: Control = null
var hierarchy_panel: Control = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _skip_close_frame: bool = true

var _undo: RefCounted = null

# Live edit context — set by request_* and consumed by the modal callbacks.
var _edit_target: String = ""        # Discriminator: panel_frame, text_color, etc.
var _edit_key: String = ""           # Sub-key (e.g. "main", "hover", "title")

const TOPBAR_H: float = 64.0
const FIELD_W: float  = 380.0
const TOPBAR_PAD: float = 18.0
const TOPBAR_BTN_GAP: float = 8.0
const TUTORIAL_BTN_W: float = 100.0
const TUTORIAL_BTN_H: float = 32.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()


func _capture_state() -> Dictionary:
    return {
        "theme_data": theme_data.duplicate(true),
        "screen_data": _screen_data.duplicate(true),
        "dirty": dirty,
        "screen_dirty": _screen_dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var t_v: Variant = snap.get("theme_data", null)
    if typeof(t_v) == TYPE_DICTIONARY:
        theme_data = t_v
        UIPanels.apply_theme_dict(theme_data)
    var s_v: Variant = snap.get("screen_data", null)
    if typeof(s_v) == TYPE_DICTIONARY:
        _screen_data = s_v
        if screen_canvas != null:
            screen_canvas.screen_data = _screen_data
            screen_canvas.queue_redraw()
        if hierarchy_panel != null:
            hierarchy_panel.screen_data = _screen_data
            hierarchy_panel.queue_redraw()
    dirty = bool(snap.get("dirty", false))
    _screen_dirty = bool(snap.get("screen_dirty", false))
    if field_panel != null and field_panel.has_method("queue_redraw"):
        field_panel.queue_redraw()
    if preview_panel != null and preview_panel.has_method("queue_redraw"):
        preview_panel.queue_redraw()


func _build_layout() -> void:
    topbar = Control.new()
    topbar.set_script(preload("res://Space/scripts/editor/ui/ui_topbar.gd"))
    topbar.editor = self
    add_child(topbar)

    field_panel = Control.new()
    field_panel.set_script(preload("res://Space/scripts/editor/ui/ui_field_panel.gd"))
    field_panel.editor = self
    add_child(field_panel)

    preview_panel = Control.new()
    preview_panel.set_script(preload("res://Space/scripts/editor/ui/ui_preview_panel.gd"))
    preview_panel.editor = self
    add_child(preview_panel)

    texture_picker = Control.new()
    texture_picker.set_script(preload("res://Space/scripts/editor/ui/ui_texture_picker.gd"))
    texture_picker.editor = self
    texture_picker.visible = false
    add_child(texture_picker)
    texture_picker.picked.connect(_on_texture_picked)
    texture_picker.cancelled.connect(_on_modal_cancelled)

    color_modal = Control.new()
    color_modal.set_script(preload("res://Space/scripts/editor/ui/ui_color_modal.gd"))
    color_modal.editor = self
    color_modal.visible = false
    add_child(color_modal)
    color_modal.submitted.connect(_on_color_submitted)
    color_modal.cancelled.connect(_on_modal_cancelled)

    number_modal = Control.new()
    number_modal.set_script(preload("res://Space/scripts/editor/ui/ui_number_modal.gd"))
    number_modal.editor = self
    number_modal.visible = false
    add_child(number_modal)
    number_modal.submitted.connect(_on_number_submitted)
    number_modal.cancelled.connect(_on_modal_cancelled)

    screen_texture_import_dialog = FileDialog.new()
    screen_texture_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    screen_texture_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
    screen_texture_import_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
    _enable_native_file_dialog(screen_texture_import_dialog)
    screen_texture_import_dialog.file_selected.connect(_on_screen_texture_file_selected)
    screen_texture_import_dialog.canceled.connect(_on_modal_cancelled)
    add_child(screen_texture_import_dialog)

    # Screen editor panels (initially hidden)
    screen_canvas = Control.new()
    screen_canvas.set_script(preload("res://Space/scripts/editor/ui/ui_canvas.gd"))
    screen_canvas.editor = self
    screen_canvas.visible = false
    add_child(screen_canvas)
    screen_canvas.element_selected.connect(_on_screen_element_selected)
    screen_canvas.element_moved.connect(_on_screen_element_changed)
    screen_canvas.element_resized.connect(_on_screen_element_changed)

    element_palette = Control.new()
    element_palette.set_script(preload("res://Space/scripts/editor/ui/ui_element_palette.gd"))
    element_palette.editor = self
    element_palette.visible = false
    add_child(element_palette)
    element_palette.element_add_requested.connect(_on_element_add_requested)

    property_panel = Control.new()
    property_panel.set_script(preload("res://Space/scripts/editor/ui/ui_property_panel.gd"))
    property_panel.editor = self
    property_panel.visible = false
    add_child(property_panel)
    property_panel.property_changed.connect(_on_property_changed)

    hierarchy_panel = Control.new()
    hierarchy_panel.set_script(preload("res://Space/scripts/editor/ui/ui_hierarchy.gd"))
    hierarchy_panel.editor = self
    hierarchy_panel.visible = false
    add_child(hierarchy_panel)
    hierarchy_panel.element_selected.connect(_on_screen_element_selected)
    hierarchy_panel.element_delete_requested.connect(_on_element_delete_requested)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    _layout_children()


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_children()


const PALETTE_W: float = 200.0
const PROP_PANEL_W: float = 280.0
const HIERARCHY_H: float = 200.0

func _layout_children() -> void:
    if topbar == null:
        return
    var vw := size.x
    var vh := size.y
    topbar.position = Vector2.ZERO
    topbar.size = Vector2(vw, TOPBAR_H)

    var in_theme_mode := editor_mode == 0

    # Theme mode panels
    if field_panel != null:
        field_panel.visible = in_theme_mode
        field_panel.position = Vector2(0, TOPBAR_H)
        field_panel.size = Vector2(FIELD_W, vh - TOPBAR_H)
    if preview_panel != null:
        preview_panel.visible = in_theme_mode
        preview_panel.position = Vector2(FIELD_W, TOPBAR_H)
        preview_panel.size = Vector2(vw - FIELD_W, vh - TOPBAR_H)

    # Screen editor panels
    var in_screen_mode := editor_mode == 1
    if element_palette != null:
        element_palette.visible = in_screen_mode
        element_palette.position = Vector2(0, TOPBAR_H)
        element_palette.size = Vector2(PALETTE_W, vh - TOPBAR_H)
    if screen_canvas != null:
        screen_canvas.visible = in_screen_mode
        screen_canvas.position = Vector2(PALETTE_W, TOPBAR_H)
        screen_canvas.size = Vector2(vw - PALETTE_W - PROP_PANEL_W, vh - TOPBAR_H - HIERARCHY_H)
    if hierarchy_panel != null:
        hierarchy_panel.visible = in_screen_mode
        hierarchy_panel.position = Vector2(PALETTE_W, vh - HIERARCHY_H)
        hierarchy_panel.size = Vector2(vw - PALETTE_W - PROP_PANEL_W, HIERARCHY_H)
    if property_panel != null:
        property_panel.visible = in_screen_mode
        property_panel.position = Vector2(vw - PROP_PANEL_W, TOPBAR_H)
        property_panel.size = Vector2(PROP_PANEL_W, vh - TOPBAR_H)

    # Modals always full-screen
    if texture_picker != null:
        texture_picker.position = Vector2.ZERO
        texture_picker.size = Vector2(vw, vh)
    if color_modal != null:
        color_modal.position = Vector2.ZERO
        color_modal.size = Vector2(vw, vh)
    if number_modal != null:
        number_modal.position = Vector2.ZERO
        number_modal.size = Vector2(vw, vh)
    if screen_texture_import_dialog != null:
        screen_texture_import_dialog.position = Vector2.ZERO
        screen_texture_import_dialog.size = Vector2(vw, vh)
    if _tutorial_btn != null:
        _layout_tutorial_button(vw)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)


func _layout_tutorial_button(vw: float) -> void:
    if _tutorial_btn == null:
        return
    var mode_label := "SCREEN UI" if editor_mode == 1 else "THEME"
    var header_label := "CAMPAIGN  %s   -   %s" % [pack_id, mode_label]
    if pack_id == "":
        header_label = "GLOBAL DEFAULT   -   %s" % mode_label
    var font: Font = ThemeDB.fallback_font
    var label_w: float = font.get_string_size(header_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
    var left_limit := TOPBAR_PAD + label_w + 18.0 + EditorTooltip.TOGGLE_WIDTH + 12.0
    var right_cluster_w := 126.0 + TOPBAR_BTN_GAP + 100.0 + TOPBAR_BTN_GAP + 130.0 + TOPBAR_BTN_GAP + 130.0 + TOPBAR_BTN_GAP + 90.0 + TOPBAR_BTN_GAP + 90.0
    var right_cluster_left := vw - TOPBAR_PAD - right_cluster_w
    var available_w := right_cluster_left - 12.0 - left_limit
    if available_w < 64.0:
        _tutorial_btn.visible = false
        return
    _tutorial_btn.visible = true
    var tutorial_w := minf(TUTORIAL_BTN_W, available_w)
    var tutorial_x := right_cluster_left - tutorial_w - 12.0
    if tutorial_x < left_limit:
        tutorial_x = left_limit
    _tutorial_btn.position = Vector2(tutorial_x, 16.0)
    _tutorial_btn.size = Vector2(tutorial_w, TUTORIAL_BTN_H)


func open_editor(p_pack_id: String = "") -> void:
    pack_id = p_pack_id
    visible = true
    _skip_close_frame = true

    theme_data = UIIo.load_or_init(pack_id)
    UIPanels.apply_theme_dict(theme_data)
    dirty = false
    if _undo != null:
        _undo.clear()

    if is_inside_tree():
        _layout_children()


func _process(_delta):
    if _skip_close_frame:
        _skip_close_frame = false
        return


func _input(event):
    if not visible:
        return
    if _skip_close_frame:
        return
    if _any_modal_visible():
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _any_modal_visible() -> bool:
    if texture_picker != null and texture_picker.visible:
        return true
    if color_modal != null and color_modal.visible:
        return true
    if number_modal != null and number_modal.visible:
        return true
    if screen_texture_import_dialog != null and screen_texture_import_dialog.visible:
        return true
    return false


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("theme")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


# ─── Save / load ────────────────────────────────────────────────────────

func save_to_pack() -> void:
    if editor_mode == 1:
        _save_active_screen()
        return
    if pack_id == "":
        push_warning("[ThemeEditor] cannot save: no pack_id set")
        return
    var ok := UIIo.save_pack_theme(pack_id, theme_data)
    if ok:
        dirty = false
        print("[ThemeEditor] saved theme for pack '%s'" % pack_id)
    else:
        push_error("[ThemeEditor] save failed for pack '%s'" % pack_id)


func save_as_default() -> void:
    var ok := UIIo.save_default_theme(theme_data)
    if ok:
        print("[ThemeEditor] saved current theme as global default")
    else:
        push_error("[ThemeEditor] failed to save default theme")


func load_from_default() -> void:
    if _undo != null:
        _undo.begin()
    var d := UIIo.load_or_init("")
    theme_data = d
    UIPanels.apply_theme_dict(theme_data)
    dirty = true
    if _undo != null:
        _undo.commit("load default theme")


func reset_to_fallback() -> void:
    if _undo != null:
        _undo.begin()
    theme_data = UITypes.default_theme()
    UIPanels.apply_theme_dict(theme_data)
    dirty = true
    if _undo != null:
        _undo.commit("reset theme")


func request_close() -> void:
    visible = false
    closed.emit()


# ─── Mutators (called from sub-panels via request_*) ────────────────────

func _apply_live() -> void:
    UIPanels.apply_theme_dict(theme_data)
    dirty = true


func set_panel_frame(key: String, path: String) -> void:
    UITypes.set_panel_frame(theme_data, key, path)
    _apply_live()


func set_panel_margin(key: String, margin: Vector2i) -> void:
    UITypes.set_panel_margin(theme_data, key, margin)
    _apply_live()


func cycle_panel_mode(key: String) -> void:
    var current := UITypes.get_panel_mode(theme_data, key)
    var next := "stretch" if current == "9slice" else "9slice"
    UITypes.set_panel_mode(theme_data, key, next)
    _apply_live()


func set_button_frame(key: String, path: String) -> void:
    UITypes.set_button_frame(theme_data, key, path)
    _apply_live()


func set_button_margin(key: String, margin: Vector2i) -> void:
    UITypes.set_button_margin(theme_data, key, margin)
    _apply_live()


func cycle_button_mode(key: String) -> void:
    var current := UITypes.get_button_mode(theme_data, key)
    var next := "stretch" if current == "9slice" else "9slice"
    UITypes.set_button_mode(theme_data, key, next)
    _apply_live()


func set_text_hex(role: String, hex: String) -> void:
    UITypes.set_text_hex(theme_data, role, hex)
    _apply_live()


func set_font_size(role: String, value: int) -> void:
    UITypes.set_font_size(theme_data, role, value)
    _apply_live()


func set_modal_dim_alpha(value: float) -> void:
    UITypes.set_modal_dim_alpha(theme_data, value)
    _apply_live()


func set_frame_stroke(hex: String) -> void:
    UITypes.set_frame_stroke(theme_data, hex)
    _apply_live()


# ─── Modal request helpers (called from field panel) ────────────────────

func request_pick_panel_frame(key: String) -> void:
    _edit_target = "panel_frame"
    _edit_key = key
    var current := str(UITypes.get_panel_entry(theme_data, key).get("frame", ""))
    texture_picker.open(pack_id, current)


func request_pick_button_frame(key: String) -> void:
    _edit_target = "button_frame"
    _edit_key = key
    var current := str(UITypes.get_button_entry(theme_data, key).get("frame", ""))
    texture_picker.open(pack_id, current)


func request_pick_screen_texture(element_id: String, prop_key: String, current_path: String = "") -> void:
    _edit_target = "screen_texture"
    _edit_key = "%s|%s" % [element_id, prop_key]
    texture_picker.open(pack_id, current_path)


func request_import_screen_texture(element_id: String, prop_key: String) -> void:
    if pack_id.is_empty():
        push_warning("[ThemeEditor] cannot import screen texture without an active pack")
        return
    if screen_texture_import_dialog == null:
        return
    _edit_target = "screen_texture_import"
    _edit_key = "%s|%s" % [element_id, prop_key]
    screen_texture_import_dialog.popup_centered_ratio(0.8)


func request_edit_screen_color(element_id: String, prop_key: String, current_hex: String = "") -> void:
    _edit_target = "screen_color"
    _edit_key = "%s|%s" % [element_id, prop_key]
    var current := current_hex.strip_edges()
    if current.is_empty():
        current = "#ffffff"
    color_modal.open("Edit %s" % prop_key, current)


func request_edit_panel_margin(key: String) -> void:
    _edit_target = "panel_margin"
    _edit_key = key
    var entry := UITypes.get_panel_entry(theme_data, key)
    var m_v: Variant = entry.get("margin", [12, 12])
    var current := _vec2i_from_variant(m_v)
    number_modal.open_int_pair("Edit %s margin" % UITypes.panel_label(key),
        current.x, current.y, "9-slice corner size in pixels (X, Y).")


func request_edit_button_margin(key: String) -> void:
    _edit_target = "button_margin"
    _edit_key = key
    var entry := UITypes.get_button_entry(theme_data, key)
    var m_v: Variant = entry.get("margin", [14, 14])
    var current := _vec2i_from_variant(m_v)
    number_modal.open_int_pair("Edit %s margin" % UITypes.button_label(key),
        current.x, current.y, "9-slice corner size in pixels (X, Y).")


func request_edit_text_color(role: String) -> void:
    _edit_target = "text_color"
    _edit_key = role
    var hex := UITypes.get_text_hex(theme_data, role)
    color_modal.open("Edit %s" % UITypes.text_label(role), hex)


func request_edit_frame_stroke() -> void:
    _edit_target = "frame_stroke"
    _edit_key = ""
    var hex := str(theme_data.get("frame_stroke", "#6699ee99"))
    color_modal.open("Edit frame stroke", hex)


func request_edit_font_size(role: String) -> void:
    _edit_target = "font_size"
    _edit_key = role
    var current := UITypes.get_font_size(theme_data, role)
    number_modal.open_int("Edit %s" % UITypes.font_label(role),
        current, "Font size in pixels.")


func request_edit_modal_dim() -> void:
    _edit_target = "modal_dim"
    _edit_key = ""
    var current := float(theme_data.get("modal_dim_alpha", 0.55))
    number_modal.open_float("Edit modal dim alpha",
        current, "0.0 (fully transparent) to 1.0 (fully opaque).")


# ─── Modal callbacks ─────────────────────────────────────────────────────

func _on_texture_picked(path: String) -> void:
    if _undo != null:
        _undo.begin()
    match _edit_target:
        "panel_frame":  set_panel_frame(_edit_key, path)
        "button_frame": set_button_frame(_edit_key, path)
        "screen_texture": _apply_screen_texture_pick(path)
    if _undo != null:
        _undo.commit("set texture")
    _clear_edit()


func _on_color_submitted(hex: String) -> void:
    if _undo != null:
        _undo.begin()
    match _edit_target:
        "screen_color": _apply_screen_color_pick(hex)
        "text_color":   set_text_hex(_edit_key, hex)
        "frame_stroke": set_frame_stroke(hex)
    if _undo != null:
        _undo.commit("set color")
    _clear_edit()


func _on_number_submitted(payload: Dictionary) -> void:
    if _undo != null:
        _undo.begin()
    match _edit_target:
        "panel_margin":
            var v := _vec2i_from_payload(payload)
            set_panel_margin(_edit_key, v)
        "button_margin":
            var v := _vec2i_from_payload(payload)
            set_button_margin(_edit_key, v)
        "font_size":
            set_font_size(_edit_key, int(payload.get("int", 12)))
        "modal_dim":
            set_modal_dim_alpha(float(payload.get("float", 0.55)))
    if _undo != null:
        _undo.commit("set value")
    _clear_edit()


func _on_modal_cancelled() -> void:
    _clear_edit()


func _clear_edit() -> void:
    _edit_target = ""
    _edit_key = ""


func _apply_screen_texture_pick(path: String) -> void:
    var parts := _edit_key.split("|", false, 1)
    if parts.size() != 2:
        return
    var element_id := str(parts[0])
    var prop_key := str(parts[1])
    var elem := _find_element_by_id(_screen_data, element_id)
    if elem.is_empty():
        return
    var props_v: Variant = elem.get("properties", {})
    var props: Dictionary = {}
    if typeof(props_v) == TYPE_DICTIONARY:
        props = props_v
    props[prop_key] = path
    elem["properties"] = props
    _screen_dirty = true
    if property_panel != null:
        property_panel.show_element(elem)
    if screen_canvas != null:
        screen_canvas.queue_redraw()
    if hierarchy_panel != null:
        hierarchy_panel.queue_redraw()


func _apply_screen_color_pick(hex: String) -> void:
    var parts := _edit_key.split("|", false, 1)
    if parts.size() != 2:
        return
    var element_id := str(parts[0])
    var prop_key := str(parts[1])
    var elem := _find_element_by_id(_screen_data, element_id)
    if elem.is_empty():
        return
    var props_v: Variant = elem.get("properties", {})
    var props: Dictionary = {}
    if typeof(props_v) == TYPE_DICTIONARY:
        props = props_v
    props[prop_key] = hex
    elem["properties"] = props
    _screen_dirty = true
    if property_panel != null:
        property_panel.show_element(elem)
    if screen_canvas != null:
        screen_canvas.queue_redraw()
    if hierarchy_panel != null:
        hierarchy_panel.queue_redraw()


func _on_screen_texture_file_selected(source_path: String) -> void:
    if _edit_target != "screen_texture_import":
        return
    var imported_path := UIIo.import_texture_to_pack(pack_id, source_path)
    if imported_path.is_empty():
        return
    if _undo != null:
        _undo.begin()
    _apply_screen_texture_pick(imported_path)
    if _undo != null:
        _undo.commit("import screen texture")
    _clear_edit()


func _enable_native_file_dialog(dialog: FileDialog) -> void:
    for prop_v in dialog.get_property_list():
        if typeof(prop_v) != TYPE_DICTIONARY:
            continue
        var prop: Dictionary = prop_v
        if str(prop.get("name", "")) == "use_native_dialog":
            dialog.set("use_native_dialog", true)
            return


func _vec2i_from_variant(v: Variant) -> Vector2i:
    if typeof(v) == TYPE_VECTOR2I:
        return v
    if typeof(v) == TYPE_VECTOR2:
        return Vector2i(int((v as Vector2).x), int((v as Vector2).y))
    if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
        return Vector2i(int((v as Array)[0]), int((v as Array)[1]))
    return Vector2i(12, 12)


func _vec2i_from_payload(payload: Dictionary) -> Vector2i:
    return Vector2i(int(payload.get("x", 12)), int(payload.get("y", 12)))


# ─── Mode toggle ────────────────────────────────────────────────────────

func toggle_editor_mode() -> void:
    if editor_mode == 0:
        editor_mode = 1
        _load_active_screen()
    else:
        if _screen_dirty:
            _save_active_screen()
        editor_mode = 0
    _layout_children()


func get_editor_mode() -> int:
    return editor_mode


func get_active_screen_id() -> String:
    return _active_screen_id


func set_active_screen(screen_id: String) -> void:
    if _screen_dirty:
        _save_active_screen()
    _active_screen_id = screen_id
    _load_active_screen()


func _load_active_screen() -> void:
    _screen_data = UIIo.load_screen(pack_id, _active_screen_id)
    if _screen_data.is_empty():
        _screen_data = UIIo.default_stock_screen(_active_screen_id)
    if _screen_data.is_empty():
        _screen_data = UITypes.default_element(UITypes.ELEM_PANEL)
        _screen_data["id"] = _active_screen_id + "_root"
        _screen_data["rect"] = {"x": 0, "y": 0, "w": 480, "h": 272}
    _screen_dirty = false
    _sync_screen_editor_views()


func _save_active_screen() -> void:
    if property_panel != null and property_panel.has_method("commit_pending_edits"):
        property_panel.commit_pending_edits()
    if pack_id.is_empty() or _active_screen_id.is_empty():
        return
    _screen_data = UIIo.normalize_screen(_active_screen_id, _screen_data, pack_id)
    if UIIo.save_screen(pack_id, _active_screen_id, _screen_data):
        _screen_dirty = false
        print("[ThemeEditor] saved screen '%s' for pack '%s'" % [_active_screen_id, pack_id])
    else:
        var check := UIIo.validate_screen(_active_screen_id, _screen_data, pack_id)
        for issue in check.get("errors", []):
            push_error("[ThemeEditor] %s.%s" % [_active_screen_id, str(issue)])
        push_error("[ThemeEditor] save failed for screen '%s' in pack '%s'" % [_active_screen_id, pack_id])


func save_screen() -> void:
    _save_active_screen()


# ─── Screen editor callbacks ────────────────────────────────────────────

func _on_screen_element_selected(element_id: String) -> void:
    if property_panel != null and property_panel.has_method("commit_pending_edits"):
        property_panel.commit_pending_edits()
    if screen_canvas != null:
        screen_canvas.selected_element_id = element_id
    if hierarchy_panel != null:
        hierarchy_panel.selected_id = element_id
    # Find the element and show in property panel
    var elem := _find_element_by_id(_screen_data, element_id)
    if property_panel != null:
        if not elem.is_empty():
            property_panel.show_element(elem)
        else:
            property_panel.clear()


func _on_element_add_requested(element_type: String) -> void:
    if _undo != null:
        _undo.begin()
    var new_elem := UITypes.default_element(element_type)
    # Add as child of the root element.
    if not _screen_data.has("children"):
        _screen_data["children"] = []
    (_screen_data["children"] as Array).append(new_elem)
    _screen_dirty = true
    _sync_screen_editor_views()
    # Select the new element
    _on_screen_element_selected(str(new_elem["id"]))
    if _undo != null:
        _undo.commit("add element")


func _on_element_delete_requested(element_id: String) -> void:
    if _undo != null:
        _undo.begin()
    if _remove_element_by_id(_screen_data, element_id):
        _screen_dirty = true
        _sync_screen_editor_views()
        if screen_canvas != null:
            screen_canvas.selected_element_id = ""
        if property_panel != null:
            property_panel.clear()
        if hierarchy_panel != null:
            hierarchy_panel.selected_id = ""
        if _undo != null:
            _undo.commit("delete element")
    else:
        if _undo != null:
            _undo.discard()


func _on_screen_element_changed(_element_id: String) -> void:
    _screen_dirty = true
    _sync_screen_editor_views()
    var elem := _find_element_by_id(_screen_data, _element_id)
    if property_panel != null and not elem.is_empty():
        property_panel.show_element(elem)
    if hierarchy_panel != null:
        hierarchy_panel.queue_redraw()
    if property_panel != null:
        property_panel.queue_redraw()
    if screen_canvas != null:
        screen_canvas.queue_redraw()


func _on_property_changed(element_id: String, key: String, value: Variant) -> void:
    var elem := _find_element_by_id(_screen_data, element_id)
    if elem.is_empty():
        return
    if key == "id":
        var new_id := str(value)
        if new_id.is_empty():
            push_warning("[ThemeEditor] element ids cannot be empty")
            property_panel.show_element(elem)
            return
        var conflict := _find_element_by_id(_screen_data, new_id)
        if not conflict.is_empty() and str(conflict.get("id", "")) != element_id:
            push_warning("[ThemeEditor] duplicate element id '%s'" % new_id)
            property_panel.show_element(elem)
            return
        elem["id"] = new_id
        if screen_canvas != null and screen_canvas.selected_element_id == element_id:
            screen_canvas.selected_element_id = new_id
        if hierarchy_panel != null and hierarchy_panel.selected_id == element_id:
            hierarchy_panel.selected_id = new_id
        if property_panel != null:
            property_panel.show_element(elem)
    elif key == "rect":
        elem["rect"] = value
    elif key == "properties":
        elem["properties"] = value
    else:
        elem[key] = value
    _screen_dirty = true
    _sync_screen_editor_views()


func _find_element_by_id(root: Dictionary, eid: String) -> Dictionary:
    if str(root.get("id", "")) == eid:
        return root
    var children_v: Variant = root.get("children", [])
    if typeof(children_v) == TYPE_ARRAY:
        for child_v in (children_v as Array):
            if typeof(child_v) == TYPE_DICTIONARY:
                var found := _find_element_by_id(child_v, eid)
                if not found.is_empty():
                    return found
    return {}


func _remove_element_by_id(root: Dictionary, eid: String) -> bool:
    var children_v: Variant = root.get("children", [])
    if typeof(children_v) != TYPE_ARRAY:
        return false
    var children: Array = children_v
    for i in children.size():
        var child_v: Variant = children[i]
        if typeof(child_v) != TYPE_DICTIONARY:
            continue
        if str((child_v as Dictionary).get("id", "")) == eid:
            children.remove_at(i)
            return true
        if _remove_element_by_id(child_v, eid):
            return true
    return false


func _sync_screen_editor_views() -> void:
    if screen_canvas != null:
        screen_canvas.screen_data = _screen_data
        screen_canvas.queue_redraw()
    if hierarchy_panel != null:
        hierarchy_panel.screen_data = _screen_data
        hierarchy_panel.queue_redraw()

extends Control

# Top-level player editor. Tab host that mounts the 7 ped/ped_*_tab.gd tabs:
#   Sprites | Stats | Attacks | Projectiles | Abilities | Items | Equipment
#
# Each tab is a Control with the uniform interface:
#   func open(pack_id: String) -> void
#   func save() -> bool
#   func is_dirty() -> bool
#
# Topbar has the title, tab bar, SAVE ALL, and CLOSE. ESC also closes.

const SpritesTabScript     = preload("res://Space/scripts/editor/ped/ped_sprites_tab.gd")
const StatsTabScript       = preload("res://Space/scripts/editor/ped/ped_stats_tab.gd")
const AttacksTabScript     = preload("res://Space/scripts/editor/ped/ped_attacks_tab.gd")
const ProjectilesTabScript = preload("res://Space/scripts/editor/ped/ped_projectiles_tab.gd")
const AbilitiesTabScript   = preload("res://Space/scripts/editor/ped/ped_abilities_tab.gd")
const ItemsTabScript       = preload("res://Space/scripts/editor/ped/ped_items_tab.gd")
const EquipmentTabScript   = preload("res://Space/scripts/editor/ped/ped_equipment_tab.gd")
const PhysicsTabScript     = preload("res://Space/scripts/editor/ped/ped_physics_tab.gd")

signal closed

var pack_id: String = ""

const TOPBAR_H: float = 48.0
const TAB_BAR_H: float = 36.0

var _title_label: Label = null
var _save_btn: Button = null
var _close_btn: Button = null
var _tooltip_toggle: CheckButton = null
var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

# Tab bar buttons (same order as _tabs)
var _tab_buttons: Array = []
var _tabs: Array = []           # Array[Control]
var _tab_labels: Array = [
    "SPRITES", "STATS", "ATTACKS", "PROJECTILES", "ABILITIES", "ITEMS", "EQUIPMENT", "PHYSICS",
]
var _active_tab_idx: int = 0

# When the editor is re-opened we skip the first frame's ESC handling so a
# trailing ESC from the chooser doesn't immediately close us again.
var _skip_close_frame: bool = true


func _ready() -> void:
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    _build_layout.call_deferred()
    set_process(true)


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _process(_delta: float) -> void:
    if _skip_close_frame:
        _skip_close_frame = false


# ─── Public API ──────────────────────────────────────────────────────────

func open_editor(p_pack_id: String = "") -> void:
    pack_id = p_pack_id
    visible = true
    _skip_close_frame = true
    for t in _tabs:
        if t != null:
            t.open(pack_id)
    _set_active_tab(0)
    _layout_children()


func request_close() -> void:
    visible = false
    closed.emit()


# ─── Layout construction ─────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.06, 0.07, 0.1, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _title_label = Label.new()
    _title_label.text = "PLAYER EDITOR"
    _title_label.position = Vector2(16, 14)
    _title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
    add_child(_title_label)

    _save_btn = Button.new()
    _save_btn.text = "SAVE ALL"
    _save_btn.pressed.connect(_on_save_all_pressed)
    add_child(_save_btn)

    _close_btn = Button.new()
    _close_btn.text = "CLOSE"
    _close_btn.pressed.connect(request_close)
    add_child(_close_btn)

    _tooltip_toggle = CheckButton.new()
    _tooltip_toggle.text = "Tooltips"
    _tooltip_toggle.button_pressed = EditorTooltip.enabled
    _tooltip_toggle.toggled.connect(func(on: bool): EditorTooltip.set_enabled(on))
    _tooltip_toggle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
    _tooltip_toggle.add_theme_font_size_override("font_size", 11)
    add_child(_tooltip_toggle)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    # Build tab bar buttons + tab instances
    _tabs = [
        _make_tab(SpritesTabScript),
        _make_tab(StatsTabScript),
        _make_tab(AttacksTabScript),
        _make_tab(ProjectilesTabScript),
        _make_tab(AbilitiesTabScript),
        _make_tab(ItemsTabScript),
        _make_tab(EquipmentTabScript),
        _make_tab(PhysicsTabScript),
    ]
    for i in _tabs.size():
        var t: Control = _tabs[i]
        t.visible = false
        add_child(t)
        var b := Button.new()
        b.text = _tab_labels[i]
        var idx := i
        b.pressed.connect(func(): _set_active_tab(idx))
        add_child(b)
        _tab_buttons.append(b)

    var attacks_tab: Control = _tabs[2] if _tabs.size() > 2 else null
    if attacks_tab != null and attacks_tab.has_signal("edit_projectile_requested"):
        attacks_tab.connect("edit_projectile_requested", Callable(self, "_on_edit_projectile_requested"))

    _set_active_tab(0)
    _layout_children()


func _make_tab(script: Script) -> Control:
    var c := Control.new()
    c.set_script(script)
    return c


func _layout_children() -> void:
    if _title_label == null:
        return
    var vw := size.x
    var vh := size.y

    # Topbar: title left, SAVE ALL + CLOSE right
    var btn_h: float = 32.0
    var btn_y: float = (TOPBAR_H - btn_h) * 0.5
    var close_w: float = 80.0
    var save_w: float = 100.0
    _close_btn.position = Vector2(vw - close_w - 12, btn_y)
    _close_btn.size = Vector2(close_w, btn_h)
    _save_btn.position = Vector2(vw - close_w - save_w - 24, btn_y)
    _save_btn.size = Vector2(save_w, btn_h)
    if _tooltip_toggle != null:
        _tooltip_toggle.position = Vector2(vw - close_w - save_w - 160, btn_y)
        _tooltip_toggle.size = Vector2(120, btn_h)
    if _tutorial_btn != null:
        _tutorial_btn.position = Vector2(vw - close_w - save_w - 270, btn_y)
        _tutorial_btn.size = Vector2(100, btn_h)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)

    # Tab bar: all 7 buttons evenly across the row below the topbar
    var tab_y: float = TOPBAR_H
    var tab_gap: float = 6.0
    var tab_margin: float = 12.0
    var count: float = float(_tab_buttons.size())
    if count > 0:
        var usable_w: float = vw - tab_margin * 2 - tab_gap * (count - 1)
        var tab_w: float = usable_w / count
        for i in _tab_buttons.size():
            var b: Button = _tab_buttons[i]
            b.position = Vector2(tab_margin + i * (tab_w + tab_gap), tab_y + 2)
            b.size = Vector2(tab_w, TAB_BAR_H - 6)

    # Tab content area fills everything below the tab bar
    var content_y: float = TOPBAR_H + TAB_BAR_H
    var content_h: float = vh - content_y
    for t in _tabs:
        if t == null:
            continue
        t.position = Vector2(0, content_y)
        t.size = Vector2(vw, content_h)


# ─── Tab switching ───────────────────────────────────────────────────────

func _set_active_tab(idx: int) -> void:
    if idx < 0 or idx >= _tabs.size():
        return
    _active_tab_idx = idx
    for i in _tabs.size():
        var t: Control = _tabs[i]
        if t != null:
            t.visible = (i == idx)
        var b: Button = _tab_buttons[i] if i < _tab_buttons.size() else null
        if b != null:
            b.add_theme_color_override("font_color",
                Color(1.0, 0.95, 0.6) if i == idx else Color(0.75, 0.85, 0.95))
    var active_tab: Control = _tabs[idx]
    if active_tab != null and active_tab.has_method("refresh_external_refs"):
        active_tab.call("refresh_external_refs")
    var suffix: String = pack_id if not pack_id.is_empty() else "?"
    _title_label.text = "PLAYER EDITOR — %s · [%s]" % [suffix, _tab_labels[idx]]


# ─── Save all ────────────────────────────────────────────────────────────

func _on_save_all_pressed() -> void:
    var any_fail: bool = false
    for t in _tabs:
        if t == null:
            continue
        if t.is_dirty():
            if not t.save():
                any_fail = true
    if any_fail:
        push_error("[PlayerEditor] one or more tabs failed to save")
    else:
        print("[PlayerEditor] saved pack '%s'" % pack_id)


# ─── Input (ESC close) ───────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
    if not visible:
        return
    if _skip_close_frame:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        var ke: InputEventKey = event
        if ke.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("player")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


func _on_edit_projectile_requested(projectile_id: String) -> void:
    _set_active_tab(3)
    var projectiles_tab: Control = _tabs[3] if _tabs.size() > 3 else null
    if projectiles_tab != null and projectiles_tab.has_method("focus_projectile"):
        projectiles_tab.call("focus_projectile", projectile_id)

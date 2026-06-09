extends CanvasLayer

# NebulaPause — one cross-engine pause overlay (autoload, like DevConsole) that
# works in both MV (platformer) and Space (ship combat). It branches the freeze /
# save / quit mechanism per engine and hosts the Nebula Settings + Keybindings
# stack. Themed with NebulaTheme; built from the Claude Design "Pause Menu" handoff.
#
# OWNERSHIP OF ESCAPE:
#   - MV has no Escape handler, so this autoload opens the pause card on Escape via
#     _input (gated so it won't hijack Escape from inventory/map/dialogue/console).
#   - Space's _unhandled_input owns its rich context Escape chain; it calls open()
#     directly. Because this autoload uses _input (which runs before
#     _unhandled_input) it transparently consumes Escape to pop the menu once open.
#
# State machine: _mode ∈ "" (closed) | "pause" (card) | "settings". The settings
# screen and keybindings overlay are children; Back pops the deepest open layer.

const NT := preload("res://MV/scripts/console/nebula_theme.gd")
const SettingsScreenScript := preload("res://Space/scripts/ui/nebula_settings_screen.gd")
const KeybindingsScript := preload("res://Space/scripts/ui/nebula_keybindings.gd")
const UIIo := preload("res://Space/scripts/shared/ui/ui_io.gd")
const AuthoredScreenRuntime := preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource := preload("res://Space/scripts/ui/hud_data_source.gd")

const SPACE_MAIN_SCENE := "res://Space/scenes/main.tscn"

var _mode: String = ""
var _from_pause: bool = false
var _engine: String = ""           # "mv" | "space" while a gameplay pause is open
var _space_host: Node = null

var _card_root: Control = null     # veil + centered pause card
var _settings: Control = null      # NebulaSettingsScreen
var _keys: Control = null          # NebulaKeybindings
var _toast: PanelContainer = null
var _toast_label: Label = null
var _confirm: Control = null

# Authored pack pause screen (AuthoredScreenRuntime). Shown instead of the Nebula
# card when the "Use authored pack UI" setting is on AND the loaded pack ships a
# "pause" screen; otherwise the Nebula card is canonical.
var _authored_pause: Control = null
var _authored_pause_pack: String = ""


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 120
    _build_ui()
    _build_authored_pause()
    _apply_visibility()


func _build_authored_pause() -> void:
    _authored_pause = Control.new()
    _authored_pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _authored_pause.set_script(AuthoredScreenRuntime)
    _authored_pause.visible = false
    add_child(_authored_pause)
    _authored_pause.action_requested.connect(_on_authored_pause_action)


# Driven by the "Use authored pack UI" gameplay setting (off by default), shared
# with the MV HUD. When off, the Nebula overlays are canonical.
func _authored_ui_enabled() -> bool:
    var sm := get_node_or_null("/root/SettingsManager")
    if sm == null:
        return false
    return bool(sm.get_setting("gameplay", "authored_ui_path", false))


func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    return ""


func _authored_pause_active() -> bool:
    if not _authored_ui_enabled():
        return false
    var pack_id := _current_pack_id()
    return not pack_id.is_empty() and UIIo.screen_exists(pack_id, "pause")


func _refresh_authored_pause() -> void:
    if _authored_pause == null:
        return
    var pack_id := _current_pack_id()
    if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "pause"):
        return
    if pack_id != _authored_pause_pack or not bool(_authored_pause.call("has_screen")):
        _authored_pause_pack = pack_id
        var data: Dictionary = UIIo.load_screen(pack_id, "pause")
        _authored_pause.call("load_screen", "pause", data, HudDataSource.new(null, null))


# Maps authored "pause" screen button actions onto the same handlers the Nebula
# card uses, so an authored pause behaves identically (freeze/save/quit per engine).
func _on_authored_pause_action(action_id: String, _action_args: String, _element_id: String) -> void:
    match action_id:
        "resume", "close_screen":
            _resume()
        "save_game", "save":
            _do_save()
        "open_settings", "settings":
            _open_settings_from_pause()
        "quit_to_menu", "quit_game", "exit":
            _confirm_exit()
        _:
            pass


# --- Public API ----------------------------------------------------------------

# Open the gameplay pause card (freezes the active engine). Called by MV Escape
# here, and by Space main.gd's Escape chain.
func open() -> void:
    if _mode != "":
        return
    _reskin()
    if _in_mv():
        _engine = "mv"
        MvGame.simulation_paused = true
    else:
        _engine = "space"
        _space_host = get_tree().current_scene
        if _space_host != null and "pause_open" in _space_host:
            _space_host.set("pause_open", true)
        get_tree().paused = true
    _mode = "pause"
    _hide_confirm()
    _apply_visibility()


# Open the Settings screen directly, with no gameplay pause card behind it.
# Used by the main menu (host_context "main_menu").
func open_settings(host_context: String = "main_menu") -> void:
    _reskin()
    _from_pause = false
    _engine = ""
    _space_host = null
    _mode = "settings"
    _settings.call("open_menu", host_context)
    _apply_visibility()


func is_open() -> bool:
    return _mode != ""


# Pop one level deeper-first. Wired to Escape (MV) and Space's pause-resume path.
func handle_back() -> void:
    if _keys != null and _keys.visible:
        if _keys.call("is_capturing"):
            _keys.call("_cancel_capture")
        else:
            _keys.call("close_menu")
        return
    if _confirm != null and _confirm.visible:
        _hide_confirm()
        return
    if _settings != null and _settings.visible:
        _settings.call("close_menu")   # routes through _on_settings_closed
        return
    if _mode == "pause":
        _resume()


# --- Input ---------------------------------------------------------------------

func _input(event: InputEvent) -> void:
    if _mode == "":
        # Only MV opens on Escape here; Space drives open() from main.gd.
        if _in_mv() and _is_pause_pressed(event) and _can_open_mv():
            open()
            get_viewport().set_input_as_handled()
        return
    # Something is open. Forward capture key presses to the rebinder first.
    if _keys != null and _keys.visible and _keys.call("is_capturing"):
        _keys.call("feed_capture", event)
        get_viewport().set_input_as_handled()
        return
    if _is_back_pressed(event):
        handle_back()
        get_viewport().set_input_as_handled()


func _is_pause_pressed(event: InputEvent) -> bool:
    if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
        return true
    if event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
        return true
    return false


func _is_back_pressed(event: InputEvent) -> bool:
    if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
        return true
    if event is InputEventJoypadButton and event.pressed:
        var idx := (event as InputEventJoypadButton).button_index
        return idx == JOY_BUTTON_B or idx == JOY_BUTTON_START
    return false


func _in_mv() -> bool:
    return MvGame.main != null and is_instance_valid(MvGame.main)


func _can_open_mv() -> bool:
    # Don't hijack Escape if another MV overlay already froze the sim, the dev
    # console is up, or an authoring edit session is active.
    if MvGame.simulation_paused:
        return false
    if PlanetaryInterface != null and "edit_session_active" in PlanetaryInterface and PlanetaryInterface.edit_session_active:
        return false
    if DevConsole != null and "visible" in DevConsole and DevConsole.visible:
        return false
    return true


# --- Menu actions --------------------------------------------------------------

func _resume() -> void:
    if _engine == "mv":
        MvGame.simulation_paused = false
    elif _engine == "space":
        if _space_host != null and is_instance_valid(_space_host) and _space_host.has_method("_on_pause_resumed"):
            _space_host.call("_on_pause_resumed")
        else:
            get_tree().paused = false
    _engine = ""
    _space_host = null
    _mode = ""
    _hide_confirm()
    _apply_visibility()


func _do_save() -> void:
    var slot := 1
    var ok := false
    if _engine == "space":
        slot = int(GameManager.current_save_slot)
        ok = bool(GameManager.save_game(slot))
    else:
        ok = bool(MvSaveManager.save_game(slot))
    if ok:
        _show_toast("✓  Game saved — Slot %d" % slot, NT.C_SUCCESS)
    else:
        _show_toast("✕  Save failed", NT.C_ERROR)


func _open_settings_from_pause() -> void:
    _from_pause = true
    _mode = "settings"
    _settings.call("open_menu", "pause_menu")
    _apply_visibility()


func _on_settings_closed() -> void:
    if _from_pause:
        _mode = "pause"
    else:
        _mode = ""
    _from_pause = false
    _apply_visibility()


func _on_edit_keybindings_requested() -> void:
    _keys.call("open_menu")


func _confirm_exit() -> void:
    # Tear down all overlay UI first — this autoload survives the scene change, so
    # the confirm modal (and card) would otherwise linger on the main menu.
    _hide_confirm()
    if _settings != null:
        _settings.visible = false
    if _keys != null:
        _keys.visible = false
    if _engine == "space" and _space_host != null and is_instance_valid(_space_host) and _space_host.has_method("_on_quit_to_menu"):
        _space_host.call("_on_quit_to_menu")
        _engine = ""
        _space_host = null
        _mode = ""
        _apply_visibility()
        return
    # MV (or no Space host) — mirror Space's quit: reset and return to the launcher.
    MvGame.simulation_paused = false
    GameManager.skip_main_menu = false
    GameManager.reset_to_new_game()
    get_tree().paused = false
    _engine = ""
    _space_host = null
    _mode = ""
    _apply_visibility()
    get_tree().change_scene_to_file(SPACE_MAIN_SCENE)


# --- Visibility ----------------------------------------------------------------

func _apply_visibility() -> void:
    var authored := _mode == "pause" and _authored_pause_active()
    if authored:
        _refresh_authored_pause()
    if _authored_pause != null:
        _authored_pause.visible = authored
    if _card_root != null:
        _card_root.visible = _mode == "pause" and not authored
    if _settings != null and not _settings.visible and _mode == "settings":
        pass  # settings manages its own visible flag via open_menu/close_menu
    # confirm + toast manage their own visibility


func _reskin() -> void:
    var t := NT.theme()
    if _card_root != null:
        _card_root.theme = t
    if _confirm != null:
        _confirm.theme = t


# --- UI construction -----------------------------------------------------------

func _build_ui() -> void:
    var t := NT.theme()

    # Pause card (veil + centered armored card).
    _card_root = Control.new()
    _card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _card_root.theme = t
    _card_root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_card_root)

    var veil := ColorRect.new()
    veil.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.62)
    veil.set_anchors_preset(Control.PRESET_FULL_RECT)
    _card_root.add_child(veil)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _card_root.add_child(center)

    var frame := PanelContainer.new()
    frame.custom_minimum_size = Vector2(468, 0)
    center.add_child(frame)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 26)
    margin.add_theme_constant_override("margin_right", 26)
    margin.add_theme_constant_override("margin_top", 24)
    margin.add_theme_constant_override("margin_bottom", 20)
    frame.add_child(margin)

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 14)
    margin.add_child(col)

    # Header.
    var header := HBoxContainer.new()
    header.add_theme_constant_override("separation", 10)
    var title_col := VBoxContainer.new()
    title_col.add_theme_constant_override("separation", 0)
    title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title_col.add_child(NT.title_label("PAUSED"))
    var subtitle := Label.new()
    subtitle.text = "SECTOR 7 · VOID PATROL"
    subtitle.add_theme_color_override("font_color", NT.C_DIM)
    subtitle.add_theme_font_size_override("font_size", NT.size("hint"))
    title_col.add_child(subtitle)
    header.add_child(title_col)
    var close_btn := Button.new()
    close_btn.text = "✕"
    close_btn.custom_minimum_size = Vector2(40, 0)
    close_btn.pressed.connect(_resume)
    header.add_child(close_btn)
    col.add_child(header)

    # Menu rows.
    col.add_child(_menu_row("Resume", "Return to the game", _resume, "primary"))
    col.add_child(_menu_row("Save Game", "Slot 1", _do_save, "steel"))
    col.add_child(_menu_row("Settings", "Graphics · Audio · Controls", _open_settings_from_pause, "steel"))
    col.add_child(_menu_row("Exit Game", "Return to the main menu", _show_confirm, "danger"))

    # Footer.
    var footer := Label.new()
    footer.text = "SAVE SLOT 1"
    footer.add_theme_color_override("font_color", NT.C_DIM)
    footer.add_theme_font_size_override("font_size", NT.size("hint"))
    col.add_child(footer)

    # Settings + keybindings (own their visibility).
    _settings = SettingsScreenScript.new()
    add_child(_settings)
    _settings.connect("closed", _on_settings_closed)
    _settings.connect("edit_keybindings_requested", _on_edit_keybindings_requested)

    _keys = KeybindingsScript.new()
    add_child(_keys)

    _build_toast()
    _build_confirm()


func _menu_row(label_text: String, sub_text: String, on_click: Callable, variant: String) -> Control:
    var card := PanelContainer.new()
    var selected := variant == "primary"
    var box := NT.card_box(selected)
    if variant == "danger":
        box.border_color = NT.C_ERROR
        box.border_width_left = 3
    card.add_theme_stylebox_override("panel", box)
    card.mouse_filter = Control.MOUSE_FILTER_STOP
    card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    card.gui_input.connect(func(e: InputEvent) -> void:
        if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
            on_click.call())
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 10)
    card.add_child(row)
    var txt := VBoxContainer.new()
    txt.add_theme_constant_override("separation", 0)
    txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var name_lbl := Label.new()
    name_lbl.text = label_text.to_upper()
    name_lbl.add_theme_font_size_override("font_size", NT.size("button"))
    var name_col := NT.C_TITLE if variant == "primary" else NT.C_BODY
    if variant == "danger":
        name_col = NT.C_ERROR
    name_lbl.add_theme_color_override("font_color", name_col)
    if NT.font() != null:
        name_lbl.add_theme_font_override("font", NT.font())
    txt.add_child(name_lbl)
    if not sub_text.is_empty():
        var sub := Label.new()
        sub.text = sub_text
        sub.add_theme_color_override("font_color", NT.C_DIM)
        sub.add_theme_font_size_override("font_size", NT.size("hint"))
        txt.add_child(sub)
    row.add_child(txt)
    var chev := Label.new()
    chev.text = "›"
    chev.add_theme_color_override("font_color", NT.C_DIM)
    chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(chev)
    return card


func _build_toast() -> void:
    _toast = PanelContainer.new()
    var box := NT.card_box(false)
    box.border_color = NT.C_SUCCESS
    _toast.add_theme_stylebox_override("panel", box)
    _toast.visible = false
    _toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _toast.offset_bottom = -40
    _toast.offset_top = -40
    _toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
    _toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
    _toast_label = Label.new()
    _toast_label.add_theme_color_override("font_color", NT.C_SUCCESS)
    _toast.add_child(_toast_label)
    add_child(_toast)


func _show_toast(text: String, color: Color) -> void:
    if _toast == null:
        return
    var box := NT.card_box(false)
    box.border_color = color
    _toast.add_theme_stylebox_override("panel", box)
    _toast_label.text = text
    _toast_label.add_theme_color_override("font_color", color)
    _toast.visible = true
    var timer := get_tree().create_timer(2.4, true)
    timer.timeout.connect(func() -> void:
        if _toast != null:
            _toast.visible = false)


func _build_confirm() -> void:
    _confirm = Control.new()
    _confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
    _confirm.theme = NT.theme()
    _confirm.visible = false
    _confirm.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_confirm)

    var scrim := ColorRect.new()
    scrim.color = Color(4.0 / 255.0, 7.0 / 255.0, 12.0 / 255.0, 0.7)
    scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
    scrim.mouse_filter = Control.MOUSE_FILTER_STOP
    scrim.gui_input.connect(func(e: InputEvent) -> void:
        if e is InputEventMouseButton and e.pressed:
            _hide_confirm())
    _confirm.add_child(scrim)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    _confirm.add_child(center)

    var frame := PanelContainer.new()
    frame.custom_minimum_size = Vector2(420, 0)
    center.add_child(frame)
    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 22)
    margin.add_theme_constant_override("margin_bottom", 20)
    frame.add_child(margin)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 14)
    margin.add_child(col)

    var title := Label.new()
    title.text = "EXIT GAME"
    title.add_theme_color_override("font_color", NT.C_ERROR)
    title.add_theme_font_size_override("font_size", NT.size("title"))
    if NT.font() != null:
        title.add_theme_font_override("font", NT.font())
    col.add_child(title)

    var body := Label.new()
    body.text = "Return to the main menu? Any progress since your last save will be lost."
    body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    body.add_theme_color_override("font_color", NT.C_BODY)
    col.add_child(body)

    var btns := HBoxContainer.new()
    btns.add_theme_constant_override("separation", 10)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    btns.add_child(spacer)
    var cancel := NebulaUi.button("Cancel", "ghost")
    cancel.pressed.connect(_hide_confirm)
    btns.add_child(cancel)
    var exit_btn := Button.new()
    exit_btn.text = "Exit"
    exit_btn.self_modulate = NT.C_ERROR
    exit_btn.pressed.connect(_confirm_exit)
    btns.add_child(exit_btn)
    col.add_child(btns)


func _show_confirm() -> void:
    if _confirm != null:
        _confirm.theme = NT.theme()
        _confirm.visible = true


func _hide_confirm() -> void:
    if _confirm != null:
        _confirm.visible = false

extends Control

const UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")
const AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
const UiHostActions = preload("res://Space/scripts/ui/ui_host_actions.gd")



var _selected: int = -1
var _skip_close_frame: bool = true
var _save_flash: float = 0.0
var _save_flash_color: Color = Color.WHITE

signal resumed
signal load_requested
signal quit_to_menu

var _authored_screen: Control = null
var _authored_pack_id: String = ""

func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    process_mode = PROCESS_MODE_ALWAYS
    _authored_screen = Control.new()
    _authored_screen.set_script(AuthoredScreenRuntime)
    _authored_screen.visible = false
    add_child(_authored_screen)
    _authored_screen.action_requested.connect(_on_authored_action)

func open_menu():
    visible = true
    _skip_close_frame = true
    _selected = -1
    _save_flash = 0.0
    _refresh_authored_screen()

func _process(delta):
    if not visible:
        return
    if _skip_close_frame:
        _skip_close_frame = false
        return
    if _save_flash > 0:
        _save_flash -= delta * 2.0
    queue_redraw()

func _input(event):
    if not visible or not is_inside_tree():
        return
    if _has_authored_screen():
        if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
            _do_resume()
            get_viewport().set_input_as_handled()
            return
        if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B:
            _do_resume()
            get_viewport().set_input_as_handled()
            return
        if event is InputEventMouseMotion or event is InputEventMouseButton:
            return
    if event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            _do_resume()
            get_viewport().set_input_as_handled()
            return
    if event is InputEventJoypadButton and event.pressed:
        if event.button_index == JOY_BUTTON_DPAD_UP:
            if _selected == -1:
                _selected = 0
            else:
                _selected = (_selected - 1 + 4) % 4
            get_viewport().set_input_as_handled()
            return
        elif event.button_index == JOY_BUTTON_DPAD_DOWN:
            if _selected == -1:
                _selected = 0
            else:
                _selected = (_selected + 1) % 4
            get_viewport().set_input_as_handled()
            return
        elif event.button_index == JOY_BUTTON_A:
            if _selected == -1:
                _selected = 0
            else:
                _activate_selected()
            get_viewport().set_input_as_handled()
            return
        elif event.button_index == JOY_BUTTON_B:
            _do_resume()
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseMotion:
        _update_hover(event.position)
        if is_inside_tree(): get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            _handle_click(event.position)
        if is_inside_tree(): get_viewport().set_input_as_handled()

func _update_hover(pos: Vector2):
    _selected = -1
    var buttons = _get_button_rects()
    for i in buttons.size():
        if buttons[i].has_point(pos):
            _selected = i

func _handle_click(pos: Vector2):
    var buttons = _get_button_rects()
    for i in buttons.size():
        if buttons[i].has_point(pos):
            match i:
                0: _do_resume()
                1: _do_save()
                2: _do_load()
                3: _do_quit_to_menu()

func _activate_selected():
    match _selected:
        0: _do_resume()
        1: _do_save()
        2: _do_load()
        3: _do_quit_to_menu()

func _do_resume():
    visible = false
    resumed.emit()

func _do_save():
    if GameManager.save_game(GameManager.current_save_slot):
        _save_flash = 1.0
        _save_flash_color = Color(0.3, 0.85, 0.4)
    else:
        _save_flash = 1.0
        _save_flash_color = Color(0.9, 0.3, 0.2)

func _do_load():
    visible = false
    load_requested.emit()

func _do_quit_to_menu():
    visible = false
    quit_to_menu.emit()

func _get_button_rects() -> Array:
    var cx = size.x * 0.5
    var base_y = size.y * 0.38
    var btn_w = 220.0
    var btn_h = 40.0
    var gap = 10.0
    var rects: Array = []
    for i in 4:
        var bx = cx - btn_w * 0.5
        var by = base_y + float(i) * (btn_h + gap)
        rects.append(Rect2(bx, by, btn_w, btn_h))
    return rects

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")

func _draw():
    if not visible:
        return
    if _has_authored_screen():
        UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.75)
        return
    var font = ThemeDB.fallback_font

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.85)

    var pw = 300.0
    var ph = 340.0
    var px = (size.x - pw) * 0.5
    var py = (size.y - ph) * 0.5 - 20
    var panel = Rect2(px, py, pw, ph)
    UIPanels.draw_panel(self, panel, Color(0.6, 0.78, 1.0, 1.0))

    draw_string(font, Vector2(size.x * 0.5 - 30, py + 30), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.78, 0.88, 1.0))
    draw_line(Vector2(px + 20, py + 40), Vector2(px + pw - 20, py + 40), Color(0.25, 0.35, 0.5, 0.6), 1.0)

    var labels = ["RESUME", "SAVE GAME", "LOAD GAME", "QUIT TO MENU"]
    var buttons = _get_button_rects()

    for i in buttons.size():
        var rect = buttons[i]
        var label = labels[i]
        var is_hovered = _selected == i
        var tint = Color(0.55, 0.78, 1.0, 1.0)
        UIPanels.draw_button_bg(self, rect, is_hovered, tint)
        if is_hovered:
            draw_string(font, Vector2(rect.position.x + rect.size.x * 0.5 - label.length() * 4.5, rect.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.96, 1.0))
            draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 26), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.5, 0.78, 1.0))
        else:
            draw_string(font, Vector2(rect.position.x + rect.size.x * 0.5 - label.length() * 4.5, rect.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.78, 0.88))


    if _save_flash > 0:
        var flash_text = "Saved to Slot %d!" % GameManager.current_save_slot if _save_flash_color.g > 0.5 else "Save Failed!"
        draw_string(font, Vector2(size.x * 0.5 - 45, buttons[1].position.y + buttons[1].size.y + 18), flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(_save_flash_color, _save_flash))


    var hint_text = "[B] Resume  [A] Select" if GameManager.using_controller else "[ESC] Resume"
    var hint_offset = 75.0 if GameManager.using_controller else 55.0
    draw_string(font, Vector2(size.x * 0.5 - hint_offset, py + ph - 10), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.33, 0.4, 0.6))


func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    return ""


func _has_authored_screen() -> bool:
    return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
    if _authored_screen == null:
        return
    var pack_id := _current_pack_id()
    if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "pause"):
        _authored_pack_id = ""
        _authored_screen.call("clear_screen")
        return
    if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
        _authored_pack_id = pack_id
        var data: Dictionary = UIIo.load_screen(pack_id, "pause")
        _authored_screen.call("load_screen", "pause", data, HudDataSource.new(null, GameManager))
    _authored_screen.visible = true


func _on_authored_action(action_id: String, action_args: String, _element_id: String) -> void:
    _emit_ui_button_event(action_id, action_args, _element_id)
    match action_id:
        "resume", "close_screen":
            _do_resume()
        "open_screen":
            if _open_special_screen(action_args):
                return
            if not action_args.is_empty() and UIIo.screen_exists(_current_pack_id(), action_args):
                _authored_pack_id = _current_pack_id()
                var data: Dictionary = UIIo.load_screen(_authored_pack_id, action_args)
                _authored_screen.call("load_screen", action_args, data, HudDataSource.new(null, GameManager))
            else:
                push_warning("pause_menu: open_screen target '%s' was not found" % action_args)
        "fire_event":
            UiHostActions.fire_authored_event("pause", "pause_menu", action_args, _element_id)
        "save_game":
            _do_save()
        "load_game":
            _do_load()
        "quit_to_menu":
            _do_quit_to_menu()
        "play_sfx":
            UiHostActions.play_authored_sfx(action_args)
        _:
            UiHostActions.warn_unhandled_action("pause_menu", action_id, action_args)


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
    UiHostActions.emit_ui_button_event("pause", "pause_menu", action_id, action_args, element_id)


func _open_special_screen(target: String) -> bool:
    return UiHostActions.open_cinematic(_current_pack_id(), "pause_menu", target)

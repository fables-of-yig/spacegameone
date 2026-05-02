extends Control

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UIIo = preload("res://Space/scripts/editor/ui/ui_io.gd")
const AuthoredScreenRuntime = preload("res://Space/scripts/ui/authored_screen_runtime.gd")
const HudDataSource = preload("res://Space/scripts/ui/hud_data_source.gd")
const SettingsMenuScript = preload("res://Space/scripts/ui/settings_menu.gd")


var _stars: Array = []
var _time: float = 0.0
var _selected: int = -1
var _slot_info: Array = []
var _fade_in: float = 0.0


var _galaxy_size: int = 120
const GALAXY_SIZES = [10, 20, 40, 80, 120, 200]
const GALAXY_LABELS = ["Tiny (10)", "Small (20)", "Medium (40)", "Large (80)", "Huge (120)", "Epic (200)"]
var _size_index: int = 4
@warning_ignore("unused_private_class_variable")
var _slider_rect: Rect2 = Rect2()
var _slider_minus_rect: Rect2 = Rect2()
var _slider_plus_rect: Rect2 = Rect2()


var _update_state: int = 0
var _update_message: String = ""
@warning_ignore("unused_private_class_variable")
var _update_flash: float = 0.0


var _delete_confirm_slot: int = -1
var _delete_rects: Array = []


var _authored_screen: Control = null
var _authored_pack_id: String = ""
var _settings_menu: Control = null

@warning_ignore("unused_signal")
signal new_game_pressed(galaxy_size: int)
signal load_slot_pressed(slot: int)
signal creative_pressed
signal test_fly_pressed
signal test_planet_pressed
signal play_pack_pressed(pack_id: String)
# editor_chosen(kind, pack_id) fires after the user has picked a campaign
# AND a sub-editor. kind is "ship" | "realm" | "entity" | "behavior" |
# "theme" | "audio" | "player" | "trigger" | "dialogue" | "shop" | "quest".
# pack_id is always the active campaign pack; "ship" now opens the pack
# authoring hub rather than editing global SSB state.
signal editor_chosen(kind: String, pack_id: String)

# Editor modal is a two-step wizard: campaign picker → sub-editor chooser.
enum EditorModal { CLOSED, CAMPAIGN_PICKER, SUBEDITOR }
var _editor_modal: int = EditorModal.CLOSED
var _campaign_picker_mode: String = "editor"  # "editor" | "play"

# Cached on-open, rebuilt after "+ NEW CAMPAIGN". Each entry is
# {id, display_name, modified_at, has_shipped, source} from MvPackLoader.list_all_packs().
# source is "user" (user-only new pack), "override" (user layer masks a
# shipped pack of the same id), or "shipped" (shipped-only — click to clone
# into the user layer before editing).
var _campaign_list: Array = []
# Pack the user just clicked in the campaign picker — carried forward into
# the sub-editor chooser step and emitted with editor_chosen.
var _selected_pack_id: String = ""

# Rects rebuilt every _draw so _handle_click can hit-test them. Picker rects
# are parallel to _campaign_list; the "+ NEW" and cancel rects are singletons.
var _picker_pack_rects: Array = []
var _picker_rename_rects: Array = []  # per-row rename button rects
var _picker_delete_rects: Array = []  # per-row delete button rects
var _picker_new_rect: Rect2 = Rect2()
var _picker_cancel_rect: Rect2 = Rect2()

# Campaign naming/rename inline input
var _campaign_name_input: LineEdit = null
var _campaign_naming_mode: String = ""  # "" | "create" | "rename"
var _campaign_rename_idx: int = -1
var _campaign_delete_confirm_idx: int = -1  # >=0 means showing confirm
var _sub_ship_rect: Rect2 = Rect2()
var _sub_realm_rect: Rect2 = Rect2()
var _sub_entity_rect: Rect2 = Rect2()
var _sub_behavior_rect: Rect2 = Rect2()
var _sub_theme_rect: Rect2 = Rect2()
var _sub_audio_rect: Rect2 = Rect2()
var _sub_player_rect: Rect2 = Rect2()
var _sub_trigger_rect: Rect2 = Rect2()
var _sub_dialogue_rect: Rect2 = Rect2()
var _sub_shop_rect: Rect2 = Rect2()
var _sub_quest_rect: Rect2 = Rect2()
var _sub_back_rect: Rect2 = Rect2()



func _ready():
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    process_mode = PROCESS_MODE_ALWAYS
    _authored_screen = Control.new()
    _authored_screen.set_script(AuthoredScreenRuntime)
    _authored_screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    _authored_screen.visible = false
    add_child(_authored_screen)
    _authored_screen.action_requested.connect(_on_authored_action)

    _settings_menu = Control.new()
    _settings_menu.set_script(SettingsMenuScript)
    _settings_menu.visible = false
    add_child(_settings_menu)

    _campaign_name_input = LineEdit.new()
    _campaign_name_input.placeholder_text = "Campaign name..."
    _campaign_name_input.visible = false
    _campaign_name_input.text_submitted.connect(_on_campaign_name_submitted)
    add_child(_campaign_name_input)

    _refresh_slots()

    var rng = RandomNumberGenerator.new()
    rng.seed = 42
    for i in 300:
        _stars.append({
            "pos": Vector2(rng.randf_range(0, 1920), rng.randf_range(0, 1080)), 
            "brightness": rng.randf_range(0.2, 1.0), 
            "size": rng.randf_range(0.5, 2.0), 
            "twinkle_speed": rng.randf_range(1.0, 4.0), 
            "twinkle_offset": rng.randf() * TAU, 
        })

func _refresh_slots():
    _slot_info.clear()
    for i in range(1, GameManager.MAX_SAVE_SLOTS + 1):
        _slot_info.append(GameManager.get_save_info(i))

func _process(delta):
    if not visible:
        return
    _layout_runtime_controls()
    _time += delta
    _fade_in = minf(_fade_in + delta * 0.8, 1.0)
    _refresh_authored_screen()
    queue_redraw()


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_runtime_controls()


func _layout_runtime_controls() -> void:
    set_anchors_and_offsets_preset(PRESET_FULL_RECT)
    if _authored_screen != null:
        _authored_screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func _input(event):
    if not visible:
        return
    if _settings_menu != null and _settings_menu.visible:
        return
    # Editor modal eats keyboard: ESC steps back (or closes); all other
    # keys are ignored so hitting N/C/F in the modal doesn't accidentally
    # start a new game.
    if _editor_modal != EditorModal.CLOSED and event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            if _editor_modal == EditorModal.SUBEDITOR:
                _editor_modal = EditorModal.CAMPAIGN_PICKER
                queue_redraw()
            else:
                _close_editor_chooser()
        return
    var authored_active := _has_authored_screen() and _editor_modal == EditorModal.CLOSED
    if event is InputEventMouseMotion:
        if authored_active:
            return
        _update_hover(event.position)
        if _editor_modal != EditorModal.CLOSED:
            queue_redraw()
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if authored_active:
            return
        _handle_click(event.position)
        # _handle_click may swap us to a sub-editor (env/entity/etc) that
        # installs a full-rect canvas in the same frame. Without consuming
        # the event, the press bubbles to the GUI pass and lands on the
        # new canvas's _gui_input as a paint click.
        get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed:
        if event.keycode == KEY_E:
            _open_editor_chooser()
        elif event.keycode == KEY_U:
            _start_update()
        elif event.keycode == KEY_P or event.keycode == KEY_ENTER:
            _open_play_pack_picker()
        elif event.keycode == KEY_S:
            _open_settings_menu()
        elif event.keycode == KEY_Q or event.keycode == KEY_ESCAPE:
            get_tree().quit()

    elif event is InputEventJoypadButton and event.pressed:
        if authored_active:
            return
        var buttons = _get_button_rects()
        var btn_count = buttons.size()
        if _selected < 0:
            _selected = 0
        if event.button_index == JOY_BUTTON_DPAD_UP:
            _selected = (_selected - 1) if _selected > 0 else btn_count - 1
        elif event.button_index == JOY_BUTTON_DPAD_DOWN:
            _selected = (_selected + 1) % btn_count
        elif event.button_index == JOY_BUTTON_A:
            if _selected >= 0:
                _handle_click_by_index(_selected)
        elif event.button_index == JOY_BUTTON_B:
            if _editor_modal != EditorModal.CLOSED:
                _close_editor_chooser()

func _update_hover(pos: Vector2):
    _selected = -1
    var buttons = _get_button_rects()
    for i in buttons.size():
        if buttons[i].has_point(pos):
            _selected = i

func _handle_click(pos: Vector2):

    # Editor modal eats clicks first. Each state has its own hit-test set.
    if _editor_modal == EditorModal.CAMPAIGN_PICKER:
        # If name input is active, ignore other clicks.
        if _campaign_name_input != null and _campaign_name_input.visible:
            return
        if _campaign_picker_mode == "play":
            for i in _picker_pack_rects.size():
                if _picker_pack_rects[i].has_point(pos):
                    var play_entry: Dictionary = _campaign_list[i]
                    _start_play_pack_menu(str(play_entry.get("id", "")))
                    return
            if _picker_cancel_rect.has_point(pos):
                _close_editor_chooser()
                return
            return
        # Delete confirmation: YES or NO
        if _campaign_delete_confirm_idx >= 0:
            # Check if clicking YES (delete) or anything else (cancel)
            # The confirm is drawn inline — for now, check rename rect area as YES
            if _campaign_delete_confirm_idx < _picker_delete_rects.size():
                if _picker_delete_rects[_campaign_delete_confirm_idx].has_point(pos):
                    var entry: Dictionary = _campaign_list[_campaign_delete_confirm_idx]
                    MvPackLoader.delete_pack(str(entry.get("id", "")))
                    _campaign_list = MvPackLoader.list_all_packs()
            _campaign_delete_confirm_idx = -1
            queue_redraw()
            return
        # Rename buttons
        for i in _picker_rename_rects.size():
            if _picker_rename_rects[i].has_point(pos):
                var ren_entry: Dictionary = _campaign_list[i]
                if str(ren_entry.get("source", "user")) == "shipped":
                    _clone_and_select(str(ren_entry.get("id", "")))
                    return
                _campaign_naming_mode = "rename"
                _campaign_rename_idx = i
                _campaign_name_input.text = str(ren_entry.get("display_name", ""))
                _campaign_name_input.visible = true
                _campaign_name_input.grab_focus.call_deferred()
                _campaign_name_input.select_all.call_deferred()
                queue_redraw()
                return
        # Delete buttons
        for i in _picker_delete_rects.size():
            if _picker_delete_rects[i].has_point(pos):
                var del_entry: Dictionary = _campaign_list[i]
                if str(del_entry.get("source", "user")) == "shipped":
                    # Shipped-only packs can't be deleted from here.
                    return
                _campaign_delete_confirm_idx = i
                queue_redraw()
                return
        for i in _picker_pack_rects.size():
            if _picker_pack_rects[i].has_point(pos):
                var row_entry: Dictionary = _campaign_list[i]
                var pid := str(row_entry.get("id", ""))
                if str(row_entry.get("source", "user")) == "shipped":
                    _clone_and_select(pid)
                    return
                _selected_pack_id = pid
                if _campaign_picker_mode == "editor":
                    _choose_subeditor("ship")
                else:
                    _editor_modal = EditorModal.SUBEDITOR
                    queue_redraw()
                return
        if _picker_new_rect.has_point(pos):
            _create_new_campaign()
            return
        if _picker_cancel_rect.has_point(pos):
            _close_editor_chooser()
            return
        # Click outside interactive rects is a no-op — don't close accidentally.
        return

    if _editor_modal == EditorModal.SUBEDITOR:
        if _sub_ship_rect.has_point(pos):
            _choose_subeditor("ship")
            return
        if _sub_realm_rect.has_point(pos):
            _choose_subeditor("realm")
            return
        if _sub_entity_rect.has_point(pos):
            _choose_subeditor("entity")
            return
        if _sub_behavior_rect.has_point(pos):
            _choose_subeditor("behavior")
            return
        if _sub_theme_rect.has_point(pos):
            _choose_subeditor("theme")
            return
        if _sub_audio_rect.has_point(pos):
            _choose_subeditor("audio")
            return
        if _sub_player_rect.has_point(pos):
            _choose_subeditor("player")
            return
        if _sub_trigger_rect.has_point(pos):
            _choose_subeditor("trigger")
            return
        if _sub_dialogue_rect.has_point(pos):
            _choose_subeditor("dialogue")
            return
        if _sub_shop_rect.has_point(pos):
            _choose_subeditor("shop")
            return
        if _sub_quest_rect.has_point(pos):
            _choose_subeditor("quest")
            return
        if _sub_back_rect.has_point(pos):
            _editor_modal = EditorModal.CAMPAIGN_PICKER
            queue_redraw()
            return
        # Click outside buttons is a no-op — don't close accidentally.
        return

    for i in _delete_rects.size():
        if _delete_rects[i].has_point(pos) and not _slot_info[i].is_empty():
            _handle_delete_click(i + 1)
            return

    if _delete_confirm_slot >= 0:
        _delete_confirm_slot = -1
        return

    if _slider_minus_rect.has_point(pos):
        _size_index = maxi(_size_index - 1, 0)
        _galaxy_size = GALAXY_SIZES[_size_index]
        return
    if _slider_plus_rect.has_point(pos):
        _size_index = mini(_size_index + 1, GALAXY_SIZES.size() - 1)
        _galaxy_size = GALAXY_SIZES[_size_index]
        return
    var buttons = _get_button_rects()
    for i in buttons.size():
        if buttons[i].has_point(pos):
            _handle_click_by_index(i)
            return

func _handle_click_by_index(idx: int):
    if idx == 0:
        _open_editor_chooser()
    elif idx == 1:
        _start_update()
    elif idx == 2:
        _open_play_pack_picker()
    elif idx == 3:
        _open_settings_menu()
    elif idx == 4:
        get_tree().quit()

func _start_test_planet():
    visible = false
    test_planet_pressed.emit()

func _open_editor_chooser():
    _campaign_picker_mode = "editor"
    _editor_modal = EditorModal.CAMPAIGN_PICKER
    _campaign_list = MvPackLoader.list_all_packs()
    _selected_pack_id = ""
    queue_redraw()

func _open_play_pack_picker():
    _campaign_picker_mode = "play"
    _editor_modal = EditorModal.CAMPAIGN_PICKER
    _campaign_list = MvPackLoader.list_all_packs()
    _selected_pack_id = ""
    queue_redraw()

func _close_editor_chooser():
    _editor_modal = EditorModal.CLOSED
    _selected_pack_id = ""
    _campaign_picker_mode = "editor"
    queue_redraw()


func _start_play_pack_menu(pack_id: String) -> void:
    var pid: String = pack_id.strip_edges()
    if pid.is_empty():
        return
    UIIo.ensure_stock_screens(pid)
    MvPackLoader.reset_last_loaded_pack_id()
    var pack := MvPackLoader.load_pack(pid)
    if pack == null:
        push_warning("main_menu: failed to load pack '%s'" % pid)
        return
    if not UIIo.screen_exists(pid, "main_menu"):
        push_warning("main_menu: pack '%s' has no authored main_menu screen" % pid)
        return
    var data: Dictionary = UIIo.load_screen(pid, "main_menu")
    if data.is_empty():
        push_warning("main_menu: authored main_menu for pack '%s' was empty" % pid)
        return
    UIPanels.load_pack_theme(pid)
    _authored_pack_id = pid
    if _authored_screen != null:
        _authored_screen.call("load_screen", "main_menu", data, HudDataSource.new(null, GameManager))
        _authored_screen.visible = true
    _editor_modal = EditorModal.CLOSED
    _campaign_picker_mode = "editor"
    _selected_pack_id = ""
    queue_redraw()


# Shipped-only packs can't be edited in place — any edit-intent click
# (row select, rename) first copies the shipped baseline into
# user://Packs/<pack_id>/ and then proceeds as if the user pack already
# existed. Downstream editors write to user://; shipped stays untouched.
func _clone_and_select(pack_id: String) -> void:
    if pack_id.is_empty():
        return
    if not MvPackLoader.clone_shipped_pack(pack_id):
        return
    _campaign_list = MvPackLoader.list_all_packs()
    _selected_pack_id = pack_id
    if _campaign_picker_mode == "editor":
        _choose_subeditor("ship")
        return
    _editor_modal = EditorModal.SUBEDITOR
    queue_redraw()

func _create_new_campaign():
    _campaign_naming_mode = "create"
    _campaign_name_input.text = ""
    _campaign_name_input.visible = true
    _campaign_name_input.grab_focus.call_deferred()
    queue_redraw()


func _on_campaign_name_submitted(text: String) -> void:
    var display_name := text.strip_edges()
    _campaign_name_input.visible = false
    if display_name.is_empty():
        _campaign_naming_mode = ""
        return
    if _campaign_naming_mode == "create":
        # Generate a safe id from the name (lowercase, underscores).
        var safe_id := display_name.to_lower().replace(" ", "_")
        for ch in "!@#$%^&*(){}[]|\\:;\"'<>,./?\t\n":
            safe_id = safe_id.replace(ch, "")
        if safe_id.is_empty():
            safe_id = MvPackLoader.next_new_campaign_id()
        # Ensure unique
        var base := safe_id
        var n := 1
        while DirAccess.dir_exists_absolute("user://Packs/%s" % safe_id):
            safe_id = "%s_%d" % [base, n]
            n += 1
        if not MvPackLoader.create_empty_pack(safe_id, display_name):
            _campaign_naming_mode = ""
            return
        _selected_pack_id = safe_id
        _campaign_list = MvPackLoader.list_all_packs()
        _choose_subeditor("ship")
        _campaign_naming_mode = ""
        _campaign_rename_idx = -1
        queue_redraw()
        return
    elif _campaign_naming_mode == "rename" and _campaign_rename_idx >= 0 and _campaign_rename_idx < _campaign_list.size():
        var entry: Dictionary = _campaign_list[_campaign_rename_idx]
        var pid := str(entry.get("id", ""))
        MvPackLoader.rename_pack(pid, display_name)
        _campaign_list = MvPackLoader.list_all_packs()
    _campaign_naming_mode = ""
    _campaign_rename_idx = -1
    queue_redraw()

func _choose_subeditor(kind: String):
    var pid := _selected_pack_id
    _editor_modal = EditorModal.CLOSED
    _selected_pack_id = ""
    visible = false
    editor_chosen.emit(kind, pid)


# Called by main.gd when a sub-editor closes, to return the user to the
# editor picker modal instead of dropping all the way back to main menu.
func reopen_editor_picker() -> void:
    _campaign_picker_mode = "editor"
    _selected_pack_id = ""
    _editor_modal = EditorModal.CAMPAIGN_PICKER
    _campaign_list = MvPackLoader.list_all_packs()
    visible = true
    queue_redraw()

func _start_creative():
    visible = false
    creative_pressed.emit()

func _start_new_game():
    visible = false
    new_game_pressed.emit(120)


func _return_to_launcher() -> void:
    _authored_pack_id = ""
    _editor_modal = EditorModal.CLOSED
    _campaign_picker_mode = "editor"
    _selected_pack_id = ""
    if PlanetaryInterface.has_method("reset_runtime_state"):
        PlanetaryInterface.reset_runtime_state(true, true)
    MvPackLoader.clear_runtime_state()
    MvGame.main = null
    MvGame.room_manager = null
    MvGame.simulation_paused = false
    UIPanels.load_pack_theme("demo")
    if _authored_screen != null:
        _authored_screen.call("clear_screen")
        _authored_screen.visible = false
    visible = true
    queue_redraw()

func _load_slot(slot: int):
    GameManager.current_save_slot = slot
    visible = false
    load_slot_pressed.emit(slot)

func _handle_delete_click(slot: int):
    if _delete_confirm_slot == slot:

        GameManager.delete_save(slot)
        _delete_confirm_slot = -1
        _refresh_slots()
    else:

        _delete_confirm_slot = slot

func _get_button_rects() -> Array:
    var cx = size.x * 0.5
    var base_y = size.y * 0.46
    var btn_w = 320.0
    var btn_h = 42.0
    var gap = 12.0
    var rects: Array = []

    rects.append(Rect2(cx - btn_w * 0.5, base_y, btn_w, btn_h))
    rects.append(Rect2(cx - btn_w * 0.5, base_y + btn_h + gap, btn_w, btn_h))
    rects.append(Rect2(cx - btn_w * 0.5, base_y + (btn_h + gap) * 2, btn_w, btn_h))
    rects.append(Rect2(cx - btn_w * 0.5, base_y + (btn_h + gap) * 3, btn_w, btn_h))
    rects.append(Rect2(cx - btn_w * 0.5, base_y + (btn_h + gap) * 4, btn_w, btn_h))
    return rects

func _draw():
    if not visible:
        return
    var font = ThemeDB.fallback_font
    var alpha = _fade_in


    draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.015, 0.04))


    var neb_cx = size.x * 0.6
    var neb_cy = size.y * 0.4
    for i in 5:
        var r = 250.0 - float(i) * 30.0
        var na = 0.015 + float(i) * 0.005
        draw_circle(Vector2(neb_cx, neb_cy), r, Color(0.15, 0.1, 0.3, na * alpha))
    for i in 4:
        var r = 180.0 - float(i) * 25.0
        var na = 0.01 + float(i) * 0.004
        draw_circle(Vector2(size.x * 0.3, size.y * 0.7), r, Color(0.1, 0.15, 0.25, na * alpha))


    for s in _stars:
        var twinkle = sin(_time * s.twinkle_speed + s.twinkle_offset) * 0.3 + 0.7
        var b = s.brightness * twinkle * alpha
        var col = Color(0.8, 0.85, 1.0, b)
        draw_circle(s.pos, s.size, col)
        if s.size > 1.5:
            draw_circle(s.pos, s.size * 2.0, Color(col, b * 0.1))

    if _has_authored_screen() and _editor_modal == EditorModal.CLOSED:
        return


    var buttons = _get_button_rects()
    _draw_button_editor(font, buttons[0], "EDITOR", 0, alpha)

    var update_label = "UPDATE  (v%s)" % Updater.get_display_version()
    if _update_state == 1:
        update_label = "CHECKING..."
    elif _update_state == 2:
        update_label = "DOWNLOADING... %.0f%%" % Updater.download_percent
    elif _update_state == 3:
        update_label = "UPDATED — RESTART TO APPLY"
    elif _update_state == 4:
        update_label = "ALREADY UP TO DATE"
    elif _update_state == 5:
        update_label = "UPDATE FAILED"
    _draw_button_update(font, buttons[1], update_label, 1, alpha)
    _draw_button_test_planet(font, buttons[2], "PLAY PACK", 2, alpha)
    _draw_button(font, buttons[3], "SETTINGS", 3, alpha, false)
    if _editor_modal == EditorModal.CLOSED:
        _draw_button(font, buttons[4], "QUIT", 4, alpha, false)


    if _editor_modal == EditorModal.CLOSED:
        draw_string(font, Vector2(size.x * 0.5 - 40, size.y - 30), "v0.1", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.25, 0.28, 0.35, alpha * 0.6))
        if GameManager.using_controller:
            draw_string(font, Vector2(size.x * 0.5 - 160, size.y - 14), "D-Pad Navigate   A Select   B Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.33, 0.4, alpha * 0.5))
        else:
            draw_string(font, Vector2(size.x * 0.5 - 230, size.y - 14), "[E] Editor  [U] Update  [P/Enter] Play Pack  [S] Settings  [Q] Quit", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.33, 0.4, alpha * 0.5))

    # Editor modal renders on top of everything else.
    if _editor_modal == EditorModal.CAMPAIGN_PICKER:
        _draw_campaign_picker(font, alpha)
    elif _editor_modal == EditorModal.SUBEDITOR:
        _draw_subeditor_chooser(font, alpha)

func _draw_button_creative(font: Font, rect: Rect2, label: String, idx: int, alpha: float):
    var is_hovered = _selected == idx
    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24
    var tint = Color(0.55, 0.95, 0.65, alpha)
    UIPanels.draw_button_bg(self, rect, is_hovered, tint)
    if is_hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(0.2, 0.7, 0.4, (0.4 - float(gi) * 0.12) * alpha), false, gw)
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 1.0, 0.9, alpha))
        draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.4, 0.95, 0.55, alpha))
    else:
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.85, 0.65, alpha))

func _draw_button(font: Font, rect: Rect2, label: String, idx: int, alpha: float, is_disabled: bool):
    var is_hovered = _selected == idx

    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24

    if is_disabled:
        UIPanels.draw_button_bg(self, rect, false, Color(0.35, 0.4, 0.5, 0.4 * alpha))
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.32, 0.35, 0.42, 0.55 * alpha))
        return
    var tint = Color(0.6, 0.78, 1.0, alpha)
    UIPanels.draw_button_bg(self, rect, is_hovered, tint)
    if is_hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(0.3, 0.5, 0.8, (0.4 - float(gi) * 0.12) * alpha), false, gw)
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.96, 1.0, alpha))
        draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.78, 1.0, alpha))
    else:
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.78, 0.88, alpha))

func _draw_button_test_fly(font: Font, rect: Rect2, label: String, idx: int, alpha: float):
    var is_hovered = _selected == idx
    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24
    var tint = Color(1.0, 0.55, 0.25, alpha)
    UIPanels.draw_button_bg(self, rect, is_hovered, tint)
    if is_hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(0.9, 0.35, 0.15, (0.4 - float(gi) * 0.12) * alpha), false, gw)
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.5, alpha))
        draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.65, 0.25, alpha))
    else:
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.55, 0.3, alpha))



func _start_test_fly():
    visible = false
    test_fly_pressed.emit()



func _draw_button_update(font: Font, rect: Rect2, label: String, idx: int, alpha: float):
    var is_hovered = _selected == idx
    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24

    var is_busy = _update_state == 1 or _update_state == 2
    if is_busy:
        var pulse = sin(_time * 4.0) * 0.15 + 0.85
        UIPanels.draw_button_bg(self, rect, false, Color(0.45, 0.85, 0.95, alpha * pulse))
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.9, 0.97, alpha * pulse))
        if _update_state == 2 and Updater.download_percent > 0:
            var bar_y = rect.position.y + rect.size.y - 4
            var bar_w = rect.size.x - 8
            draw_rect(Rect2(rect.position.x + 4, bar_y, bar_w, 3), Color(0.1, 0.15, 0.2, alpha))
            draw_rect(Rect2(rect.position.x + 4, bar_y, bar_w * Updater.download_percent / 100.0, 3), Color(0.3, 0.8, 0.9, alpha))
    elif _update_state == 3:
        UIPanels.draw_button_bg(self, rect, false, Color(0.45, 1.0, 0.55, alpha))
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 1.0, 0.65, alpha))
    elif _update_state == 4:
        UIPanels.draw_button_bg(self, rect, false, Color(0.4, 0.5, 0.6, 0.7 * alpha))
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.65, 0.7, alpha * 0.85))
    elif _update_state == 5:
        UIPanels.draw_button_bg(self, rect, false, Color(0.95, 0.35, 0.3, alpha))
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.95, 0.5, 0.45, alpha))
    else:
        var tint = Color(0.45, 0.85, 0.95, alpha)
        UIPanels.draw_button_bg(self, rect, is_hovered, tint)
        if is_hovered:
            for gi in 3:
                var gw = 1.0 + float(gi) * 0.5
                draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                    Color(0.2, 0.7, 0.8, (0.4 - float(gi) * 0.12) * alpha), false, gw)
            draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.97, 1.0, alpha))
            draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.92, 0.97, alpha))
        else:
            draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.5, 0.78, 0.85, alpha))

    if _update_message != "":
        var msg_col = Color(0.5, 0.8, 0.5, alpha * 0.7) if _update_state == 3 else Color(0.7, 0.4, 0.35, alpha * 0.7) if _update_state == 5 else Color(0.5, 0.6, 0.65, alpha * 0.6)
        draw_string(font, Vector2(rect.position.x + 8, rect.position.y + rect.size.y + 12), _update_message, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x), 9, msg_col)

func _draw_button_test_planet(font: Font, rect: Rect2, label: String, idx: int, alpha: float):
    var is_hovered = _selected == idx
    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24
    var tint = Color(0.95, 0.55, 1.0, alpha)
    UIPanels.draw_button_bg(self, rect, is_hovered, tint)
    if is_hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(0.85, 0.3, 0.9, (0.4 - float(gi) * 0.12) * alpha), false, gw)
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.82, 1.0, alpha))
        draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.6, 1.0, alpha))
    else:
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.55, 0.95, alpha))

func _draw_button_editor(font: Font, rect: Rect2, label: String, idx: int, alpha: float):
    var is_hovered = _selected == idx
    var text_w = label.length() * 5.5
    var text_x = rect.position.x + (rect.size.x - text_w) * 0.5
    var text_y = rect.position.y + 24
    var tint = Color(0.55, 0.95, 1.0, alpha)
    UIPanels.draw_button_bg(self, rect, is_hovered, tint)
    if is_hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(0.3, 0.85, 0.95, (0.4 - float(gi) * 0.12) * alpha), false, gw)
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.97, 1.0, alpha))
        draw_string(font, Vector2(rect.position.x + 8, text_y), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.92, 1.0, alpha))
    else:
        draw_string(font, Vector2(text_x, text_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.8, 0.92, alpha))

# Campaign picker — step 1 of the editor modal wizard. Lists user packs
# and offers "+ NEW CAMPAIGN". Each row is hit-testable via _picker_pack_rects,
# which is rebuilt here every frame so _handle_click can find them.
func _draw_campaign_picker(font: Font, alpha: float):
    var panel_w: float = 700.0
    var visible_rows: int = mini(_campaign_list.size(), 8)
    var row_h: float = 62.0
    var header_h: float = 112.0
    var is_play_picker := _campaign_picker_mode == "play"
    var footer_h: float = 64.0 if is_play_picker else 152.0
    var panel_h: float = header_h + float(visible_rows) * row_h + footer_h
    var panel_x: float = (size.x - panel_w) * 0.5
    var panel_y: float = (size.y - panel_h) * 0.5
    var panel_rect = Rect2(panel_x, panel_y, panel_w, panel_h)

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.6 * alpha)
    UIPanels.draw_panel(self, panel_rect, Color(0.85, 0.95, 1.0, alpha), UIPanels.PanelVariant.ALT)

    var title = "PLAY PACK" if is_play_picker else "SELECT CAMPAIGN"
    var title_w = title.length() * 7.0
    draw_string(font, Vector2(panel_x + (panel_w - title_w) * 0.5, panel_y + 36),
        title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.9, 1.0, alpha))

    var sub = "Pick a pack to open its authored game menu." if is_play_picker else "Pick a campaign to edit, or create a new one.   USER = your pack  OVERRIDE = masks shipped  SHIPPED = click to clone into user layer"
    draw_string(font, Vector2(panel_x + 24, panel_y + 62),
        sub, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w - 48), 10, Color(0.55, 0.65, 0.75, alpha * 0.85))
    if not is_play_picker:
        draw_string(font, Vector2(panel_x + 24, panel_y + 84),
            "Click a campaign card to open it. Card actions live on the button strip underneath each row.",
            HORIZONTAL_ALIGNMENT_LEFT, int(panel_w - 48), 10, Color(0.62, 0.72, 0.82, alpha * 0.78))

    var mouse_pos = get_local_mouse_position()

    _picker_pack_rects.clear()
    _picker_rename_rects.clear()
    _picker_delete_rects.clear()
    var list_x: float = panel_x + 24.0
    var list_w: float = panel_w - 48.0
    var list_y: float = panel_y + header_h
    var action_btn_w: float = 74.0
    var action_btn_h: float = 20.0
    var action_gap: float = 6.0
    if _campaign_list.is_empty():
        draw_string(font, Vector2(list_x, list_y + 20),
            "(no playable packs found)" if is_play_picker else "(no campaigns yet — hit + NEW CAMPAIGN below)",
            HORIZONTAL_ALIGNMENT_LEFT, int(list_w), 11, Color(0.45, 0.5, 0.6, alpha * 0.7))
    else:
        for i in visible_rows:
            var entry: Dictionary = _campaign_list[i]
            var row_rect := Rect2(list_x, list_y + float(i) * row_h, list_w, row_h - 6.0)
            _picker_pack_rects.append(row_rect)
            var hovered := row_rect.has_point(mouse_pos)

            # Delete confirmation overlay
            if _campaign_delete_confirm_idx == i:
                draw_rect(Rect2(list_x, list_y + float(i) * row_h, list_w, row_h - 4.0),
                    Color(0.5, 0.15, 0.15, alpha * 0.9))
                draw_string(font, Vector2(list_x + 10, list_y + float(i) * row_h + 20),
                    "Delete \"%s\"? Click DELETE again to confirm." % str(entry.get("display_name", "")),
                    HORIZONTAL_ALIGNMENT_LEFT, int(list_w - 20), 11, Color(1, 0.7, 0.7, alpha))
            else:
                _draw_pack_row(font, row_rect, entry, hovered, alpha)

            if is_play_picker:
                continue

            var is_shipped_only := str(entry.get("source", "user")) == "shipped"

            # Rename button (for shipped-only packs, shows CLONE instead — clicking
            # still routes through _handle_click, which auto-clones on any interaction).
            var action_y: float = row_rect.position.y + row_rect.size.y - action_btn_h - 7.0
            var del_x: float = row_rect.position.x + row_rect.size.x - action_btn_w - 10.0
            var ren_x: float = del_x - action_gap - action_btn_w
            var ren_rect := Rect2(ren_x, action_y, action_btn_w, action_btn_h)
            _picker_rename_rects.append(ren_rect)
            var ren_hover := ren_rect.has_point(mouse_pos)
            var ren_tint: Color
            var ren_text_col: Color
            var ren_label: String
            if is_shipped_only:
                ren_tint = Color(0.4, 0.8, 0.55, alpha * 0.7)
                ren_text_col = Color(0.85, 1.0, 0.9, alpha) if ren_hover else Color(0.6, 0.85, 0.7, alpha)
                ren_label = "CLONE"
            else:
                ren_tint = Color(0.4, 0.55, 0.8, alpha * 0.7)
                ren_text_col = Color(0.85, 0.9, 1.0, alpha) if ren_hover else Color(0.6, 0.7, 0.8, alpha)
                ren_label = "REN"
            UIPanels.draw_button_bg(self, ren_rect, ren_hover, ren_tint)
            var ren_label_w: float = font.get_string_size(ren_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
            draw_string(font, Vector2(ren_rect.position.x + (ren_rect.size.x - ren_label_w) * 0.5, ren_rect.position.y + 14),
                ren_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ren_text_col)

            # Delete button — disabled (rendered dim, click ignored) for shipped-only.
            var del_rect := Rect2(del_x, action_y, action_btn_w, action_btn_h)
            _picker_delete_rects.append(del_rect)
            var del_hover := del_rect.has_point(mouse_pos) and not is_shipped_only
            var del_tint: Color
            var del_text_col: Color
            if is_shipped_only:
                del_tint = Color(0.25, 0.2, 0.22, alpha * 0.5)
                del_text_col = Color(0.45, 0.35, 0.36, alpha * 0.8)
            else:
                del_tint = Color(0.8, 0.3, 0.3, alpha * 0.7)
                del_text_col = Color(1, 0.8, 0.8, alpha) if del_hover else Color(0.7, 0.5, 0.5, alpha)
            UIPanels.draw_button_bg(self, del_rect, del_hover, del_tint)
            var del_label_w: float = font.get_string_size("DEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
            draw_string(font, Vector2(del_rect.position.x + (del_rect.size.x - del_label_w) * 0.5, del_rect.position.y + 14),
                "DEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, del_text_col)

    # Position the name input if it's visible
    if _campaign_name_input != null and _campaign_name_input.visible:
        var input_w: float = 300.0
        var input_x: float = panel_x + (panel_w - input_w) * 0.5
        var input_y: float = list_y + float(visible_rows) * row_h - 4.0
        _campaign_name_input.position = Vector2(input_x, input_y)
        _campaign_name_input.size = Vector2(input_w, 30)

    if is_play_picker:
        var cancel_w_play: float = 140.0
        var cancel_x_play: float = panel_x + (panel_w - cancel_w_play) * 0.5
        var cancel_y_play: float = list_y + float(visible_rows) * row_h + 16.0
        _picker_new_rect = Rect2()
        _picker_cancel_rect = Rect2(cancel_x_play, cancel_y_play, cancel_w_play, 32)
        var cancel_hover_play := _picker_cancel_rect.has_point(mouse_pos)
        var cancel_text_col_play := Color(0.95, 0.55, 0.5, alpha) if cancel_hover_play else Color(0.65, 0.42, 0.45, alpha)
        UIPanels.draw_button_bg(self, _picker_cancel_rect, cancel_hover_play, Color(0.85, 0.35, 0.32, alpha))
        var cancel_label_play = "CANCEL"
        var cancel_label_w_play = cancel_label_play.length() * 5.5
        draw_string(font, Vector2(cancel_x_play + (cancel_w_play - cancel_label_w_play) * 0.5, cancel_y_play + 21),
            cancel_label_play, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cancel_text_col_play)
        return

    var new_y: float = list_y + float(visible_rows) * row_h + 12.0
    _picker_new_rect = Rect2(list_x, new_y, list_w, 36.0)
    var new_hover := _picker_new_rect.has_point(mouse_pos)
    _draw_chooser_btn(font, _picker_new_rect, "+ NEW CAMPAIGN", new_hover, alpha,
        Color(0.55, 0.95, 0.65), Color(0.75, 1.0, 0.85))

    var cancel_w: float = 140.0
    var cancel_x: float = panel_x + (panel_w - cancel_w) * 0.5
    var cancel_y: float = new_y + 48.0
    _picker_cancel_rect = Rect2(cancel_x, cancel_y, cancel_w, 32)
    var cancel_hover := _picker_cancel_rect.has_point(mouse_pos)
    var cancel_text_col := Color(0.95, 0.55, 0.5, alpha) if cancel_hover else Color(0.65, 0.42, 0.45, alpha)
    UIPanels.draw_button_bg(self, _picker_cancel_rect, cancel_hover, Color(0.85, 0.35, 0.32, alpha))
    var cancel_label = "CANCEL"
    var cancel_label_w = cancel_label.length() * 5.5
    draw_string(font, Vector2(cancel_x + (cancel_w - cancel_label_w) * 0.5, cancel_y + 21),
        cancel_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cancel_text_col)


# Single row in the campaign picker list.
func _draw_pack_row(font: Font, rect: Rect2, entry: Dictionary, hovered: bool, alpha: float):
    var source := str(entry.get("source", "user"))
    var bg_tint: Color
    var outline_tint: Color
    if source == "shipped":
        bg_tint = Color(0.12, 0.15, 0.22, alpha * (0.8 if hovered else 0.45))
        outline_tint = Color(0.5, 0.5, 0.65, alpha * (0.7 if hovered else 0.3))
    elif source == "override":
        bg_tint = Color(0.2, 0.18, 0.12, alpha * (0.9 if hovered else 0.55))
        outline_tint = Color(0.85, 0.65, 0.3, alpha * (0.8 if hovered else 0.4))
    else:
        bg_tint = Color(0.15, 0.2, 0.3, alpha * (0.9 if hovered else 0.55))
        outline_tint = Color(0.4, 0.55, 0.7, alpha * (0.8 if hovered else 0.35))
    draw_rect(rect, bg_tint)
    draw_rect(rect, outline_tint, false, 1.0)

    var display_name := str(entry.get("display_name", "???"))
    var pack_id := str(entry.get("id", ""))
    var text_col := Color(0.85, 0.92, 1.0, alpha) if hovered else Color(0.65, 0.75, 0.85, alpha * 0.9)
    draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 20),
        display_name, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 190), 12, text_col)

    # Source badge on the right edge of the row.
    var badge_label := ""
    var badge_col := Color(1, 1, 1, alpha)
    if source == "override":
        badge_label = "OVERRIDE"
        badge_col = Color(1.0, 0.78, 0.4, alpha)
    elif source == "shipped":
        badge_label = "SHIPPED"
        badge_col = Color(0.55, 0.7, 0.95, alpha * 0.9)
    else:
        badge_label = "USER"
        badge_col = Color(0.55, 0.95, 0.7, alpha * 0.85)
    var badge_w: float = float(badge_label.length()) * 5.5 + 10.0
    var badge_x: float = rect.position.x + rect.size.x - badge_w - 6.0
    var badge_y: float = rect.position.y + 6.0
    var badge_rect := Rect2(badge_x, badge_y, badge_w, 18.0)
    draw_rect(badge_rect, Color(badge_col.r * 0.25, badge_col.g * 0.25, badge_col.b * 0.25, alpha * 0.75))
    draw_rect(badge_rect, badge_col, false, 1.0)
    draw_string(font, Vector2(badge_x + 5, badge_y + 14),
        badge_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, badge_col)

    draw_string(font, Vector2(rect.position.x + 10, rect.position.y + 38),
        pack_id, HORIZONTAL_ALIGNMENT_LEFT, int(rect.size.x - 20), 10, Color(0.45, 0.55, 0.65, alpha * 0.8))


# Sub-editor chooser — step 2 of the editor modal wizard. The CONTENT
# button opens the pack authoring hub; the others jump directly into the
# corresponding pack-aware editor.
func _draw_subeditor_chooser(font: Font, alpha: float):
    var panel_w: float = 1280.0
    var panel_h: float = 560.0
    var panel_x: float = (size.x - panel_w) * 0.5
    var panel_y: float = (size.y - panel_h) * 0.5
    var panel_rect = Rect2(panel_x, panel_y, panel_w, panel_h)

    UIPanels.draw_dim(self, Rect2(Vector2.ZERO, size), 0.6 * alpha)
    UIPanels.draw_panel(self, panel_rect, Color(0.85, 0.95, 1.0, alpha), UIPanels.PanelVariant.ALT)

    var title = "PICK AN EDITOR"
    var title_w = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
    draw_string(font, Vector2(panel_x + (panel_w - title_w) * 0.5, panel_y + 54),
        title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.85, 0.9, 1.0, alpha))

    var sub := "Campaign: %s" % _selected_pack_id
    draw_string(font, Vector2(panel_x + 36, panel_y + 92),
        sub, HORIZONTAL_ALIGNMENT_LEFT, int(panel_w - 72), 14, Color(0.55, 0.65, 0.75, alpha * 0.85))

    var mouse_pos = get_local_mouse_position()

    var btn_w: float = 180.0
    var btn_h: float = 140.0
    var btn_gap: float = 28.0
    var row_v_gap: float = 72.0
    # Row 1: 5 buttons, Row 2: 5 buttons — fits inside the 1280px panel.
    var row1_count: int = 5
    var row2_count: int = 6
    var row1_total_w: float = btn_w * row1_count + btn_gap * (row1_count - 1)
    var row2_total_w: float = btn_w * row2_count + btn_gap * (row2_count - 1)
    var row1_x: float = panel_x + (panel_w - row1_total_w) * 0.5
    var row2_x: float = panel_x + (panel_w - row2_total_w) * 0.5
    var row1_y: float = panel_y + 128.0
    var row2_y: float = row1_y + btn_h + row_v_gap

    _sub_ship_rect = Rect2(row1_x, row1_y, btn_w, btn_h)
    _sub_realm_rect = Rect2(row1_x + (btn_w + btn_gap) * 1, row1_y, btn_w, btn_h)
    _sub_entity_rect = Rect2(row1_x + (btn_w + btn_gap) * 2, row1_y, btn_w, btn_h)
    _sub_behavior_rect = Rect2(row1_x + (btn_w + btn_gap) * 3, row1_y, btn_w, btn_h)
    _sub_theme_rect = Rect2(row1_x + (btn_w + btn_gap) * 4, row1_y, btn_w, btn_h)
    _sub_audio_rect = Rect2(row2_x, row2_y, btn_w, btn_h)
    _sub_player_rect = Rect2(row2_x + (btn_w + btn_gap) * 1, row2_y, btn_w, btn_h)
    _sub_trigger_rect = Rect2(row2_x + (btn_w + btn_gap) * 2, row2_y, btn_w, btn_h)
    _sub_dialogue_rect = Rect2(row2_x + (btn_w + btn_gap) * 3, row2_y, btn_w, btn_h)
    _sub_shop_rect = Rect2(row2_x + (btn_w + btn_gap) * 4, row2_y, btn_w, btn_h)
    _sub_quest_rect = Rect2(row2_x + (btn_w + btn_gap) * 5, row2_y, btn_w, btn_h)

    _draw_chooser_btn(font, _sub_ship_rect, "CONTENT",
        _sub_ship_rect.has_point(mouse_pos), alpha,
        Color(0.3, 0.85, 0.95), Color(0.75, 0.95, 1.0))
    _draw_chooser_btn(font, _sub_realm_rect, "REALM",
        _sub_realm_rect.has_point(mouse_pos), alpha,
        Color(0.85, 0.3, 0.9), Color(1.0, 0.7, 1.0))
    _draw_chooser_btn(font, _sub_entity_rect, "ENTITY",
        _sub_entity_rect.has_point(mouse_pos), alpha,
        Color(0.95, 0.7, 0.3), Color(1.0, 0.85, 0.6))
    _draw_chooser_btn(font, _sub_behavior_rect, "BEHAVIOR",
        _sub_behavior_rect.has_point(mouse_pos), alpha,
        Color(0.4, 0.85, 0.6), Color(0.75, 1.0, 0.85))
    _draw_chooser_btn(font, _sub_theme_rect, "THEME",
        _sub_theme_rect.has_point(mouse_pos), alpha,
        Color(0.95, 0.85, 0.3), Color(1.0, 0.95, 0.6))
    _draw_chooser_btn(font, _sub_audio_rect, "AUDIO",
        _sub_audio_rect.has_point(mouse_pos), alpha,
        Color(0.5, 0.7, 1.0), Color(0.8, 0.9, 1.0))
    _draw_chooser_btn(font, _sub_player_rect, "PLAYER",
        _sub_player_rect.has_point(mouse_pos), alpha,
        Color(0.95, 0.45, 0.55), Color(1.0, 0.75, 0.8))
    _draw_chooser_btn(font, _sub_trigger_rect, "TRIGGER",
        _sub_trigger_rect.has_point(mouse_pos), alpha,
        Color(0.9, 0.6, 0.2), Color(1.0, 0.8, 0.5))
    _draw_chooser_btn(font, _sub_dialogue_rect, "DIALOGUE",
        _sub_dialogue_rect.has_point(mouse_pos), alpha,
        Color(0.5, 0.85, 0.85), Color(0.75, 1.0, 1.0))
    _draw_chooser_btn(font, _sub_shop_rect, "SHOP",
        _sub_shop_rect.has_point(mouse_pos), alpha,
        Color(0.8, 0.7, 0.4), Color(1.0, 0.9, 0.6))
    _draw_chooser_btn(font, _sub_quest_rect, "QUEST",
        _sub_quest_rect.has_point(mouse_pos), alpha,
        Color(0.55, 0.82, 0.35), Color(0.82, 1.0, 0.62))

    # Red X close (top-right of panel) — replaces the old BACK + CANCEL
    # buttons. Reuses _sub_back_rect so the existing click handler dispatches
    # a "back to campaign picker" transition.
    var x_size: float = 44.0
    var x_pad: float = 16.0
    var x_x: float = panel_x + panel_w - x_size - x_pad
    var x_y: float = panel_y + x_pad
    _sub_back_rect = Rect2(x_x, x_y, x_size, x_size)
    var x_hover := _sub_back_rect.has_point(mouse_pos)
    var x_bg := Color(0.95, 0.35, 0.32, alpha) if x_hover else Color(0.7, 0.22, 0.24, alpha)
    draw_rect(_sub_back_rect, x_bg)
    draw_rect(_sub_back_rect, Color(1.0, 0.55, 0.55, alpha), false, 1.5)
    var x_col := Color(1.0, 1.0, 1.0, alpha) if x_hover else Color(0.95, 0.85, 0.85, alpha)
    var x_pad2: float = 12.0
    draw_line(Vector2(x_x + x_pad2, x_y + x_pad2),
        Vector2(x_x + x_size - x_pad2, x_y + x_size - x_pad2),
        x_col, 3.0, true)
    draw_line(Vector2(x_x + x_size - x_pad2, x_y + x_pad2),
        Vector2(x_x + x_pad2, x_y + x_size - x_pad2),
        x_col, 3.0, true)

func _draw_chooser_btn(font: Font, rect: Rect2, label: String, hovered: bool, alpha: float, accent: Color, _text_col: Color):
    UIPanels.draw_button_bg(self, rect, hovered, Color(accent.r, accent.g, accent.b, alpha))
    if hovered:
        for gi in 3:
            var gw = 1.0 + float(gi) * 0.5
            draw_rect(Rect2(rect.position - Vector2(gi, gi), rect.size + Vector2(gi * 2, gi * 2)),
                Color(accent.r, accent.g, accent.b, (0.45 - float(gi) * 0.12) * alpha), false, gw)
    var is_compact := rect.size.y <= 48.0
    var font_size: int = 12 if is_compact else 24
    var lbl_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
    var lbl_x: float = rect.position.x + (rect.size.x - lbl_size.x) * 0.5
    var lbl_y: float
    if is_compact:
        lbl_y = rect.position.y + (rect.size.y - lbl_size.y) * 0.5 + lbl_size.y - 1.0
    else:
        lbl_y = rect.position.y + rect.size.y + 8.0 + lbl_size.y
    var yellow := Color(1.0, 0.92, 0.3, alpha) if hovered else Color(0.95, 0.82, 0.15, alpha * 0.92)
    draw_string(font, Vector2(lbl_x, lbl_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, yellow)

func _start_update():
    if _update_state == 1 or _update_state == 2:
        return

    if Updater.state == Updater.State.UPDATE_AVAILABLE:
        _update_state = 2
        _update_message = "Downloading..."
        Updater.start_download()
        return

    _update_state = 1
    _update_message = "Checking for updates..."

    if not Updater.update_check_complete.is_connected(_on_update_check):
        Updater.update_check_complete.connect(_on_update_check)
    if not Updater.download_complete.is_connected(_on_download_done):
        Updater.download_complete.connect(_on_download_done)
    Updater.check_for_update()

func _on_update_check(has_update: bool, _latest_version: String):
    if has_update:

        _update_state = 2
        _update_message = "Downloading %s..." % _latest_version
        Updater.start_download()
    else:
        if Updater.state == Updater.State.DONE_ERROR:
            _update_state = 5
            _update_message = Updater.error_message
        else:
            _update_state = 4
            _update_message = Updater.result_message

func _on_download_done(success: bool, message: String):
    if success:
        _update_state = 3
        _update_message = message
    else:
        _update_state = 5
        _update_message = message


func _current_pack_id() -> String:
    if MvPackLoader.current_pack != null:
        return MvPackLoader.current_pack.pack_id
    if not _authored_pack_id.is_empty():
        return _authored_pack_id
    return ""


func _has_authored_screen() -> bool:
    return _authored_screen != null and _authored_screen.visible and _authored_screen.has_method("has_screen") and _authored_screen.has_screen()


func _refresh_authored_screen() -> void:
    if _authored_screen == null:
        return
    if _editor_modal != EditorModal.CLOSED:
        _authored_screen.visible = false
        return
    var pack_id := _current_pack_id()
    if pack_id.is_empty() or not UIIo.screen_exists(pack_id, "main_menu"):
        _authored_pack_id = ""
        _authored_screen.call("clear_screen")
        return
    if pack_id != _authored_pack_id or not _authored_screen.call("has_screen"):
        _authored_pack_id = pack_id
        var data: Dictionary = UIIo.load_screen(pack_id, "main_menu")
        _authored_screen.call("load_screen", "main_menu", data, HudDataSource.new(null, GameManager))
    _authored_screen.visible = true


func _first_populated_slot() -> int:
    for i in range(1, GameManager.MAX_SAVE_SLOTS + 1):
        if i - 1 < _slot_info.size() and not (_slot_info[i - 1] as Dictionary).is_empty():
            return i
    return -1


func _on_authored_action(action_id: String, action_args: String, _element_id: String) -> void:
    _emit_ui_button_event(action_id, action_args, _element_id)
    match action_id:
        "open_screen":
            if _open_special_screen(action_args):
                return
            if not UiContract.host_supports_open_target("main_menu", action_args):
                push_warning("main_menu: open_screen target '%s' is not supported by host" % action_args)
            elif not action_args.is_empty() and UIIo.screen_exists(_current_pack_id(), action_args):
                _authored_pack_id = _current_pack_id()
                var data: Dictionary = UIIo.load_screen(_authored_pack_id, action_args)
                _authored_screen.call("load_screen", action_args, data, HudDataSource.new(null, GameManager))
            else:
                push_warning("main_menu: open_screen target '%s' was not found" % action_args)
        "new_game":
            MvPackLoader.reset_last_loaded_pack_id()
            visible = false
            play_pack_pressed.emit(_current_pack_id())
        "creative_mode":
            _start_creative()
        "test_fly":
            _start_test_fly()
        "test_planet":
            _start_test_planet()
        "open_editor":
            _open_editor_chooser()
        "update_game":
            _start_update()
        "load_slot":
            if action_args.is_valid_int():
                var slot := int(action_args)
                if slot >= 1 and slot <= GameManager.MAX_SAVE_SLOTS and not _slot_info[slot - 1].is_empty():
                    _load_slot(slot)
        "load_game":
            var slot := int(action_args) if action_args.is_valid_int() else GameManager.current_save_slot
            if slot <= 0 or slot > GameManager.MAX_SAVE_SLOTS or _slot_info[slot - 1].is_empty():
                slot = _first_populated_slot()
            if slot > 0:
                _load_slot(slot)
        "fire_event":
            UiHostActions.fire_authored_event("main_menu", "main_menu", action_args, _element_id, {
                "pack_id": _current_pack_id(),
            })
        "open_settings":
            _open_settings_menu()
        "quit_to_menu":
            _return_to_launcher()
        "quit_game":
            get_tree().quit()
        "play_sfx":
            UiHostActions.play_authored_sfx(action_args)
        _:
            UiHostActions.warn_unhandled_action("main_menu", action_id, action_args)


func _emit_ui_button_event(action_id: String, action_args: String, element_id: String) -> void:
    UiHostActions.emit_ui_button_event("main_menu", "main_menu", action_id, action_args, element_id, {
        "pack_id": _current_pack_id(),
    })


func _open_special_screen(target: String) -> bool:
    return UiHostActions.open_cinematic(_current_pack_id(), "main_menu", target)


func _open_settings_menu() -> void:
    if _settings_menu != null and _settings_menu.has_method("open_menu"):
        _settings_menu.call("open_menu", "main_menu")

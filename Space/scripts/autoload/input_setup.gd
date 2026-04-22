class_name InputSetup
extends RefCounted

# InputMap action setup, extracted from GameManager. Called once from
# GameManager._ready() via install(). Runtime polling and device
# detection (using_controller, controller_aim, poll_*_stick,
# detect_input_device, get_button_prompt) stay on GameManager because
# they mutate state referenced across 11 files.

static func install() -> void:
    _add_key("move_up", KEY_W)
    _add_key("move_down", KEY_S)
    _add_key("move_left", KEY_A)
    _add_key("move_right", KEY_D)
    _add_key("jump", KEY_SPACE)
    _add_mouse("fire_primary", MOUSE_BUTTON_LEFT)
    _add_mouse("fire_secondary", MOUSE_BUTTON_RIGHT)
    _add_key("toggle_ship_builder", KEY_B)
    _add_key("toggle_star_map", KEY_M)
    _add_key("map", KEY_M)
    _add_key("interact", KEY_E)
    _add_key("melee_attack", KEY_C)
    _add_key("ranged_attack", KEY_V)
    _add_key("grapple", KEY_G)
    _add_key("dodge_roll", KEY_Z)
    _add_key("scan", KEY_Q)
    _add_key("boost", KEY_SHIFT)
    _add_key("cycle_primary", KEY_1)
    _add_key("cycle_secondary", KEY_2)
    _add_key("cycle_special", KEY_3)
    _add_key("cycle_power", KEY_TAB)
    _add_key("save_game", KEY_F5)
    _add_key("load_game", KEY_F9)
    _add_key("handbrake", KEY_SPACE)
    _add_key("toggle_editor", KEY_F1)
    _add_key("launch_boarding", KEY_V)
    _add_key("fire_special", KEY_F)
    _add_key("toggle_pause", KEY_QUOTELEFT)
    _add_key("fire_harpoon", KEY_R)
    _add_key("liftoff", KEY_T)



    _add_joy_button("move_up", JOY_BUTTON_DPAD_UP)
    _add_joy_button("move_down", JOY_BUTTON_DPAD_DOWN)
    _add_joy_button("move_left", JOY_BUTTON_DPAD_LEFT)
    _add_joy_button("move_right", JOY_BUTTON_DPAD_RIGHT)
    _add_joy_button("jump", JOY_BUTTON_A)
    _add_joy_button("interact", JOY_BUTTON_X)
    _add_joy_button("melee_attack", JOY_BUTTON_RIGHT_SHOULDER)
    _add_joy_axis("ranged_attack", JOY_AXIS_TRIGGER_RIGHT, 0.1)
    _add_joy_axis("grapple", JOY_AXIS_TRIGGER_LEFT, 0.1)
    _add_joy_button("dodge_roll", JOY_BUTTON_B)
    _add_joy_button("liftoff", JOY_BUTTON_Y)


    _add_joy_axis("fire_primary", JOY_AXIS_TRIGGER_RIGHT, 0.1)
    _add_joy_axis("fire_secondary", JOY_AXIS_TRIGGER_LEFT, 0.1)
    _add_joy_button("scan", JOY_BUTTON_LEFT_SHOULDER)
    _add_joy_button("boost", JOY_BUTTON_LEFT_STICK)
    _add_joy_button("handbrake", JOY_BUTTON_RIGHT_STICK)
    _add_joy_button("fire_special", JOY_BUTTON_RIGHT_SHOULDER)
    _add_joy_button("launch_boarding", JOY_BUTTON_Y)
    _add_joy_button("fire_harpoon", JOY_BUTTON_B)


    _add_joy_button("toggle_ship_builder", JOY_BUTTON_X)
    _add_joy_button("toggle_pause", JOY_BUTTON_START)
    _add_joy_button("toggle_star_map", JOY_BUTTON_BACK)
    _add_joy_button("map", JOY_BUTTON_BACK)


    _add_joy_button("cycle_power", JOY_BUTTON_DPAD_UP)
    _add_joy_button("cycle_primary", JOY_BUTTON_DPAD_RIGHT)
    _add_joy_button("cycle_secondary", JOY_BUTTON_DPAD_LEFT)
    _add_joy_button("cycle_special", JOY_BUTTON_DPAD_DOWN)



    _add_joy_button_to("ui_accept", JOY_BUTTON_A)
    _add_joy_button_to("ui_cancel", JOY_BUTTON_B)
    _add_joy_button_to("ui_up", JOY_BUTTON_DPAD_UP)
    _add_joy_button_to("ui_down", JOY_BUTTON_DPAD_DOWN)
    _add_joy_button_to("ui_left", JOY_BUTTON_DPAD_LEFT)
    _add_joy_button_to("ui_right", JOY_BUTTON_DPAD_RIGHT)

    _add_joy_axis_to("ui_up", JOY_AXIS_LEFT_Y, -0.5)
    _add_joy_axis_to("ui_down", JOY_AXIS_LEFT_Y, 0.5)
    _add_joy_axis_to("ui_left", JOY_AXIS_LEFT_X, -0.5)
    _add_joy_axis_to("ui_right", JOY_AXIS_LEFT_X, 0.5)


    if not InputMap.has_action("ui_tab_left"):
        InputMap.add_action("ui_tab_left")
    _add_joy_button("ui_tab_left", JOY_BUTTON_LEFT_SHOULDER)
    if not InputMap.has_action("ui_tab_right"):
        InputMap.add_action("ui_tab_right")
    _add_joy_button("ui_tab_right", JOY_BUTTON_RIGHT_SHOULDER)


    if not InputMap.has_action("zoom_in"):
        InputMap.add_action("zoom_in")
    if not InputMap.has_action("zoom_out"):
        InputMap.add_action("zoom_out")
    _add_joy_button("zoom_in", JOY_BUTTON_RIGHT_SHOULDER)
    _add_joy_button("zoom_out", JOY_BUTTON_LEFT_SHOULDER)


static func _add_key(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventKey.new()
    ev.physical_keycode = key
    InputMap.action_add_event(action, ev)


static func _add_key_ctrl(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventKey.new()
    ev.physical_keycode = key
    ev.ctrl_pressed = true
    InputMap.action_add_event(action, ev)


static func _add_key_shift(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventKey.new()
    ev.physical_keycode = key
    ev.shift_pressed = true
    InputMap.action_add_event(action, ev)


static func _add_mouse(action: String, button: MouseButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventMouseButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _add_joy_button(action: String, button: JoyButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventJoypadButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _add_joy_button_to(action: String, button: JoyButton) -> void:
    var ev = InputEventJoypadButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _add_joy_axis(action: String, axis: JoyAxis, threshold: float = 0.5) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev = InputEventJoypadMotion.new()
    ev.axis = axis
    ev.axis_value = threshold if threshold >= 0 else threshold
    InputMap.action_add_event(action, ev)


static func _add_joy_axis_to(action: String, axis: JoyAxis, threshold: float) -> void:
    var ev = InputEventJoypadMotion.new()
    ev.axis = axis
    ev.axis_value = threshold
    InputMap.action_add_event(action, ev)

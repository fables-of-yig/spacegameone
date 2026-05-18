class_name InputSetup
extends RefCounted

# InputMap action setup, extracted from GameManager. Called once from
# GameManager._ready() via install(). Runtime polling and device
# detection stay on GameManager; this script owns the action catalog,
# default bindings, serialization, and prompt formatting used by the
# settings menu + HUD help text.

const SECTION_SPACE := "space"
const SECTION_PLANETARY := "planetary"
const SECTION_MV := "mv"
const SECTION_UI := "ui"

const DEVICE_KBM := "kbm"
const DEVICE_CONTROLLER := "controller"

const ACTION_LABELS: Dictionary = {
    "move_up": "Move Up / Thrust",
    "move_down": "Move Down / Reverse",
    "move_left": "Move Left",
    "move_right": "Move Right",
    "controller_move_left": "Controller Move Stick Left",
    "controller_move_right": "Controller Move Stick Right",
    "controller_move_up": "Controller Move Stick Up",
    "controller_move_down": "Controller Move Stick Down",
    "controller_aim_left": "Controller Aim Stick Left",
    "controller_aim_right": "Controller Aim Stick Right",
    "controller_aim_up": "Controller Aim Stick Up",
    "controller_aim_down": "Controller Aim Stick Down",
    "jump": "Jump",
    "crouch": "Crouch",
    "aim_up": "Aim Up",
    "interact": "Interact / Confirm",
    "melee_attack": "Melee Attack",
    "ranged_attack": "Ranged Attack",
    "grapple": "Grapple",
    "dodge_roll": "Dodge Roll",
    "liftoff": "Liftoff / Launch",
    "fire_primary": "Fire Primary",
    "fire_secondary": "Fire Secondary",
    "fire_special": "Fire Special",
    "fire_harpoon": "Fire Harpoon",
    "boost": "Boost",
    "handbrake": "Handbrake / Orbit Lock",
    "scan": "Scan / Shield Supercharger",
    "cycle_primary": "Cycle Primary Weapons",
    "cycle_secondary": "Cycle Secondary Weapons",
    "cycle_special": "Cycle Special Weapons",
    "cycle_power": "Cycle Power Preset",
    "toggle_ship_builder": "Toggle Ship Builder",
    "toggle_star_map": "Toggle Star Map",
    "map": "Map",
    "toggle_pause": "Pause / Menu",
    "launch_boarding": "Launch Boarding Pod",
    "save_game": "Quick Save",
    "load_game": "Quick Load",
    "ui_accept": "Menu Accept",
    "ui_cancel": "Menu Cancel / Back",
    "ui_up": "Menu Up",
    "ui_down": "Menu Down",
    "ui_left": "Menu Left",
    "ui_right": "Menu Right",
    "ui_tab_left": "Menu Tab Left",
    "ui_tab_right": "Menu Tab Right",
}

const CONTROL_SECTIONS: Array = [
    {
        "id": SECTION_SPACE,
        "label": "Space",
        "description": "Ship flight, weapons, and ship-side utility controls.",
        "actions": [
            "move_up", "move_down", "move_left", "move_right",
            "controller_move_left", "controller_move_right", "controller_move_up", "controller_move_down",
            "controller_aim_left", "controller_aim_right", "controller_aim_up", "controller_aim_down",
            "fire_primary", "fire_secondary", "fire_special", "fire_harpoon",
            "boost", "handbrake", "scan",
            "cycle_primary", "cycle_secondary", "cycle_special", "cycle_power",
            "toggle_ship_builder", "toggle_star_map", "map", "launch_boarding",
            "toggle_pause", "save_game", "load_game",
        ],
    },
    {
        "id": SECTION_PLANETARY,
        "label": "Planetary",
        "description": "Planet-surface movement and POI interaction.",
        "actions": [
            "move_up", "move_down", "move_left", "move_right",
            "interact", "liftoff", "map", "toggle_pause",
        ],
    },
    {
        "id": SECTION_MV,
        "label": "MV",
        "description": "Sideview movement, combat, and room interaction controls.",
        "actions": [
            "move_left", "move_right", "jump", "crouch", "aim_up",
            "melee_attack", "ranged_attack", "grapple", "dodge_roll",
            "interact", "toggle_pause",
        ],
    },
    {
        "id": SECTION_UI,
        "label": "Menus",
        "description": "Shared menu navigation for pads, keyboards, and accessibility remaps.",
        "actions": [
            "ui_accept", "ui_cancel", "ui_up", "ui_down",
            "ui_left", "ui_right", "ui_tab_left", "ui_tab_right",
        ],
    },
]

static func install() -> void:
    _add_key("move_up", KEY_W)
    _add_key("move_down", KEY_S)
    _add_key("move_left", KEY_A)
    _add_key("move_right", KEY_D)
    _add_key("jump", KEY_SPACE)
    _add_mouse("fire_primary", MOUSE_BUTTON_LEFT)
    _add_key("toggle_ship_builder", KEY_B)
    _add_key("toggle_star_map", KEY_M)
    _add_key("map", KEY_M)
    _add_key("interact", KEY_E)
    _add_key("melee_attack", KEY_C)
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
    _add_joy_axis("controller_move_left", JOY_AXIS_LEFT_X, -0.5)
    _add_joy_axis("controller_move_right", JOY_AXIS_LEFT_X, 0.5)
    _add_joy_axis("controller_move_up", JOY_AXIS_LEFT_Y, -0.5)
    _add_joy_axis("controller_move_down", JOY_AXIS_LEFT_Y, 0.5)
    _add_joy_axis("controller_aim_left", JOY_AXIS_RIGHT_X, -0.5)
    _add_joy_axis("controller_aim_right", JOY_AXIS_RIGHT_X, 0.5)
    _add_joy_axis("controller_aim_up", JOY_AXIS_RIGHT_Y, -0.5)
    _add_joy_axis("controller_aim_down", JOY_AXIS_RIGHT_Y, 0.5)
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


static func tracked_actions() -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for section_v in CONTROL_SECTIONS:
        var section: Dictionary = section_v
        var actions_v: Variant = section.get("actions", [])
        if typeof(actions_v) != TYPE_ARRAY:
            continue
        for action_v in (actions_v as Array):
            var action := str(action_v)
            if action.is_empty() or seen.has(action):
                continue
            seen[action] = true
            out.append(action)
    return out


static func control_sections() -> Array:
    return CONTROL_SECTIONS.duplicate(true)


static func action_label(action: String) -> String:
    return str(ACTION_LABELS.get(action, action.replace("_", " ").capitalize()))


static func capture_bindings(actions: Array = []) -> Dictionary:
    var target_actions := actions if not actions.is_empty() else tracked_actions()
    var out: Dictionary = {}
    for action_v in target_actions:
        var action := str(action_v)
        out[action] = serialize_action_events(action)
    return out


static func serialize_action_events(action: String) -> Array:
    var out: Array = []
    if not InputMap.has_action(action):
        return out
    for event_v in InputMap.action_get_events(action):
        var spec := serialize_event(event_v)
        if not spec.is_empty():
            out.append(spec)
    return out


static func apply_binding_map(bindings: Dictionary) -> void:
    var clean_bindings := sanitize_binding_map(bindings)
    for action_v in tracked_actions():
        var action := str(action_v)
        if not clean_bindings.has(action):
            continue
        set_action_binding_specs(action, clean_bindings.get(action, []))
    _remove_mouse_button("fire_secondary", MOUSE_BUTTON_RIGHT)


static func sanitize_binding_map(bindings: Dictionary) -> Dictionary:
    var out := bindings.duplicate(true)
    if out.has("fire_secondary"):
        var specs_v: Variant = out.get("fire_secondary", [])
        if typeof(specs_v) == TYPE_ARRAY:
            var cleaned: Array = []
            for spec_v in (specs_v as Array):
                if typeof(spec_v) == TYPE_DICTIONARY:
                    var spec: Dictionary = spec_v
                    if str(spec.get("kind", "")) == "mouse_button" \
                            and int(spec.get("button_index", 0)) == int(MOUSE_BUTTON_RIGHT):
                        continue
                cleaned.append(spec_v)
            out["fire_secondary"] = cleaned
    return out


static func set_action_binding_specs(action: String, specs_v: Variant) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var deadzone := InputMap.action_get_deadzone(action)
    InputMap.action_erase_events(action)
    if typeof(specs_v) == TYPE_ARRAY:
        for spec_v in (specs_v as Array):
            if typeof(spec_v) != TYPE_DICTIONARY:
                continue
            var event := deserialize_event(spec_v as Dictionary)
            if event != null:
                InputMap.action_add_event(action, event)
    InputMap.action_set_deadzone(action, deadzone)


static func action_bindings_by_device(action: String) -> Dictionary:
    var split := {
        DEVICE_KBM: [],
        DEVICE_CONTROLLER: [],
    }
    if not InputMap.has_action(action):
        return split
    for event_v in InputMap.action_get_events(action):
        var spec := serialize_event(event_v)
        if spec.is_empty():
            continue
        var device_group := device_group_for_spec(spec)
        if not split.has(device_group):
            split[device_group] = []
        (split[device_group] as Array).append(spec)
    return split


static func update_binding_slot(binding_map: Dictionary, action: String, device_group: String,
        slot_index: int, spec: Dictionary) -> Dictionary:
    var next_map := binding_map.duplicate(true)
    var split := _binding_map_entry_by_device(next_map.get(action, []))
    var target: Array = (split.get(device_group, []) as Array).duplicate(true)
    while target.size() <= slot_index:
        target.append({})
    target[slot_index] = spec.duplicate(true)
    split[device_group] = target
    next_map[action] = _merge_binding_device_arrays(split)
    return next_map


static func clear_binding_slot(binding_map: Dictionary, action: String, device_group: String,
        slot_index: int) -> Dictionary:
    var next_map := binding_map.duplicate(true)
    var split := _binding_map_entry_by_device(next_map.get(action, []))
    var target: Array = (split.get(device_group, []) as Array).duplicate(true)
    if slot_index >= 0 and slot_index < target.size():
        target.remove_at(slot_index)
    split[device_group] = target
    next_map[action] = _merge_binding_device_arrays(split)
    return next_map


static func format_action_prompt(action: String, prefer_controller: bool, fallback: String = "") -> String:
    var split := action_bindings_by_device(action)
    var device_group := DEVICE_CONTROLLER if prefer_controller else DEVICE_KBM
    var events: Array = split.get(device_group, [])
    if events.is_empty():
        events = split.get(DEVICE_KBM if prefer_controller else DEVICE_CONTROLLER, [])
    if events.is_empty():
        return fallback if not fallback.is_empty() else action_label(action)
    return format_binding_spec(events[0])


static func format_binding_spec(spec_v: Variant) -> String:
    if typeof(spec_v) != TYPE_DICTIONARY:
        return "Unbound"
    var spec: Dictionary = spec_v
    match str(spec.get("kind", "")):
        "key":
            return _format_key_spec(spec)
        "mouse_button":
            return _format_mouse_button(int(spec.get("button_index", 0)))
        "joy_button":
            return _format_joy_button(int(spec.get("button_index", -1)))
        "joy_axis":
            return _format_joy_axis(int(spec.get("axis", -1)), float(spec.get("axis_value", 0.0)))
    return "Unbound"


static func serialize_event(event_v: Variant) -> Dictionary:
    if event_v is InputEventKey:
        var event: InputEventKey = event_v
        return {
            "kind": "key",
            "physical_keycode": int(event.physical_keycode),
            "keycode": int(event.keycode),
            "shift": event.shift_pressed,
            "alt": event.alt_pressed,
            "ctrl": event.ctrl_pressed,
            "meta": event.meta_pressed,
        }
    if event_v is InputEventMouseButton:
        var mouse_event: InputEventMouseButton = event_v
        return {
            "kind": "mouse_button",
            "button_index": int(mouse_event.button_index),
        }
    if event_v is InputEventJoypadButton:
        var joy_button: InputEventJoypadButton = event_v
        return {
            "kind": "joy_button",
            "button_index": int(joy_button.button_index),
        }
    if event_v is InputEventJoypadMotion:
        var joy_axis: InputEventJoypadMotion = event_v
        return {
            "kind": "joy_axis",
            "axis": int(joy_axis.axis),
            "axis_value": float(joy_axis.axis_value),
        }
    return {}


static func deserialize_event(spec: Dictionary) -> InputEvent:
    match str(spec.get("kind", "")):
        "key":
            var key_event := InputEventKey.new()
            key_event.physical_keycode = int(spec.get("physical_keycode", 0))
            key_event.keycode = int(spec.get("keycode", 0))
            key_event.shift_pressed = bool(spec.get("shift", false))
            key_event.alt_pressed = bool(spec.get("alt", false))
            key_event.ctrl_pressed = bool(spec.get("ctrl", false))
            key_event.meta_pressed = bool(spec.get("meta", false))
            return key_event
        "mouse_button":
            var mouse_event := InputEventMouseButton.new()
            mouse_event.button_index = int(spec.get("button_index", 0))
            return mouse_event
        "joy_button":
            var joy_button := InputEventJoypadButton.new()
            joy_button.button_index = int(spec.get("button_index", 0))
            return joy_button
        "joy_axis":
            var joy_axis := InputEventJoypadMotion.new()
            joy_axis.axis = int(spec.get("axis", 0))
            joy_axis.axis_value = float(spec.get("axis_value", 0.0))
            return joy_axis
    return null


static func device_group_for_spec(spec: Dictionary) -> String:
    var kind := str(spec.get("kind", ""))
    if kind == "joy_button" or kind == "joy_axis":
        return DEVICE_CONTROLLER
    return DEVICE_KBM


static func make_event_spec(event_v: Variant) -> Dictionary:
    return serialize_event(event_v)


static func _binding_map_entry_by_device(specs_v: Variant) -> Dictionary:
    var split := {
        DEVICE_KBM: [],
        DEVICE_CONTROLLER: [],
    }
    if typeof(specs_v) != TYPE_ARRAY:
        return split
    for spec_v in (specs_v as Array):
        if typeof(spec_v) != TYPE_DICTIONARY:
            continue
        var spec: Dictionary = spec_v
        var device_group := device_group_for_spec(spec)
        (split[device_group] as Array).append(spec.duplicate(true))
    return split


static func _merge_binding_device_arrays(split: Dictionary) -> Array:
    var out: Array = []
    var kbm: Array = split.get(DEVICE_KBM, [])
    var controller: Array = split.get(DEVICE_CONTROLLER, [])
    for spec_v in kbm:
        if typeof(spec_v) == TYPE_DICTIONARY and not (spec_v as Dictionary).is_empty():
            out.append((spec_v as Dictionary).duplicate(true))
    for spec_v in controller:
        if typeof(spec_v) == TYPE_DICTIONARY and not (spec_v as Dictionary).is_empty():
            out.append((spec_v as Dictionary).duplicate(true))
    return out


static func _format_key_spec(spec: Dictionary) -> String:
    var parts: Array[String] = []
    if bool(spec.get("ctrl", false)):
        parts.append("Ctrl")
    if bool(spec.get("alt", false)):
        parts.append("Alt")
    if bool(spec.get("shift", false)):
        parts.append("Shift")
    if bool(spec.get("meta", false)):
        parts.append("Meta")
    var keycode := int(spec.get("physical_keycode", 0))
    if keycode == 0:
        keycode = int(spec.get("keycode", 0))
    var key_name := OS.get_keycode_string(keycode)
    if key_name.is_empty():
        key_name = "Key %d" % keycode
    parts.append(key_name)
    return "+".join(parts)


static func _format_mouse_button(button_index: int) -> String:
    match button_index:
        MOUSE_BUTTON_LEFT:
            return "LMB"
        MOUSE_BUTTON_RIGHT:
            return "RMB"
        MOUSE_BUTTON_MIDDLE:
            return "MMB"
        MOUSE_BUTTON_WHEEL_UP:
            return "Wheel Up"
        MOUSE_BUTTON_WHEEL_DOWN:
            return "Wheel Down"
        MOUSE_BUTTON_XBUTTON1:
            return "Mouse 4"
        MOUSE_BUTTON_XBUTTON2:
            return "Mouse 5"
    return "Mouse %d" % button_index


static func _format_joy_button(button_index: int) -> String:
    match button_index:
        JOY_BUTTON_A:
            return "A"
        JOY_BUTTON_B:
            return "B"
        JOY_BUTTON_X:
            return "X"
        JOY_BUTTON_Y:
            return "Y"
        JOY_BUTTON_BACK:
            return "Back"
        JOY_BUTTON_GUIDE:
            return "Guide"
        JOY_BUTTON_START:
            return "Start"
        JOY_BUTTON_LEFT_STICK:
            return "L3"
        JOY_BUTTON_RIGHT_STICK:
            return "R3"
        JOY_BUTTON_LEFT_SHOULDER:
            return "LB"
        JOY_BUTTON_RIGHT_SHOULDER:
            return "RB"
        JOY_BUTTON_DPAD_UP:
            return "D-Pad Up"
        JOY_BUTTON_DPAD_DOWN:
            return "D-Pad Down"
        JOY_BUTTON_DPAD_LEFT:
            return "D-Pad Left"
        JOY_BUTTON_DPAD_RIGHT:
            return "D-Pad Right"
    return "Pad %d" % button_index


static func _format_joy_axis(axis: int, axis_value: float) -> String:
    match axis:
        JOY_AXIS_TRIGGER_LEFT:
            return "LT"
        JOY_AXIS_TRIGGER_RIGHT:
            return "RT"
        JOY_AXIS_LEFT_X:
            return "Left Stick %s" % ("Right" if axis_value >= 0.0 else "Left")
        JOY_AXIS_LEFT_Y:
            return "Left Stick %s" % ("Down" if axis_value >= 0.0 else "Up")
        JOY_AXIS_RIGHT_X:
            return "Right Stick %s" % ("Right" if axis_value >= 0.0 else "Left")
        JOY_AXIS_RIGHT_Y:
            return "Right Stick %s" % ("Down" if axis_value >= 0.0 else "Up")
    return "Axis %d %s" % [axis, "+" if axis_value >= 0.0 else "-"]


static func _add_key(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventKey.new()
    ev.physical_keycode = key
    InputMap.action_add_event(action, ev)


static func _add_key_ctrl(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventKey.new()
    ev.physical_keycode = key
    ev.ctrl_pressed = true
    InputMap.action_add_event(action, ev)


static func _add_key_shift(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventKey.new()
    ev.physical_keycode = key
    ev.shift_pressed = true
    InputMap.action_add_event(action, ev)


static func _add_mouse(action: String, button: MouseButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventMouseButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _remove_mouse_button(action: String, button: MouseButton) -> void:
    if not InputMap.has_action(action):
        return
    for event_v in InputMap.action_get_events(action):
        if event_v is InputEventMouseButton and int((event_v as InputEventMouseButton).button_index) == int(button):
            InputMap.action_erase_event(action, event_v)


static func _add_joy_button(action: String, button: JoyButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventJoypadButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _add_joy_button_to(action: String, button: JoyButton) -> void:
    var ev := InputEventJoypadButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)


static func _add_joy_axis(action: String, axis: JoyAxis, threshold: float = 0.5) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventJoypadMotion.new()
    ev.axis = axis
    ev.axis_value = threshold if threshold >= 0.0 else threshold
    InputMap.action_add_event(action, ev)


static func _add_joy_axis_to(action: String, axis: JoyAxis, threshold: float) -> void:
    var ev := InputEventJoypadMotion.new()
    ev.axis = axis
    ev.axis_value = threshold
    InputMap.action_add_event(action, ev)

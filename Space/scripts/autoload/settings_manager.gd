extends Node

const SETTINGS_PATH := "user://settings.json"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_VOICE := "Voice"

const WINDOW_MODE_WINDOWED := "windowed"
const WINDOW_MODE_FULLSCREEN := "fullscreen"
const WINDOW_MODE_EXCLUSIVE := "exclusive_fullscreen"

# Audio channels that drive a real AudioServer bus (stored 0..1, surfaced 0..100).
const AUDIO_BUS_CHANNELS := ["master", "music", "sfx", "voice"]

signal audio_settings_changed
signal video_settings_changed
signal input_settings_changed
# Fired for any catalog-driven setting (graphics/gameplay/controls + audio/video).
signal settings_changed(section: String, key: String)

var _settings: Dictionary = {}
var _default_input_bindings: Dictionary = {}
var _input_defaults_registered: bool = false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _settings = _load_settings()
    _ensure_audio_buses()
    apply_audio_settings()
    call_deferred("apply_video_settings")
    call_deferred("apply_graphics_settings")


func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
        _apply_focus_mute(what == NOTIFICATION_APPLICATION_FOCUS_OUT)


func register_input_defaults() -> void:
    if _input_defaults_registered:
        return
    _default_input_bindings = InputSetup.capture_bindings()
    _input_defaults_registered = true
    _normalize_input_settings()
    apply_input_settings()


func get_audio_settings() -> Dictionary:
    return (_ensure_section("audio", _default_audio_settings()) as Dictionary).duplicate(true)


func set_audio_volume(channel: String, volume_linear: float) -> void:
    var audio := _ensure_section("audio", _default_audio_settings()) as Dictionary
    audio[channel] = clampf(volume_linear, 0.0, 1.0)
    apply_audio_settings()
    _save_settings()
    audio_settings_changed.emit()


func reset_audio_settings() -> void:
    _settings["audio"] = _default_audio_settings()
    apply_audio_settings()
    _save_settings()
    audio_settings_changed.emit()


func apply_audio_settings() -> void:
    _ensure_audio_buses()
    var audio := get_audio_settings()
    _set_bus_linear(BUS_MASTER, float(audio.get("master", 0.8)))
    _set_bus_linear(BUS_MUSIC, float(audio.get("music", 0.8)))
    _set_bus_linear(BUS_SFX, float(audio.get("sfx", 0.8)))
    _set_bus_linear(BUS_VOICE, float(audio.get("voice", 0.8)))


func get_video_settings() -> Dictionary:
    return (_ensure_section("video", _default_video_settings()) as Dictionary).duplicate(true)


func set_window_mode(mode_name: String) -> void:
    var video := _ensure_section("video", _default_video_settings()) as Dictionary
    video["window_mode"] = _sanitize_window_mode(mode_name)
    apply_video_settings()
    _save_settings()
    video_settings_changed.emit()


func set_resolution(size: Vector2i) -> void:
    var clamped := Vector2i(maxi(size.x, 640), maxi(size.y, 360))
    var video := _ensure_section("video", _default_video_settings()) as Dictionary
    video["width"] = clamped.x
    video["height"] = clamped.y
    apply_video_settings()
    _save_settings()
    video_settings_changed.emit()


func reset_video_settings() -> void:
    _settings["video"] = _default_video_settings()
    apply_video_settings()
    _save_settings()
    video_settings_changed.emit()


func apply_video_settings() -> void:
    var video := get_video_settings()
    var mode_name := _sanitize_window_mode(str(video.get("window_mode", WINDOW_MODE_FULLSCREEN)))
    var mode := _display_server_mode(mode_name)
    DisplayServer.window_set_mode(mode)
    if mode_name == WINDOW_MODE_WINDOWED:
        var current_size := Vector2i(DisplayServer.window_get_size())
        var target_size := Vector2i(int(video.get("width", current_size.x)), int(video.get("height", current_size.y)))
        DisplayServer.window_set_size(target_size)


func resolution_options() -> Array:
    var screen_idx := DisplayServer.window_get_current_screen()
    var screen_size := DisplayServer.screen_get_size(screen_idx)
    var candidates := [
        Vector2i(1280, 720),
        Vector2i(1366, 768),
        Vector2i(1600, 900),
        Vector2i(1920, 1080),
        Vector2i(2560, 1440),
        Vector2i(3200, 1800),
        Vector2i(3840, 2160),
    ]
    var seen: Dictionary = {}
    var out: Array = []
    for res in candidates:
        if res.x > screen_size.x or res.y > screen_size.y:
            continue
        var key := "%dx%d" % [res.x, res.y]
        if seen.has(key):
            continue
        seen[key] = true
        out.append({
            "label": key,
            "size": res,
        })
    var current := Vector2i(DisplayServer.window_get_size())
    var current_key := "%dx%d" % [current.x, current.y]
    if not seen.has(current_key):
        out.append({
            "label": current_key,
            "size": current,
        })
    out.sort_custom(func(a, b):
        var size_a: Vector2i = a.get("size", Vector2i.ZERO)
        var size_b: Vector2i = b.get("size", Vector2i.ZERO)
        if size_a.x == size_b.x:
            return size_a.y < size_b.y
        return size_a.x < size_b.x
    )
    return out


func input_binding_map() -> Dictionary:
    if not _input_defaults_registered:
        return {}
    return _effective_input_bindings()


func set_input_binding_map(binding_map: Dictionary) -> void:
    if not _input_defaults_registered:
        return
    var input := _ensure_section("input", {}) as Dictionary
    input["bindings"] = binding_map.duplicate(true)
    apply_input_settings()
    _save_settings()
    input_settings_changed.emit()


func set_input_binding_slot(action: String, device_group: String, slot_index: int, spec: Dictionary) -> void:
    var next_map := InputSetup.update_binding_slot(input_binding_map(), action, device_group, slot_index, spec)
    set_input_binding_map(next_map)


func clear_input_binding_slot(action: String, device_group: String, slot_index: int) -> void:
    var next_map := InputSetup.clear_binding_slot(input_binding_map(), action, device_group, slot_index)
    set_input_binding_map(next_map)


func reset_input_action(action: String) -> void:
    if not _input_defaults_registered:
        return
    var input := _ensure_section("input", {}) as Dictionary
    var bindings_v: Variant = input.get("bindings", {})
    if typeof(bindings_v) != TYPE_DICTIONARY:
        bindings_v = {}
    var bindings: Dictionary = (bindings_v as Dictionary).duplicate(true)
    bindings[action] = _default_input_bindings.get(action, [])
    input["bindings"] = bindings
    apply_input_settings()
    _save_settings()
    input_settings_changed.emit()


func reset_input_settings() -> void:
    if not _input_defaults_registered:
        return
    _settings["input"] = {
        "bindings": _default_input_bindings.duplicate(true),
    }
    apply_input_settings()
    _save_settings()
    input_settings_changed.emit()


func reset_all_settings() -> void:
    _settings = _default_settings()
    if _input_defaults_registered:
        (_settings["input"] as Dictionary)["bindings"] = _default_input_bindings.duplicate(true)
    apply_audio_settings()
    apply_video_settings()
    apply_graphics_settings()
    apply_input_settings()
    _save_settings()
    audio_settings_changed.emit()
    video_settings_changed.emit()
    input_settings_changed.emit()
    settings_changed.emit("", "")


func apply_input_settings() -> void:
    if not _input_defaults_registered:
        return
    InputSetup.apply_binding_map(_effective_input_bindings())


func current_window_mode() -> String:
    return _sanitize_window_mode(str(get_video_settings().get("window_mode", WINDOW_MODE_FULLSCREEN)))


func current_resolution() -> Vector2i:
    var video := get_video_settings()
    var current_size := Vector2i(DisplayServer.window_get_size())
    return Vector2i(int(video.get("width", current_size.x)), int(video.get("height", current_size.y)))


# --- Generic catalog-driven settings (graphics / gameplay / controls + the
# audio/video keys the Nebula settings screen drives). Values persist to the same
# user://settings.json; only keys with a real apply path actually change engine
# state (see SettingsCatalog `wired`). Audio bus channels are stored 0..1 but
# surfaced 0..100 to match the catalog sliders. ---

func get_setting(section: String, key: String, default_value: Variant) -> Variant:
    if section == "video":
        if key == "window_mode":
            return current_window_mode()
        if key == "resolution":
            var res := current_resolution()
            return "%dx%d" % [res.x, res.y]
    var sec := _ensure_section(section, {}) as Dictionary
    if not sec.has(key):
        if section == "audio" and AUDIO_BUS_CHANNELS.has(key):
            return float(_default_audio_settings().get(key, 0.8)) * 100.0
        return default_value
    var stored: Variant = sec[key]
    if section == "audio" and AUDIO_BUS_CHANNELS.has(key):
        return clampf(float(stored), 0.0, 1.0) * 100.0
    return stored


func set_setting(section: String, key: String, value: Variant) -> void:
    if section == "video":
        if key == "window_mode":
            set_window_mode(str(value))
            settings_changed.emit(section, key)
            return
        if key == "resolution":
            var parts := str(value).split("x")
            if parts.size() == 2:
                set_resolution(Vector2i(int(parts[0]), int(parts[1])))
            settings_changed.emit(section, key)
            return
    var sec := _ensure_section(section, {}) as Dictionary
    var store_val: Variant = value
    if section == "audio" and AUDIO_BUS_CHANNELS.has(key):
        store_val = clampf(float(value) / 100.0, 0.0, 1.0)
    sec[key] = store_val
    _apply_one(section, key, store_val)
    _save_settings()
    settings_changed.emit(section, key)
    if section == "audio":
        audio_settings_changed.emit()


# Re-apply every wired graphics knob (called on boot + after Restore Defaults).
func apply_graphics_settings() -> void:
    _apply_one("graphics", "vsync", get_setting("graphics", "vsync", true))
    _apply_one("graphics", "fps_limit", get_setting("graphics", "fps_limit", "144"))
    _apply_one("graphics", "ui_scale", get_setting("graphics", "ui_scale", 100))


# The single dispatch point for "this value drives real engine state". Anything
# not listed here is persisted only (a catalog `wired:false` PREVIEW row).
func _apply_one(section: String, key: String, value: Variant) -> void:
    if section == "graphics":
        match key:
            "vsync":
                var mode := DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED
                DisplayServer.window_set_vsync_mode(mode)
            "fps_limit":
                Engine.max_fps = maxi(int(str(value)), 0)
            "ui_scale":
                var root := get_tree().root
                if root != null:
                    root.content_scale_factor = clampf(float(value) / 100.0, 0.5, 2.0)
    elif section == "audio":
        if AUDIO_BUS_CHANNELS.has(key):
            apply_audio_settings()
        elif key == "mute_when_unfocused":
            # Effect lands on the next focus change; nothing to apply right now.
            pass


func _apply_focus_mute(unfocused: bool) -> void:
    var want_mute := bool(get_setting("audio", "mute_when_unfocused", true)) and unfocused
    var idx := AudioServer.get_bus_index(BUS_MASTER)
    if idx != -1:
        AudioServer.set_bus_mute(idx, want_mute)


func _default_settings() -> Dictionary:
    return {
        "audio": _default_audio_settings(),
        "video": _default_video_settings(),
        "graphics": {},
        "gameplay": {},
        "controls": {},
        "input": {
            "bindings": {},
        },
    }


func _default_audio_settings() -> Dictionary:
    return {
        "master": 0.8,
        "music": 0.8,
        "sfx": 0.8,
        "voice": 0.8,
    }


func _default_video_settings() -> Dictionary:
    var size := Vector2i(DisplayServer.window_get_size())
    return {
        "window_mode": _window_mode_name(DisplayServer.window_get_mode()),
        "width": maxi(size.x, 640),
        "height": maxi(size.y, 360),
    }


func _load_settings() -> Dictionary:
    if not FileAccess.file_exists(SETTINGS_PATH):
        return _default_settings()
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
    if file == null:
        return _default_settings()
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return _default_settings()
    var loaded: Dictionary = parsed
    var merged := _default_settings()
    for section_v in loaded.keys():
        var section := str(section_v)
        if typeof(loaded[section]) == TYPE_DICTIONARY:
            merged[section] = (loaded[section] as Dictionary).duplicate(true)
    return merged


func _save_settings() -> void:
    var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
    if file == null:
        push_error("SettingsManager: failed to open %s for write" % SETTINGS_PATH)
        return
    file.store_string(JSON.stringify(_settings, "\t"))
    file.close()


func _ensure_section(section: String, defaults: Dictionary) -> Variant:
    var current: Variant = _settings.get(section, null)
    if typeof(current) != TYPE_DICTIONARY:
        current = defaults.duplicate(true)
        _settings[section] = current
    return current


func _normalize_input_settings() -> void:
    var input := _ensure_section("input", {}) as Dictionary
    var bindings_v: Variant = input.get("bindings", {})
    if typeof(bindings_v) != TYPE_DICTIONARY:
        input["bindings"] = {}
        return
    var bindings: Dictionary = bindings_v
    for action_v in InputSetup.tracked_actions():
        var action := str(action_v)
        if not bindings.has(action):
            continue
        if typeof(bindings[action]) != TYPE_ARRAY:
            bindings[action] = _default_input_bindings.get(action, [])


func _effective_input_bindings() -> Dictionary:
    var merged := _default_input_bindings.duplicate(true)
    var input := _ensure_section("input", {}) as Dictionary
    var bindings_v: Variant = input.get("bindings", {})
    if typeof(bindings_v) != TYPE_DICTIONARY:
        return InputSetup.sanitize_binding_map(merged)
    var bindings: Dictionary = bindings_v
    for action_v in bindings.keys():
        merged[str(action_v)] = bindings[action_v]
    return InputSetup.sanitize_binding_map(merged)


func _ensure_audio_buses() -> void:
    _ensure_audio_bus(BUS_MUSIC)
    _ensure_audio_bus(BUS_SFX)
    _ensure_audio_bus(BUS_VOICE)


func _ensure_audio_bus(bus_name: String) -> void:
    if AudioServer.get_bus_index(bus_name) != -1:
        return
    var insert_at := AudioServer.get_bus_count()
    AudioServer.add_bus(insert_at)
    AudioServer.set_bus_name(insert_at, bus_name)


func _set_bus_linear(bus_name: String, volume_linear: float) -> void:
    var bus_idx := AudioServer.get_bus_index(bus_name)
    if bus_idx == -1:
        return
    AudioServer.set_bus_volume_db(bus_idx, _linear_to_db(volume_linear))


func _linear_to_db(value: float) -> float:
    if value <= 0.001:
        return -80.0
    return 20.0 * log(value) / log(10.0)


func _sanitize_window_mode(mode_name: String) -> String:
    match mode_name:
        WINDOW_MODE_WINDOWED, WINDOW_MODE_FULLSCREEN, WINDOW_MODE_EXCLUSIVE:
            return mode_name
    return WINDOW_MODE_FULLSCREEN


func _window_mode_name(mode: int) -> String:
    match mode:
        DisplayServer.WINDOW_MODE_WINDOWED:
            return WINDOW_MODE_WINDOWED
        DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
            return WINDOW_MODE_EXCLUSIVE
        _:
            return WINDOW_MODE_FULLSCREEN


func _display_server_mode(mode_name: String) -> int:
    match mode_name:
        WINDOW_MODE_WINDOWED:
            return DisplayServer.WINDOW_MODE_WINDOWED
        WINDOW_MODE_EXCLUSIVE:
            return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
        _:
            return DisplayServer.WINDOW_MODE_FULLSCREEN

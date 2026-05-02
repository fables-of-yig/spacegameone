extends RefCounted

# Pure IO for the in-game theme editor. Handles theme JSON load/save and
# enumerates available 9-slice textures across the user/shipped pack
# layers + the global Assets/UI folder. Mirrors env_io.gd / ent_io.gd
# in shape so the editor wire-up stays consistent.

const UIPanels = preload("res://Space/scripts/ui/ui_panels.gd")
const UiContract = preload("res://Space/scripts/ui/ui_contract.gd")
const UITypes  = preload("res://Space/scripts/editor/ui/ui_types.gd")


static func user_pack_dir(pack_id: String) -> String:
    return "user://Packs/%s/" % pack_id


static func shipped_pack_dir(pack_id: String) -> String:
    return "res://Content/%s/" % pack_id


static func pack_theme_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "UI/theme.json"


static func shipped_pack_theme_path(pack_id: String) -> String:
    return shipped_pack_dir(pack_id) + "UI/theme.json"


static func default_theme_path() -> String:
    return "user://default_ui_theme.json"


# Loads a theme dict for the editor's working state. Resolution order:
#   1. user://Packs/<pack>/UI/theme.json
#   2. res://Content/<pack>/UI/theme.json
#   3. user://default_ui_theme.json
#   4. UIPanels.FALLBACK_THEME (always succeeds)
# The returned dict is a deep-copy and safe to mutate.
static func load_or_init(pack_id: String) -> Dictionary:
    if pack_id != "":
        var user_path := pack_theme_path(pack_id)
        var d := _read_json(user_path)
        if not d.is_empty():
            return d
        var ship_path := shipped_pack_theme_path(pack_id)
        d = _read_json(ship_path)
        if not d.is_empty():
            return d
    var glob := _read_json(default_theme_path())
    if not glob.is_empty():
        return glob
    return UITypes.default_theme()


static func save_pack_theme(pack_id: String, data: Dictionary) -> bool:
    if pack_id == "":
        push_error("UIIo: cannot save pack theme with empty pack_id")
        return false
    _ensure_dir(user_pack_dir(pack_id) + "UI")
    return _write_json(pack_theme_path(pack_id), data)


static func save_default_theme(data: Dictionary) -> bool:
    return _write_json(default_theme_path(), data)


# Returns a sorted list of {path, label} dicts for every texture the
# theme editor can offer in the picker. Sources scanned (in order):
#   - user://Packs/<pack>/Assets/UI/*.png
#   - res://Content/<pack>/Assets/UI/*.png
#   - res://Assets/UI/*.png
#   - res://Space/art/ui/*.png
# Duplicates (by absolute resource path) are de-duped.
static func list_available_textures(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    var sources: Array = []
    if pack_id != "":
        sources.append({
            "dir":   user_pack_dir(pack_id) + "Assets/UI",
            "label": "pack/user",
        })
        sources.append({
            "dir":   shipped_pack_dir(pack_id) + "Assets/UI",
            "label": "pack/shipped",
        })
    sources.append({"dir": "res://Assets/UI", "label": "global"})
    sources.append({"dir": "res://Space/art/ui", "label": "ssb-ui"})

    for src in sources:
        var dir_path: String = src["dir"]
        var label: String = src["label"]
        for path in _list_pngs(dir_path):
            if seen.has(path):
                continue
            seen[path] = true
            out.append({
                "path":  path,
                "label": label,
                "name":  path.get_file(),
            })

    out.sort_custom(func(a, b):
        return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
    )
    return out


# Loads a Texture2D from a res://, user:// or absolute path. Returns null
# on failure so callers can degrade gracefully.
static func load_texture(path: String) -> Texture2D:
    if path == "":
        return null
    if path.begins_with("res://"):
        return load(path) as Texture2D
    if path.begins_with("user://") or path.contains(":/") or path.begins_with("/"):
        if not FileAccess.file_exists(path):
            return null
        var f := FileAccess.open(path, FileAccess.READ)
        if f == null:
            return null
        var bytes := f.get_buffer(f.get_length())
        f.close()
        var img := Image.new()
        if img.load_png_from_buffer(bytes) != OK:
            return null
        return ImageTexture.create_from_image(img)
    return null


static func import_texture_to_pack(pack_id: String, source_path: String, preferred_name: String = "") -> String:
    if pack_id.is_empty() or source_path.strip_edges().is_empty():
        return ""
    var ext := source_path.get_extension().to_lower()
    if ext != "png":
        push_error("UIIo: only PNG import is supported for UI textures")
        return ""
    var src := FileAccess.open(source_path, FileAccess.READ)
    if src == null:
        push_error("UIIo: cannot open import source %s" % source_path)
        return ""
    var bytes := src.get_buffer(src.get_length())
    src.close()
    var target_dir := user_pack_dir(pack_id) + "Assets/UI"
    _ensure_dir(target_dir)
    var base_name := preferred_name.strip_edges()
    if base_name.is_empty():
        base_name = source_path.get_file().get_basename()
    base_name = _sanitize_file_stem(base_name)
    var file_name := base_name + ".png"
    var target_path := target_dir.rstrip("/") + "/" + file_name
    var suffix := 2
    while FileAccess.file_exists(target_path):
        target_path = target_dir.rstrip("/") + "/%s_%d.png" % [base_name, suffix]
        suffix += 1
    var dst := FileAccess.open(target_path, FileAccess.WRITE)
    if dst == null:
        push_error("UIIo: cannot create imported texture %s" % target_path)
        return ""
    dst.store_buffer(bytes)
    dst.close()
    return target_path


static func _list_pngs(dir_path: String) -> Array:
    var d := DirAccess.open(dir_path)
    if d == null:
        return []
    var out: Array = []
    d.list_dir_begin()
    var fn := d.get_next()
    while fn != "":
        if not d.current_is_dir() and fn.to_lower().ends_with(".png"):
            out.append(dir_path.rstrip("/") + "/" + fn)
        fn = d.get_next()
    d.list_dir_end()
    return out


static func _read_json(path: String) -> Dictionary:
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


static func _write_json(path: String, data: Dictionary) -> bool:
    var text := JSON.stringify(data, "\t")
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        push_error("UIIo: cannot open %s for write" % path)
        return false
    f.store_string(text)
    f.close()
    return true


static func _ensure_dir(path: String) -> void:
    DirAccess.make_dir_recursive_absolute(path)


# ─── Screen JSON IO ─────────────────────────────────────────────────────

static func screen_dir(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "UI/screens/"


static func screen_path(pack_id: String, screen_id: String) -> String:
    return screen_dir(pack_id) + screen_id + ".json"


static func load_screen(pack_id: String, screen_id: String) -> Dictionary:
    # Try user layer first, then shipped.
    var user_path := screen_path(pack_id, screen_id)
    var d := _read_json(user_path)
    if not d.is_empty():
        return normalize_screen(screen_id, d, pack_id)
    var shipped_path := shipped_pack_dir(pack_id) + "UI/screens/" + screen_id + ".json"
    return normalize_screen(screen_id, _read_json(shipped_path), pack_id)


static func save_screen(pack_id: String, screen_id: String, data: Dictionary) -> bool:
    var normalized := normalize_screen(screen_id, data, pack_id)
    var check := validate_screen(screen_id, normalized, pack_id)
    var errors: Array = check.get("errors", [])
    var warnings: Array = check.get("warnings", [])
    if not errors.is_empty():
        for issue in errors:
            push_error("UIIo: screen '%s' invalid: %s" % [screen_id, str(issue)])
        return false
    for issue in warnings:
        push_warning("UIIo: screen '%s' warning: %s" % [screen_id, str(issue)])
    _ensure_dir(screen_dir(pack_id))
    return _write_json(screen_path(pack_id, screen_id), normalized)


static func normalize_screen(screen_id: String, data: Dictionary, pack_id: String = "") -> Dictionary:
    if data.is_empty():
        return {}
    var normalized := data.duplicate(true)
    var host_id := UiContract.screen_host_id(screen_id)
    _normalize_screen_element(normalized, screen_id, host_id, pack_id)
    _normalize_screen_layout(normalized, screen_id)
    return normalized


static func _normalize_screen_element(elem: Dictionary, screen_id: String, host_id: String, pack_id: String) -> void:
    _ensure_default_element_properties(elem)
    _normalize_legacy_screen_actions(elem, screen_id, host_id, pack_id)
    var children_v: Variant = elem.get("children", [])
    if typeof(children_v) != TYPE_ARRAY:
        return
    for child_v in (children_v as Array):
        if typeof(child_v) == TYPE_DICTIONARY:
            _normalize_screen_element(child_v as Dictionary, screen_id, host_id, pack_id)


static func _normalize_legacy_screen_actions(elem: Dictionary, screen_id: String, host_id: String, _pack_id: String) -> void:
    if str(elem.get("type", "")) != UITypes.ELEM_BUTTON:
        return
    var props_v: Variant = elem.get("properties", {})
    if typeof(props_v) != TYPE_DICTIONARY:
        return
    var props: Dictionary = props_v
    var eid := str(elem.get("id", ""))
    if screen_id == "main_menu" and eid == "main_menu_settings" \
            and str(props.get("action_id", "")) == "play_sfx" \
            and str(props.get("action_args", "")) == "ui_accept":
        props["action_id"] = "open_settings"
        props["action_args"] = ""
        _replace_legacy_button_label(props, ["PLAY SFX"], "SETTINGS")
    var action_id := str(props.get("action_id", ""))
    if action_id != "open_screen":
        return
    var action_args := str(props.get("action_args", "")).strip_edges()
    if UiContract.host_supports_open_target(host_id, action_args):
        return
    match screen_id:
        "main_menu":
            if eid == "main_menu_settings" and action_args == "inventory":
                props["action_id"] = "open_settings"
                props["action_args"] = ""
                _replace_legacy_button_label(props, ["OPEN INVENTORY", "INVENTORY", "PLAY SFX"], "SETTINGS")
        "pause":
            if eid == "pause_inventory" and action_args == "inventory":
                props["action_id"] = "save_game"
                props["action_args"] = ""
                _replace_legacy_button_label(props, ["OPEN INVENTORY", "INVENTORY"], "SAVE GAME")
            elif eid == "pause_map" and action_args == "map":
                props["action_id"] = "load_game"
                props["action_args"] = ""
                _replace_legacy_button_label(props, ["OPEN MAP", "MAP"], "LOAD")


static func _replace_legacy_button_label(props: Dictionary, old_labels: Array, new_label: String) -> void:
    var current := str(props.get("label", "")).strip_edges()
    if old_labels.has(current.to_upper()):
        props["label"] = new_label


static func _ensure_default_element_properties(elem: Dictionary) -> void:
    var etype := str(elem.get("type", "")).strip_edges()
    if etype.is_empty():
        return
    var defaults_v: Variant = UITypes.default_element(etype).get("properties", {})
    if typeof(defaults_v) != TYPE_DICTIONARY:
        return
    var defaults: Dictionary = defaults_v
    var props_v: Variant = elem.get("properties", {})
    if typeof(props_v) != TYPE_DICTIONARY:
        props_v = {}
        elem["properties"] = props_v
    var props: Dictionary = props_v
    for key_v in defaults.keys():
        var key := str(key_v)
        if not props.has(key):
            props[key] = defaults[key]
    if etype in [UITypes.ELEM_PANEL, UITypes.ELEM_LABEL]:
        props["opacity"] = clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
    match etype:
        UITypes.ELEM_PANEL:
            props["sprite_tint"] = _normalize_hex_color_string(props.get("sprite_tint", "#ffffff"), "#ffffff")
        UITypes.ELEM_BUTTON:
            props["sprite_tint"] = _normalize_hex_color_string(props.get("sprite_tint", "#ffffff"), "#ffffff")
        UITypes.ELEM_ICON:
            props["tint"] = _normalize_hex_color_string(props.get("tint", "#ffffff"), "#ffffff")
        UITypes.ELEM_PROGRESS_BAR:
            props["fill_color"] = _normalize_hex_color_string(props.get("fill_color", "#ff4444"), "#ff4444")
            props["bg_color"] = _normalize_hex_color_string(props.get("bg_color", "#1f2228"), "#1f2228")


static func _normalize_hex_color_string(value: Variant, fallback: String) -> String:
    var text := str(value).strip_edges().to_lower()
    var fallback_text := str(fallback).strip_edges().to_lower()
    if text.is_empty():
        return fallback_text
    if not text.begins_with("#"):
        text = "#" + text
    var digits := text.substr(1)
    if digits.is_empty():
        return fallback_text
    if [1, 2, 5, 7].has(digits.length()):
        var pad := digits.substr(digits.length() - 1, 1)
        while not [3, 4, 6, 8].has(digits.length()):
            digits += pad
    if not [3, 4, 6, 8].has(digits.length()):
        return fallback_text
    for i in range(digits.length()):
        var ch := digits.unicode_at(i)
        var is_hex := (ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102)
        if not is_hex:
            return fallback_text
    return "#" + digits


static func _normalize_screen_layout(screen_data: Dictionary, screen_id: String) -> void:
    match screen_id:
        "dialogue_box":
            _ensure_dialogue_box_layout(screen_data)
        "pause":
            _ensure_pause_settings_layout(screen_data)


static func _ensure_pause_settings_layout(screen_data: Dictionary) -> void:
    var children_v: Variant = screen_data.get("children", [])
    if typeof(children_v) != TYPE_ARRAY:
        return
    var children := children_v as Array
    var has_settings := false
    var has_resume := false
    var has_quit := false
    var has_stock_secondary := false
    var quit_elem: Dictionary = {}
    var note_elem: Dictionary = {}
    for child_v in children:
        if typeof(child_v) != TYPE_DICTIONARY:
            continue
        var child: Dictionary = child_v
        match str(child.get("id", "")):
            "pause_settings":
                has_settings = true
            "pause_resume":
                has_resume = true
            "pause_quit":
                has_quit = true
                quit_elem = child
            "pause_note":
                note_elem = child
            "pause_save", "pause_load", "pause_inventory", "pause_map":
                has_stock_secondary = true
    if has_settings:
        return
    if not has_resume or not has_quit or not has_stock_secondary:
        return
    if not quit_elem.is_empty():
        var quit_rect: Variant = quit_elem.get("rect", {})
        if typeof(quit_rect) == TYPE_DICTIONARY:
            (quit_rect as Dictionary)["x"] = 302
            (quit_rect as Dictionary)["y"] = 88
            (quit_rect as Dictionary)["w"] = 162
    if not note_elem.is_empty():
        var note_rect: Variant = note_elem.get("rect", {})
        if typeof(note_rect) == TYPE_DICTIONARY:
            (note_rect as Dictionary)["y"] = 132
            (note_rect as Dictionary)["w"] = 446
    children.append(_button("pause_settings", 150, 88, 140, 28, "SETTINGS", "open_settings"))


static func _ensure_dialogue_box_layout(screen_data: Dictionary) -> void:
    var rect_v: Variant = screen_data.get("rect", {})
    if typeof(rect_v) == TYPE_DICTIONARY:
        var root_rect: Dictionary = rect_v
        var root_h := float(root_rect.get("h", 272.0))
        if absf(root_h - 272.0) <= 1.0:
            root_rect["w"] = 480.0
            root_rect["h"] = 156.0
    var children_v: Variant = screen_data.get("children", [])
    if typeof(children_v) != TYPE_ARRAY:
        return
    for child_v in (children_v as Array):
        if typeof(child_v) != TYPE_DICTIONARY:
            continue
        var child: Dictionary = child_v
        var eid := str(child.get("id", ""))
        var child_rect_v: Variant = child.get("rect", {})
        if typeof(child_rect_v) != TYPE_DICTIONARY:
            child_rect_v = {}
            child["rect"] = child_rect_v
        var child_rect: Dictionary = child_rect_v
        var props_v: Variant = child.get("properties", {})
        if typeof(props_v) != TYPE_DICTIONARY:
            props_v = {}
            child["properties"] = props_v
        var props: Dictionary = props_v
        match eid:
            "dialogue_speaker":
                var speaker_legacy := float(child_rect.get("w", 200.0)) <= 200.0 and float(child_rect.get("h", 18.0)) <= 18.0
                if speaker_legacy:
                    child_rect["x"] = 14.0
                    child_rect["y"] = 10.0
                    child_rect["w"] = 452.0
                    child_rect["h"] = 18.0
                props["opacity"] = clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
            "dialogue_text":
                var text_legacy := not bool(props.get("wrap", false)) \
                    and float(child_rect.get("w", 200.0)) <= 220.0 \
                    and float(child_rect.get("h", 20.0)) <= 24.0
                if text_legacy:
                    child_rect["x"] = 14.0
                    child_rect["y"] = 32.0
                    child_rect["w"] = 452.0
                    child_rect["h"] = 52.0
                props["wrap"] = true
                props["opacity"] = clampf(float(props.get("opacity", 1.0)), 0.0, 1.0)
            "dialogue_choices":
                var choices_legacy := (str(props.get("item_action_arg_key", "__index__")) == "__index__" \
                    or not bool(props.get("item_wrap", false))) \
                    and float(child_rect.get("w", 200.0)) <= 220.0 \
                    and float(child_rect.get("h", 28.0)) <= 32.0
                if choices_legacy:
                    child_rect["x"] = 14.0
                    child_rect["y"] = 90.0
                    child_rect["w"] = 452.0
                    child_rect["h"] = 52.0
                props["item_wrap"] = true
                props["item_min_height"] = maxf(float(props.get("item_min_height", 20.0)), 20.0)
                props["spacing"] = maxf(float(props.get("spacing", 6.0)), 6.0)
                props["item_action_arg_key"] = "choice_index"


static func list_screens(pack_id: String) -> Array:
    var seen: Dictionary = {}
    var out: Array = []
    for base in [screen_dir(pack_id), shipped_pack_dir(pack_id) + "UI/screens/"]:
        var d := DirAccess.open(base)
        if d == null:
            continue
        d.list_dir_begin()
        var fn := d.get_next()
        while fn != "":
            if not d.current_is_dir() and fn.ends_with(".json"):
                var sid := fn.get_basename()
                if not seen.has(sid):
                    seen[sid] = true
                    out.append(sid)
            fn = d.get_next()
        d.list_dir_end()
    out.sort()
    return out


static func screen_exists(pack_id: String, screen_id: String) -> bool:
    return FileAccess.file_exists(screen_path(pack_id, screen_id)) \
        or FileAccess.file_exists(shipped_pack_dir(pack_id) + "UI/screens/" + screen_id + ".json")


static func ensure_stock_screens(pack_id: String) -> void:
    if pack_id.is_empty():
        return
    _ensure_dir(screen_dir(pack_id))
    for screen_id in UITypes.SCREEN_IDS:
        if screen_exists(pack_id, screen_id):
            continue
        var data := default_stock_screen(screen_id)
        if not data.is_empty():
            _write_json(screen_path(pack_id, screen_id), data)
    var input_path := input_map_path(pack_id)
    if not FileAccess.file_exists(input_path):
        save_input_map(pack_id, load_input_map(""))


static func default_stock_screen(screen_id: String) -> Dictionary:
    match screen_id:
        "hud_space":
            return _stock_space_hud_screen()
        "hud_mv":
            return _stock_mv_hud_screen()
        "main_menu":
            return _stock_main_menu_screen()
        "pause":
            return _stock_pause_screen()
        "inventory":
            return _stock_inventory_screen()
        "shop":
            return _stock_shop_screen()
        "map":
            return _stock_map_screen()
        "dialogue_box":
            return _stock_dialogue_box_screen()
        "hud":
            return _stock_hud_screen()
        "game_over":
            return _stock_game_over_screen()
        "boss_intro":
            return _stock_boss_intro_screen()
    return {}


static func validate_screen(screen_id: String, data: Dictionary, pack_id: String = "") -> Dictionary:
    var errors: Array = []
    var warnings: Array = []
    if data.is_empty():
        errors.append("screen data is empty")
        return {"errors": errors, "warnings": warnings}
    if not UiContract.is_known_screen(screen_id):
        errors.append("screen id '%s' is not in UiContract.SCREEN_DEFS" % screen_id)
    var ids_seen: Dictionary = {}
    _validate_element(data, screen_id, screen_id, ids_seen, errors, warnings, pack_id)
    if not UiContract.screen_mount_is_supported(screen_id):
        errors.append("runtime mounting is not implemented for authored screen '%s' yet" % screen_id)
    return {"errors": errors, "warnings": warnings}


static func _validate_element(elem: Dictionary, screen_id: String, path: String,
        ids_seen: Dictionary, errors: Array, warnings: Array, pack_id: String) -> void:
    var etype := str(elem.get("type", ""))
    var eid := str(elem.get("id", ""))
    if etype.is_empty():
        errors.append("%s: missing element type" % path)
    elif not UITypes.ELEMENT_TYPES.has(etype):
        errors.append("%s: unknown element type '%s'" % [path, etype])
    if eid.is_empty():
        errors.append("%s: missing element id" % path)
    elif ids_seen.has(eid):
        errors.append("%s: duplicate element id '%s'" % [path, eid])
    else:
        ids_seen[eid] = true

    var rect_v: Variant = elem.get("rect", null)
    if typeof(rect_v) != TYPE_DICTIONARY:
        errors.append("%s[%s]: missing rect dictionary" % [path, eid])
    else:
        var rect: Dictionary = rect_v
        for key in ["x", "y", "w", "h"]:
            if not rect.has(key):
                errors.append("%s[%s]: rect missing '%s'" % [path, eid, key])
        if rect.has("w") and float(rect.get("w", 0)) <= 0.0:
            errors.append("%s[%s]: rect width must be > 0" % [path, eid])
        if rect.has("h") and float(rect.get("h", 0)) <= 0.0:
            errors.append("%s[%s]: rect height must be > 0" % [path, eid])

    var anchor := str(elem.get("anchor", ""))
    if anchor != "" and not UITypes.ANCHOR_OPTIONS.has(anchor):
        errors.append("%s[%s]: unknown anchor '%s'" % [path, eid, anchor])

    var props_v: Variant = elem.get("properties", {})
    if typeof(props_v) != TYPE_DICTIONARY:
        errors.append("%s[%s]: properties must be a dictionary" % [path, eid])
    else:
        _validate_properties(screen_id, etype, eid, props_v, errors, warnings, pack_id)

    var children_v: Variant = elem.get("children", [])
    if typeof(children_v) != TYPE_ARRAY:
        errors.append("%s[%s]: children must be an array" % [path, eid])
        return
    for i in (children_v as Array).size():
        var child_v: Variant = (children_v as Array)[i]
        if typeof(child_v) != TYPE_DICTIONARY:
            errors.append("%s[%s].children[%d]: child is not a dictionary" % [path, eid, i])
            continue
        _validate_element(child_v, screen_id, "%s[%s].children[%d]" % [path, eid, i], ids_seen, errors, warnings, pack_id)


static func _validate_properties(screen_id: String, etype: String, eid: String,
        props_v: Variant, errors: Array, warnings: Array, pack_id: String) -> void:
    var props: Dictionary = props_v
    var host_id := UiContract.screen_host_id(screen_id)
    match etype:
        UITypes.ELEM_LABEL:
            _validate_binding(str(props.get("bind_var", "")), "%s.bind_var" % eid, errors, warnings)
        UITypes.ELEM_PROGRESS_BAR:
            _validate_binding(str(props.get("bind_current", "")), "%s.bind_current" % eid, errors, warnings)
            _validate_binding(str(props.get("bind_max", "")), "%s.bind_max" % eid, errors, warnings)
        UITypes.ELEM_ICON:
            _validate_binding(str(props.get("bind_sprite", "")), "%s.bind_sprite" % eid, errors, warnings)
        UITypes.ELEM_LIST, UITypes.ELEM_GRID:
            _validate_binding(str(props.get("bind_array", "")), "%s.bind_array" % eid, errors, warnings)
            var item_action_id := str(props.get("item_action_id", ""))
            if item_action_id != "" and not UiContract.is_known_action(item_action_id):
                errors.append("%s.item_action_id '%s' is unknown" % [eid, item_action_id])
            elif item_action_id != "" and not UiContract.host_supports_action(host_id, item_action_id):
                errors.append("%s.item_action_id '%s' is not supported by host '%s'" % [eid, item_action_id, host_id])
            if item_action_id != "":
                _validate_action_args(screen_id, host_id, item_action_id,
                    str(props.get("item_action_arg_key", "")),
                    "%s.item_action_id" % eid, errors, warnings, pack_id, true)
        UITypes.ELEM_TAB_BAR:
            pass
        UITypes.ELEM_BUTTON:
            var action_id := str(props.get("action_id", ""))
            if action_id != "" and not UiContract.is_known_action(action_id):
                errors.append("%s.action_id '%s' is unknown" % [eid, action_id])
            elif action_id != "" and not UiContract.host_supports_action(host_id, action_id):
                errors.append("%s.action_id '%s' is not supported by host '%s'" % [eid, action_id, host_id])
            if action_id != "":
                _validate_action_args(screen_id, host_id, action_id,
                    str(props.get("action_args", "")),
                    "%s.action_id" % eid, errors, warnings, pack_id)
            _validate_binding(str(props.get("enabled_condition", "")), "%s.enabled_condition" % eid, errors, warnings)
        UITypes.ELEM_CONDITIONAL:
            if str(props.get("condition_type", "")) == "binding_truthy":
                _validate_binding(str(props.get("condition", "")), "%s.condition" % eid, errors, warnings)


static func _validate_binding(binding: String, path: String, errors: Array, warnings: Array) -> void:
    if binding == "":
        return
    if not UiContract.is_known_binding(binding):
        errors.append("%s '%s' is not in the known binding vocabulary" % [path, binding])
        return
    if not UiContract.binding_has_runtime_support(binding):
        warnings.append("%s '%s' is exposed by the editor but not resolved by the current runtime data source yet" % [path, binding])


static func _validate_action_args(screen_id: String, host_id: String, action_id: String,
        action_args: String, path: String, errors: Array, warnings: Array,
        pack_id: String, item_action: bool = false) -> void:
    var rule: Dictionary = UiContract.action_arg_rule(action_id)
    var trimmed := action_args.strip_edges()
    if bool(rule.get("required", false)) and trimmed.is_empty():
        errors.append("%s '%s' requires action args" % [path, action_id])
        return
    if item_action and action_id == "choose_dialogue":
        if trimmed not in ["__index__", "choice_index"]:
            errors.append("%s '%s' must use item_action_arg_key '__index__' or 'choice_index'" % [path, action_id])
        return
    if bool(rule.get("integer", false)) and not trimmed.is_empty() and not trimmed.is_valid_int():
        errors.append("%s '%s' requires an integer action arg" % [path, action_id])
    if action_id == "open_screen":
        if not UiContract.host_supports_open_target(host_id, trimmed):
            errors.append("%s open_screen target '%s' is not supported by host '%s'" % [path, trimmed, host_id])
            return
        if trimmed in ["cinematic", "boss_intro"]:
            return
        if trimmed.begins_with("shop:"):
            var shop_id := trimmed.substr("shop:".length()).strip_edges()
            if shop_id.is_empty():
                errors.append("%s open_screen target '%s' is missing a shop id" % [path, trimmed])
            elif pack_id != "" and not _shop_exists(pack_id, shop_id):
                errors.append("%s open_screen target references missing shop '%s'" % [path, shop_id])
            return
        if not trimmed.is_empty() and UiContract.is_known_screen(trimmed) and pack_id != "" and trimmed != screen_id and not screen_exists(pack_id, trimmed):
            warnings.append("%s open_screen target '%s' is not authored in pack '%s' yet" % [path, trimmed, pack_id])
    elif action_id == "fire_event" and trimmed.contains(" "):
        warnings.append("%s fire_event '%s' contains whitespace" % [path, trimmed])
    elif action_id == "choose_dialogue" and not item_action and trimmed.is_empty():
        errors.append("%s choose_dialogue requires a choice index" % path)


static func _shop_exists(pack_id: String, shop_id: String) -> bool:
    if pack_id.is_empty() or shop_id.is_empty():
        return false
    var file_name := shop_id
    if not file_name.ends_with(".json"):
        file_name += ".json"
    return FileAccess.file_exists(user_pack_dir(pack_id) + "Shops/" + file_name) \
        or FileAccess.file_exists(shipped_pack_dir(pack_id) + "Shops/" + file_name)


static func _sanitize_file_stem(name: String) -> String:
    var out := ""
    for i in range(name.length()):
        var ch := name.unicode_at(i)
        var keep := (ch >= 48 and ch <= 57) or (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or ch == 95 or ch == 45
        out += name.substr(i, 1) if keep else "_"
    out = out.strip_edges()
    while out.begins_with("_"):
        out = out.substr(1)
    while out.ends_with("_"):
        out = out.substr(0, out.length() - 1)
    return out if not out.is_empty() else "ui_texture"


static func _base_screen(screen_id: String, width: int = 480, height: int = 272) -> Dictionary:
    return {
        "type": "panel",
        "id": "%s_root" % screen_id,
        "rect": {"x": 0, "y": 0, "w": width, "h": height},
        "anchor": "top_left",
        "anchor_offset": {"x": 0, "y": 0},
        "properties": {
            "variant": "dark",
            "opacity": 1.0,
            "padding": 8,
            "scroll": "none",
            "sprite_source": "",
            "sprite_mode": "9slice",
            "sprite_slice_x": 0,
            "sprite_slice_y": 0,
            "sprite_tint": "#ffffff",
            "tab_id": "",
            "tab_group": "default",
        },
        "children": [],
    }


static func _elem(id: String, type: String, rect: Dictionary, props: Dictionary, children: Array = []) -> Dictionary:
    return {
        "type": type,
        "id": id,
        "rect": rect,
        "anchor": "top_left",
        "anchor_offset": {"x": 0, "y": 0},
        "properties": props,
        "children": children,
    }


static func _label(id: String, x: int, y: int, w: int, h: int, text: String, role: String = "body", bind_var: String = "") -> Dictionary:
    return _elem(id, "label", {"x": x, "y": y, "w": w, "h": h}, {
        "text_role": role,
        "opacity": 1.0,
        "static_text": text,
        "bind_var": bind_var,
        "format": "{value}",
        "decimal_places": 0,
        "alignment": "left",
        "wrap": false,
        "tab_id": "",
        "tab_group": "default",
    })


static func _button(id: String, x: int, y: int, w: int, h: int, label: String, action_id: String, action_args: String = "") -> Dictionary:
    return _elem(id, "button", {"x": x, "y": y, "w": w, "h": h}, {
        "label": label,
        "action_id": action_id,
        "action_args": action_args,
        "enabled_condition": "",
        "sprite_normal": "",
        "sprite_hover": "",
        "sprite_pressed": "",
        "sprite_tint": "#ffffff",
        "show_label": true,
        "tab_id": "",
        "tab_group": "default",
    })


static func _grid(id: String, x: int, y: int, w: int, h: int, bind_array: String, columns: int = 4, slot_size: int = 32, item_action_id: String = "", item_action_arg_key: String = "") -> Dictionary:
    return _elem(id, "grid", {"x": x, "y": y, "w": w, "h": h}, {
        "bind_array": bind_array,
        "slot_template": {},
        "columns": columns,
        "slot_size": slot_size,
        "empty_slot_style": "dim",
        "item_action_id": item_action_id,
        "item_action_arg_key": item_action_arg_key,
        "tab_id": "",
        "tab_group": "default",
    })


static func _list(id: String, x: int, y: int, w: int, h: int, bind_array: String, item_action_id: String = "", item_action_arg_key: String = "") -> Dictionary:
    return _elem(id, "list", {"x": x, "y": y, "w": w, "h": h}, {
        "bind_array": bind_array,
        "item_template": {},
        "spacing": 4,
        "max_visible": 10,
        "item_action_id": item_action_id,
        "item_action_arg_key": item_action_arg_key,
        "tab_id": "",
        "tab_group": "default",
    })


static func _progress(id: String, x: int, y: int, w: int, h: int, current_bind: String, max_bind: String, fill_color: String = "#ff4444") -> Dictionary:
    return _elem(id, "progress_bar", {"x": x, "y": y, "w": w, "h": h}, {
        "fill_color": fill_color,
        "bg_color": "#1f2228",
        "bind_current": current_bind,
        "bind_max": max_bind,
        "direction": "left_to_right",
        "show_label": true,
        "animate_fill": true,
        "pulse_on_low": true,
        "pulse_threshold": 0.25,
        "tab_id": "",
        "tab_group": "default",
    })


static func _stock_main_menu_screen() -> Dictionary:
    var root := _base_screen("main_menu")
    root["children"] = [
        _label("main_menu_title", 118, 24, 240, 28, "NEW PACK MENU", "title"),
        _label("main_menu_hint", 88, 54, 308, 18, "Edit these buttons, replace the art, then wire your own pack flow.", "dim"),
        _button("main_menu_new_game", 154, 92, 172, 32, "NEW GAME", "new_game"),
        _button("main_menu_load", 154, 132, 172, 32, "LOAD SLOT 1", "load_slot", "1"),
        _button("main_menu_settings", 154, 172, 172, 32, "SETTINGS", "open_settings"),
        _button("main_menu_quit", 154, 212, 172, 32, "QUIT TO LAUNCHER", "quit_to_menu"),
    ]
    return root


static func _stock_pause_screen() -> Dictionary:
    var root := _base_screen("pause")
    root["children"] = [
        _label("pause_title", 18, 16, 200, 24, "PAUSED", "title"),
        _button("pause_resume", 18, 50, 120, 28, "RESUME", "resume"),
        _button("pause_save", 150, 50, 140, 28, "SAVE GAME", "save_game"),
        _button("pause_load", 302, 50, 100, 28, "LOAD", "load_game"),
        _button("pause_settings", 150, 88, 140, 28, "SETTINGS", "open_settings"),
        _button("pause_quit", 302, 88, 162, 28, "QUIT TO MENU", "quit_to_menu"),
        _label("pause_note", 18, 132, 446, 18, "Stock pause screen. Swap art, relabel actions, or add trigger events from buttons.", "dim"),
    ]
    return root


static func _stock_inventory_screen() -> Dictionary:
    var root := _base_screen("inventory")
    root["children"] = [
        _label("inventory_title", 16, 12, 200, 24, "INVENTORY", "title"),
        _label("inventory_help", 16, 36, 448, 18, "This stock screen is data-bound. Replace labels/art and wire specific buttons as you author items.", "dim"),
        _label("inventory_items_lbl", 16, 64, 160, 18, "Items", "body"),
        _grid("inventory_items", 16, 84, 180, 140, "inventory.items", 4, 36),
        _label("inventory_equip_lbl", 214, 64, 120, 18, "Equipment", "body"),
        _list("inventory_equipment", 214, 84, 120, 140, "inventory.equipment"),
        _label("inventory_abilities_lbl", 348, 64, 120, 18, "Abilities", "body"),
        _list("inventory_abilities", 348, 84, 116, 140, "inventory.abilities"),
        _button("inventory_close", 16, 234, 120, 26, "CLOSE", "close_screen"),
        _button("inventory_fire_event", 148, 234, 180, 26, "FIRE UI EVENT", "fire_event", "ui_button"),
    ]
    return root


static func _stock_shop_screen() -> Dictionary:
    var root := _base_screen("shop")
    root["children"] = [
        _label("shop_title", 16, 12, 160, 24, "SHOP", "title"),
        _label("shop_gold", 300, 14, 164, 18, "", "success", "game_var.gold"),
        _label("shop_hint", 16, 36, 448, 18, "Hover an offer for details. Click an affordable row to buy it.", "dim"),
        _label("shop_message", 16, 56, 448, 18, "", "body", "shop.message"),
        _label("shop_vendor_lbl", 16, 82, 180, 18, "Vendor stock", "body"),
        _list("shop_vendor_items", 16, 102, 244, 112, "shop.items", "buy_item", "stock_id"),
        _label("shop_player_lbl", 278, 82, 180, 18, "Player inventory", "body"),
        _list("shop_player_items", 278, 102, 186, 112, "inventory.items", "sell_item", "key"),
        _label("shop_barter_lbl", 16, 224, 180, 18, "Barter offer / notes", "body"),
        _label("shop_barter_note", 16, 242, 300, 18, "Shop items use authored item effects, prices, and trigger events.", "dim"),
        _button("shop_close", 356, 232, 108, 28, "CLOSE", "close_screen"),
    ]
    root["children"][1]["properties"]["format"] = "Gold: {value}"
    root["children"][5]["properties"]["item_wrap"] = true
    root["children"][5]["properties"]["item_min_height"] = 26
    root["children"][7]["properties"]["item_wrap"] = true
    root["children"][7]["properties"]["item_min_height"] = 22
    return root


static func _stock_map_screen() -> Dictionary:
    var root := _base_screen("map")
    root["children"] = [
        _label("map_title", 16, 14, 140, 24, "MAP", "title"),
        _list("map_rooms", 16, 48, 448, 176, "map.rooms"),
        _button("map_close", 16, 232, 110, 28, "CLOSE", "close_screen"),
    ]
    return root


static func _stock_dialogue_box_screen() -> Dictionary:
    var root := _base_screen("dialogue_box", 480, 156)
    var speaker := _label("dialogue_speaker", 14, 10, 452, 18, "", "title", "dialogue.speaker")
    var text := _label("dialogue_text", 14, 32, 452, 52, "", "body", "dialogue.text")
    text["properties"]["wrap"] = true
    var choices := _list("dialogue_choices", 14, 90, 452, 52, "dialogue.choices", "choose_dialogue", "choice_index")
    choices["properties"]["item_wrap"] = true
    choices["properties"]["item_min_height"] = 20
    choices["properties"]["spacing"] = 6
    root["children"] = [
        speaker,
        text,
        choices,
    ]
    return root


static func _stock_space_hud_screen() -> Dictionary:
    var root := _base_screen("hud_space")
    root["rect"]["h"] = 71
    root["children"] = [
        _label("hud_space_hull_label", 12, 10, 80, 16, "HULL", "body"),
        _progress("hud_space_hull_bar", 54, 10, 136, 14, "player.health", "player.max_health", "#5cd96a"),
        _label("hud_space_shield_label", 12, 30, 80, 16, "SHD", "body"),
        _progress("hud_space_shield_bar", 54, 30, 136, 14, "player.shields", "player.max_shields", "#4f9cff"),
        _label("hud_space_system", 314, 10, 152, 16, "", "dim", "gamemanager.current_system"),
        _label("hud_space_fuel", 314, 30, 152, 16, "Fuel {value}", "body", "gamemanager.fuel"),
    ]
    return root


static func _make_stock_mv_hud_screen(screen_id: String) -> Dictionary:
    var root := _base_screen(screen_id)
    root["rect"]["h"] = 71
    root["children"] = [
        _label("hud_mv_hp_label", 12, 10, 52, 16, "", "body", "player.hp"),
        _label("hud_mv_hp_max", 62, 10, 42, 16, "", "body", "player.max_hp"),
        _progress("hud_mv_hp_bar", 108, 10, 86, 14, "player.hp", "player.max_hp", "#d85353"),
        _label("hud_mv_weapon_label", 214, 10, 100, 16, "", "body", "current_weapon.name"),
        _label("hud_mv_room_label", 326, 10, 140, 16, "", "dim", "room.name"),
        _label("hud_mv_gold", 214, 30, 100, 16, "", "success", "game_var.gold"),
        _label("hud_mv_missiles", 326, 30, 88, 16, "", "body", "game_var.ammo_missile"),
        _label("hud_mv_missile_max", 412, 30, 54, 16, "", "body", "game_var.max_ammo_missile"),
        _label("hud_mv_quest_title", 12, 30, 190, 16, "", "body", "quest.current.title"),
        _label("hud_mv_quest_stage", 12, 48, 210, 16, "", "dim", "quest.current.stage_title"),
    ]
    root["children"][0]["properties"]["format"] = "E {value}/"
    root["children"][1]["properties"]["format"] = "{value}"
    root["children"][5]["properties"]["format"] = "Gold: {value}"
    root["children"][6]["properties"]["format"] = "Missiles: {value}/"
    root["children"][7]["properties"]["format"] = "{value}"
    return root


static func _stock_hud_screen() -> Dictionary:
    return _make_stock_mv_hud_screen("hud")


static func _stock_mv_hud_screen() -> Dictionary:
    return _make_stock_mv_hud_screen("hud_mv")


static func _stock_game_over_screen() -> Dictionary:
    var root := _base_screen("game_over")
    root["children"] = [
        _label("game_over_title", 150, 62, 200, 24, "GAME OVER", "title"),
        _button("game_over_retry", 152, 112, 172, 30, "LOAD SLOT 1", "load_slot", "1"),
        _button("game_over_menu", 152, 152, 172, 30, "QUIT TO MENU", "quit_to_menu"),
    ]
    return root


static func _stock_boss_intro_screen() -> Dictionary:
    var root := _base_screen("boss_intro", 480, 120)
    root["children"] = [
        _label("boss_intro_title", 32, 26, 416, 24, "CINEMATIC", "title"),
        _label("boss_intro_subtitle", 32, 56, 416, 18, "Use this screen for letterboxed scenes, title cards, or dialogue-free moments.", "dim"),
        _button("boss_intro_close", 182, 84, 116, 24, "CONTINUE", "close_screen"),
    ]
    return root


# ─── Input map IO ───────────────────────────────────────────────────────

static func input_map_path(pack_id: String) -> String:
    return user_pack_dir(pack_id) + "UI/input_map.json"


static func load_input_map(pack_id: String) -> Dictionary:
    var d := _read_json(input_map_path(pack_id))
    if not d.is_empty():
        return d
    var shipped := _read_json(shipped_pack_dir(pack_id) + "UI/input_map.json")
    if not shipped.is_empty():
        return shipped
    # Default mapping
    return {
        "escape_mv": "inventory",
        "escape_space": "pause",
        "map_key": "map",
        "interact_npc": "dialogue_box",
        "player_died": "game_over",
        "game_start": "main_menu",
    }


static func save_input_map(pack_id: String, data: Dictionary) -> bool:
    _ensure_dir(user_pack_dir(pack_id) + "UI")
    return _write_json(input_map_path(pack_id), data)

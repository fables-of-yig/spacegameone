extends Control

const EntIO = preload("res://Space/scripts/editor/ent/ent_io.gd")
const EntTypes = preload("res://Space/scripts/editor/ent/ent_types.gd")

const BehIO = preload("res://Space/scripts/editor/beh/beh_io.gd")

# Entity sprite editor main controller. Owns the entities.json tree for
# the active pack, the currently-selected entity, and the cached sprite
# textures. Child panels:
#   ent_topbar.gd      — pack label + ADD / SAVE / CLOSE buttons
#   ent_list_panel.gd  — left sidebar: entity list with rename/delete
#   ent_detail_panel.gd — right pane: id/name/category/description/scene/sprite_set
#
# Pass 2a ships the registry CRUD layer only. Pass 2b will add a center
# sprite-set browser + PNG preview. Pass 2c will add per-animation
# metadata (poses.json) and animation playback.

signal closed

var pack_id: String = ""
var entities_data: Dictionary = {"entities": []}
var selected_entity_id: String = ""
var dirty: bool = false

# Cache of known behavior ids in this pack; used by ent_detail_panel to
# mark unresolved behavior bindings. Refreshed on open and after the
# behavior picker returns (so edits there flow back without an editor
# reopen).
var _known_behavior_ids: Dictionary = {}

# Pose metadata cache keyed by sprite_set_rel. Each value is the full
# poses.json dict (`{"poses": {filename: {frames, fps, loop_from, ...}}}`).
# Entries are populated lazily the first time a sprite set is inspected,
# and written back to user://Packs/<pack>/<set>/poses.json when dirty.
var _poses_cache: Dictionary = {}
var _poses_dirty: Dictionary = {}

var topbar: Control = null
var list_panel: Control = null
var detail_panel: Control = null
var sprite_panel: Control = null
var text_modal: Control = null
var set_picker: Control = null
var behavior_picker: Control = null
var file_dialog: FileDialog = null
var import_conflict_modal: Control = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _undo: RefCounted = null

var _skip_close_frame: bool = true
var _modal_callback: Callable = Callable()
var _importing: bool = false
var _pending_import_files: PackedStringArray = PackedStringArray()
var _pending_import_set_rel: String = ""
var _pending_import_fresh: Array = []
var _pending_import_overwrite: Array = []

const TOPBAR_H: float = 64.0
const SIDEBAR_W: float = 280.0
const DETAIL_W: float = 380.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    _build_layout.call_deferred()


func _build_layout() -> void:
    topbar = Control.new()
    topbar.set_script(preload("res://Space/scripts/editor/ent/ent_topbar.gd"))
    topbar.editor = self
    add_child(topbar)

    list_panel = Control.new()
    list_panel.set_script(preload("res://Space/scripts/editor/ent/ent_list_panel.gd"))
    list_panel.editor = self
    add_child(list_panel)

    detail_panel = Control.new()
    detail_panel.set_script(preload("res://Space/scripts/editor/ent/ent_detail_panel.gd"))
    detail_panel.editor = self
    add_child(detail_panel)

    sprite_panel = Control.new()
    sprite_panel.set_script(preload("res://Space/scripts/editor/ent/ent_sprite_panel.gd"))
    sprite_panel.editor = self
    add_child(sprite_panel)

    set_picker = Control.new()
    set_picker.set_script(preload("res://Space/scripts/editor/ent/ent_set_picker.gd"))
    set_picker.editor = self
    set_picker.visible = false
    add_child(set_picker)
    set_picker.picked.connect(_on_set_picked)
    set_picker.import_requested.connect(_on_set_picker_import_requested)

    file_dialog = FileDialog.new()
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    file_dialog.use_native_dialog = true
    file_dialog.title = "Import sprite PNGs"
    file_dialog.add_filter("*.png", "PNG Files")
    file_dialog.files_selected.connect(_on_import_files_selected)
    file_dialog.canceled.connect(_on_import_cancelled)
    add_child(file_dialog)

    import_conflict_modal = Control.new()
    import_conflict_modal.set_script(preload("res://Space/scripts/editor/import_conflict_modal.gd"))
    import_conflict_modal.visible = false
    add_child(import_conflict_modal)
    import_conflict_modal.chose.connect(_on_import_conflict_chose)

    behavior_picker = Control.new()
    behavior_picker.set_script(preload("res://Space/scripts/editor/ent/ent_behavior_picker.gd"))
    behavior_picker.editor = self
    behavior_picker.visible = false
    add_child(behavior_picker)
    behavior_picker.picked.connect(_on_behavior_picked)

    text_modal = Control.new()
    text_modal.set_script(preload("res://Space/scripts/editor/env/env_text_modal.gd"))
    text_modal.visible = false
    add_child(text_modal)
    text_modal.submitted.connect(_on_modal_submit)
    text_modal.cancelled.connect(_on_modal_cancel)

    _tutorial_btn = Button.new()
    _tutorial_btn.text = "TUTORIAL"
    _tutorial_btn.pressed.connect(_on_tutorial_pressed)
    add_child(_tutorial_btn)

    _tutorial_overlay = Control.new()
    _tutorial_overlay.set_script(preload("res://Space/scripts/editor/editor_tutorial.gd"))
    _tutorial_overlay.visible = false
    add_child(_tutorial_overlay)

    _layout_children()
    _undo = EditorUndo.new(_capture_state, _apply_state)


func _capture_state() -> Dictionary:
    return {
        "entities_data": entities_data.duplicate(true),
        "poses_cache": _poses_cache.duplicate(true),
        "poses_dirty": _poses_dirty.duplicate(true),
        "selected_entity_id": selected_entity_id,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var ed_v: Variant = snap.get("entities_data", null)
    if typeof(ed_v) == TYPE_DICTIONARY:
        entities_data = ed_v
    var pc_v: Variant = snap.get("poses_cache", null)
    if typeof(pc_v) == TYPE_DICTIONARY:
        _poses_cache = pc_v
    var pd_v: Variant = snap.get("poses_dirty", null)
    if typeof(pd_v) == TYPE_DICTIONARY:
        _poses_dirty = pd_v
    selected_entity_id = str(snap.get("selected_entity_id", ""))
    dirty = bool(snap.get("dirty", false))


func _notification(what):
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _layout_children() -> void:
    if topbar == null:
        return
    var vw := size.x
    var vh := size.y
    topbar.position = Vector2.ZERO
    topbar.size = Vector2(vw, TOPBAR_H)
    list_panel.position = Vector2(0, TOPBAR_H)
    list_panel.size = Vector2(SIDEBAR_W, vh - TOPBAR_H)
    detail_panel.position = Vector2(SIDEBAR_W, TOPBAR_H)
    detail_panel.size = Vector2(DETAIL_W, vh - TOPBAR_H)
    if sprite_panel != null:
        sprite_panel.position = Vector2(SIDEBAR_W + DETAIL_W, TOPBAR_H)
        sprite_panel.size = Vector2(vw - SIDEBAR_W - DETAIL_W, vh - TOPBAR_H)
    if set_picker != null:
        set_picker.position = Vector2.ZERO
        set_picker.size = Vector2(vw, vh)
    if behavior_picker != null:
        behavior_picker.position = Vector2.ZERO
        behavior_picker.size = Vector2(vw, vh)
    if text_modal != null:
        text_modal.position = Vector2.ZERO
        text_modal.size = Vector2(vw, vh)
    if import_conflict_modal != null:
        import_conflict_modal.position = Vector2.ZERO
        import_conflict_modal.size = Vector2(vw, vh)
    if _tutorial_btn != null:
        _tutorial_btn.position = Vector2(SIDEBAR_W + DETAIL_W + 16, TOPBAR_H + 12)
        _tutorial_btn.size = Vector2(100, 32)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)


func open_editor(p_pack_id: String = ""):
    pack_id = p_pack_id
    visible = true
    _skip_close_frame = true

    entities_data = EntIO.load_or_init(pack_id)
    var arr: Array = entities_data.get("entities", [])
    if arr.is_empty():
        selected_entity_id = ""
    else:
        var first: Variant = arr[0]
        if typeof(first) == TYPE_DICTIONARY:
            selected_entity_id = str((first as Dictionary).get("id", ""))
    dirty = false
    _poses_cache.clear()
    _poses_dirty.clear()
    refresh_known_behaviors()

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
    if text_modal != null and text_modal.visible:
        return
    if set_picker != null and set_picker.visible:
        return
    if behavior_picker != null and behavior_picker.visible:
        return
    if file_dialog != null and file_dialog.visible:
        return
    if import_conflict_modal != null and import_conflict_modal.visible:
        return
    if _tutorial_overlay != null and _tutorial_overlay.visible:
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_S and event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
            save_all()
            get_viewport().set_input_as_handled()
            return
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("entity")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


# ─── Queries ─────────────────────────────────────────────────────────────

func get_entities() -> Array:
    var arr_v: Variant = entities_data.get("entities", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return []
    return arr_v

func get_selected_entity() -> Dictionary:
    var arr := get_entities()
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("id", "")) == selected_entity_id:
            return e
    return {}

func select_entity(id: String) -> void:
    selected_entity_id = id


# ─── Registry CRUD ───────────────────────────────────────────────────────

func request_add_entity() -> void:
    show_text_modal("Add entity", _suggest_new_entity_id(),
        "Unique id (snake_case).",
        Callable(self, "_create_new_entity"))

func request_rename_entity(old_id: String) -> void:
    show_text_modal("Rename entity", old_id,
        "New id for \"%s\" (must be unique)." % old_id,
        Callable(self, "_rename_entity_to").bind(old_id))

func request_edit_field(field: String, title: String, prompt: String) -> void:
    var e := get_selected_entity()
    if e.is_empty():
        return
    var value: Variant = e.get(field, "")
    var default_val := str(value)
    show_text_modal(title, default_val, prompt,
        Callable(self, "_set_field").bind(field))

func delete_entity(id: String) -> void:
    var arr := get_entities()
    for i in arr.size():
        var e_v: Variant = arr[i]
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        if str((e_v as Dictionary).get("id", "")) == id:
            if _undo != null:
                _undo.begin()
            arr.remove_at(i)
            entities_data["entities"] = arr
            if selected_entity_id == id:
                if arr.is_empty():
                    selected_entity_id = ""
                else:
                    var first: Variant = arr[0]
                    if typeof(first) == TYPE_DICTIONARY:
                        selected_entity_id = str((first as Dictionary).get("id", ""))
            dirty = true
            if _undo != null:
                _undo.commit("delete entity")
            return

func cycle_category() -> void:
    var e := get_selected_entity()
    if e.is_empty():
        return
    if _undo != null:
        _undo.begin()
    var cur := str(e.get("category", "other"))
    var idx := EntTypes.CATEGORIES.find(cur)
    idx = (idx + 1) % EntTypes.CATEGORIES.size()
    e["category"] = str(EntTypes.CATEGORIES[idx])
    dirty = true
    if _undo != null:
        _undo.commit("cycle category")

func _suggest_new_entity_id() -> String:
    var arr := get_entities()
    var ids: Dictionary = {}
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        ids[str((e_v as Dictionary).get("id", ""))] = true
    var i := 1
    while true:
        var candidate := "entity_%d" % i
        if not ids.has(candidate):
            return candidate
        i += 1
    return "entity_new"

func _create_new_entity(id: String) -> void:
    id = id.strip_edges()
    if id.is_empty():
        push_warning("[EntEditor] empty entity id ignored")
        return
    var arr := get_entities()
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        if str((e_v as Dictionary).get("id", "")) == id:
            push_warning("[EntEditor] entity '%s' already exists" % id)
            return
    if _undo != null:
        _undo.begin()
    arr.append(EntIO.default_entity(id))
    entities_data["entities"] = arr
    selected_entity_id = id
    dirty = true
    if _undo != null:
        _undo.commit("add entity")

func _rename_entity_to(new_id: String, old_id: String) -> void:
    new_id = new_id.strip_edges()
    if new_id.is_empty() or new_id == old_id:
        return
    var arr := get_entities()
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        if str((e_v as Dictionary).get("id", "")) == new_id:
            push_warning("[EntEditor] entity '%s' already exists" % new_id)
            return
    for e_v in arr:
        if typeof(e_v) != TYPE_DICTIONARY:
            continue
        var e: Dictionary = e_v
        if str(e.get("id", "")) == old_id:
            if _undo != null:
                _undo.begin()
            e["id"] = new_id
            if selected_entity_id == old_id:
                selected_entity_id = new_id
            dirty = true
            if _undo != null:
                _undo.commit("rename entity")
            return

func _set_field(value: String, field: String) -> void:
    var e := get_selected_entity()
    if e.is_empty():
        return
    var parsed := _parse_field_value(field, value)
    if not bool(parsed.get("ok", false)):
        push_warning("[EntEditor] %s" % str(parsed.get("error", "invalid value")))
        return
    if _undo != null:
        _undo.begin()
    e[field] = parsed.get("value")
    dirty = true
    if _undo != null:
        _undo.commit("edit " + field)


func _parse_field_value(field: String, value: String) -> Dictionary:
    var text := value.strip_edges()
    if field in ["hp", "attack_damage", "contact_damage", "projectile_damage",
        "melee_attack_trigger_frame", "projectile_attack_trigger_frame"]:
        if not text.is_valid_int():
            return {"ok": false, "error": "%s must be a whole number" % field}
        var int_value := int(text)
        if field.ends_with("_trigger_frame"):
            return {"ok": true, "value": max(-1, int_value)}
        return {"ok": true, "value": maxi(0, int_value)}
    if field in ["contact_cooldown", "move_speed", "projectile_speed",
        "melee_range", "projectile_range"]:
        if not text.is_valid_float():
            return {"ok": false, "error": "%s must be a number" % field}
        return {"ok": true, "value": maxf(0.0, float(text))}
    if field == "item_drops":
        if text.is_empty():
            return {"ok": true, "value": []}
        var parsed: Variant = JSON.parse_string(text)
        if typeof(parsed) != TYPE_ARRAY:
            return {"ok": false, "error": "item_drops must be a JSON array"}
        return {"ok": true, "value": parsed}
    return {"ok": true, "value": value}

func set_selected_sprite_set(sprite_set_rel: String) -> void:
    _set_field(sprite_set_rel, "sprite_set")

func request_pick_sprite_set() -> void:
    if set_picker == null:
        return
    if get_selected_entity().is_empty():
        return
    set_picker.open(pack_id, str(get_selected_entity().get("sprite_set", "")))

func _on_set_picked(sprite_set_rel: String) -> void:
    set_selected_sprite_set(sprite_set_rel)


# ─── Sprite import flow ──────────────────────────────────────────────────
# set_picker → file_dialog → text_modal → copy files → reopen set_picker

func _on_set_picker_import_requested() -> void:
    if file_dialog == null:
        return
    _importing = true
    _pending_import_files = PackedStringArray()
    file_dialog.current_dir = ""
    file_dialog.popup_centered(Vector2i(900, 600))


func _on_import_files_selected(paths: PackedStringArray) -> void:
    if paths.is_empty():
        _on_import_cancelled()
        return
    _pending_import_files = paths
    var first_name := String(paths[0]).get_file().get_basename()
    show_text_modal("Import sprites → set name",
        first_name,
        "Folder name under Sprites/ to receive these PNG(s). Existing files are overwritten.",
        Callable(self, "_commit_import"))


func _on_import_cancelled() -> void:
    _clear_import_state()
    _reopen_set_picker()


func _commit_import(set_entry_name: String) -> void:
    var files := _pending_import_files
    _pending_import_files = PackedStringArray()
    var clean := set_entry_name.strip_edges()
    if clean == "" or files.is_empty():
        _clear_import_state()
        _reopen_set_picker()
        return
    var sprite_set_rel := "Sprites/" + clean
    var fresh: Array = []
    var conflicts: Array = []
    var conflict_names: Array = []
    for p_v in files:
        var p := String(p_v)
        var dest := EntIO.sprite_png_dest_path(pack_id, sprite_set_rel, p)
        if FileAccess.file_exists(dest):
            conflicts.append(p)
            conflict_names.append(dest.get_file())
        else:
            fresh.append(p)
    if conflicts.is_empty():
        _importing = false
        _execute_import(sprite_set_rel, fresh + conflicts)
        return
    _pending_import_set_rel = sprite_set_rel
    _pending_import_fresh = fresh
    _pending_import_overwrite = conflicts
    _importing = true
    import_conflict_modal.open(sprite_set_rel, conflict_names)


func _on_import_conflict_chose(action: String) -> void:
    var set_rel := _pending_import_set_rel
    var fresh := _pending_import_fresh
    var overwrite := _pending_import_overwrite
    _clear_import_state()
    match action:
        "overwrite":
            _execute_import(set_rel, fresh + overwrite)
        "skip":
            if fresh.is_empty():
                _reopen_set_picker()
            else:
                _execute_import(set_rel, fresh)
        _:
            _reopen_set_picker()


func _execute_import(sprite_set_rel: String, paths: Array) -> void:
    var imported: int = 0
    for p_v in paths:
        if EntIO.import_sprite_png(pack_id, sprite_set_rel, str(p_v)):
            imported += 1
    print("[EntEditor] imported %d/%d PNG(s) into %s" \
        % [imported, paths.size(), sprite_set_rel])
    if imported > 0:
        if not get_selected_entity().is_empty():
            set_selected_sprite_set(sprite_set_rel)
        _reopen_set_picker(sprite_set_rel)
    else:
        _reopen_set_picker()


func _clear_import_state() -> void:
    _importing = false
    _pending_import_files = PackedStringArray()
    _pending_import_set_rel = ""
    _pending_import_fresh = []
    _pending_import_overwrite = []


func _reopen_set_picker(preselect: String = "") -> void:
    if set_picker == null:
        return
    var sel := preselect
    if sel == "":
        var e := get_selected_entity()
        if not e.is_empty():
            sel = str(e.get("sprite_set", ""))
    set_picker.open(pack_id, sel)

func set_selected_behavior(behavior_id: String) -> void:
    _set_field(behavior_id, "behavior")

func request_pick_behavior() -> void:
    if behavior_picker == null:
        return
    if get_selected_entity().is_empty():
        return
    # Refresh so pickers reflect edits made in the behavior editor
    # since this entity editor was opened.
    refresh_known_behaviors()
    behavior_picker.open(pack_id, str(get_selected_entity().get("behavior", "")))

func _on_behavior_picked(behavior_id: String) -> void:
    set_selected_behavior(behavior_id)


func refresh_known_behaviors() -> void:
    _known_behavior_ids.clear()
    var data: Dictionary = BehIO.load_or_init(pack_id)
    var arr_v: Variant = data.get("behaviors", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return
    for b_v in arr_v:
        if typeof(b_v) != TYPE_DICTIONARY:
            continue
        var id_str: String = str((b_v as Dictionary).get("id", "")).strip_edges()
        if not id_str.is_empty():
            _known_behavior_ids[id_str] = true


func is_known_behavior(id: String) -> bool:
    return id.is_empty() or _known_behavior_ids.has(id)


# ─── Pose cache ──────────────────────────────────────────────────────────

func get_or_load_poses(sprite_set_rel: String) -> Dictionary:
    if sprite_set_rel == "":
        return {"poses": {}}
    if not _poses_cache.has(sprite_set_rel):
        _poses_cache[sprite_set_rel] = EntIO.load_poses(pack_id, sprite_set_rel)
    return _poses_cache[sprite_set_rel]

func get_pose_for(sprite_set_rel: String, filename: String) -> Dictionary:
    if sprite_set_rel == "" or filename == "":
        return {}
    var data := get_or_load_poses(sprite_set_rel)
    var poses_v: Variant = data.get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        return {}
    var poses: Dictionary = poses_v
    var pose_v: Variant = poses.get(filename, {})
    if typeof(pose_v) != TYPE_DICTIONARY:
        return {}
    return pose_v

func set_pose_field(sprite_set_rel: String, filename: String,
        field: String, value: Variant) -> void:
    if sprite_set_rel == "" or filename == "":
        return
    if _undo != null:
        _undo.begin()
    var data := get_or_load_poses(sprite_set_rel)
    if not data.has("poses") or typeof(data["poses"]) != TYPE_DICTIONARY:
        data["poses"] = {}
    var poses: Dictionary = data["poses"]
    var pose: Dictionary = {}
    if poses.has(filename) and typeof(poses[filename]) == TYPE_DICTIONARY:
        pose = poses[filename]
    pose[field] = value
    poses[filename] = pose
    data["poses"] = poses
    _poses_cache[sprite_set_rel] = data
    _poses_dirty[sprite_set_rel] = true
    dirty = true
    if _undo != null:
        _undo.commit("edit pose " + field)

func request_edit_pose_field(sprite_set_rel: String, filename: String,
        field: String, title: String, prompt: String) -> void:
    if sprite_set_rel == "" or filename == "":
        return
    var pose := get_pose_for(sprite_set_rel, filename)
    var default_val := ""
    if pose.has(field):
        default_val = str(pose[field])
    show_text_modal(title, default_val, prompt,
        Callable(self, "_commit_pose_field").bind(sprite_set_rel, filename, field))

func _commit_pose_field(value: String, sprite_set_rel: String,
        filename: String, field: String) -> void:
    value = value.strip_edges()
    if value == "":
        return
    var parsed: Variant = value
    if field == "frames" or field == "loop_from":
        if not value.is_valid_int():
            push_warning("[EntEditor] '%s' must be an integer" % field)
            return
        parsed = int(value)
    elif field == "fps" or field == "y_offset" or field == "y_radius":
        if not value.is_valid_float():
            push_warning("[EntEditor] '%s' must be a number" % field)
            return
        parsed = float(value)
    set_pose_field(sprite_set_rel, filename, field, parsed)


# ─── Save / close ────────────────────────────────────────────────────────

func save_all() -> void:
    var ok := EntIO.save_entities(pack_id, entities_data)
    if not ok:
        push_error("[EntEditor] entities.json save failed for pack '%s'" % pack_id)
        return
    var pose_failures: int = 0
    for set_rel_v in _poses_dirty.keys():
        var set_rel := str(set_rel_v)
        var data_v: Variant = _poses_cache.get(set_rel, {})
        if typeof(data_v) != TYPE_DICTIONARY:
            continue
        if not EntIO.save_poses(pack_id, set_rel, data_v):
            pose_failures += 1
    if pose_failures > 0:
        push_error("[EntEditor] %d poses.json saves failed for pack '%s'" \
            % [pose_failures, pack_id])
        return
    _poses_dirty.clear()
    dirty = false
    print("[EntEditor] saved entities + poses for pack '%s'" % pack_id)

func request_close() -> void:
    visible = false
    closed.emit()


# ─── Modal plumbing ──────────────────────────────────────────────────────

func show_text_modal(title: String, default_text: String, prompt: String, cb: Callable) -> void:
    _modal_callback = cb
    text_modal.open(title, default_text, prompt)

func _on_modal_submit(text: String) -> void:
    var cb := _modal_callback
    _modal_callback = Callable()
    if cb.is_valid():
        cb.call(text)

func _on_modal_cancel() -> void:
    _modal_callback = Callable()
    if _importing:
        _clear_import_state()
        _reopen_set_picker()

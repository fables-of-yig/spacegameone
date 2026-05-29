extends Control

const AudIO = preload("res://Space/scripts/editor/aud/aud_io.gd")


# Audio editor main controller. Owns the clips.json registry for the
# active pack, the currently-selected clip, a reusable AudioStreamPlayer
# for preview, and the modal plumbing for import / rename / edit.
#
# Panels:
#   aud_topbar.gd      — pack label + IMPORT / ADD / SAVE / CLOSE buttons
#   aud_list_panel.gd  — left sidebar: clip list with rename/delete
#   aud_detail_panel.gd — right pane: clip fields + PLAY/STOP

signal closed

var pack_id: String = ""
var clips_data: Dictionary = {"clips": []}
var selected_clip_id: String = ""
var dirty: bool = false

var topbar: Control = null
var list_panel: Control = null
var detail_panel: Control = null
var text_modal: Control = null
var file_dialog: FileDialog = null
var import_conflict_modal: Control = null
var manifest_modal: Control = null
var preview_player: AudioStreamPlayer = null

var _tutorial_btn: Button = null
var _tutorial_overlay: Control = null

var _skip_close_frame: bool = true
var _modal_callback: Callable = Callable()

var _undo: RefCounted = null
var _importing: bool = false
var _pending_import_files: PackedStringArray = PackedStringArray()
var _pending_import_folder_rel: String = ""
var _pending_import_fresh: Array = []
var _pending_import_overwrite: Array = []
var _preview_stop_timer: float = 0.0

# Cache of clip durations keyed by pack-relative file path. Populated
# lazily the first time the detail panel asks for a duration; cleared
# on open_editor so a pack switch doesn't show stale numbers.
var _duration_cache: Dictionary = {}

# Trim session state. After an OGG import, each imported file flows
# through a "pending clip" step where the detail panel lets the user
# trim + rename before committing the entry to clips.json. Clips only
# ever exist via this flow — there is no "add empty clip" action.
var _pending_clip: Dictionary = {}
var _pending_queue: Array = []

const TOPBAR_H: float = 64.0
const SIDEBAR_W: float = 300.0
const DETAIL_W: float = 460.0


func _ready():
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)
    mouse_filter = MOUSE_FILTER_STOP
    _skip_close_frame = true
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()


func _capture_state() -> Dictionary:
    return {
        "clips_data": clips_data.duplicate(true),
        "selected_clip_id": selected_clip_id,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var c_v: Variant = snap.get("clips_data", null)
    if typeof(c_v) == TYPE_DICTIONARY:
        clips_data = c_v
    selected_clip_id = str(snap.get("selected_clip_id", ""))
    dirty = bool(snap.get("dirty", false))
    if list_panel != null and list_panel.has_method("queue_redraw"):
        list_panel.queue_redraw()
    if detail_panel != null and detail_panel.has_method("queue_redraw"):
        detail_panel.queue_redraw()


func _build_layout() -> void:
    topbar = Control.new()
    topbar.set_script(preload("res://Space/scripts/editor/aud/aud_topbar.gd"))
    topbar.editor = self
    add_child(topbar)

    list_panel = Control.new()
    list_panel.set_script(preload("res://Space/scripts/editor/aud/aud_list_panel.gd"))
    list_panel.editor = self
    add_child(list_panel)

    detail_panel = Control.new()
    detail_panel.set_script(preload("res://Space/scripts/editor/aud/aud_detail_panel.gd"))
    detail_panel.editor = self
    add_child(detail_panel)

    file_dialog = FileDialog.new()
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
    file_dialog.use_native_dialog = true
    file_dialog.title = "Import OGG audio"
    file_dialog.add_filter("*.ogg", "OGG Vorbis")
    file_dialog.files_selected.connect(_on_import_files_selected)
    file_dialog.canceled.connect(_on_import_cancelled)
    add_child(file_dialog)

    import_conflict_modal = Control.new()
    import_conflict_modal.set_script(preload("res://Space/scripts/editor/import_conflict_modal.gd"))
    import_conflict_modal.visible = false
    add_child(import_conflict_modal)
    import_conflict_modal.chose.connect(_on_import_conflict_chose)

    text_modal = Control.new()
    text_modal.set_script(preload("res://Space/scripts/editor/env/env_text_modal.gd"))
    text_modal.visible = false
    add_child(text_modal)
    text_modal.submitted.connect(_on_modal_submit)
    text_modal.cancelled.connect(_on_modal_cancel)

    manifest_modal = Control.new()
    manifest_modal.set_script(preload("res://Space/scripts/editor/aud/aud_manifest_modal.gd"))
    manifest_modal.visible = false
    add_child(manifest_modal)

    preview_player = AudioStreamPlayer.new()
    add_child(preview_player)

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
    if text_modal != null:
        text_modal.position = Vector2.ZERO
        text_modal.size = Vector2(vw, vh)
    if import_conflict_modal != null:
        import_conflict_modal.position = Vector2.ZERO
        import_conflict_modal.size = Vector2(vw, vh)
    if manifest_modal != null:
        manifest_modal.position = Vector2.ZERO
        manifest_modal.size = Vector2(vw, vh)
    if _tutorial_btn != null:
        _tutorial_btn.position = Vector2(vw - 240, 16)
        _tutorial_btn.size = Vector2(100, 32)
    if _tutorial_overlay != null:
        _tutorial_overlay.position = Vector2.ZERO
        _tutorial_overlay.size = Vector2(vw, vh)


func open_editor(p_pack_id: String = ""):
    pack_id = p_pack_id
    visible = true
    _skip_close_frame = true

    clips_data = AudIO.load_or_init(pack_id)
    var arr: Array = clips_data.get("clips", [])
    if arr.is_empty():
        selected_clip_id = ""
    else:
        var first: Variant = arr[0]
        if typeof(first) == TYPE_DICTIONARY:
            selected_clip_id = str((first as Dictionary).get("id", ""))
    dirty = false
    _duration_cache.clear()
    _pending_clip = {}
    _pending_queue.clear()
    stop_preview()
    if _undo != null:
        _undo.clear()

    if is_inside_tree():
        _layout_children()


func _process(delta):
    if _skip_close_frame:
        _skip_close_frame = false
        return
    if _preview_stop_timer > 0.0:
        _preview_stop_timer -= delta
        if _preview_stop_timer <= 0.0:
            stop_preview()


func _input(event):
    if not visible:
        return
    if _skip_close_frame:
        return
    if text_modal != null and text_modal.visible:
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
        if event.keycode == KEY_ESCAPE:
            request_close()
            get_viewport().set_input_as_handled()


func _on_tutorial_pressed() -> void:
    if _tutorial_overlay == null:
        return
    var EditorTutorial := preload("res://Space/scripts/editor/editor_tutorial.gd")
    var tut: Dictionary = EditorTutorial.get_tutorial("audio")
    _tutorial_overlay.show_tutorial(str(tut["title"]), tut["steps"])


# ─── Queries ─────────────────────────────────────────────────────────────

func get_clips() -> Array:
    var arr_v: Variant = clips_data.get("clips", [])
    if typeof(arr_v) != TYPE_ARRAY:
        return []
    return arr_v

func get_selected_clip() -> Dictionary:
    if not _pending_clip.is_empty():
        return _pending_clip
    var arr := get_clips()
    for c_v in arr:
        if typeof(c_v) != TYPE_DICTIONARY:
            continue
        var c: Dictionary = c_v
        if str(c.get("id", "")) == selected_clip_id:
            return c
    return {}

func select_clip(id: String) -> void:
    if not _pending_clip.is_empty():
        return
    selected_clip_id = id

func is_pending() -> bool:
    return not _pending_clip.is_empty()

func get_pending_queue_remaining() -> int:
    return _pending_queue.size()

# Returns the clip duration in seconds. Loads the OGG stream on first
# access and caches the result so the detail panel can call this from
# _draw without thrashing the disk every frame. Returns 0.0 if the
# file can't be loaded.
func get_clip_duration(file_rel: String) -> float:
    if file_rel == "":
        return 0.0
    if _duration_cache.has(file_rel):
        return float(_duration_cache[file_rel])
    var stream := AudIO.load_ogg_stream(pack_id, file_rel)
    if stream == null:
        _duration_cache[file_rel] = 0.0
        return 0.0
    var dur: float = stream.get_length()
    _duration_cache[file_rel] = dur
    return dur

func get_preview_playing() -> bool:
    return preview_player != null and preview_player.playing

# Returns the current playback position in seconds, or -1 when the
# preview isn't running.
func get_preview_position() -> float:
    if preview_player == null or not preview_player.playing:
        return -1.0
    return preview_player.get_playback_position()

# Setter used by the timeline drag. Updates a trim field on the
# selected clip without routing through the text modal.
func set_clip_trim(field: String, value: float) -> void:
    if field != "start_sec" and field != "end_sec":
        return
    var c := get_selected_clip()
    if c.is_empty():
        return
    c[field] = value
    dirty = true


# ─── Registry CRUD ───────────────────────────────────────────────────────

func request_rename_clip(old_id: String) -> void:
    show_text_modal("Rename clip", old_id,
        "New id for \"%s\" (must be unique)." % old_id,
        Callable(self, "_rename_clip_to").bind(old_id))

func request_edit_clip_field(field: String, title: String, prompt: String) -> void:
    var c := get_selected_clip()
    if c.is_empty():
        return
    var default_val := ""
    if c.has(field):
        var v: Variant = c[field]
        if field == "tags" and typeof(v) == TYPE_ARRAY:
            var parts: Array = []
            for t in v:
                parts.append(str(t))
            default_val = ", ".join(parts)
        elif field == "start_sec" or field == "end_sec":
            default_val = "%.2f" % float(v)
        else:
            default_val = str(v)
    show_text_modal(title, default_val, prompt,
        Callable(self, "_set_clip_field").bind(field))

func delete_clip(id: String) -> void:
    var arr := get_clips()
    for i in arr.size():
        var c_v: Variant = arr[i]
        if typeof(c_v) != TYPE_DICTIONARY:
            continue
        if str((c_v as Dictionary).get("id", "")) == id:
            if _undo != null:
                _undo.begin()
            arr.remove_at(i)
            clips_data["clips"] = arr
            if selected_clip_id == id:
                if arr.is_empty():
                    selected_clip_id = ""
                else:
                    var first: Variant = arr[0]
                    if typeof(first) == TYPE_DICTIONARY:
                        selected_clip_id = str((first as Dictionary).get("id", ""))
            dirty = true
            if _undo != null:
                _undo.commit("delete clip")
            return

func _rename_clip_to(new_id: String, old_id: String) -> void:
    new_id = new_id.strip_edges()
    if new_id.is_empty() or new_id == old_id:
        return
    var arr := get_clips()
    for c_v in arr:
        if typeof(c_v) != TYPE_DICTIONARY:
            continue
        if str((c_v as Dictionary).get("id", "")) == new_id:
            push_warning("[AudEditor] clip '%s' already exists" % new_id)
            return
    for c_v in arr:
        if typeof(c_v) != TYPE_DICTIONARY:
            continue
        var c: Dictionary = c_v
        if str(c.get("id", "")) == old_id:
            if _undo != null:
                _undo.begin()
            c["id"] = new_id
            if selected_clip_id == old_id:
                selected_clip_id = new_id
            dirty = true
            if _undo != null:
                _undo.commit("rename clip")
            return

func _set_clip_field(value: String, field: String) -> void:
    var c := get_selected_clip()
    if c.is_empty():
        return
    value = value.strip_edges()
    if _undo != null:
        _undo.begin()
    if field == "start_sec" or field == "end_sec":
        if not value.is_valid_float():
            push_warning("[AudEditor] '%s' must be a number" % field)
            if _undo != null:
                _undo.discard()
            return
        c[field] = float(value)
    elif field == "tags":
        var parts: Array = []
        for raw in value.split(","):
            var t := String(raw).strip_edges()
            if t != "":
                parts.append(t)
        c[field] = parts
    else:
        c[field] = value
    dirty = true
    if _undo != null:
        _undo.commit("set clip field")


# ─── Import flow ─────────────────────────────────────────────────────────
# topbar → file_dialog → text_modal (folder name) → conflict_modal? →
# copy files + auto-create clip entries

func request_import_ogg() -> void:
    if file_dialog == null:
        return
    _importing = true
    _pending_import_files = PackedStringArray()
    file_dialog.current_dir = ""
    file_dialog.popup_centered(Vector2i(900, 600))


func request_open_manifest() -> void:
    if manifest_modal == null:
        return
    manifest_modal.open(pack_id)


func _on_import_files_selected(paths: PackedStringArray) -> void:
    if paths.is_empty():
        _on_import_cancelled()
        return
    _pending_import_files = paths
    var first_name := String(paths[0]).get_file().get_basename()
    show_text_modal("Import OGG → folder name",
        first_name,
        "Folder name under Audio/ to receive these OGG(s). Existing files are overwritten.",
        Callable(self, "_commit_import"))


func _on_import_cancelled() -> void:
    _clear_import_state()


func _commit_import(folder_name: String) -> void:
    var files := _pending_import_files
    _pending_import_files = PackedStringArray()
    var clean := folder_name.strip_edges()
    if clean == "" or files.is_empty():
        _clear_import_state()
        return
    var folder_rel := "Audio/" + clean
    var fresh: Array = []
    var conflicts: Array = []
    var conflict_names: Array = []
    for p_v in files:
        var p := String(p_v)
        var dest := AudIO.audio_dest_path(pack_id, folder_rel, p)
        if FileAccess.file_exists(dest):
            conflicts.append(p)
            conflict_names.append(dest.get_file())
        else:
            fresh.append(p)
    if conflicts.is_empty():
        _importing = false
        _execute_import(folder_rel, fresh + conflicts)
        return
    _pending_import_folder_rel = folder_rel
    _pending_import_fresh = fresh
    _pending_import_overwrite = conflicts
    _importing = true
    import_conflict_modal.open(folder_rel, conflict_names)


func _on_import_conflict_chose(action: String) -> void:
    var folder_rel := _pending_import_folder_rel
    var fresh := _pending_import_fresh
    var overwrite := _pending_import_overwrite
    _clear_import_state()
    match action:
        "overwrite":
            _execute_import(folder_rel, fresh + overwrite)
        "skip":
            if not fresh.is_empty():
                _execute_import(folder_rel, fresh)
        _:
            pass


func _execute_import(folder_rel: String, paths: Array) -> void:
    var imported: int = 0
    stop_preview()
    for p_v in paths:
        var p := String(p_v)
        if not AudIO.import_ogg(pack_id, folder_rel, p):
            continue
        imported += 1
        var base := p.get_file()
        if not base.to_lower().ends_with(".ogg"):
            base += ".ogg"
        var file_rel := folder_rel + "/" + base
        if _duration_cache.has(file_rel):
            _duration_cache.erase(file_rel)
        _pending_queue.append(file_rel)
    print("[AudEditor] imported %d/%d OGG(s) into %s, queued for trim" \
        % [imported, paths.size(), folder_rel])
    _begin_next_pending_clip()


func _begin_next_pending_clip() -> void:
    if _pending_queue.is_empty():
        _pending_clip = {}
        return
    var file_rel := str(_pending_queue[0])
    _pending_queue.remove_at(0)
    var base := file_rel.get_file()
    var auto_id := _auto_clip_id_for(base)
    _pending_clip = AudIO.default_clip(auto_id, file_rel)
    stop_preview()


# Commits the current pending clip to the registry. Auto-bumps the id
# on collision with an existing saved clip, then advances to the next
# pending clip (if any) or exits the trim session.
func save_pending_clip() -> void:
    if _pending_clip.is_empty():
        return
    var desired_id := str(_pending_clip.get("id", "")).strip_edges()
    if desired_id == "":
        push_warning("[AudEditor] pending clip has empty id; cannot save")
        return
    if _undo != null:
        _undo.begin()
    var existing := get_clips()
    var ids: Dictionary = {}
    for c_v in existing:
        if typeof(c_v) == TYPE_DICTIONARY:
            ids[str((c_v as Dictionary).get("id", ""))] = true
    var final_id := desired_id
    if ids.has(final_id):
        var i := 2
        while ids.has("%s_%d" % [final_id, i]):
            i += 1
        final_id = "%s_%d" % [final_id, i]
        _pending_clip["id"] = final_id
    existing.append(_pending_clip.duplicate(true))
    clips_data["clips"] = existing
    selected_clip_id = final_id
    _pending_clip = {}
    dirty = true
    stop_preview()
    _begin_next_pending_clip()
    if _undo != null:
        _undo.commit("commit pending clip")


# Drops the current pending clip without writing it to the registry.
# The underlying .ogg is left on disk — the user can re-import or hand-
# author a clip entry referencing it later if they change their mind.
func discard_pending_clip() -> void:
    _pending_clip = {}
    stop_preview()
    _begin_next_pending_clip()


func _auto_clip_id_for(filename: String) -> String:
    var base := filename.get_basename()
    var id := base.to_lower().replace(" ", "_").replace("-", "_")
    if id == "":
        id = "clip"
    var arr := get_clips()
    var ids: Dictionary = {}
    for c_v in arr:
        if typeof(c_v) != TYPE_DICTIONARY:
            continue
        ids[str((c_v as Dictionary).get("id", ""))] = true
    if not ids.has(id):
        return id
    var i := 2
    while ids.has("%s_%d" % [id, i]):
        i += 1
    return "%s_%d" % [id, i]


func _clear_import_state() -> void:
    _importing = false
    _pending_import_files = PackedStringArray()
    _pending_import_folder_rel = ""
    _pending_import_fresh = []
    _pending_import_overwrite = []


# ─── Preview ─────────────────────────────────────────────────────────────

func play_selected_clip() -> void:
    var c := get_selected_clip()
    if c.is_empty():
        return
    var file_rel := str(c.get("file", ""))
    if file_rel == "":
        push_warning("[AudEditor] clip '%s' has no file" % str(c.get("id", "")))
        return
    var stream := AudIO.load_ogg_stream(pack_id, file_rel)
    if stream == null:
        push_error("[AudEditor] failed to load stream for '%s'" % file_rel)
        return
    stop_preview()
    preview_player.stream = stream
    var start_sec := float(c.get("start_sec", 0.0))
    var end_sec := float(c.get("end_sec", -1.0))
    preview_player.play(max(0.0, start_sec))
    if end_sec > 0.0 and end_sec > start_sec:
        _preview_stop_timer = end_sec - max(0.0, start_sec)
    else:
        _preview_stop_timer = 0.0


func stop_preview() -> void:
    if preview_player != null and preview_player.playing:
        preview_player.stop()
    _preview_stop_timer = 0.0


# ─── Save / close ────────────────────────────────────────────────────────

func save_all() -> void:
    var ok := AudIO.save_clips(pack_id, clips_data)
    if not ok:
        push_error("[AudEditor] clips.json save failed for pack '%s'" % pack_id)
        return
    dirty = false
    ContentValidator.validate_and_log(pack_id, "audio save")
    print("[AudEditor] saved clips for pack '%s'" % pack_id)

func request_close() -> void:
    stop_preview()
    _pending_clip = {}
    _pending_queue.clear()
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

extends Control

# Editor panel for per-pack factions. Two-column layout: left is the list
# of authored faction ids (with +/-/reorder buttons), right is the detail
# form for the selected faction. Mirrors the System Editor's structure
# but simpler — no inset map, no NPC placement, just a flat list of
# faction records and a relations matrix.
#
# Hosted by content_editor.gd as a sub-tile under Game Pieces. Persists
# to Content/<pack>/Factions/factions.json via FactionsIO.
#
# Re-exports `closed` so the content editor can restore its tile grid
# when this panel exits.

const FactionsIO = preload("res://Space/scripts/shared/factions_io.gd")
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")
# EditorTooltipWrap, ContentReferenceIndex, ContentReferenceRefactor are
# globally accessible via their class_name declarations — no preload
# needed, and shadowing them as local consts produces SHADOWED_GLOBAL
# warnings on every line of this file.

const RESERVED_FACTION_IDS: Array = ["independent"]
const SYMBOL_PREVIEW_PX: float = 64.0
const ID_SLUG_REGEX: String = "^[a-z0-9_]+$"

signal status_changed(text: String)
signal closed

var _pack_id: String = ""
var _factions: Dictionary = {}
var _selected_id: String = ""
var _dirty: bool = false
var _suppress: bool = false

var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null
var _detail_box: VBoxContainer = null
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _symbol_btn: Button = null
var _symbol_clear_btn: Button = null
var _symbol_preview: TextureRect = null
var _symbol_label: Label = null
var _disposition_pick: OptionButton = null
var _rep_spin: SpinBox = null
var _desc_edit: TextEdit = null
var _relations_box: VBoxContainer = null
var _relations_widgets: Dictionary = {}  # other_id -> OptionButton
var _symbol_dialog: FileDialog = null
var _slug_regex: RegEx = null
# Pending rename state — populated when _commit_id_rename detects external
# references and pops the confirmation dialog; consumed by the dialog's
# confirmed/canceled handlers so the actual rewrite waits for the user.
var _rename_dialog: ConfirmationDialog = null
var _pending_rename_old: String = ""
var _pending_rename_new: String = ""


func request_close() -> void:
    visible = false
    closed.emit()


func open(pack_id: String) -> void:
    _pack_id = pack_id
    _factions = FactionsIO.load_or_empty(pack_id)
    _ensure_reserved_factions()
    _selected_id = _factions.keys()[0] if not _factions.is_empty() else ""
    _dirty = false
    _refresh_list()
    _show_detail(_selected_id)


func open_editor(pack_id: String) -> void:
    open(pack_id)
    visible = true
    size = get_viewport_rect().size
    set_anchors_preset(PRESET_FULL_RECT)


func save() -> bool:
    if not _flush_detail():
        return false
    if FactionsIO.save(_pack_id, _factions):
        _dirty = false
        status_changed.emit("Factions saved.")
        return true
    status_changed.emit("Factions save failed.")
    return false


func is_dirty() -> bool:
    return _dirty


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _slug_regex = RegEx.new()
    _slug_regex.compile(ID_SLUG_REGEX)
    _build_ui()


func _build_ui() -> void:
    var root := HSplitContainer.new()
    root.anchor_right = 1.0
    root.anchor_bottom = 1.0
    root.split_offset = 240
    add_child(root)

    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.add_theme_constant_override("separation", 6)
    root.add_child(left)

    var topbar := HBoxContainer.new()
    left.add_child(topbar)
    var back_btn := Button.new()
    back_btn.text = "Back"
    back_btn.tooltip_text = "Close the factions editor and return to the previous screen."
    back_btn.pressed.connect(request_close)
    topbar.add_child(back_btn)
    var save_btn := Button.new()
    save_btn.text = "Save"
    save_btn.tooltip_text = "Persist factions.json to this pack."
    save_btn.pressed.connect(save)
    topbar.add_child(save_btn)

    var list_label := Label.new()
    list_label.text = "Factions in this pack"
    list_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96))
    left.add_child(list_label)

    _list = ItemList.new()
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.item_selected.connect(_on_list_selected)
    left.add_child(_list)

    var list_btns := HBoxContainer.new()
    left.add_child(list_btns)
    _add_btn = Button.new()
    _add_btn.text = "+ Faction"
    _add_btn.tooltip_text = "Add a new faction. You can edit the id afterwards."
    _add_btn.pressed.connect(_on_add_faction)
    list_btns.add_child(_add_btn)
    _del_btn = Button.new()
    _del_btn.text = "- Faction"
    _del_btn.tooltip_text = "Delete the selected faction. Reserved ids (independent) cannot be deleted."
    _del_btn.pressed.connect(_on_delete_faction)
    list_btns.add_child(_del_btn)

    var right_scroll := ScrollContainer.new()
    right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.add_child(right_scroll)
    _detail_box = VBoxContainer.new()
    _detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _detail_box.add_theme_constant_override("separation", 8)
    right_scroll.add_child(_detail_box)

    _build_detail_form()

    _symbol_dialog = FileDialog.new()
    _symbol_dialog.access = FileDialog.ACCESS_FILESYSTEM
    _symbol_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _symbol_dialog.filters = PackedStringArray(["*.png ; PNG Images"])
    _symbol_dialog.title = "Pick faction symbol PNG"
    _symbol_dialog.file_selected.connect(_on_symbol_picked)
    add_child(_symbol_dialog)

    _rename_dialog = ConfirmationDialog.new()
    _rename_dialog.title = "Rename faction"
    _rename_dialog.ok_button_text = "Rename + Update references"
    _rename_dialog.cancel_button_text = "Cancel"
    _rename_dialog.confirmed.connect(_on_rename_confirmed)
    _rename_dialog.canceled.connect(_on_rename_canceled)
    add_child(_rename_dialog)

    EditorTooltipWrap.wrap_tree(self)


func _build_detail_form() -> void:
    _add_field_label("ID")
    _id_edit = LineEdit.new()
    _id_edit.placeholder_text = "lowercase_snake_id"
    _id_edit.tooltip_text = "Stable id used by systems.json, placed_npcs, and dialogue speaker_faction. Renaming triggers cross-references to update. Slug only: a-z, 0-9, underscore."
    _id_edit.text_submitted.connect(func(_t): _commit_id_rename())
    _id_edit.focus_exited.connect(_commit_id_rename)
    _detail_box.add_child(_id_edit)

    _add_field_label("Display name")
    _name_edit = LineEdit.new()
    _name_edit.placeholder_text = "Display Name"
    _name_edit.tooltip_text = "How the faction appears in dialogues, scan reports, the star map legend."
    _name_edit.text_changed.connect(func(_t): _mark_dirty_and_flush())
    _detail_box.add_child(_name_edit)

    _add_field_label("Symbol PNG")
    var sym_row := HBoxContainer.new()
    _detail_box.add_child(sym_row)
    _symbol_preview = TextureRect.new()
    _symbol_preview.custom_minimum_size = Vector2(SYMBOL_PREVIEW_PX, SYMBOL_PREVIEW_PX)
    _symbol_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _symbol_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sym_row.add_child(_symbol_preview)
    var sym_col := VBoxContainer.new()
    sym_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sym_row.add_child(sym_col)
    _symbol_label = Label.new()
    _symbol_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.92))
    _symbol_label.add_theme_font_size_override("font_size", 11)
    _symbol_label.text = "(no symbol)"
    sym_col.add_child(_symbol_label)
    var sym_btns := HBoxContainer.new()
    sym_col.add_child(sym_btns)
    _symbol_btn = Button.new()
    _symbol_btn.text = "Pick symbol..."
    _symbol_btn.tooltip_text = "Pick a PNG from Content/<pack>/Factions/Symbols/. Files outside that folder are copied in."
    _symbol_btn.pressed.connect(_on_open_symbol_picker)
    sym_btns.add_child(_symbol_btn)
    _symbol_clear_btn = Button.new()
    _symbol_clear_btn.text = "Clear"
    _symbol_clear_btn.tooltip_text = "Remove the symbol from this faction. The faction's id stays valid; dialogues that referenced its symbol will simply render nothing."
    _symbol_clear_btn.pressed.connect(_on_clear_symbol)
    sym_btns.add_child(_symbol_clear_btn)

    _add_field_label("Disposition to player")
    _disposition_pick = OptionButton.new()
    _disposition_pick.add_item("friendly")
    _disposition_pick.add_item("neutral")
    _disposition_pick.add_item("hostile")
    _disposition_pick.tooltip_text = "Default attitude toward the player. Drives initial faction reputation when no explicit value is set."
    _disposition_pick.item_selected.connect(_on_disposition_selected)
    _detail_box.add_child(_disposition_pick)

    _add_field_label("Starting reputation (-100 to +100)")
    _rep_spin = SpinBox.new()
    _rep_spin.min_value = -100
    _rep_spin.max_value = 100
    _rep_spin.step = 1
    _rep_spin.tooltip_text = "Player's starting reputation with this faction. Defaults from disposition (+25 friendly / 0 neutral / -25 hostile) but you can override per faction."
    _rep_spin.value_changed.connect(func(_v): _mark_dirty_and_flush())
    _detail_box.add_child(_rep_spin)

    _add_field_label("Description")
    _desc_edit = TextEdit.new()
    _desc_edit.custom_minimum_size = Vector2(0, 60)
    _desc_edit.placeholder_text = "Free-form lore / authoring notes."
    _desc_edit.tooltip_text = "Description displayed in the star map legend and any UI that surfaces faction info."
    _desc_edit.text_changed.connect(_mark_dirty_and_flush)
    _detail_box.add_child(_desc_edit)

    _add_field_label("Relations with other factions")
    var rel_hint := Label.new()
    rel_hint.text = "Set how this faction views each other one. Missing entries default to neutral."
    rel_hint.add_theme_color_override("font_color", Color(0.65, 0.74, 0.86))
    rel_hint.add_theme_font_size_override("font_size", 10)
    _detail_box.add_child(rel_hint)
    _relations_box = VBoxContainer.new()
    _relations_box.add_theme_constant_override("separation", 4)
    _detail_box.add_child(_relations_box)


func _add_field_label(text: String) -> void:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_color_override("font_color", Color(0.78, 0.86, 0.96))
    lbl.add_theme_font_size_override("font_size", 11)
    _detail_box.add_child(lbl)


# ─── List ──────────────────────────────────────────────────────────────

func _refresh_list() -> void:
    if _list == null:
        return
    _suppress = true
    _list.clear()
    var ids: Array = _factions.keys()
    ids.sort()
    var sel_idx: int = -1
    for i in range(ids.size()):
        var fid: String = str(ids[i])
        var display_name: String = str((_factions[fid] as Dictionary).get("name", ""))
        var label: String = "%s — %s" % [fid, display_name] if not display_name.is_empty() else fid
        if RESERVED_FACTION_IDS.has(fid):
            label += "  [reserved]"
        _list.add_item(label)
        _list.set_item_metadata(i, fid)
        if fid == _selected_id:
            sel_idx = i
    if sel_idx >= 0:
        _list.select(sel_idx)
    _suppress = false


func _on_list_selected(idx: int) -> void:
    if _suppress:
        return
    if not _flush_detail():
        return
    _selected_id = str(_list.get_item_metadata(idx))
    _show_detail(_selected_id)


func _on_add_faction() -> void:
    if not _flush_detail():
        return
    var base := "new_faction"
    var idx := 1
    var fid := base
    while _factions.has(fid):
        idx += 1
        fid = "%s_%d" % [base, idx]
    _factions[fid] = FactionsIO.normalize_entry({
        "name": "New Faction",
        "disposition_to_player": "neutral",
    })
    _selected_id = fid
    _dirty = true
    _refresh_list()
    _show_detail(_selected_id)


func _on_delete_faction() -> void:
    if _selected_id.is_empty():
        return
    if RESERVED_FACTION_IDS.has(_selected_id):
        status_changed.emit("Cannot delete reserved faction '%s'." % _selected_id)
        return
    _factions.erase(_selected_id)
    # Strip dead references from other factions' relations dicts so the
    # next save doesn't write back stale keys.
    for other_fid in _factions.keys():
        var rels: Dictionary = (_factions[other_fid] as Dictionary).get("relations", {})
        if rels.has(_selected_id):
            rels.erase(_selected_id)
            (_factions[other_fid] as Dictionary)["relations"] = rels
    _dirty = true
    _selected_id = _factions.keys()[0] if not _factions.is_empty() else ""
    _refresh_list()
    _show_detail(_selected_id)


# ─── Detail form ───────────────────────────────────────────────────────

func _show_detail(fid: String) -> void:
    _suppress = true
    if fid.is_empty() or not _factions.has(fid):
        _id_edit.text = ""
        _name_edit.text = ""
        _symbol_label.text = "(no symbol)"
        _symbol_preview.texture = null
        _disposition_pick.select(1)
        _rep_spin.value = 0
        _desc_edit.text = ""
        _rebuild_relations_grid()
        _suppress = false
        return
    var entry: Dictionary = _factions[fid]
    _id_edit.text = fid
    _id_edit.editable = not RESERVED_FACTION_IDS.has(fid)
    _name_edit.text = str(entry.get("name", ""))
    _update_symbol_widgets(str(entry.get("symbol_path", "")))
    var disp: String = str(entry.get("disposition_to_player", "neutral"))
    _disposition_pick.select(_disposition_index(disp))
    _rep_spin.value = float(int(entry.get("player_rep_start", 0)))
    _desc_edit.text = str(entry.get("desc", ""))
    _rebuild_relations_grid()
    _suppress = false


func _flush_detail() -> bool:
    if _suppress:
        return true
    if _selected_id.is_empty() or not _factions.has(_selected_id):
        return true
    var entry: Dictionary = _factions[_selected_id]
    entry["name"] = _name_edit.text.strip_edges()
    entry["disposition_to_player"] = _disposition_pick.get_item_text(_disposition_pick.selected)
    entry["player_rep_start"] = int(_rep_spin.value)
    entry["desc"] = _desc_edit.text
    # Symbol_path is set directly by the picker callback; relations are
    # written through their per-row item_selected handlers. The id field
    # is committed by _commit_id_rename to keep rename validation
    # centralized in one place.
    _factions[_selected_id] = entry
    return true


func _mark_dirty_and_flush() -> void:
    if _suppress:
        return
    if _flush_detail():
        _dirty = true


func _commit_id_rename() -> void:
    if _suppress:
        return
    if _selected_id.is_empty():
        return
    var old_id: String = _selected_id
    var new_id: String = _id_edit.text.strip_edges()
    if new_id == old_id:
        return
    if RESERVED_FACTION_IDS.has(old_id):
        _id_edit.text = old_id
        status_changed.emit("Reserved faction '%s' cannot be renamed." % old_id)
        return
    if not _is_valid_slug(new_id):
        _id_edit.text = old_id
        status_changed.emit("Faction id must match %s (lowercase a-z 0-9 underscore)." % ID_SLUG_REGEX)
        return
    if _factions.has(new_id):
        _id_edit.text = old_id
        status_changed.emit("Faction id '%s' already exists." % new_id)
        return

    # Look for OUTBOUND references — system.faction, placed_npc.faction,
    # dialogue speaker_faction, and inter-faction relations entries in
    # other factions on disk. Use the on-disk reference index so we catch
    # everything the runtime resolves at load time, not just whatever
    # happens to be loaded in this editor session.
    var refs: Array = ContentReferenceIndex.find_references(_pack_id, "faction", old_id)
    if refs.is_empty():
        _apply_rename_local(old_id, new_id)
        status_changed.emit("Renamed faction '%s' → '%s'." % [old_id, new_id])
        return

    # Stash and prompt. The dialog's confirmed/canceled handlers consume
    # _pending_rename_old/_pending_rename_new exactly once.
    _pending_rename_old = old_id
    _pending_rename_new = new_id
    _rename_dialog.dialog_text = _format_rename_prompt(old_id, new_id, refs)
    _rename_dialog.popup_centered(Vector2i(560, 320))


# Same in-place edits the old _commit_id_rename did, factored out so both
# the no-refs path and the dialog-confirmed path share the rewrite.
func _apply_rename_local(old_id: String, new_id: String) -> void:
    var entry: Dictionary = _factions[old_id]
    _factions.erase(old_id)
    _factions[new_id] = entry
    # Rewrite relations keys across all OTHER factions so they keep
    # pointing at this entry.
    for other_fid in _factions.keys():
        if other_fid == new_id:
            continue
        var rels: Dictionary = (_factions[other_fid] as Dictionary).get("relations", {})
        if rels.has(old_id):
            rels[new_id] = rels[old_id]
            rels.erase(old_id)
            (_factions[other_fid] as Dictionary)["relations"] = rels
    _selected_id = new_id
    _dirty = true
    _refresh_list()


# Builds the body text for the rename confirmation dialog. Lists up to 8
# concrete references so the author can sanity-check what's about to be
# rewritten, plus a "...and N more" tail when the list is longer.
func _format_rename_prompt(old_id: String, new_id: String, refs: Array) -> String:
    var lines := PackedStringArray()
    lines.append("Rename '%s' → '%s'?" % [old_id, new_id])
    lines.append("")
    lines.append("%d external reference(s) will be updated:" % refs.size())
    var limit := mini(refs.size(), 8)
    for i in range(limit):
        var ref_v: Variant = refs[i]
        if typeof(ref_v) != TYPE_DICTIONARY:
            continue
        var ref: Dictionary = ref_v
        lines.append("- %s . %s (%s)" % [
            str(ref.get("source", "")),
            str(ref.get("field", "")),
            str(ref.get("role", "")),
        ])
    if refs.size() > limit:
        lines.append("- ...and %d more." % (refs.size() - limit))
    lines.append("")
    lines.append("Cancel keeps the old id; confirming saves factions.json AND rewrites every consumer file in one pass.")
    return "\n".join(lines)


func _on_rename_confirmed() -> void:
    var old_id := _pending_rename_old
    var new_id := _pending_rename_new
    _pending_rename_old = ""
    _pending_rename_new = ""
    if old_id.is_empty() or new_id.is_empty() or not _factions.has(old_id):
        return
    # Apply in-memory rename + persist factions.json so the on-disk file
    # has the new key BEFORE rename_references runs. Without the save,
    # rename_references reads the stale old_id key from disk, and any
    # other unsaved fields on this faction would be discarded.
    _apply_rename_local(old_id, new_id)
    if not FactionsIO.save(_pack_id, _factions):
        status_changed.emit("Renamed locally but factions.json save failed; aborting external rewrite.")
        return
    _dirty = false
    var refactor: Dictionary = ContentReferenceRefactor.rename_references(
        _pack_id, "faction", old_id, new_id)
    if not bool(refactor.get("ok", true)):
        var errs: Array = refactor.get("errors", [])
        status_changed.emit("Rename saved, but reference rewrite reported errors: %s" % str(errs))
        return
    var changed_refs: int = int(refactor.get("changed_refs", 0))
    var changed_files: int = (refactor.get("changed_files", []) as Array).size()
    status_changed.emit("Renamed faction '%s' → '%s'. Updated %d reference(s) across %d file(s)." % [
        old_id, new_id, changed_refs, changed_files,
    ])


func _on_rename_canceled() -> void:
    _pending_rename_old = ""
    _pending_rename_new = ""
    # Restore the LineEdit to the currently-selected id since the rename
    # was abandoned.
    if _id_edit != null:
        _suppress = true
        _id_edit.text = _selected_id
        _suppress = false
    status_changed.emit("Rename canceled.")


func _is_valid_slug(text: String) -> bool:
    if text.is_empty() or _slug_regex == null:
        return false
    return _slug_regex.search(text) != null


func _on_disposition_selected(_idx: int) -> void:
    _mark_dirty_and_flush()


func _disposition_index(disposition: String) -> int:
    match disposition:
        "friendly": return 0
        "hostile": return 2
        _: return 1


# ─── Symbol picker ────────────────────────────────────────────────────

func _on_open_symbol_picker() -> void:
    if _symbol_dialog == null or _pack_id.is_empty():
        return
    var dir_path: String = PackPaths.writable_pack_dir(_pack_id) + "/" + FactionsIO.FOLDER + "/" + FactionsIO.SYMBOLS_SUBFOLDER
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
    _symbol_dialog.current_dir = dir_path
    _symbol_dialog.popup_centered_ratio(0.7)


func _on_symbol_picked(path: String) -> void:
    if _selected_id.is_empty() or not _factions.has(_selected_id):
        return
    var pack_symbols_dir: String = PackPaths.writable_pack_dir(_pack_id) + "/" + FactionsIO.FOLDER + "/" + FactionsIO.SYMBOLS_SUBFOLDER
    var pack_dir_abs: String = ProjectSettings.globalize_path(pack_symbols_dir)
    var picked_abs: String = ProjectSettings.globalize_path(path)
    var final_rel: String = ""
    if picked_abs.begins_with(pack_dir_abs):
        var filename: String = picked_abs.substr(pack_dir_abs.length()).lstrip("/").lstrip("\\")
        final_rel = "%s/%s/%s" % [FactionsIO.FOLDER, FactionsIO.SYMBOLS_SUBFOLDER, filename]
    else:
        # Outside the pack's symbols folder — copy it in so the symbol
        # travels with the pack on export.
        var filename: String = picked_abs.get_file()
        DirAccess.make_dir_recursive_absolute(pack_dir_abs)
        var dest_abs: String = pack_dir_abs.path_join(filename)
        var err: int = DirAccess.copy_absolute(picked_abs, dest_abs)
        if err != OK:
            status_changed.emit("Failed to copy symbol PNG (err %d)." % err)
            return
        final_rel = "%s/%s/%s" % [FactionsIO.FOLDER, FactionsIO.SYMBOLS_SUBFOLDER, filename]
    (_factions[_selected_id] as Dictionary)["symbol_path"] = final_rel
    _update_symbol_widgets(final_rel)
    _dirty = true


func _on_clear_symbol() -> void:
    if _selected_id.is_empty() or not _factions.has(_selected_id):
        return
    (_factions[_selected_id] as Dictionary)["symbol_path"] = ""
    _update_symbol_widgets("")
    _dirty = true


func _update_symbol_widgets(rel_path: String) -> void:
    if rel_path.is_empty():
        _symbol_label.text = "(no symbol)"
        _symbol_preview.texture = null
        return
    _symbol_label.text = rel_path
    var abs_user: String = PackPaths.writable_pack_file(_pack_id, rel_path)
    var path_to_load: String = ""
    if FileAccess.file_exists(abs_user):
        path_to_load = abs_user
    else:
        var shipped: String = "res://Content/%s/%s" % [_pack_id, rel_path]
        if FileAccess.file_exists(shipped):
            path_to_load = shipped
    if path_to_load.is_empty():
        _symbol_preview.texture = null
        return
    var img := Image.new()
    if img.load(path_to_load) == OK:
        _symbol_preview.texture = ImageTexture.create_from_image(img)


# ─── Relations grid ───────────────────────────────────────────────────

func _rebuild_relations_grid() -> void:
    for child in _relations_box.get_children():
        child.queue_free()
    _relations_widgets.clear()
    if _selected_id.is_empty() or not _factions.has(_selected_id):
        return
    var entry: Dictionary = _factions[_selected_id]
    var rels: Dictionary = entry.get("relations", {})
    var others: Array = []
    for fid_v in _factions.keys():
        var fid: String = str(fid_v)
        if fid != _selected_id:
            others.append(fid)
    others.sort()
    for other_fid in others:
        var row := HBoxContainer.new()
        var lbl := Label.new()
        var other_name: String = str((_factions[other_fid] as Dictionary).get("name", other_fid))
        lbl.text = "%s (%s)" % [other_name, other_fid]
        lbl.custom_minimum_size = Vector2(220, 0)
        row.add_child(lbl)
        var pick := OptionButton.new()
        for rel in FactionsIO.ALLOWED_RELATIONS:
            pick.add_item(str(rel))
        var current: String = str(rels.get(other_fid, "neutral"))
        pick.select(maxi(0, FactionsIO.ALLOWED_RELATIONS.find(current)))
        pick.item_selected.connect(_on_relation_changed.bind(other_fid))
        row.add_child(pick)
        _relations_box.add_child(row)
        _relations_widgets[other_fid] = pick
    EditorTooltipWrap.wrap_tree(_relations_box)


func _on_relation_changed(idx: int, other_fid: String) -> void:
    if _suppress or _selected_id.is_empty() or not _factions.has(_selected_id):
        return
    var entry: Dictionary = _factions[_selected_id]
    var rels: Dictionary = entry.get("relations", {})
    rels[other_fid] = str(FactionsIO.ALLOWED_RELATIONS[idx])
    entry["relations"] = rels
    _factions[_selected_id] = entry
    _dirty = true


# ─── Reserved factions ────────────────────────────────────────────────

func _ensure_reserved_factions() -> void:
    for reserved_v in RESERVED_FACTION_IDS:
        var reserved: String = reserved_v
        if not _factions.has(reserved):
            _factions[reserved] = FactionsIO.normalize_entry({
                "name": reserved.capitalize(),
                "disposition_to_player": "neutral",
                "desc": "Reserved fallback faction. Cannot be deleted.",
            })

extends Control

const PspIO = preload("res://Space/scripts/shared/psp/psp_io.gd")
const PedUtil = preload("res://Space/scripts/editor/ped/ped_util.gd")
const FRAME_ROTATION_STEP_DEG: float = 22.5

# Player editor — Sprites tab. Authors player_sheet.png + player_frames.json +
# player_poses.json for a content pack. Mounted as a child of player_editor.gd's
# content area; sized by the host.
#
# Data model (in-memory):
#   _sheet_meta = {frame_width, frame_height, center_x, center_y, sheet_cols}
#   _frames     = { pose_id: [sheet_frame_index, ...] }   (animation order)
#   _poses      = { pose_id: {name, dir, mvtype, y_radius, y_offset,
#                              collision_x,
#                              collision_width, hurtbox_x/y/w/h,
#                              weapon_anchor_x/y,
#                              timing:[int], anim_speed, loop_from, transition_to} }

var pack_id: String = ""
var dirty: bool = false

var _sheet_texture: Texture2D = null
var _sheet_textures: Dictionary = {}
var _sheet_defs: Array = []
var _active_sheet_id: String = PspIO.BASE_SHEET_ID
var _sheet_meta: Dictionary = {
    "frame_width": 50,
    "frame_height": 44,
    "center_x": 25,
    "center_y": 22,
    "sheet_cols": 10,
}
var _frames: Dictionary = {}
var _poses: Dictionary = {}
var _loaded_frames_root: Dictionary = {}
var _loaded_poses_root: Dictionary = {}
var _selected_pose_id: int = -1
var _selected_strip_idx: int = -1

# Left pose list
var _pose_list: ItemList = null
var _add_pose_btn: Button = null
var _del_pose_btn: Button = null

# Sheet panel + import
var _sheet_panel: Control = null
var _import_btn: Button = null
var _sheet_option: OptionButton = null
var _remove_sheet_btn: Button = null
var _layer_mode_btn: Button = null
var _preset_option: OptionButton = null
var _apply_preset_btn: Button = null
var _overwrite_preset_btn: Button = null
var _save_as_preset_btn: Button = null
var _save_as_preset_dialog: ConfirmationDialog = null
var _save_as_preset_id_edit: LineEdit = null
var _save_as_preset_name_edit: LineEdit = null
var _save_as_preset_desc_edit: LineEdit = null
var _save_as_preset_error_label: Label = null
var _preset_entries: Array = []
var _file_dialog: FileDialog = null
var _sheet_zoom: float = 1.0
var _sheet_pan: Vector2 = Vector2.ZERO
var _sheet_pan_active: bool = false
var _sheet_pan_start: Vector2 = Vector2.ZERO
var _sheet_pan_origin: Vector2 = Vector2.ZERO

# Sheet metadata inputs
var _fw_edit: LineEdit = null
var _fh_edit: LineEdit = null
var _cols_edit: LineEdit = null
var _rows_edit: LineEdit = null
var _cx_edit: LineEdit = null
var _cy_edit: LineEdit = null
var _meta_labels: Array = []
var _suppress_meta_events: bool = false

# Frame strip
var _strip_panel: Control = null
var _timing_edit: LineEdit = null
var _del_frame_btn: Button = null
var _rot_ccw_btn: Button = null
var _rot_cw_btn: Button = null
var _rot_reset_btn: Button = null
var _rot_value_label: Label = null

# Properties panel
var _name_edit: LineEdit = null
var _pose_id_edit: LineEdit = null
var _dir_option: OptionButton = null
var _mvtype_option: OptionButton = null
var _yrad_edit: LineEdit = null
var _yofs_edit: LineEdit = null
var _colw_edit: LineEdit = null
var _hurt_x_edit: LineEdit = null
var _hurt_y_edit: LineEdit = null
var _hurt_w_edit: LineEdit = null
var _hurt_h_edit: LineEdit = null
var _anchor_x_edit: LineEdit = null
var _anchor_y_edit: LineEdit = null
var _anim_speed_edit: LineEdit = null
var _loop_edit: LineEdit = null
var _trans_edit: LineEdit = null
var _prop_labels: Array = []

# Live preview
var _preview_sprite: Sprite2D = null
var _preview_layer_sprites: Dictionary = {}
var _preview_anchor: Control = null
var _preview_tick: float = 0.0
var _preview_anim_idx: int = 0

# Hitbox cutter state
var _cut_active: bool = false
var _cut_collision_btn: Button = null
var _cut_hurtbox_btn: Button = null
var _copy_collision_all_btn: Button = null
var _copy_hurtbox_all_btn: Button = null
var _cut_enabled: bool = false
var _cut_target: String = "collision"
var _cut_drag_mode: String = ""
var _cut_drag_rect: Rect2 = Rect2()
var _cut_origin_rect: Rect2 = Rect2()
var _cut_pointer_start: Vector2 = Vector2.ZERO

var _undo: RefCounted = null

const LEFT_W: float = 200.0
const RIGHT_W: float = 260.0
const STRIP_H: float = 128.0
const META_H: float = 44.0
const TOP_ACTION_H: float = 76.0
const DEFAULT_WEAPON_ANCHOR_Y: int = -8
const COLLISION_COLOR: Color = Color(0.35, 0.72, 1.0, 0.95)
const COLLISION_FILL_COLOR: Color = Color(0.35, 0.72, 1.0, 0.12)
const HURTBOX_COLOR: Color = Color(1.0, 0.38, 0.38, 0.95)
const HURTBOX_FILL_COLOR: Color = Color(1.0, 0.38, 0.38, 0.12)
const FRAME_BOX_KEYS: Array = [
    "y_radius",
    "y_offset",
    "collision_x",
    "collision_width",
    "hurtbox_x",
    "hurtbox_y",
    "hurtbox_w",
    "hurtbox_h",
]

const MVTYPE_NAMES: Array = [
    ["Stand / Idle", 0, "Default grounded idle pose."],
    ["Run", 1, "Ground movement pose while running."],
    ["Jump Rise", 2, "Upward jump pose while the player is ascending."],
    ["Spin / Ball", 3, "Spin or morph-ball style movement pose."],
    ["Crouch", 5, "Grounded crouch pose."],
    ["Fall", 6, "Airborne falling pose after upward momentum is gone."],
    ["Turn Around", 14, "Grounded turnaround pose when reversing direction."],
    ["Transition", 15, "Bridge pose used between other movement states."],
    ["Wall Jump", 20, "Pose played during or right after a wall jump."],
    ["Turn In Air", 23, "Airborne turnaround pose while changing facing."],
    ["Turn While Falling", 24, "Falling turnaround pose."],
    ["Parry", 30, "Defensive parry pose. Plays when the player presses the parry input (Q). Combat / deflect behavior is authored separately."],
    ["Knockdown", 31, "Player has been knocked down. Played by attacks that explicitly call apply_knockdown() (not by ordinary damage). Author this as a one-shot animation with transition_to set to the matching stand_up pose ID; input is locked and invuln granted for the whole knockdown -> stand_up chain."],
    ["Stand Up", 32, "Stand-up animation that plays after Knockdown finishes. Author this as a one-shot with transition_to set to the standing pose ID (1 for right, 2 for left). The chain ends when this pose transitions out, which releases the input lock."],
]


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "sheet_meta": _sheet_meta.duplicate(true),
        "sheet_defs": _sheet_defs.duplicate(true),
        "frames": _frames.duplicate(true),
        "poses": _poses.duplicate(true),
        "sheet_zoom": _sheet_zoom,
        "sheet_pan": _sheet_pan,
        "active_sheet_id": _active_sheet_id,
        "selected_pose_id": _selected_pose_id,
        "selected_strip_idx": _selected_strip_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var sm_v: Variant = snap.get("sheet_meta", null)
    if typeof(sm_v) == TYPE_DICTIONARY:
        _sheet_meta = sm_v
    var sd_v: Variant = snap.get("sheet_defs", null)
    if typeof(sd_v) == TYPE_ARRAY:
        _sheet_defs = sd_v
    var f_v: Variant = snap.get("frames", null)
    if typeof(f_v) == TYPE_DICTIONARY:
        _frames = f_v
    var p_v: Variant = snap.get("poses", null)
    if typeof(p_v) == TYPE_DICTIONARY:
        _poses = p_v
    _sheet_zoom = float(snap.get("sheet_zoom", 1.0))
    var pan_v: Variant = snap.get("sheet_pan", Vector2.ZERO)
    if pan_v is Vector2:
        _sheet_pan = pan_v
    _active_sheet_id = str(snap.get("active_sheet_id", PspIO.BASE_SHEET_ID))
    _selected_pose_id = int(snap.get("selected_pose_id", -1))
    _selected_strip_idx = int(snap.get("selected_strip_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _sheet_textures = PspIO.load_sheet_textures(pack_id, _sheet_defs)
    _sheet_texture = _active_sheet_texture()
    _rebuild_sheet_option()
    _rebuild_preview_layer_sprites()
    _populate_pose_list()
    if _pose_list != null and _selected_pose_id >= 0 and _poses.has(_selected_pose_id):
        var keys: Array = _poses.keys()
        keys.sort()
        var idx := keys.find(_selected_pose_id)
        if idx >= 0:
            _pose_list.select(idx)
    _apply_pose_to_inputs()
    _apply_sheet_meta_to_inputs()
    _apply_preview_sprite_layout()
    if _sheet_panel != null:
        _sheet_panel.queue_redraw()
    if _strip_panel != null:
        _strip_panel.queue_redraw()


func _input(event: InputEvent) -> void:
    if not is_visible_in_tree():
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if _has_text_focus():
            return
        if _undo != null and _undo.handle_key(event):
            get_viewport().set_input_as_handled()


func _has_text_focus() -> bool:
    var focused := get_viewport().gui_get_focus_owner()
    if focused == null:
        return false
    return focused is LineEdit or focused is TextEdit


func _notification(what: int) -> void:
    if what == NOTIFICATION_RESIZED:
        _layout_children()


func _process(delta: float) -> void:
    if not is_visible_in_tree():
        return
    _tick_preview(delta)
    _update_tooltips()


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    # Sheet metadata fields
    if _fw_edit != null and Rect2(_fw_edit.position, _fw_edit.size).has_point(mp):
        EditorTooltip.show_text("Frame width in pixels. Each cell in the sprite sheet grid is this wide. Must match the actual art.")
    elif _fh_edit != null and Rect2(_fh_edit.position, _fh_edit.size).has_point(mp):
        EditorTooltip.show_text("Frame height in pixels. Each cell in the sprite sheet grid is this tall. Must match the actual art.")
    elif _cols_edit != null and Rect2(_cols_edit.position, _cols_edit.size).has_point(mp):
        EditorTooltip.show_text("Number of columns in the sprite sheet grid. The runtime uses this to convert a flat frame index into a row/column UV lookup.")
    elif _rows_edit != null and Rect2(_rows_edit.position, _rows_edit.size).has_point(mp):
        EditorTooltip.show_text("Number of rows in the sprite sheet grid. Auto-calculated from the sheet height and frame height if left at 0.")
    elif _cx_edit != null and Rect2(_cx_edit.position, _cx_edit.size).has_point(mp):
        EditorTooltip.show_text("Center X -- horizontal pivot point within each frame, in pixels from the left edge. Used to align the sprite on the collision center.")
    elif _cy_edit != null and Rect2(_cy_edit.position, _cy_edit.size).has_point(mp):
        EditorTooltip.show_text("Center Y -- vertical pivot point within each frame, in pixels from the top edge. Used to align the sprite on the collision center.")
    # Pose property fields
    elif _yrad_edit != null and Rect2(_yrad_edit.position, _yrad_edit.size).has_point(mp):
        EditorTooltip.show_text("Y Radius -- half-height of the player's collision box while in this pose. Smaller values crouch the hitbox (e.g. 8 for ducking vs 16 for standing).")
    elif _yofs_edit != null and Rect2(_yofs_edit.position, _yofs_edit.size).has_point(mp):
        EditorTooltip.show_text("Y Offset -- vertical pixel shift of the sprite relative to the collision center. Use this to align art that doesn't sit centered on the hitbox.")
    elif _colw_edit != null and Rect2(_colw_edit.position, _colw_edit.size).has_point(mp):
        EditorTooltip.show_text("Collision Width -- horizontal size of the player's solid physics body for this pose. Use this for crouches, spins, or narrow poses that should collide differently from the standing profile.")
    elif _hurt_x_edit != null and Rect2(_hurt_x_edit.position, _hurt_x_edit.size).has_point(mp):
        EditorTooltip.show_text("Hurtbox X -- horizontal offset of the damageable hurtbox center from the player's origin for this pose. Enemy projectiles can target this instead of the whole body.")
    elif _hurt_y_edit != null and Rect2(_hurt_y_edit.position, _hurt_y_edit.size).has_point(mp):
        EditorTooltip.show_text("Hurtbox Y -- vertical offset of the damageable hurtbox center from the player's origin for this pose. Negative values move it upward.")
    elif _hurt_w_edit != null and Rect2(_hurt_w_edit.position, _hurt_w_edit.size).has_point(mp):
        EditorTooltip.show_text("Hurtbox Width -- width of the damageable hurtbox rectangle for this pose. Keep it tight to the actual body art, not the whole animation frame.")
    elif _hurt_h_edit != null and Rect2(_hurt_h_edit.position, _hurt_h_edit.size).has_point(mp):
        EditorTooltip.show_text("Hurtbox Height -- height of the damageable hurtbox rectangle for this pose. This can be smaller than the collision box when the animation has extra cloth, hair, or weapon motion.")
    elif _anchor_x_edit != null and Rect2(_anchor_x_edit.position, _anchor_x_edit.size).has_point(mp):
        EditorTooltip.show_text("Weapon Anchor X -- horizontal attack origin offset from the player's origin for this pose. Used as the base muzzle / shoulder point for aimed attacks.")
    elif _anchor_y_edit != null and Rect2(_anchor_y_edit.position, _anchor_y_edit.size).has_point(mp):
        EditorTooltip.show_text("Weapon Anchor Y -- vertical attack origin offset from the player's origin for this pose. Lets each pose aim from the correct shoulder or hand height.")
    elif _anim_speed_edit != null and Rect2(_anim_speed_edit.position, _anim_speed_edit.size).has_point(mp):
        EditorTooltip.show_text("Animation Speed -- playback multiplier for this pose. 1.0 is normal speed, 2.0 is twice as fast, and 0.5 is half speed.")
    elif _mvtype_option != null and Rect2(_mvtype_option.position, _mvtype_option.size).has_point(mp):
        EditorTooltip.show_text("Movement state tag. The controller picks poses by state: Stand / Idle = default grounded pose, Run = ground movement, Jump Rise = ascending, Fall = descending, Turn Around = grounded facing swap, Transition = bridge pose between states, Wall Jump = wall-jump pose, Turn In Air / Turn While Falling = airborne direction changes.")
    elif _loop_edit != null and Rect2(_loop_edit.position, _loop_edit.size).has_point(mp):
        EditorTooltip.show_text("Loop From -- frame index the animation rewinds to after reaching the last frame. Set to 0 to loop the whole sequence, or higher to skip an intro.")
    elif _trans_edit != null and Rect2(_trans_edit.position, _trans_edit.size).has_point(mp):
        EditorTooltip.show_text("Transition To -- pose ID to switch to after this animation finishes. Use -1 for no transition (the pose loops instead).")
    elif _timing_edit != null and Rect2(_timing_edit.position, _timing_edit.size).has_point(mp):
        EditorTooltip.show_text("Frame hold time in physics ticks (1/60 s). Higher values make this frame display longer. Select a frame in the strip first.")
    elif _preset_option != null and Rect2(_preset_option.position, _preset_option.size).has_point(mp):
        EditorTooltip.show_text("Shipped player-sprite presets. These swap the whole sprite setup: sheets, frame strips, and pose timings.")
    elif _apply_preset_btn != null and Rect2(_apply_preset_btn.position, _apply_preset_btn.size).has_point(mp):
        EditorTooltip.show_text("Apply the selected preset into this pack's player sprite data. This rewrites the current sprite setup for the active pack.")
    elif _overwrite_preset_btn != null and Rect2(_overwrite_preset_btn.position, _overwrite_preset_btn.size).has_point(mp):
        EditorTooltip.show_text("Overwrite the selected preset with the current editor state so you can fix and reship a preset from this tab.")
    elif _save_as_preset_btn != null and Rect2(_save_as_preset_btn.position, _save_as_preset_btn.size).has_point(mp):
        EditorTooltip.show_text("Save the current editor state as a brand-new preset inside this pack. The preset is written to res://Content/<pack>/Sprites/presets/<id>/ alongside its sheet PNGs so it ships with the pack.")
    elif _rot_ccw_btn != null and Rect2(_rot_ccw_btn.position, _rot_ccw_btn.size).has_point(mp):
        EditorTooltip.show_text("Rotate the selected frame 22.5 degrees counter-clockwise. Useful for spin frames when the source pack doesn't ship a dedicated spin strip.")
    elif _rot_cw_btn != null and Rect2(_rot_cw_btn.position, _rot_cw_btn.size).has_point(mp):
        EditorTooltip.show_text("Rotate the selected frame 22.5 degrees clockwise.")
    elif _rot_reset_btn != null and Rect2(_rot_reset_btn.position, _rot_reset_btn.size).has_point(mp):
        EditorTooltip.show_text("Clear any authored frame rotation on the selected strip frame.")
    elif _dir_option != null and Rect2(_dir_option.position, _dir_option.size).has_point(mp):
        EditorTooltip.show_text("Facing direction for this pose. Left-facing poses can leave their frame strip empty and automatically mirror a matching right-facing pose such as stand_right -> stand_left.")
    elif _name_edit != null and Rect2(_name_edit.position, _name_edit.size).has_point(mp):
        EditorTooltip.show_text("Display name for this pose. Only used in the editor list -- the runtime identifies poses by their numeric ID.")
    elif _pose_id_edit != null and Rect2(_pose_id_edit.position, _pose_id_edit.size).has_point(mp):
        EditorTooltip.show_text("Numeric pose ID. The player controller references poses by this number. Changing it here re-keys the pose in the data.")
    elif _cut_collision_btn != null and Rect2(_cut_collision_btn.position, _cut_collision_btn.size).has_point(mp):
        EditorTooltip.show_text("Toggle collision cutter. Drag inside the blue box to move it, drag the edge handles to resize it, or drag empty space to draw a new one. This writes collision_x, collision_width, y_radius, and y_offset for this pose.")
    elif _cut_hurtbox_btn != null and Rect2(_cut_hurtbox_btn.position, _cut_hurtbox_btn.size).has_point(mp):
        EditorTooltip.show_text("Toggle hurtbox cutter. Drag inside the red box to move it, drag the edge handles to resize it, or drag empty space to draw a new one. This writes hurtbox_x, hurtbox_y, hurtbox_w, and hurtbox_h for this pose.")
    elif _copy_collision_all_btn != null and Rect2(_copy_collision_all_btn.position, _copy_collision_all_btn.size).has_point(mp):
        EditorTooltip.show_text("Copy the current pose's collision settings to every pose. Left-facing poses mirror the horizontal offset automatically when their direction differs from the source pose.")
    elif _copy_hurtbox_all_btn != null and Rect2(_copy_hurtbox_all_btn.position, _copy_hurtbox_all_btn.size).has_point(mp):
        EditorTooltip.show_text("Copy the current pose's hurtbox settings to every pose. Left-facing poses mirror the horizontal offset automatically when their direction differs from the source pose.")


# ─── Public API (host calls these) ───────────────────────────────────────

func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_pack_data()
    _populate_pose_list()
    if _pose_list != null and _pose_list.item_count > 0:
        _pose_list.select(0)
        _on_pose_list_selected(0)
    _layout_children()
    dirty = false
    if _undo != null:
        _undo.clear()


func _on_apply_preset_pressed() -> void:
    var preset_id: String = _selected_preset_id()
    if preset_id.is_empty():
        return
    if not PspIO.apply_preset(pack_id, preset_id):
        push_error("[PedSpritesTab] failed to apply preset '%s'" % preset_id)
        return
    _selected_pose_id = -1
    _selected_strip_idx = -1
    _load_pack_data()
    _populate_pose_list()
    if _pose_list != null and _pose_list.item_count > 0:
        _pose_list.select(0)
        _on_pose_list_selected(0)
    dirty = false
    if _undo != null:
        _undo.clear()


func _on_overwrite_preset_pressed() -> void:
    var preset_id: String = _selected_preset_id()
    if preset_id.is_empty():
        return
    var payload: Dictionary = _build_save_payload()
    var frames_data_v: Variant = payload.get("frames", {})
    var poses_data_v: Variant = payload.get("poses", {})
    if typeof(frames_data_v) != TYPE_DICTIONARY or typeof(poses_data_v) != TYPE_DICTIONARY:
        push_error("[PedSpritesTab] invalid overwrite payload for preset '%s'" % preset_id)
        return
    var frames_data: Dictionary = frames_data_v
    var poses_data: Dictionary = poses_data_v
    if not _commit_save_payload(frames_data, poses_data):
        push_error("[PedSpritesTab] overwrite preset aborted because saving the current pack failed")
        return
    if not PspIO.overwrite_preset(pack_id, preset_id, frames_data, poses_data):
        push_error("[PedSpritesTab] failed to overwrite preset '%s'" % preset_id)
        return


func _on_save_as_preset_pressed() -> void:
    _ensure_save_as_preset_dialog()
    if _save_as_preset_id_edit != null:
        _save_as_preset_id_edit.text = ""
    if _save_as_preset_name_edit != null:
        _save_as_preset_name_edit.text = ""
    if _save_as_preset_desc_edit != null:
        _save_as_preset_desc_edit.text = ""
    if _save_as_preset_error_label != null:
        _save_as_preset_error_label.text = ""
        _save_as_preset_error_label.visible = false
    _save_as_preset_dialog.popup_centered(Vector2(420, 280))
    if _save_as_preset_id_edit != null:
        _save_as_preset_id_edit.grab_focus()


func _ensure_save_as_preset_dialog() -> void:
    if _save_as_preset_dialog != null:
        return
    _save_as_preset_dialog = ConfirmationDialog.new()
    _save_as_preset_dialog.title = "Save current sprites as new preset"
    _save_as_preset_dialog.ok_button_text = "Save preset"
    _save_as_preset_dialog.cancel_button_text = "Cancel"
    _save_as_preset_dialog.hide_on_ok = false
    _save_as_preset_dialog.get_ok_button().disabled = false

    var vbox := VBoxContainer.new()
    vbox.custom_minimum_size = Vector2(380, 0)

    var id_label := Label.new()
    id_label.text = "Preset ID (lowercase letters, digits, underscores)"
    vbox.add_child(id_label)
    _save_as_preset_id_edit = LineEdit.new()
    _save_as_preset_id_edit.placeholder_text = "my_preset"
    vbox.add_child(_save_as_preset_id_edit)

    var name_label := Label.new()
    name_label.text = "Display name"
    vbox.add_child(name_label)
    _save_as_preset_name_edit = LineEdit.new()
    _save_as_preset_name_edit.placeholder_text = "My Preset"
    vbox.add_child(_save_as_preset_name_edit)

    var desc_label := Label.new()
    desc_label.text = "Description (optional)"
    vbox.add_child(desc_label)
    _save_as_preset_desc_edit = LineEdit.new()
    _save_as_preset_desc_edit.placeholder_text = "Notes about this preset"
    vbox.add_child(_save_as_preset_desc_edit)

    _save_as_preset_error_label = Label.new()
    _save_as_preset_error_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4, 1.0))
    _save_as_preset_error_label.visible = false
    vbox.add_child(_save_as_preset_error_label)

    _save_as_preset_dialog.add_child(vbox)
    _save_as_preset_dialog.confirmed.connect(_on_save_as_preset_confirmed)
    add_child(_save_as_preset_dialog)


func _on_save_as_preset_confirmed() -> void:
    var raw_id: String = _save_as_preset_id_edit.text if _save_as_preset_id_edit != null else ""
    var preset_id: String = raw_id.strip_edges()
    if preset_id.is_empty():
        _show_save_as_preset_error("Preset ID is required.")
        return
    var lowered: String = preset_id.to_lower()
    for c in lowered:
        if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
            _show_save_as_preset_error("Preset ID may only contain lowercase letters, digits, and underscores.")
            return
    preset_id = lowered

    var preset_name: String = ""
    if _save_as_preset_name_edit != null:
        preset_name = _save_as_preset_name_edit.text.strip_edges()
    var preset_desc: String = ""
    if _save_as_preset_desc_edit != null:
        preset_desc = _save_as_preset_desc_edit.text.strip_edges()

    var payload: Dictionary = _build_save_payload()
    var frames_data_v: Variant = payload.get("frames", {})
    var poses_data_v: Variant = payload.get("poses", {})
    if typeof(frames_data_v) != TYPE_DICTIONARY or typeof(poses_data_v) != TYPE_DICTIONARY:
        _show_save_as_preset_error("Could not build sprite payload from current state.")
        return
    var frames_data: Dictionary = frames_data_v
    var poses_data: Dictionary = poses_data_v

    if not _commit_save_payload(frames_data, poses_data):
        _show_save_as_preset_error("Saving the current pack failed; preset not written.")
        return

    if not PspIO.save_as_new_preset(pack_id, preset_id, preset_name, preset_desc, frames_data, poses_data):
        _show_save_as_preset_error("Preset '%s' could not be written. Check the Godot console." % preset_id)
        return

    _preset_entries = PspIO.list_presets(pack_id)
    _rebuild_preset_option()
    if _preset_option != null:
        for i in range(_preset_entries.size()):
            var entry_v: Variant = _preset_entries[i]
            if typeof(entry_v) != TYPE_DICTIONARY:
                continue
            if str((entry_v as Dictionary).get("id", "")).strip_edges() == preset_id:
                _preset_option.select(i)
                break
    if _save_as_preset_dialog != null:
        _save_as_preset_dialog.hide()


func _show_save_as_preset_error(msg: String) -> void:
    if _save_as_preset_error_label != null:
        _save_as_preset_error_label.text = msg
        _save_as_preset_error_label.visible = true


func save() -> bool:
    var payload: Dictionary = _build_save_payload()
    var frames_data_v: Variant = payload.get("frames", {})
    var poses_data_v: Variant = payload.get("poses", {})
    if typeof(frames_data_v) != TYPE_DICTIONARY or typeof(poses_data_v) != TYPE_DICTIONARY:
        push_error("[PedSpritesTab] save payload build failed for pack '%s'" % pack_id)
        return false
    var frames_data: Dictionary = frames_data_v
    var poses_data: Dictionary = poses_data_v
    if _commit_save_payload(frames_data, poses_data):
        return true
    push_error("[PedSpritesTab] save failed for pack '%s'" % pack_id)
    return false


func _build_save_payload() -> Dictionary:
    var out_frames: Array = []
    var pose_keys: Array = _frames.keys()
    pose_keys.sort()
    for pose_id in pose_keys:
        var seq: Array = _frames[pose_id]
        for frame_v in seq:
            var frame_entry: Dictionary = _normalize_frame_entry(frame_v)
            frame_entry["pose"] = int(pose_id)
            out_frames.append(frame_entry)

    var frames_data: Dictionary = _loaded_frames_root.duplicate(true)
    frames_data["frame_width"] = int(_sheet_meta["frame_width"])
    frames_data["frame_height"] = int(_sheet_meta["frame_height"])
    frames_data["center_x"] = int(_sheet_meta["center_x"])
    frames_data["center_y"] = int(_sheet_meta["center_y"])
    frames_data["sheet_cols"] = int(_sheet_meta["sheet_cols"])
    frames_data["sheets"] = _sheet_defs.duplicate(true)
    frames_data["frames"] = out_frames

    var out_poses: Dictionary = {}
    for pose_id in _poses.keys():
        var p: Dictionary = _sanitized_pose_for_save(int(pose_id), _poses[pose_id])
        out_poses[str(int(pose_id))] = {
            "name":          str(p.get("name", "")),
            "dir":           int(p.get("dir", 1)),
            "mvtype":        int(p.get("mvtype", 0)),
            "y_radius":      int(p.get("y_radius", 16)),
            "y_offset":      int(p.get("y_offset", 0)),
            "collision_x":   int(p.get("collision_x", 0)),
            "collision_width": int(p.get("collision_width", _default_collision_width())),
            "hurtbox_x":     int(p.get("hurtbox_x", 0)),
            "hurtbox_y":     int(p.get("hurtbox_y", _default_hurtbox_y(p))),
            "hurtbox_w":     int(p.get("hurtbox_w", int(p.get("collision_width", _default_collision_width())))),
            "hurtbox_h":     int(p.get("hurtbox_h", int(p.get("y_radius", 16)) * 2)),
            "weapon_anchor_x": int(p.get("weapon_anchor_x", 0)),
            "weapon_anchor_y": int(p.get("weapon_anchor_y", _default_weapon_anchor_y(p))),
            "timing":        _normalized_timing_for_save(int(pose_id), p),
            "anim_speed":    _normalized_anim_speed(p.get("anim_speed", 1.0)),
            "frame_boxes":   _serialize_frame_boxes(p.get("frame_boxes", [])),
            "loop_from":     int(p.get("loop_from", 0)),
            "transition_to": int(p.get("transition_to", -1)),
        }
    var poses_data: Dictionary = _loaded_poses_root.duplicate(true)
    poses_data["poses"] = out_poses

    return {
        "frames": frames_data,
        "poses": poses_data,
    }


func _sanitized_pose_for_save(pose_id: int, pose_v: Variant) -> Dictionary:
    var pose: Dictionary = {}
    if typeof(pose_v) == TYPE_DICTIONARY:
        pose = (pose_v as Dictionary).duplicate(true)
    pose["timing"] = _normalized_timing_for_save(pose_id, pose)
    var local_frame_count: int = 0
    if _frames.has(pose_id):
        local_frame_count = (_frames[pose_id] as Array).size()
    pose = _ensure_frame_boxes_size(pose, local_frame_count)
    return pose


func _normalized_timing_for_save(pose_id: int, pose: Dictionary) -> Array:
    var timing: Array = _int_array(pose.get("timing", []))
    var local_frame_count: int = 0
    if _frames.has(pose_id):
        local_frame_count = (_frames[pose_id] as Array).size()

    var owner_id: int = _resolved_animation_owner_id(pose_id)
    var owner_frame_count: int = local_frame_count
    if owner_id >= 0 and _frames.has(owner_id):
        owner_frame_count = (_frames[owner_id] as Array).size()

    if timing.is_empty() and owner_id >= 0 and owner_id != pose_id and _poses.has(owner_id):
        timing = _int_array((_poses[owner_id] as Dictionary).get("timing", []))

    var desired_size: int = owner_frame_count if owner_frame_count > 0 else 1
    if timing.is_empty():
        while timing.size() < desired_size:
            timing.append(10)
        return timing

    var last_ticks: int = maxi(1, int(timing[timing.size() - 1]))
    while timing.size() < desired_size:
        timing.append(last_ticks)
    while owner_frame_count > 0 and timing.size() > desired_size:
        timing.remove_at(timing.size() - 1)

    for i in timing.size():
        timing[i] = maxi(1, int(timing[i]))
    return timing


func _commit_save_payload(frames_data: Dictionary, poses_data: Dictionary) -> bool:
    var ok_f: bool = PspIO.save_frames(pack_id, frames_data)
    var ok_p: bool = PspIO.save_poses(pack_id, poses_data)
    if not ok_f or not ok_p:
        return false
    _loaded_frames_root = frames_data.duplicate(true)
    _loaded_poses_root = poses_data.duplicate(true)
    dirty = false
    return true


func is_dirty() -> bool:
    return dirty


# ─── Layout construction ─────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.09, 0.1, 0.13, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _import_btn = Button.new()
    _import_btn.text = "ADD SHEET"
    _import_btn.pressed.connect(_on_import_pressed)
    add_child(_import_btn)

    _sheet_option = OptionButton.new()
    _sheet_option.item_selected.connect(_on_sheet_option_selected)
    add_child(_sheet_option)

    _remove_sheet_btn = Button.new()
    _remove_sheet_btn.text = "REMOVE"
    _remove_sheet_btn.pressed.connect(_on_remove_sheet_pressed)
    add_child(_remove_sheet_btn)

    _layer_mode_btn = Button.new()
    _layer_mode_btn.text = "LAYER FRAME"
    _layer_mode_btn.toggle_mode = true
    add_child(_layer_mode_btn)

    _preset_option = OptionButton.new()
    add_child(_preset_option)

    _apply_preset_btn = Button.new()
    _apply_preset_btn.text = "APPLY PRESET"
    _apply_preset_btn.pressed.connect(_on_apply_preset_pressed)
    add_child(_apply_preset_btn)

    _overwrite_preset_btn = Button.new()
    _overwrite_preset_btn.text = "OVERWRITE PRESET"
    _overwrite_preset_btn.pressed.connect(_on_overwrite_preset_pressed)
    add_child(_overwrite_preset_btn)

    _save_as_preset_btn = Button.new()
    _save_as_preset_btn.text = "SAVE AS PRESET"
    _save_as_preset_btn.pressed.connect(_on_save_as_preset_pressed)
    add_child(_save_as_preset_btn)

    _pose_list = ItemList.new()
    _pose_list.item_selected.connect(_on_pose_list_selected)
    add_child(_pose_list)

    _add_pose_btn = Button.new()
    _add_pose_btn.text = "+ POSE"
    _add_pose_btn.pressed.connect(_on_add_pose_pressed)
    add_child(_add_pose_btn)

    _del_pose_btn = Button.new()
    _del_pose_btn.text = "- POSE"
    _del_pose_btn.pressed.connect(_on_del_pose_pressed)
    add_child(_del_pose_btn)

    _sheet_panel = Control.new()
    _sheet_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _sheet_panel.clip_contents = true
    _sheet_panel.draw.connect(_draw_sheet_panel)
    _sheet_panel.gui_input.connect(_on_sheet_gui_input)
    add_child(_sheet_panel)

    _fw_edit = _make_int_edit(_on_frame_size_changed)
    _fh_edit = _make_int_edit(_on_frame_size_changed)
    _cols_edit = _make_int_edit(_on_grid_changed)
    _rows_edit = _make_int_edit(_on_grid_changed)
    _cx_edit = _make_int_edit(_on_center_changed)
    _cy_edit = _make_int_edit(_on_center_changed)
    add_child(_fw_edit)
    add_child(_fh_edit)
    add_child(_cols_edit)
    add_child(_rows_edit)
    add_child(_cx_edit)
    add_child(_cy_edit)

    # Labels for sheet metadata fields
    _meta_labels = []
    var mlabel_texts := ["W:", "H:", "Cols:", "Rows:", "CX:", "CY:"]
    for mlt in mlabel_texts:
        var lbl := Label.new()
        lbl.text = mlt
        lbl.add_theme_font_size_override("font_size", 10)
        lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1.0))
        add_child(lbl)
        _meta_labels.append(lbl)

    _strip_panel = Control.new()
    _strip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
    _strip_panel.draw.connect(_draw_strip_panel)
    _strip_panel.gui_input.connect(_on_strip_gui_input)
    add_child(_strip_panel)

    _timing_edit = _make_int_edit(_on_timing_changed)
    _timing_edit.placeholder_text = "ticks"
    add_child(_timing_edit)

    _del_frame_btn = Button.new()
    _del_frame_btn.text = "DELETE FRAME"
    _del_frame_btn.pressed.connect(_on_del_frame_pressed)
    add_child(_del_frame_btn)

    _rot_ccw_btn = Button.new()
    _rot_ccw_btn.text = "rot cnt"
    _rot_ccw_btn.pressed.connect(func(): _rotate_selected_frame(-FRAME_ROTATION_STEP_DEG))
    add_child(_rot_ccw_btn)

    _rot_cw_btn = Button.new()
    _rot_cw_btn.text = "rot cws"
    _rot_cw_btn.pressed.connect(func(): _rotate_selected_frame(FRAME_ROTATION_STEP_DEG))
    add_child(_rot_cw_btn)

    _rot_reset_btn = Button.new()
    _rot_reset_btn.text = "RESET ROT"
    _rot_reset_btn.pressed.connect(func(): _set_selected_frame_rotation(0.0))
    add_child(_rot_reset_btn)

    _rot_value_label = Label.new()
    _rot_value_label.add_theme_font_size_override("font_size", 10)
    _rot_value_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 1.0))
    add_child(_rot_value_label)

    _name_edit = LineEdit.new()
    _name_edit.text_changed.connect(func(_t): _on_pose_field_changed())
    add_child(_name_edit)

    _pose_id_edit = _make_int_edit(_on_pose_id_changed)
    add_child(_pose_id_edit)

    _dir_option = OptionButton.new()
    _dir_option.add_item("Right-facing", 1)
    _dir_option.add_item("Left-facing", -1)
    _dir_option.item_selected.connect(func(_i): _on_pose_field_changed())
    add_child(_dir_option)

    _mvtype_option = OptionButton.new()
    for pair in MVTYPE_NAMES:
        _mvtype_option.add_item(str(pair[0]), int(pair[1]))
        _mvtype_option.set_item_tooltip(_mvtype_option.item_count - 1, str(pair[2]))
    _mvtype_option.item_selected.connect(func(_i): _on_pose_field_changed())
    add_child(_mvtype_option)

    _yrad_edit = _make_int_edit(_on_pose_field_changed)
    _yofs_edit = _make_int_edit(_on_pose_field_changed)
    _colw_edit = _make_int_edit(_on_pose_field_changed)
    _hurt_x_edit = _make_int_edit(_on_pose_field_changed)
    _hurt_y_edit = _make_int_edit(_on_pose_field_changed)
    _hurt_w_edit = _make_int_edit(_on_pose_field_changed)
    _hurt_h_edit = _make_int_edit(_on_pose_field_changed)
    _anchor_x_edit = _make_int_edit(_on_pose_field_changed)
    _anchor_y_edit = _make_int_edit(_on_pose_field_changed)
    _anim_speed_edit = _make_float_edit(_on_pose_field_changed)
    _anim_speed_edit.placeholder_text = "1.0"
    _loop_edit = _make_int_edit(_on_pose_field_changed)
    _trans_edit = _make_int_edit(_on_pose_field_changed)
    add_child(_yrad_edit)
    add_child(_yofs_edit)
    add_child(_colw_edit)
    add_child(_hurt_x_edit)
    add_child(_hurt_y_edit)
    add_child(_hurt_w_edit)
    add_child(_hurt_h_edit)
    add_child(_anchor_x_edit)
    add_child(_anchor_y_edit)
    add_child(_anim_speed_edit)
    add_child(_loop_edit)
    add_child(_trans_edit)

    # Labels for the right-side property fields.
    _prop_labels = []
    var label_names := [
        "Name", "Pose ID", "Direction", "Move Type",
        "Y Radius", "Y Offset", "Col Width",
        "Hurtbox X", "Hurtbox Y", "Hurtbox W", "Hurtbox H",
        "Anchor X", "Anchor Y",
        "Anim Speed",
        "Loop From", "Transition"
    ]
    for lname in label_names:
        var lbl := Label.new()
        lbl.text = lname
        lbl.add_theme_font_size_override("font_size", 11)
        lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 1.0))
        add_child(lbl)
        _prop_labels.append(lbl)

    _preview_anchor = Control.new()
    _preview_anchor.mouse_filter = Control.MOUSE_FILTER_STOP
    _preview_anchor.draw.connect(_draw_preview_bg)
    _preview_anchor.gui_input.connect(_on_preview_gui_input)
    add_child(_preview_anchor)

    _preview_sprite = Sprite2D.new()
    _preview_sprite.centered = true
    _preview_anchor.add_child(_preview_sprite)
    _preview_layer_sprites[PspIO.BASE_SHEET_ID] = _preview_sprite

    _cut_collision_btn = Button.new()
    _cut_collision_btn.text = "CUT COLLISION"
    _cut_collision_btn.toggle_mode = true
    _cut_collision_btn.toggled.connect(_on_cut_collision_toggled)
    add_child(_cut_collision_btn)

    _cut_hurtbox_btn = Button.new()
    _cut_hurtbox_btn.text = "CUT HURTBOX"
    _cut_hurtbox_btn.toggle_mode = true
    _cut_hurtbox_btn.toggled.connect(_on_cut_hurtbox_toggled)
    add_child(_cut_hurtbox_btn)

    _copy_collision_all_btn = Button.new()
    _copy_collision_all_btn.text = "COPY COLLISION TO ALL"
    _copy_collision_all_btn.pressed.connect(_on_copy_collision_all_pressed)
    add_child(_copy_collision_all_btn)

    _copy_hurtbox_all_btn = Button.new()
    _copy_hurtbox_all_btn.text = "COPY HURTBOX TO ALL"
    _copy_hurtbox_all_btn.pressed.connect(_on_copy_hurtbox_all_pressed)
    add_child(_copy_hurtbox_all_btn)

    _layout_children()


func _make_int_edit(cb: Callable) -> LineEdit:
    var le := LineEdit.new()
    le.text_changed.connect(func(_t): cb.call())
    return le


func _make_float_edit(cb: Callable) -> LineEdit:
    var le := LineEdit.new()
    le.text_changed.connect(func(_t): cb.call())
    return le


func _active_sheet_texture() -> Texture2D:
    return _sheet_textures.get(_active_sheet_id, null) as Texture2D


func _normalize_frame_entry(frame_v: Variant) -> Dictionary:
    return PspIO.normalize_frame_entry(frame_v)


func _frame_layers(frame_v: Variant) -> Array:
    var entry: Dictionary = _normalize_frame_entry(frame_v)
    var layers_v: Variant = entry.get("layers", [])
    return layers_v if typeof(layers_v) == TYPE_ARRAY else []


func _frame_primary_index(frame_v: Variant, preferred_sheet_id: String = "") -> int:
    var layers: Array = _frame_layers(frame_v)
    if layers.is_empty():
        return 0
    if not preferred_sheet_id.is_empty():
        for layer_v in layers:
            if typeof(layer_v) != TYPE_DICTIONARY:
                continue
            var layer: Dictionary = layer_v
            if str(layer.get("sheet", "")).strip_edges() == preferred_sheet_id:
                return int(layer.get("index", 0))
    return int((layers[0] as Dictionary).get("index", 0))


func _frame_has_sheet(frame_v: Variant, sheet_id: String) -> bool:
    for layer_v in _frame_layers(frame_v):
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        if str((layer_v as Dictionary).get("sheet", "")).strip_edges() == sheet_id:
            return true
    return false


func _sheet_z(sheet_id: String) -> int:
    for sheet_def_v in _sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        if str(sheet_def.get("id", "")).strip_edges() == sheet_id:
            return int(sheet_def.get("z", 0))
    return 0


func _sorted_frame_layers(frame_v: Variant) -> Array:
    var layers: Array = _frame_layers(frame_v).duplicate(true)
    layers.sort_custom(func(a: Variant, b: Variant) -> bool:
        if typeof(a) != TYPE_DICTIONARY or typeof(b) != TYPE_DICTIONARY:
            return false
        var a_sheet: String = str((a as Dictionary).get("sheet", PspIO.BASE_SHEET_ID)).strip_edges()
        var b_sheet: String = str((b as Dictionary).get("sheet", PspIO.BASE_SHEET_ID)).strip_edges()
        return _sheet_z(a_sheet) < _sheet_z(b_sheet)
    )
    return layers


func _frame_entry_for_sheet(sheet_idx: int, sheet_id: String) -> Dictionary:
    return {
        "pose": _selected_pose_id,
        "rotation_deg": 0.0,
        "layers": [{
            "sheet": sheet_id,
            "index": sheet_idx,
        }],
    }


func _frame_entry_with_layer(frame_v: Variant, sheet_id: String, sheet_idx: int) -> Dictionary:
    var frame_entry: Dictionary = _normalize_frame_entry(frame_v)
    var layers: Array = _frame_layers(frame_entry)
    var replaced: bool = false
    for i in range(layers.size()):
        if typeof(layers[i]) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = layers[i]
        if str(layer.get("sheet", "")).strip_edges() != sheet_id:
            continue
        layer["index"] = sheet_idx
        layers[i] = layer
        replaced = true
        break
    if not replaced:
        layers.append({
            "sheet": sheet_id,
            "index": sheet_idx,
        })
    frame_entry["layers"] = layers
    if not frame_entry.has("rotation_deg"):
        frame_entry["rotation_deg"] = 0.0
    return frame_entry


func _remove_sheet_from_frame(frame_v: Variant, sheet_id: String) -> Dictionary:
    var frame_entry: Dictionary = _normalize_frame_entry(frame_v)
    var kept_layers: Array = []
    for layer_v in _frame_layers(frame_entry):
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = layer_v
        if str(layer.get("sheet", "")).strip_edges() == sheet_id:
            continue
        kept_layers.append(layer.duplicate(true))
    if kept_layers.is_empty():
        kept_layers.append({
            "sheet": PspIO.BASE_SHEET_ID,
            "index": 0,
        })
    frame_entry["layers"] = kept_layers
    return frame_entry


func _frame_rotation_deg(frame_v: Variant) -> float:
    var frame_entry: Dictionary = _normalize_frame_entry(frame_v)
    return float(frame_entry.get("rotation_deg", 0.0))


func _display_frame_rotation(pose_id: int, rotation_deg: float) -> float:
    return -rotation_deg if _pose_uses_mirrored_fallback(pose_id) else rotation_deg


func _ensure_active_sheet_valid() -> void:
    if _sheet_defs.is_empty():
        _sheet_defs = PspIO.default_sheet_defs()
    var known_ids: Array = []
    for sheet_def_v in _sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        known_ids.append(str((sheet_def_v as Dictionary).get("id", "")).strip_edges())
    if known_ids.has(_active_sheet_id):
        return
    _active_sheet_id = str((_sheet_defs[0] as Dictionary).get("id", PspIO.BASE_SHEET_ID))


func _rebuild_sheet_option() -> void:
    if _sheet_option == null:
        return
    _ensure_active_sheet_valid()
    _sheet_option.clear()
    var selected_idx: int = -1
    for i in range(_sheet_defs.size()):
        if typeof(_sheet_defs[i]) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = _sheet_defs[i]
        var sheet_id: String = str(sheet_def.get("id", "")).strip_edges()
        var file_name: String = str(sheet_def.get("file", "")).strip_edges()
        _sheet_option.add_item("%s (%s)" % [sheet_id, file_name], i)
        if sheet_id == _active_sheet_id:
            selected_idx = _sheet_option.item_count - 1
    if selected_idx >= 0:
        _sheet_option.select(selected_idx)
    if _remove_sheet_btn != null:
        _remove_sheet_btn.disabled = _sheet_defs.size() <= 1


func _rebuild_preset_option() -> void:
    if _preset_option == null:
        return
    _preset_option.clear()
    for i in range(_preset_entries.size()):
        var entry_v: Variant = _preset_entries[i]
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        _preset_option.add_item(str(entry.get("name", "preset_%d" % i)), i)
        var desc: String = str(entry.get("description", "")).strip_edges()
        if not desc.is_empty():
            _preset_option.set_item_tooltip(_preset_option.item_count - 1, desc)
    if _preset_option.item_count > 0:
        _preset_option.select(0)
    _preset_option.disabled = _preset_option.item_count == 0
    if _apply_preset_btn != null:
        _apply_preset_btn.disabled = _preset_option.item_count == 0
    if _overwrite_preset_btn != null:
        _overwrite_preset_btn.disabled = _preset_option.item_count == 0


func _selected_preset_id() -> String:
    if _preset_option == null or _preset_option.item_count == 0:
        return ""
    var selected_idx: int = _preset_option.get_selected_id()
    if selected_idx < 0 or selected_idx >= _preset_entries.size():
        return ""
    var entry_v: Variant = _preset_entries[selected_idx]
    if typeof(entry_v) != TYPE_DICTIONARY:
        return ""
    return str((entry_v as Dictionary).get("id", "")).strip_edges()


func _ensure_preview_layer_sprite(sheet_id: String) -> Sprite2D:
    if _preview_layer_sprites.has(sheet_id):
        return _preview_layer_sprites[sheet_id]
    var spr := Sprite2D.new()
    spr.centered = true
    _preview_anchor.add_child(spr)
    _preview_layer_sprites[sheet_id] = spr
    return spr


func _rebuild_preview_layer_sprites() -> void:
    if _preview_anchor == null:
        return
    var keep_ids: Dictionary = {}
    for sheet_def_v in _sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        var sheet_id: String = str(sheet_def.get("id", "")).strip_edges()
        if sheet_id.is_empty():
            continue
        keep_ids[sheet_id] = true
        var spr: Sprite2D = _ensure_preview_layer_sprite(sheet_id)
        spr.texture = _sheet_textures.get(sheet_id, null) as Texture2D
        spr.z_index = int(sheet_def.get("z", 0))
        spr.visible = false
    for sheet_id_v in _preview_layer_sprites.keys():
        var sheet_id: String = str(sheet_id_v)
        if keep_ids.has(sheet_id):
            continue
        var stale: Sprite2D = _preview_layer_sprites[sheet_id]
        if is_instance_valid(stale):
            stale.queue_free()
        _preview_layer_sprites.erase(sheet_id)
    _preview_sprite = _ensure_preview_layer_sprite(PspIO.BASE_SHEET_ID)


func _layout_children() -> void:
    if _pose_list == null:
        return
    var vw := size.x
    var vh := size.y

    var top_gap: float = 8.0
    var top_left: float = 8.0
    var top_right: float = vw - 8.0
    var import_w: float = 106.0
    var remove_w: float = 92.0
    var layer_w: float = 132.0
    var row1_fixed: float = import_w + remove_w + layer_w + top_gap * 3.0
    var row1_dropdown_w: float = maxf(170.0, top_right - top_left - row1_fixed)
    var row1_x: float = top_left
    _import_btn.position = Vector2(row1_x, 6)
    _import_btn.size = Vector2(import_w, 28)
    row1_x += import_w + top_gap
    if _sheet_option != null:
        _sheet_option.position = Vector2(row1_x, 6)
        _sheet_option.size = Vector2(row1_dropdown_w, 28)
    row1_x += row1_dropdown_w + top_gap
    if _remove_sheet_btn != null:
        _remove_sheet_btn.position = Vector2(row1_x, 6)
        _remove_sheet_btn.size = Vector2(remove_w, 28)
    row1_x += remove_w + top_gap
    if _layer_mode_btn != null:
        var row1_layer_w: float = maxf(110.0, top_right - row1_x)
        _layer_mode_btn.position = Vector2(row1_x, 6)
        _layer_mode_btn.size = Vector2(row1_layer_w, 28)

    var preset_w: float = 200.0
    var apply_w: float = 110.0
    var overwrite_w: float = 142.0
    var save_as_w: float = 142.0
    var row2_fixed: float = preset_w + apply_w + overwrite_w + save_as_w + top_gap * 3.0
    if row2_fixed > (top_right - top_left):
        var shrink: float = row2_fixed - (top_right - top_left)
        preset_w = maxf(140.0, preset_w - shrink)
    var row2_x: float = top_left
    if _preset_option != null:
        _preset_option.position = Vector2(row2_x, 40)
        _preset_option.size = Vector2(preset_w, 28)
    row2_x += preset_w + top_gap
    if _apply_preset_btn != null:
        _apply_preset_btn.position = Vector2(row2_x, 40)
        _apply_preset_btn.size = Vector2(apply_w, 28)
    row2_x += apply_w + top_gap
    if _overwrite_preset_btn != null:
        _overwrite_preset_btn.position = Vector2(row2_x, 40)
        _overwrite_preset_btn.size = Vector2(overwrite_w, 28)
    row2_x += overwrite_w + top_gap
    if _save_as_preset_btn != null:
        _save_as_preset_btn.position = Vector2(row2_x, 40)
        _save_as_preset_btn.size = Vector2(maxf(120.0, top_right - row2_x), 28)

    var content_y: float = TOP_ACTION_H
    var content_h: float = vh - TOP_ACTION_H

    # Left pose list
    _pose_list.position = Vector2(8, content_y + 8)
    _pose_list.size = Vector2(LEFT_W - 16, content_h - 56)
    _add_pose_btn.position = Vector2(8, vh - 40)
    _add_pose_btn.size = Vector2((LEFT_W - 20) * 0.5, 28)
    _del_pose_btn.position = Vector2(8 + (LEFT_W - 20) * 0.5 + 4, vh - 40)
    _del_pose_btn.size = Vector2((LEFT_W - 20) * 0.5, 28)

    # Right properties panel
    var right_x: float = vw - RIGHT_W
    var prop_x: float = right_x + 12
    var prop_w: float = RIGHT_W - 24
    var prop_field_h: float = 24.0
    var prop_row_gap: float = 8.0
    var prop_y: float = content_y + 28

    var _prop_controls := [
        _name_edit, _pose_id_edit, _dir_option, _mvtype_option,
        _yrad_edit, _yofs_edit, _colw_edit,
        _hurt_x_edit, _hurt_y_edit, _hurt_w_edit, _hurt_h_edit,
        _anchor_x_edit, _anchor_y_edit,
        _anim_speed_edit,
        _loop_edit, _trans_edit
    ]
    for i in _prop_controls.size():
        var row_y := prop_y + (prop_field_h + prop_row_gap) * i
        _place_property_row(_prop_controls[i], prop_x, row_y, prop_w, prop_field_h)
        if i < _prop_labels.size():
            _prop_labels[i].position = Vector2(prop_x, row_y + 3)
            _prop_labels[i].size = Vector2(82, prop_field_h)

    var prev_y: float = prop_y + (prop_field_h + prop_row_gap) * _prop_controls.size() + 12
    var preview_controls_h: float = 140.0
    var prev_h: float = vh - prev_y - preview_controls_h - 24.0
    prev_h = maxf(140.0, prev_h)
    _preview_anchor.position = Vector2(right_x + 12, prev_y)
    _preview_anchor.size = Vector2(prop_w, prev_h)
    _preview_sprite.position = _preview_anchor.size * 0.5
    _preview_anchor.queue_redraw()
    if _cut_collision_btn != null and _cut_hurtbox_btn != null and _copy_collision_all_btn != null and _copy_hurtbox_all_btn != null:
        var cut_y: float = prev_y + prev_h + 6.0
        var row_gap: float = 4.0
        var button_h: float = 28.0
        _cut_collision_btn.position = Vector2(right_x + 12, cut_y)
        _cut_collision_btn.size = Vector2(prop_w, button_h)
        _cut_hurtbox_btn.position = Vector2(right_x + 12, cut_y + button_h + row_gap)
        _cut_hurtbox_btn.size = Vector2(prop_w, button_h)
        _copy_collision_all_btn.position = Vector2(right_x + 12, cut_y + (button_h + row_gap) * 2.0)
        _copy_collision_all_btn.size = Vector2(prop_w, button_h)
        _copy_hurtbox_all_btn.position = Vector2(right_x + 12, cut_y + (button_h + row_gap) * 3.0)
        _copy_hurtbox_all_btn.size = Vector2(prop_w, button_h)

    # Frame strip bottom center
    var strip_y: float = vh - STRIP_H - 8
    var strip_x: float = LEFT_W + 8
    var strip_w: float = vw - LEFT_W - RIGHT_W - 16
    _strip_panel.position = Vector2(strip_x, strip_y)
    _strip_panel.size = Vector2(strip_w - 200, STRIP_H)
    _strip_panel.queue_redraw()

    _timing_edit.position = Vector2(strip_x + strip_w - 192, strip_y + 10)
    _timing_edit.size = Vector2(180, 28)
    if _rot_value_label != null:
        _rot_value_label.position = Vector2(strip_x + strip_w - 192, strip_y + 44)
        _rot_value_label.size = Vector2(180, 14)
    if _rot_ccw_btn != null:
        _rot_ccw_btn.position = Vector2(strip_x + strip_w - 192, strip_y + 58)
        _rot_ccw_btn.size = Vector2(56, 24)
    if _rot_cw_btn != null:
        _rot_cw_btn.position = Vector2(strip_x + strip_w - 130, strip_y + 58)
        _rot_cw_btn.size = Vector2(56, 24)
    if _rot_reset_btn != null:
        _rot_reset_btn.position = Vector2(strip_x + strip_w - 68, strip_y + 58)
        _rot_reset_btn.size = Vector2(56, 24)
    _del_frame_btn.position = Vector2(strip_x + strip_w - 192, strip_y + 90)
    _del_frame_btn.size = Vector2(180, 28)

    var meta_y: float = strip_y - META_H - 4
    # Meta fields: W, H, Cols, Rows, CX, CY — with labels
    var meta_field_w: float = 50.0
    var meta_label_w: float = 34.0
    var meta_gap: float = 6.0
    var meta_unit := meta_label_w + meta_field_w + meta_gap
    var meta_fields := [_fw_edit, _fh_edit, _cols_edit, _rows_edit, _cx_edit, _cy_edit]
    for mi in meta_fields.size():
        var mx := strip_x + float(mi) * meta_unit
        meta_fields[mi].position = Vector2(mx + meta_label_w, meta_y + 10)
        meta_fields[mi].size = Vector2(meta_field_w, 26)
        if mi < _meta_labels.size():
            _meta_labels[mi].position = Vector2(mx, meta_y + 14)
            _meta_labels[mi].size = Vector2(meta_label_w, 20)

    _sheet_panel.position = Vector2(strip_x, content_y + 8)
    _sheet_panel.size = Vector2(strip_w, meta_y - content_y - 12)
    _clamp_sheet_pan()
    _sheet_panel.queue_redraw()


func _place_property_row(w: Control, x: float, y: float, width: float, height: float) -> void:
    var label_w: float = 84.0
    w.position = Vector2(x + label_w, y)
    w.size = Vector2(width - label_w, height)


# ─── Data load / pose list ───────────────────────────────────────────────

func _load_pack_data() -> void:
    var loaded: Dictionary = PspIO.load_or_init(pack_id)
    var frames_data: Dictionary = loaded.get("frames", {})
    var poses_data: Dictionary = loaded.get("poses", {})
    _loaded_frames_root = frames_data.duplicate(true)
    _loaded_poses_root = poses_data.duplicate(true)
    _sheet_defs = PspIO.normalize_sheet_defs(frames_data.get("sheets", []))
    _ensure_active_sheet_valid()

    _sheet_meta["frame_width"]  = int(frames_data.get("frame_width", 50))
    _sheet_meta["frame_height"] = int(frames_data.get("frame_height", 44))
    @warning_ignore("integer_division")
    _sheet_meta["center_x"]     = int(frames_data.get("center_x", _sheet_meta["frame_width"] / 2))
    @warning_ignore("integer_division")
    _sheet_meta["center_y"]     = int(frames_data.get("center_y", _sheet_meta["frame_height"] / 2))
    _sheet_meta["sheet_cols"]   = int(frames_data.get("sheet_cols", 10))

    _frames.clear()
    var raw_frames: Array = frames_data.get("frames", [])
    for item_v in raw_frames:
        var item: Dictionary = _normalize_frame_entry(item_v)
        var pose_id := int(item.get("pose", 0))
        if not _frames.has(pose_id):
            _frames[pose_id] = []
        (_frames[pose_id] as Array).append(item.duplicate(true))

    _poses.clear()
    var raw_poses: Dictionary = poses_data.get("poses", {})
    for key in raw_poses.keys():
        var key_str := str(key)
        if not key_str.is_valid_int():
            continue
        var pose_id := int(key_str)
        var p_v: Variant = raw_poses[key]
        if typeof(p_v) != TYPE_DICTIONARY:
            continue
        var p: Dictionary = p_v
        _poses[pose_id] = {
            "name":          str(p.get("name", "pose_%d" % pose_id)),
            "dir":           int(p.get("dir", 1)),
            "mvtype":        int(p.get("mvtype", 0)),
            "y_radius":      int(p.get("y_radius", 16)),
            "y_offset":      int(p.get("y_offset", 0)),
            "collision_x":   int(p.get("collision_x", 0)),
            "collision_width": int(p.get("collision_width", _default_collision_width())),
            "hurtbox_x":     int(p.get("hurtbox_x", 0)),
            "hurtbox_y":     int(p.get("hurtbox_y", _default_hurtbox_y(p))),
            "hurtbox_w":     int(p.get("hurtbox_w", int(p.get("collision_width", _default_collision_width())))),
            "hurtbox_h":     int(p.get("hurtbox_h", int(p.get("y_radius", 16)) * 2)),
            "weapon_anchor_x": int(p.get("weapon_anchor_x", 0)),
            "weapon_anchor_y": int(p.get("weapon_anchor_y", _default_weapon_anchor_y(p))),
            "timing":        _int_array(p.get("timing", [10])),
            "anim_speed":    _normalized_anim_speed(p.get("anim_speed", 1.0)),
            "frame_boxes":   _frame_boxes_array(p.get("frame_boxes", [])),
            "loop_from":     int(p.get("loop_from", 0)),
            "transition_to": int(p.get("transition_to", -1)),
        }

    _sheet_textures = PspIO.load_sheet_textures(pack_id, _sheet_defs)
    _sheet_texture = _active_sheet_texture()
    _rebuild_sheet_option()
    _preset_entries = PspIO.list_presets(pack_id)
    _rebuild_preset_option()
    _rebuild_preview_layer_sprites()
    _apply_sheet_meta_to_inputs()
    _apply_preview_sprite_layout()
    _refresh_frame_edit_controls()
    dirty = false


static func _int_array(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) != TYPE_ARRAY:
        return out
    for x in v:
        out.append(int(x))
    return out


static func _frame_boxes_array(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) != TYPE_ARRAY:
        return out
    for entry_v in v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            out.append({})
            continue
        var entry: Dictionary = entry_v
        var box: Dictionary = {}
        for key_v in FRAME_BOX_KEYS:
            var key: String = str(key_v)
            if entry.has(key):
                box[key] = int(entry.get(key, 0))
        out.append(box)
    return out


static func _serialize_frame_boxes(v: Variant) -> Array:
    var out: Array = []
    if typeof(v) != TYPE_ARRAY:
        return out
    for entry_v in v:
        if typeof(entry_v) != TYPE_DICTIONARY:
            out.append({})
            continue
        var entry: Dictionary = entry_v
        var box: Dictionary = {}
        for key_v in FRAME_BOX_KEYS:
            var key: String = str(key_v)
            if entry.has(key):
                box[key] = int(entry.get(key, 0))
        out.append(box)
    return out


static func _normalized_anim_speed(value: Variant) -> float:
    var speed: float = 1.0
    match typeof(value):
        TYPE_INT, TYPE_FLOAT:
            speed = float(value)
        _:
            var text := str(value).strip_edges()
            if not text.is_empty():
                speed = text.to_float()
    if is_zero_approx(speed):
        speed = 1.0
    return maxf(0.05, speed)


static func _format_anim_speed(value: float) -> String:
    var rounded := snappedf(value, 0.01)
    if is_equal_approx(rounded, round(rounded)):
        return str(int(round(rounded)))
    return String.num(rounded, 2)


func _default_collision_width() -> float:
    return _physics_collision_width()


func _default_hurtbox_y(pose: Dictionary) -> int:
    return -int(pose.get("y_radius", 16))


func _default_weapon_anchor_y(pose: Dictionary) -> int:
    return -int(pose.get("y_radius", 16)) + DEFAULT_WEAPON_ANCHOR_Y


func _find_pose_id_by_name(pose_name: String) -> int:
    if pose_name.is_empty():
        return -1
    for pose_id_v in _poses.keys():
        var pose_id: int = int(pose_id_v)
        var pose: Dictionary = _poses[pose_id]
        if str(pose.get("name", "")) == pose_name:
            return pose_id
    return -1


func _mirror_source_pose_id(pose_id: int) -> int:
    if not _poses.has(pose_id):
        return -1
    var pose: Dictionary = _poses[pose_id]
    if int(pose.get("dir", 1)) >= 0:
        return -1
    var pose_name: String = str(pose.get("name", ""))
    if pose_name.ends_with("_left"):
        var partner_id: int = _find_pose_id_by_name(pose_name.trim_suffix("_left") + "_right")
        if partner_id >= 0:
            return partner_id
    var mvtype: int = int(pose.get("mvtype", 0))
    for other_id_v in _poses.keys():
        var other_id: int = int(other_id_v)
        if other_id == pose_id:
            continue
        var other: Dictionary = _poses[other_id]
        if int(other.get("dir", 1)) > 0 and int(other.get("mvtype", -999)) == mvtype:
            return other_id
    return -1


func _sync_frame_box_counts_for_pose(pose_id: int) -> void:
    if pose_id < 0 or not _poses.has(pose_id):
        return
    var pose: Dictionary = (_poses[pose_id] as Dictionary).duplicate(true)
    pose = _ensure_frame_boxes_size(pose, _frame_count_for_pose(pose_id))
    _poses[pose_id] = pose


func _resolved_animation_owner_id(pose_id: int) -> int:
    var local_seq: Array = (_frames[pose_id] as Array) if _frames.has(pose_id) else []
    if not local_seq.is_empty() and not (_pose_dir_value(_poses.get(pose_id, {})) < 0 and _frame_sequence_is_legacy_placeholder(local_seq)):
        return pose_id
    var mirror_id: int = _mirror_source_pose_id(pose_id)
    if mirror_id >= 0 and _frames.has(mirror_id) and not (_frames[mirror_id] as Array).is_empty():
        return mirror_id
    return -1


func _pose_dir_value(pose: Dictionary) -> int:
    var pose_name: String = str(pose.get("name", ""))
    if pose_name.ends_with("_left"):
        return -1
    if pose_name.ends_with("_right"):
        return 1
    var raw_dir: int = int(pose.get("dir", 1))
    return -1 if raw_dir < 0 else 1


func _frame_sequence_is_legacy_placeholder(seq: Array) -> bool:
    if seq.is_empty():
        return false
    for entry_v in seq:
        var entry: Dictionary = _normalize_frame_entry(entry_v)
        var layers: Array = _frame_layers(entry)
        if layers.size() != 1:
            return false
        var layer: Dictionary = layers[0]
        if str(layer.get("sheet", PspIO.BASE_SHEET_ID)).strip_edges() != PspIO.BASE_SHEET_ID:
            return false
        if int(layer.get("index", -1)) != 0:
            return false
    return true


func _resolved_animation_pose_dict(pose_id: int) -> Dictionary:
    var owner_id: int = _resolved_animation_owner_id(pose_id)
    if owner_id >= 0 and _poses.has(owner_id):
        return _poses[owner_id]
    return {}


func _resolved_frames_for_pose(pose_id: int) -> Array:
    var owner_id: int = _resolved_animation_owner_id(pose_id)
    if owner_id >= 0 and _frames.has(owner_id):
        return (_frames[owner_id] as Array)
    return []


func _pose_uses_mirrored_fallback(pose_id: int) -> bool:
    if not _poses.has(pose_id):
        return false
    var owner_id: int = _resolved_animation_owner_id(pose_id)
    if owner_id < 0 or owner_id == pose_id:
        return false
    return _pose_dir_value(_poses[pose_id] as Dictionary) < 0


func _animation_owner_label(pose_id: int) -> String:
    var owner_id: int = _resolved_animation_owner_id(pose_id)
    if owner_id < 0 or owner_id == pose_id or not _poses.has(owner_id):
        return ""
    return str((_poses[owner_id] as Dictionary).get("name", "pose_%d" % owner_id))


func _populate_pose_list() -> void:
    _pose_list.clear()
    var keys: Array = _poses.keys()
    keys.sort()
    for pose_id in keys:
        var p: Dictionary = _poses[pose_id]
        _pose_list.add_item("[%d] %s" % [pose_id, p.get("name", "?")])


func _selected_pose_dict() -> Dictionary:
    if not _poses.has(_selected_pose_id):
        return {}
    return _poses[_selected_pose_id]


func _selected_pose_edit_dict() -> Dictionary:
    var pose: Dictionary = _selected_pose_dict()
    return pose.duplicate(true)


func _frame_count_for_pose(pose_id: int) -> int:
    return _resolved_frames_for_pose(pose_id).size()


func _ensure_frame_boxes_size(pose: Dictionary, desired_size: int) -> Dictionary:
    var frame_boxes: Array = _frame_boxes_array(pose.get("frame_boxes", []))
    while frame_boxes.size() < desired_size:
        frame_boxes.append({})
    while frame_boxes.size() > desired_size:
        frame_boxes.remove_at(frame_boxes.size() - 1)
    pose["frame_boxes"] = frame_boxes
    return pose


func _effective_box_values(pose: Dictionary) -> Dictionary:
    var effective: Dictionary = pose.duplicate(true)
    var frame_boxes_v: Variant = pose.get("frame_boxes", [])
    if _selected_strip_idx >= 0 and typeof(frame_boxes_v) == TYPE_ARRAY:
        var frame_boxes: Array = frame_boxes_v
        if _selected_strip_idx < frame_boxes.size() and typeof(frame_boxes[_selected_strip_idx]) == TYPE_DICTIONARY:
            var box: Dictionary = frame_boxes[_selected_strip_idx]
            for key_v in FRAME_BOX_KEYS:
                var key: String = str(key_v)
                if box.has(key):
                    effective[key] = int(box.get(key, effective.get(key, 0)))
    return effective


func _current_box_values() -> Dictionary:
    var pose: Dictionary = _selected_pose_dict()
    if pose.is_empty():
        return {}
    return _effective_box_values(pose)


func _apply_box_values_to_pose(pose: Dictionary, values: Dictionary, write_to_frame: bool, pose_id: int = -1) -> Dictionary:
    if write_to_frame:
        var target_pose_id: int = pose_id if pose_id >= 0 else _selected_pose_id
        pose = _ensure_frame_boxes_size(pose, _frame_count_for_pose(target_pose_id))
        var frame_boxes: Array = _frame_boxes_array(pose.get("frame_boxes", []))
        if _selected_strip_idx >= 0 and _selected_strip_idx < frame_boxes.size():
            var box: Dictionary = {}
            for key_v in FRAME_BOX_KEYS:
                var key: String = str(key_v)
                box[key] = int(values.get(key, pose.get(key, 0)))
            frame_boxes[_selected_strip_idx] = box
        pose["frame_boxes"] = frame_boxes
        return pose
    for key_v in FRAME_BOX_KEYS:
        var key: String = str(key_v)
        pose[key] = int(values.get(key, pose.get(key, 0)))
    return pose


func _mirror_x_for_pose(value: int, source_pose: Dictionary, target_pose: Dictionary) -> int:
    if _pose_dir_value(source_pose) == _pose_dir_value(target_pose):
        return value
    return -value


func _on_pose_list_selected(index: int) -> void:
    var keys: Array = _poses.keys()
    keys.sort()
    if index < 0 or index >= keys.size():
        _selected_pose_id = -1
        return
    _selected_pose_id = int(keys[index])
    _selected_strip_idx = 0
    _preview_anim_idx = 0
    _preview_tick = 0.0
    _apply_pose_to_inputs()
    _strip_panel.queue_redraw()
    _sheet_panel.queue_redraw()


func _on_add_pose_pressed() -> void:
    if _undo != null:
        _undo.begin()
    var new_id: int = _next_free_pose_id()
    _poses[new_id] = {
        "name":          "pose_%d" % new_id,
        "dir":           1,
        "mvtype":        0,
        "y_radius":      16,
        "y_offset":      0,
        "collision_x":   0,
        "collision_width": int(_default_collision_width()),
        "hurtbox_x":     0,
        "hurtbox_y":     _default_hurtbox_y({"y_radius": 16}),
        "hurtbox_w":     int(_default_collision_width()),
        "hurtbox_h":     32,
        "weapon_anchor_x": 0,
        "weapon_anchor_y": _default_weapon_anchor_y({"y_radius": 16}),
        "timing":        [],
        "anim_speed":    1.0,
        "frame_boxes":   [],
        "loop_from":     0,
        "transition_to": -1,
    }
    _frames[new_id] = []
    dirty = true
    _populate_pose_list()
    var keys: Array = _poses.keys()
    keys.sort()
    var idx := keys.find(new_id)
    if idx >= 0:
        _pose_list.select(idx)
        _on_pose_list_selected(idx)
    if _undo != null:
        _undo.commit("add pose")


func _on_del_pose_pressed() -> void:
    if _selected_pose_id < 0:
        return
    if _undo != null:
        _undo.begin()
    _poses.erase(_selected_pose_id)
    _frames.erase(_selected_pose_id)
    _selected_pose_id = -1
    dirty = true
    _populate_pose_list()
    if _pose_list.item_count > 0:
        _pose_list.select(0)
        _on_pose_list_selected(0)
    else:
        _apply_pose_to_inputs()
    if _undo != null:
        _undo.commit("delete pose")


func _next_free_pose_id() -> int:
    var i: int = 1
    while _poses.has(i):
        i += 1
    return i


# ─── Field wiring ────────────────────────────────────────────────────────

func _apply_pose_to_inputs() -> void:
    var pose: Dictionary = _selected_pose_dict()
    var have := not pose.is_empty()
    _name_edit.editable = have
    _pose_id_edit.editable = have
    _dir_option.disabled = not have
    _mvtype_option.disabled = not have
    _yrad_edit.editable = have
    _yofs_edit.editable = have
    _colw_edit.editable = have
    _hurt_x_edit.editable = have
    _hurt_y_edit.editable = have
    _hurt_w_edit.editable = have
    _hurt_h_edit.editable = have
    _anchor_x_edit.editable = have
    _anchor_y_edit.editable = have
    _anim_speed_edit.editable = have
    _loop_edit.editable = have
    _trans_edit.editable = have
    if _copy_collision_all_btn != null:
        _copy_collision_all_btn.disabled = not have
    if _copy_hurtbox_all_btn != null:
        _copy_hurtbox_all_btn.disabled = not have

    if not have:
        _name_edit.text = ""
        _pose_id_edit.text = ""
        _yrad_edit.text = ""
        _yofs_edit.text = ""
        _colw_edit.text = ""
        _hurt_x_edit.text = ""
        _hurt_y_edit.text = ""
        _hurt_w_edit.text = ""
        _hurt_h_edit.text = ""
        _anchor_x_edit.text = ""
        _anchor_y_edit.text = ""
        _anim_speed_edit.text = ""
        _loop_edit.text = ""
        _trans_edit.text = ""
        _refresh_frame_edit_controls()
        return

    var p: Dictionary = _effective_box_values(pose)
    _name_edit.text = str(pose.get("name", ""))
    _pose_id_edit.text = str(_selected_pose_id)
    _dir_option.select(0 if int(pose.get("dir", 1)) >= 0 else 1)
    _mvtype_option.select(_mvtype_index_for(int(pose.get("mvtype", 0))))
    _yrad_edit.text = str(int(p.get("y_radius", 16)))
    _yofs_edit.text = str(int(p.get("y_offset", 0)))
    _colw_edit.text = str(int(p.get("collision_width", _default_collision_width())))
    _hurt_x_edit.text = str(int(p.get("hurtbox_x", 0)))
    _hurt_y_edit.text = str(int(p.get("hurtbox_y", _default_hurtbox_y(p))))
    _hurt_w_edit.text = str(int(p.get("hurtbox_w", int(p.get("collision_width", _default_collision_width())))))
    _hurt_h_edit.text = str(int(p.get("hurtbox_h", int(p.get("y_radius", 16)) * 2)))
    _anchor_x_edit.text = str(int(pose.get("weapon_anchor_x", 0)))
    _anchor_y_edit.text = str(int(pose.get("weapon_anchor_y", _default_weapon_anchor_y(pose))))
    _anim_speed_edit.text = _format_anim_speed(float(pose.get("anim_speed", 1.0)))
    _loop_edit.text = str(int(pose.get("loop_from", 0)))
    _trans_edit.text = str(int(pose.get("transition_to", -1)))
    _apply_strip_timing_to_input()
    _refresh_frame_edit_controls()


func _mvtype_index_for(value: int) -> int:
    for i in MVTYPE_NAMES.size():
        if int(MVTYPE_NAMES[i][1]) == value:
            return i
    return 0


func _apply_sheet_meta_to_inputs() -> void:
    _suppress_meta_events = true
    _fw_edit.text = str(int(_sheet_meta["frame_width"]))
    _fh_edit.text = str(int(_sheet_meta["frame_height"]))
    _cols_edit.text = str(int(_sheet_meta["sheet_cols"]))
    var auto_rows: int = 1
    if _sheet_texture != null and int(_sheet_meta["frame_height"]) > 0:
        @warning_ignore("integer_division")
        auto_rows = maxi(1, _sheet_texture.get_height() / int(_sheet_meta["frame_height"]))
    _rows_edit.text = str(int(_sheet_meta.get("sheet_rows", auto_rows)))
    _cx_edit.text = str(int(_sheet_meta["center_x"]))
    _cy_edit.text = str(int(_sheet_meta["center_y"]))
    _suppress_meta_events = false


# Rows/columns are the primary inputs: when they change, derive frame_width/height
# from the sheet's pixel dimensions. Frame W/H stay editable as a fallback for
# weird sheets but auto-fill from rows/cols here.
func _on_grid_changed() -> void:
    if _suppress_meta_events:
        return
    var cols: int = maxi(1, PedUtil.to_int(_cols_edit.text, 10))
    var rows: int = maxi(1, PedUtil.to_int(_rows_edit.text, 1))
    _sheet_meta["sheet_cols"] = cols
    _sheet_meta["sheet_rows"] = rows
    if _sheet_texture != null:
        var tex_size := _sheet_texture.get_size()
        @warning_ignore("integer_division")
        var new_fw: int = maxi(1, int(tex_size.x) / cols)
        @warning_ignore("integer_division")
        var new_fh: int = maxi(1, int(tex_size.y) / rows)
        _sheet_meta["frame_width"] = new_fw
        _sheet_meta["frame_height"] = new_fh
        _suppress_meta_events = true
        _fw_edit.text = str(new_fw)
        _fh_edit.text = str(new_fh)
        _suppress_meta_events = false
    _recompute_center_auto()
    dirty = true
    _apply_preview_sprite_layout()
    _sheet_panel.queue_redraw()
    _strip_panel.queue_redraw()


func _on_frame_size_changed() -> void:
    if _suppress_meta_events:
        return
    var fw: int = maxi(1, PedUtil.to_int(_fw_edit.text, 50))
    var fh: int = maxi(1, PedUtil.to_int(_fh_edit.text, 44))
    _sheet_meta["frame_width"] = fw
    _sheet_meta["frame_height"] = fh
    if _sheet_texture != null:
        var tex_size := _sheet_texture.get_size()
        @warning_ignore("integer_division")
        var new_cols: int = maxi(1, int(tex_size.x) / fw)
        @warning_ignore("integer_division")
        var new_rows: int = maxi(1, int(tex_size.y) / fh)
        _sheet_meta["sheet_cols"] = new_cols
        _sheet_meta["sheet_rows"] = new_rows
        _suppress_meta_events = true
        _cols_edit.text = str(new_cols)
        _rows_edit.text = str(new_rows)
        _suppress_meta_events = false
    _recompute_center_auto()
    dirty = true
    _apply_preview_sprite_layout()
    _sheet_panel.queue_redraw()
    _strip_panel.queue_redraw()


func _recompute_center_auto() -> void:
    @warning_ignore("integer_division")
    var auto_cx: int = int(_sheet_meta["frame_width"]) / 2
    @warning_ignore("integer_division")
    var auto_cy: int = int(_sheet_meta["frame_height"]) / 2
    _sheet_meta["center_x"] = auto_cx
    _sheet_meta["center_y"] = auto_cy
    _suppress_meta_events = true
    _cx_edit.text = str(auto_cx)
    _cy_edit.text = str(auto_cy)
    _suppress_meta_events = false


func _on_center_changed() -> void:
    if _suppress_meta_events:
        return
    _sheet_meta["center_x"] = maxi(0, PedUtil.to_int(_cx_edit.text, int(_sheet_meta["center_x"])))
    _sheet_meta["center_y"] = maxi(0, PedUtil.to_int(_cy_edit.text, int(_sheet_meta["center_y"])))
    dirty = true
    _apply_preview_sprite_layout()


func _on_pose_id_changed() -> void:
    if _selected_pose_id < 0:
        return
    var new_id := PedUtil.to_int(_pose_id_edit.text, _selected_pose_id)
    if new_id == _selected_pose_id:
        return
    if new_id < 0 or _poses.has(new_id):
        return
    _poses[new_id] = _poses[_selected_pose_id]
    _poses.erase(_selected_pose_id)
    if _frames.has(_selected_pose_id):
        _frames[new_id] = _frames[_selected_pose_id]
        _frames.erase(_selected_pose_id)
    _selected_pose_id = new_id
    dirty = true
    _populate_pose_list()
    var keys: Array = _poses.keys()
    keys.sort()
    var idx := keys.find(new_id)
    if idx >= 0:
        _pose_list.select(idx)


func _on_pose_field_changed() -> void:
    var p: Dictionary = _selected_pose_edit_dict()
    if p.is_empty():
        return
    var current_values: Dictionary = _current_box_values()
    p["name"]          = _name_edit.text
    p["dir"]           = int(_dir_option.get_selected_id()) if _dir_option.get_selected_id() != -1 else 1
    p["mvtype"]        = int(_mvtype_option.get_selected_id()) if _mvtype_option.get_selected_id() != -1 else 0
    p["weapon_anchor_x"] = PedUtil.to_int(_anchor_x_edit.text, 0)
    p["weapon_anchor_y"] = PedUtil.to_int(_anchor_y_edit.text, _default_weapon_anchor_y(p))
    p["anim_speed"]    = _normalized_anim_speed(PedUtil.to_float(_anim_speed_edit.text, float(p.get("anim_speed", 1.0))))
    p["loop_from"]     = PedUtil.to_int(_loop_edit.text, 0)
    p["transition_to"] = PedUtil.to_int(_trans_edit.text, -1)
    var box_seed: Dictionary = current_values if not current_values.is_empty() else _effective_box_values(p)
    var box_values: Dictionary = {
        "y_radius": maxi(2, PedUtil.to_int(_yrad_edit.text, int(box_seed.get("y_radius", 16)))),
        "y_offset": PedUtil.to_int(_yofs_edit.text, int(box_seed.get("y_offset", 0))),
        "collision_x": int(box_seed.get("collision_x", 0)),
        "collision_width": maxi(1, PedUtil.to_int(_colw_edit.text, int(box_seed.get("collision_width", _default_collision_width())))),
        "hurtbox_x": PedUtil.to_int(_hurt_x_edit.text, int(box_seed.get("hurtbox_x", 0))),
        "hurtbox_y": PedUtil.to_int(_hurt_y_edit.text, int(box_seed.get("hurtbox_y", _default_hurtbox_y(box_seed)))),
        "hurtbox_w": maxi(1, PedUtil.to_int(_hurt_w_edit.text, int(box_seed.get("hurtbox_w", box_seed.get("collision_width", _default_collision_width()))))),
        "hurtbox_h": maxi(1, PedUtil.to_int(_hurt_h_edit.text, int(box_seed.get("hurtbox_h", int(box_seed.get("y_radius", 16)) * 2)))),
    }
    p = _apply_box_values_to_pose(p, box_values, _selected_strip_idx >= 0, _selected_pose_id)
    _poses[_selected_pose_id] = p
    dirty = true
    _populate_pose_list()
    var keys: Array = _poses.keys()
    keys.sort()
    var idx := keys.find(_selected_pose_id)
    if idx >= 0:
        _pose_list.select(idx)
    if _preview_anchor != null:
        _preview_anchor.queue_redraw()


func _apply_strip_timing_to_input() -> void:
    var p := _resolved_animation_pose_dict(_selected_pose_id)
    if p.is_empty():
        _timing_edit.text = ""
        _timing_edit.editable = false
        _refresh_frame_edit_controls()
        return
    var timing: Array = p.get("timing", [])
    var valid: bool = _selected_strip_idx >= 0 and _selected_strip_idx < timing.size()
    _timing_edit.editable = valid
    _timing_edit.text = str(int(timing[_selected_strip_idx])) if valid else ""
    _refresh_frame_edit_controls()


func _on_timing_changed() -> void:
    var owner_id: int = _resolved_animation_owner_id(_selected_pose_id)
    if owner_id < 0:
        return
    var p := _resolved_animation_pose_dict(_selected_pose_id)
    if p.is_empty():
        return
    var timing: Array = p.get("timing", []).duplicate()
    if _selected_strip_idx < 0 or _selected_strip_idx >= timing.size():
        return
    timing[_selected_strip_idx] = maxi(1, PedUtil.to_int(_timing_edit.text, 10))
    p["timing"] = timing
    _poses[owner_id] = p
    dirty = true


func _on_del_frame_pressed() -> void:
    var owner_id: int = _resolved_animation_owner_id(_selected_pose_id)
    if owner_id < 0:
        return
    var p := _resolved_animation_pose_dict(_selected_pose_id)
    if p.is_empty():
        return
    var seq: Array = _frames.get(owner_id, []).duplicate()
    if _selected_strip_idx < 0 or _selected_strip_idx >= seq.size():
        return
    if _undo != null:
        _undo.begin()
    seq.remove_at(_selected_strip_idx)
    _frames[owner_id] = seq
    var timing: Array = p.get("timing", []).duplicate()
    if _selected_strip_idx < timing.size():
        timing.remove_at(_selected_strip_idx)
    p["timing"] = timing
    p = _ensure_frame_boxes_size(p, seq.size())
    _poses[owner_id] = p
    _sync_frame_box_counts_for_pose(owner_id)
    _selected_strip_idx = mini(_selected_strip_idx, seq.size() - 1)
    dirty = true
    _strip_panel.queue_redraw()
    _sheet_panel.queue_redraw()
    _apply_pose_to_inputs()
    _apply_strip_timing_to_input()
    _apply_preview_sprite_layout()
    _refresh_frame_edit_controls()
    if _undo != null:
        _undo.commit("delete frame")


func _refresh_frame_edit_controls() -> void:
    var valid: bool = _selected_pose_id >= 0
    var seq: Array = _resolved_frames_for_pose(_selected_pose_id) if valid else []
    valid = valid and _selected_strip_idx >= 0 and _selected_strip_idx < seq.size()
    var sprite_rotation: float = _frame_rotation_deg(seq[_selected_strip_idx]) if valid else 0.0
    if _rot_value_label != null:
        _rot_value_label.text = "ROTATION: %s deg" % _format_rotation_deg(sprite_rotation)
    if _rot_ccw_btn != null:
        _rot_ccw_btn.disabled = not valid
    if _rot_cw_btn != null:
        _rot_cw_btn.disabled = not valid
    if _rot_reset_btn != null:
        _rot_reset_btn.disabled = not valid
    if _del_frame_btn != null:
        _del_frame_btn.disabled = not valid


func _rotate_selected_frame(delta_deg: float) -> void:
    var valid: bool = _selected_pose_id >= 0
    var seq: Array = _resolved_frames_for_pose(_selected_pose_id) if valid else []
    if not valid or _selected_strip_idx < 0 or _selected_strip_idx >= seq.size():
        return
    _set_selected_frame_rotation(_frame_rotation_deg(seq[_selected_strip_idx]) + delta_deg)


func _set_selected_frame_rotation(rotation_deg: float) -> void:
    var owner_id: int = _resolved_animation_owner_id(_selected_pose_id)
    if owner_id < 0:
        return
    var seq: Array = _frames.get(owner_id, []).duplicate(true)
    if _selected_strip_idx < 0 or _selected_strip_idx >= seq.size():
        return
    if _undo != null:
        _undo.begin()
    var normalized: float = fposmod(rotation_deg, 360.0)
    if normalized > 180.0:
        normalized -= 360.0
    var frame_entry: Dictionary = _normalize_frame_entry(seq[_selected_strip_idx])
    frame_entry["rotation_deg"] = normalized
    seq[_selected_strip_idx] = frame_entry
    _frames[owner_id] = seq
    dirty = true
    _refresh_frame_edit_controls()
    if _strip_panel != null:
        _strip_panel.queue_redraw()
    if _preview_anchor != null:
        _preview_anchor.queue_redraw()
    _apply_pose_to_inputs()
    _apply_strip_timing_to_input()
    if _undo != null:
        _undo.commit("rotate frame")


func _format_rotation_deg(sprite_rotation: float) -> String:
    var display_rotation: float = snappedf(sprite_rotation, 0.1)
    if absf(display_rotation - roundf(display_rotation)) < 0.0001:
        return str(int(roundf(display_rotation)))
    return "%.1f" % display_rotation


# ─── Sheet viewer draw + click ───────────────────────────────────────────

func _draw_sheet_panel() -> void:
    var rect := Rect2(Vector2.ZERO, _sheet_panel.size)
    _sheet_panel.draw_rect(rect, Color(0.12, 0.14, 0.18, 1.0), true)
    _sheet_panel.draw_rect(rect, Color(0.25, 0.3, 0.4, 1.0), false)
    if _sheet_texture == null:
        var f := ThemeDB.fallback_font
        _sheet_panel.draw_string(f, Vector2(16, 28), "No sheet loaded. Click ADD SHEET.",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.75, 0.85))
        return

    var fw: float = float(int(_sheet_meta["frame_width"]))
    var fh: float = float(int(_sheet_meta["frame_height"]))
    var cols: int = int(_sheet_meta["sheet_cols"])
    var tex_size: Vector2 = _sheet_texture.get_size()
    var view_scale: float = _sheet_view_scale()
    var draw_w: float = tex_size.x * view_scale
    var draw_h: float = tex_size.y * view_scale
    var origin: Vector2 = _sheet_draw_origin(Vector2(draw_w, draw_h))

    _sheet_panel.draw_texture_rect(_sheet_texture, Rect2(origin, Vector2(draw_w, draw_h)), false)

    if fw > 0 and fh > 0 and cols > 0:
        var cell_w := fw * view_scale
        var cell_h := fh * view_scale
        var grid_rows: int = int(ceil(tex_size.y / fh))
        var grid_cols: int = mini(cols, int(ceil(tex_size.x / fw)))
        for r in range(grid_rows + 1):
            var y := origin.y + r * cell_h
            _sheet_panel.draw_line(Vector2(origin.x, y), Vector2(origin.x + grid_cols * cell_w, y),
                Color(1.0, 1.0, 1.0, 0.12))
        for c in range(grid_cols + 1):
            var x := origin.x + c * cell_w
            _sheet_panel.draw_line(Vector2(x, origin.y), Vector2(x, origin.y + grid_rows * cell_h),
                Color(1.0, 1.0, 1.0, 0.12))

        if _selected_pose_id >= 0:
            var seq: Array = _resolved_frames_for_pose(_selected_pose_id)
            for i in seq.size():
                if not _frame_has_sheet(seq[i], _active_sheet_id):
                    continue
                var idx: int = _frame_primary_index(seq[i], _active_sheet_id)
                @warning_ignore("integer_division")
                var row := idx / cols
                var col := idx % cols
                var cell_rect := Rect2(origin.x + col * cell_w, origin.y + row * cell_h, cell_w, cell_h)
                var hi := Color(0.3, 1.0, 0.5, 0.35) if i != _selected_strip_idx else Color(1.0, 0.85, 0.3, 0.55)
                _sheet_panel.draw_rect(cell_rect, hi, true)
                _sheet_panel.draw_rect(cell_rect, Color(0.9, 1.0, 0.8, 0.9), false)


func _on_sheet_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
            _zoom_sheet_at(mb.position, 1.15)
            return
        if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
            _zoom_sheet_at(mb.position, 1.0 / 1.15)
            return
        if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
            _sheet_pan_active = mb.pressed
            if mb.pressed:
                _sheet_pan_start = mb.position
                _sheet_pan_origin = _sheet_pan
            return
        if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
            return
        if _sheet_texture == null or _selected_pose_id < 0:
            return
        var fw: float = float(int(_sheet_meta["frame_width"]))
        var fh: float = float(int(_sheet_meta["frame_height"]))
        var cols: int = int(_sheet_meta["sheet_cols"])
        if fw <= 0.0 or fh <= 0.0 or cols <= 0:
            return
        var local: Vector2 = _sheet_local_to_texture(mb.position)
        if local.x < 0.0 or local.y < 0.0:
            return
        var col: int = int(local.x / fw)
        var row: int = int(local.y / fh)
        if col < 0 or col >= cols:
            return
        var idx: int = row * cols + col
        if idx >= 0:
            _add_frame_to_selected_pose(idx)
    elif event is InputEventMouseMotion and _sheet_pan_active:
        var motion: InputEventMouseMotion = event
        _sheet_pan = _sheet_pan_origin + (motion.position - _sheet_pan_start)
        _clamp_sheet_pan()
        _sheet_panel.queue_redraw()


func _add_frame_to_selected_pose(sheet_idx: int) -> void:
    if _selected_pose_id < 0:
        return
    var owner_id: int = _resolved_animation_owner_id(_selected_pose_id)
    if owner_id < 0:
        owner_id = _selected_pose_id
    var p: Dictionary = _poses.get(owner_id, {})
    if p.is_empty():
        return
    if not _frames.has(owner_id):
        _frames[owner_id] = []
    var seq: Array = (_frames[owner_id] as Array)
    if _layer_mode_btn != null and _layer_mode_btn.button_pressed and _selected_strip_idx >= 0 and _selected_strip_idx < seq.size():
        seq[_selected_strip_idx] = _frame_entry_with_layer(seq[_selected_strip_idx], _active_sheet_id, sheet_idx)
    else:
        seq.append(_frame_entry_for_sheet(sheet_idx, _active_sheet_id))
        var timing: Array = p.get("timing", []).duplicate()
        timing.append(10)
        p["timing"] = timing
        _selected_strip_idx = seq.size() - 1
    p = _ensure_frame_boxes_size(p, seq.size())
    _poses[owner_id] = p
    _sync_frame_box_counts_for_pose(owner_id)
    dirty = true
    _strip_panel.queue_redraw()
    _sheet_panel.queue_redraw()
    _apply_pose_to_inputs()
    _apply_strip_timing_to_input()
    _apply_preview_sprite_layout()


# ─── Frame strip draw + click ────────────────────────────────────────────

func _draw_strip_panel() -> void:
    var rect := Rect2(Vector2.ZERO, _strip_panel.size)
    _strip_panel.draw_rect(rect, Color(0.12, 0.14, 0.18, 1.0), true)
    _strip_panel.draw_rect(rect, Color(0.25, 0.3, 0.4, 1.0), false)

    var f := ThemeDB.fallback_font
    _strip_panel.draw_string(f, Vector2(8, 16), "FRAME SEQUENCE",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.95))
    _strip_panel.draw_string(f, Vector2(118, 16), "(click selected frame to remove)",
        HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.52, 0.62, 0.76))

    if _selected_pose_id < 0:
        return
    var seq: Array = _resolved_frames_for_pose(_selected_pose_id)
    var p: Dictionary = _resolved_animation_pose_dict(_selected_pose_id)
    var owner_label: String = _animation_owner_label(_selected_pose_id)
    var timing: Array = p.get("timing", [])
    var cell: float = 72.0
    var start_x: float = 8.0
    var start_y: float = 24.0
    if not owner_label.is_empty():
        _strip_panel.draw_string(f, Vector2(8, 30), "mirroring: %s" % owner_label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.9, 0.78, 0.42))
        start_y = 38.0
    var fw: int = int(_sheet_meta["frame_width"])
    var fh: int = int(_sheet_meta["frame_height"])
    var cols: int = int(_sheet_meta["sheet_cols"])
    for i in seq.size():
        var x: float = start_x + i * (cell + 6)
        if x + cell > _strip_panel.size.x:
            break
        var frame_entry: Dictionary = _normalize_frame_entry(seq[i])
        var frame_rotation: float = float(frame_entry.get("rotation_deg", 0.0))
        var cell_rect := Rect2(x, start_y, cell, cell - 8)
        var bg_col := Color(0.18, 0.22, 0.3, 1.0)
        if i == _selected_strip_idx:
            bg_col = Color(0.3, 0.35, 0.5, 1.0)
        _strip_panel.draw_rect(cell_rect, bg_col, true)
        _strip_panel.draw_rect(cell_rect, Color(0.5, 0.6, 0.75, 1.0), false)

        if fw > 0 and fh > 0 and cols > 0:
            var dst_scale: float = minf((cell - 12) / float(fw), (cell - 20) / float(fh))
            if dst_scale < 0.1:
                dst_scale = 0.1
            var dst_w: float = fw * dst_scale
            var dst_h: float = fh * dst_scale
            var dst := Rect2(
                Vector2(x + (cell - dst_w) * 0.5, start_y + (cell - 8 - dst_h) * 0.5),
                Vector2(dst_w, dst_h)
            )
            for layer_v in _sorted_frame_layers(frame_entry):
                if typeof(layer_v) != TYPE_DICTIONARY:
                    continue
                var layer: Dictionary = layer_v
                var sheet_id: String = str(layer.get("sheet", PspIO.BASE_SHEET_ID)).strip_edges()
                var tex: Texture2D = _sheet_textures.get(sheet_id, null) as Texture2D
                if tex == null:
                    continue
                var idx: int = int(layer.get("index", 0))
                var src_col := idx % cols
                @warning_ignore("integer_division")
                var src_row := idx / cols
                var src_rect := Rect2(Vector2(src_col * fw, src_row * fh), Vector2(fw, fh))
                if absf(frame_rotation) > 0.001:
                    _strip_panel.draw_set_transform(dst.get_center(), deg_to_rad(frame_rotation), Vector2.ONE)
                    _strip_panel.draw_texture_rect_region(tex, Rect2(-dst.size * 0.5, dst.size), src_rect)
                    _strip_panel.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
                else:
                    _strip_panel.draw_texture_rect_region(tex, dst, src_rect)

        var tick: int = int(timing[i]) if i < timing.size() else 0
        _strip_panel.draw_string(f, Vector2(x + 4, start_y + cell - 4),
            "L%d | %dt" % [_frame_layers(seq[i]).size(), tick],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.92, 1.0))


func _on_strip_gui_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton):
        return
    var mb: InputEventMouseButton = event
    if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
        return
    if _selected_pose_id < 0:
        return
    var seq: Array = _resolved_frames_for_pose(_selected_pose_id)
    var cell: float = 72.0
    var start_x: float = 8.0
    var start_y: float = 24.0
    if not _animation_owner_label(_selected_pose_id).is_empty():
        start_y = 38.0
    var cell_h: float = cell - 8
    if mb.position.y < start_y or mb.position.y > start_y + cell_h:
        return
    var rel := mb.position.x - start_x
    if rel < 0:
        return
    var step: float = cell + 6
    var idx := int(rel / step)
    if idx < 0 or idx >= seq.size():
        return
    if idx == _selected_strip_idx:
        _on_del_frame_pressed()
        return
    _selected_strip_idx = idx
    _apply_pose_to_inputs()
    _apply_strip_timing_to_input()
    _strip_panel.queue_redraw()
    _sheet_panel.queue_redraw()


# ─── Preview ────────────────────────────────────────────────────────────

func _apply_preview_sprite_layout() -> void:
    if _preview_sprite == null:
        return
    var fw: int = int(_sheet_meta["frame_width"])
    var fh: int = int(_sheet_meta["frame_height"])
    var cols: int = int(_sheet_meta["sheet_cols"])
    if fw <= 0 or fh <= 0 or cols <= 0:
        return
    var avail_w: float = _preview_anchor.size.x - 16
    var avail_h: float = _preview_anchor.size.y - 16
    var s: float = minf(avail_w / float(fw), avail_h / float(fh))
    s = minf(s, 6.0)
    if s < 1.0:
        s = 1.0
    var center: Vector2 = _preview_anchor.size * 0.5
    for sheet_id_v in _preview_layer_sprites.keys():
        var sheet_id: String = str(sheet_id_v)
        var spr: Sprite2D = _preview_layer_sprites[sheet_id]
        if not is_instance_valid(spr):
            continue
        var tex: Texture2D = _sheet_textures.get(sheet_id, null) as Texture2D
        spr.texture = tex
        spr.position = center
        spr.scale = Vector2(s, s)
        if tex != null:
            var tex_size: Vector2 = tex.get_size()
            var rows: int = maxi(1, int(ceil(tex_size.y / float(fh))))
            spr.hframes = cols
            spr.vframes = rows
        spr.visible = false


func _draw_preview_bg() -> void:
    var rect := Rect2(Vector2.ZERO, _preview_anchor.size)
    _preview_anchor.draw_rect(rect, Color(0.14, 0.16, 0.22, 1.0), true)
    _preview_anchor.draw_rect(rect, Color(0.3, 0.4, 0.55, 1.0), false)
    var f := ThemeDB.fallback_font
    var header := "PREVIEW"
    if _cut_enabled:
        header = "PREVIEW  —  cutting hitbox (drag)"
    if _cut_enabled:
        header = "PREVIEW  -  cutting %s (drag)" % _cut_target
    _preview_anchor.draw_string(f, Vector2(8, 16), header,
        HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
        Color(1, 0.82, 0.4, 1) if _cut_enabled else Color(0.6, 0.75, 0.9))

    var p := _current_box_values()
    if p.is_empty():
        return
    var scale_v: float = _preview_scale()
    if scale_v <= 0.0:
        return
    var center := _preview_sprite.position
    var col_w: int = int(p.get("collision_width", _default_collision_width()))
    var yr: int = int(p.get("y_radius", 16))
    var yoff: int = int(p.get("y_offset", 0))
    var collision_rect: Rect2 = _current_collision_rect()
    var hurt_rect: Rect2 = _current_hurtbox_rect()
    _preview_anchor.draw_rect(hurt_rect, HURTBOX_FILL_COLOR, true)
    _preview_anchor.draw_rect(hurt_rect, HURTBOX_COLOR, false, 2.0)
    _preview_anchor.draw_rect(collision_rect, COLLISION_FILL_COLOR, true)
    _preview_anchor.draw_rect(collision_rect, COLLISION_COLOR, false, 3.0)

    var origin := Vector2(center.x, center.y + float(yoff + yr) * scale_v)
    var anchor := origin + Vector2(
        float(int(p.get("weapon_anchor_x", 0))) * scale_v,
        float(int(p.get("weapon_anchor_y", _default_weapon_anchor_y(p)))) * scale_v
    )
    _preview_anchor.draw_line(anchor + Vector2(-6, 0), anchor + Vector2(6, 0), Color(1.0, 0.82, 0.35, 0.95), 2.0)
    _preview_anchor.draw_line(anchor + Vector2(0, -6), anchor + Vector2(0, 6), Color(1.0, 0.82, 0.35, 0.95), 2.0)

    _preview_anchor.draw_string(f, Vector2(8, _preview_anchor.size.y - 20),
        "collision(blue): x=%d w=%d yr=%d yoff=%d   hurt(red): x=%d y=%d w=%d h=%d" % [
            int(p.get("collision_x", 0)),
            int(p.get("collision_width", _default_collision_width())),
            yr, yoff,
            int(p.get("hurtbox_x", 0)),
            int(p.get("hurtbox_y", _default_hurtbox_y(p))),
            int(p.get("hurtbox_w", col_w)),
            int(p.get("hurtbox_h", yr * 2)),
        ],
        HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
        Color(0.85, 0.95, 0.85, 0.9))

    if _cut_enabled and _cut_target == "collision":
        var collision_handle_col: Color = Color(0.78, 0.9, 1.0, 0.95)
        _preview_anchor.draw_rect(Rect2(collision_rect.position + Vector2(collision_rect.size.x * 0.5 - 6, -4), Vector2(12, 8)), collision_handle_col, true)
        _preview_anchor.draw_rect(Rect2(collision_rect.position + Vector2(collision_rect.size.x * 0.5 - 6, collision_rect.size.y - 4), Vector2(12, 8)), collision_handle_col, true)
        _preview_anchor.draw_rect(Rect2(collision_rect.position + Vector2(-4, collision_rect.size.y * 0.5 - 6), Vector2(8, 12)), collision_handle_col, true)
        _preview_anchor.draw_rect(Rect2(collision_rect.position + Vector2(collision_rect.size.x - 4, collision_rect.size.y * 0.5 - 6), Vector2(8, 12)), collision_handle_col, true)

    if _cut_enabled and _cut_target == "hurtbox":
        var handle_rect: Rect2 = hurt_rect
        var hurt_handle_col: Color = Color(1.0, 0.88, 0.68, 0.95)
        _preview_anchor.draw_rect(Rect2(handle_rect.position + Vector2(handle_rect.size.x * 0.5 - 6, -4), Vector2(12, 8)), hurt_handle_col, true)
        _preview_anchor.draw_rect(Rect2(handle_rect.position + Vector2(handle_rect.size.x * 0.5 - 6, handle_rect.size.y - 4), Vector2(12, 8)), hurt_handle_col, true)
        _preview_anchor.draw_rect(Rect2(handle_rect.position + Vector2(-4, handle_rect.size.y * 0.5 - 6), Vector2(8, 12)), hurt_handle_col, true)
        _preview_anchor.draw_rect(Rect2(handle_rect.position + Vector2(handle_rect.size.x - 4, handle_rect.size.y * 0.5 - 6), Vector2(8, 12)), hurt_handle_col, true)

    if _cut_active:
        _preview_anchor.draw_rect(_cut_drag_rect, Color(1, 0.75, 0.2, 0.9), false, 1.0)
        _preview_anchor.draw_rect(_cut_drag_rect, Color(1, 0.75, 0.2, 0.18), true)


func _preview_scale() -> float:
    if _preview_sprite == null:
        return 1.0
    return _preview_sprite.scale.y


func _physics_collision_width() -> float:
    var ProfileScript: GDScript = load("res://MV/scripts/physics_profile.gd")
    if ProfileScript != null:
        var defaults: Resource = ProfileScript.new()
        if defaults != null and "collision_width" in defaults:
            return float(defaults.collision_width)
    return 24.0


func _sheet_fit_scale() -> float:
    if _sheet_texture == null:
        return 1.0
    var tex_size: Vector2 = _sheet_texture.get_size()
    var avail_w: float = maxf(1.0, _sheet_panel.size.x - 16.0)
    var avail_h: float = maxf(1.0, _sheet_panel.size.y - 16.0)
    var sx: float = avail_w / tex_size.x if tex_size.x > 0.0 else 1.0
    var sy: float = avail_h / tex_size.y if tex_size.y > 0.0 else 1.0
    return maxf(0.05, minf(sx, sy))


func _sheet_view_scale() -> float:
    return clampf(_sheet_fit_scale() * _sheet_zoom, 0.05, 16.0)


func _sheet_draw_origin(draw_size: Vector2) -> Vector2:
    return ((_sheet_panel.size - draw_size) * 0.5) + _sheet_pan


func _clamp_sheet_pan() -> void:
    if _sheet_texture == null:
        _sheet_pan = Vector2.ZERO
        return
    var draw_size: Vector2 = _sheet_texture.get_size() * _sheet_view_scale()
    var overflow_x: float = maxf(0.0, draw_size.x - _sheet_panel.size.x)
    var overflow_y: float = maxf(0.0, draw_size.y - _sheet_panel.size.y)
    _sheet_pan.x = clampf(_sheet_pan.x, -overflow_x * 0.5, overflow_x * 0.5)
    _sheet_pan.y = clampf(_sheet_pan.y, -overflow_y * 0.5, overflow_y * 0.5)


func _sheet_local_to_texture(local_pos: Vector2) -> Vector2:
    if _sheet_texture == null:
        return Vector2(-1.0, -1.0)
    var scale_v: float = _sheet_view_scale()
    var draw_size: Vector2 = _sheet_texture.get_size() * scale_v
    var origin: Vector2 = _sheet_draw_origin(draw_size)
    var tex_pos: Vector2 = (local_pos - origin) / scale_v
    var tex_size: Vector2 = _sheet_texture.get_size()
    if tex_pos.x < 0.0 or tex_pos.y < 0.0 or tex_pos.x >= tex_size.x or tex_pos.y >= tex_size.y:
        return Vector2(-1.0, -1.0)
    return tex_pos


func _zoom_sheet_at(local_pos: Vector2, factor: float) -> void:
    if _sheet_texture == null:
        return
    var before: Vector2 = _sheet_local_to_texture(local_pos)
    var old_zoom: float = _sheet_zoom
    _sheet_zoom = clampf(_sheet_zoom * factor, 0.25, 12.0)
    var old_scale: float = _sheet_fit_scale() * old_zoom
    var new_scale: float = _sheet_view_scale()
    if before.x >= 0.0 and before.y >= 0.0 and old_scale > 0.0 and new_scale > 0.0:
        var old_draw_size: Vector2 = _sheet_texture.get_size() * old_scale
        var new_draw_size: Vector2 = _sheet_texture.get_size() * new_scale
        var old_origin: Vector2 = ((_sheet_panel.size - old_draw_size) * 0.5) + _sheet_pan
        var new_origin: Vector2 = local_pos - (before * new_scale)
        _sheet_pan += new_origin - ((_sheet_panel.size - new_draw_size) * 0.5) - (old_origin - ((_sheet_panel.size - old_draw_size) * 0.5))
    _clamp_sheet_pan()
    _sheet_panel.queue_redraw()


func _current_collision_rect() -> Rect2:
    var p: Dictionary = _current_box_values()
    if p.is_empty():
        return Rect2()
    var scale_v: float = _preview_scale()
    var center: Vector2 = _preview_sprite.position
    var col_x: float = float(int(p.get("collision_x", 0))) * scale_v
    var col_w: float = float(int(p.get("collision_width", _default_collision_width()))) * scale_v
    var yr: float = float(int(p.get("y_radius", 16))) * scale_v
    var yoff: float = float(int(p.get("y_offset", 0))) * scale_v
    return Rect2(center.x + col_x - col_w * 0.5, center.y + yoff - yr, col_w, yr * 2.0)


func _current_hurtbox_rect() -> Rect2:
    var p: Dictionary = _current_box_values()
    if p.is_empty():
        return Rect2()
    var scale_v: float = _preview_scale()
    var center: Vector2 = _preview_sprite.position
    var yr: int = int(p.get("y_radius", 16))
    var yoff: int = int(p.get("y_offset", 0))
    var origin: Vector2 = Vector2(center.x, center.y + float(yoff + yr) * scale_v)
    var hurt_center: Vector2 = origin + Vector2(
        float(int(p.get("hurtbox_x", 0))) * scale_v,
        float(int(p.get("hurtbox_y", _default_hurtbox_y(p)))) * scale_v
    )
    var hurt_size: Vector2 = Vector2(
        maxf(1.0, float(int(p.get("hurtbox_w", _default_collision_width()))) * scale_v),
        maxf(1.0, float(int(p.get("hurtbox_h", yr * 2))) * scale_v)
    )
    return Rect2(hurt_center - hurt_size * 0.5, hurt_size)


func _current_cut_rect() -> Rect2:
    if _cut_target == "hurtbox":
        return _current_hurtbox_rect()
    return _current_collision_rect()


func _cut_mode_for_point(rect: Rect2, pos: Vector2) -> String:
    var top_rect: Rect2 = Rect2(rect.position.x + rect.size.x * 0.5 - 8.0, rect.position.y - 6.0, 16.0, 12.0)
    var bottom_rect: Rect2 = Rect2(rect.position.x + rect.size.x * 0.5 - 8.0, rect.end.y - 6.0, 16.0, 12.0)
    var left_rect: Rect2 = Rect2(rect.position.x - 6.0, rect.position.y + rect.size.y * 0.5 - 8.0, 12.0, 16.0)
    var right_rect: Rect2 = Rect2(rect.end.x - 6.0, rect.position.y + rect.size.y * 0.5 - 8.0, 12.0, 16.0)
    if top_rect.has_point(pos):
        return "top"
    if bottom_rect.has_point(pos):
        return "bottom"
    if left_rect.has_point(pos):
        return "left"
    if right_rect.has_point(pos):
        return "right"
    if rect.grow(8.0).has_point(pos):
        return "move"
    return "new"


func _update_cut_drag(pos: Vector2) -> void:
    match _cut_drag_mode:
        "new":
            _cut_drag_rect = _normalized_rect(Rect2(_cut_pointer_start, pos - _cut_pointer_start))
        "move":
            _cut_drag_rect = _cut_origin_rect
            _cut_drag_rect.position += pos - _cut_pointer_start
        "top":
            _cut_drag_rect = _normalized_rect(Rect2(
                Vector2(_cut_origin_rect.position.x, pos.y),
                Vector2(_cut_origin_rect.size.x, _cut_origin_rect.end.y - pos.y)
            ))
        "bottom":
            _cut_drag_rect = _normalized_rect(Rect2(
                _cut_origin_rect.position,
                Vector2(_cut_origin_rect.size.x, pos.y - _cut_origin_rect.position.y)
            ))
        "left":
            _cut_drag_rect = _normalized_rect(Rect2(
                Vector2(pos.x, _cut_origin_rect.position.y),
                Vector2(_cut_origin_rect.end.x - pos.x, _cut_origin_rect.size.y)
            ))
        "right":
            _cut_drag_rect = _normalized_rect(Rect2(
                _cut_origin_rect.position,
                Vector2(pos.x - _cut_origin_rect.position.x, _cut_origin_rect.size.y)
            ))


func _normalized_rect(rect: Rect2) -> Rect2:
    var x1: float = minf(rect.position.x, rect.end.x)
    var x2: float = maxf(rect.position.x, rect.end.x)
    var y1: float = minf(rect.position.y, rect.end.y)
    var y2: float = maxf(rect.position.y, rect.end.y)
    return Rect2(Vector2(x1, y1), Vector2(x2 - x1, y2 - y1))


func _set_cut_tool(target: String, pressed: bool) -> void:
    _cut_enabled = pressed
    _cut_target = target
    _cut_active = false
    _cut_drag_mode = ""
    _cut_drag_rect = _current_cut_rect()
    if _preview_anchor != null:
        _preview_anchor.queue_redraw()


func _on_cut_collision_toggled(pressed: bool) -> void:
    if pressed and _cut_hurtbox_btn != null and _cut_hurtbox_btn.button_pressed:
        _cut_hurtbox_btn.set_pressed_no_signal(false)
    _set_cut_tool("collision", pressed)


func _on_cut_hurtbox_toggled(pressed: bool) -> void:
    if pressed and _cut_collision_btn != null and _cut_collision_btn.button_pressed:
        _cut_collision_btn.set_pressed_no_signal(false)
    _set_cut_tool("hurtbox", pressed)


func _on_copy_collision_all_pressed() -> void:
    _copy_current_box_to_all_poses("collision")


func _on_copy_hurtbox_all_pressed() -> void:
    _copy_current_box_to_all_poses("hurtbox")


func _copy_current_box_to_all_poses(box_kind: String) -> void:
    var source_pose: Dictionary = _selected_pose_dict()
    if source_pose.is_empty():
        return
    var source_values: Dictionary = _current_box_values()
    if _undo != null:
        _undo.begin()
    for pose_id_v in _poses.keys():
        var pose_id: int = int(pose_id_v)
        var target_pose: Dictionary = (_poses[pose_id] as Dictionary).duplicate(true)
        if box_kind == "collision":
            var collision_values: Dictionary = {
                "y_radius": int(source_values.get("y_radius", 16)),
                "y_offset": int(source_values.get("y_offset", 0)),
                "collision_width": int(source_values.get("collision_width", int(_default_collision_width()))),
                "collision_x": _mirror_x_for_pose(int(source_values.get("collision_x", 0)), source_pose, target_pose),
                "hurtbox_x": int(target_pose.get("hurtbox_x", 0)),
                "hurtbox_y": int(target_pose.get("hurtbox_y", _default_hurtbox_y(target_pose))),
                "hurtbox_w": int(target_pose.get("hurtbox_w", int(target_pose.get("collision_width", _default_collision_width())))),
                "hurtbox_h": int(target_pose.get("hurtbox_h", int(target_pose.get("y_radius", 16)) * 2)),
            }
            target_pose = _apply_box_values_to_pose(target_pose, collision_values, false)
            target_pose = _ensure_frame_boxes_size(target_pose, _frame_count_for_pose(pose_id))
            var collision_boxes: Array = _frame_boxes_array(target_pose.get("frame_boxes", []))
            for i in range(collision_boxes.size()):
                var box: Dictionary = collision_boxes[i] if typeof(collision_boxes[i]) == TYPE_DICTIONARY else {}
                box["y_radius"] = int(collision_values["y_radius"])
                box["y_offset"] = int(collision_values["y_offset"])
                box["collision_width"] = int(collision_values["collision_width"])
                box["collision_x"] = int(collision_values["collision_x"])
                collision_boxes[i] = box
            target_pose["frame_boxes"] = collision_boxes
        else:
            var hurt_values: Dictionary = {
                "y_radius": int(target_pose.get("y_radius", 16)),
                "y_offset": int(target_pose.get("y_offset", 0)),
                "collision_x": int(target_pose.get("collision_x", 0)),
                "collision_width": int(target_pose.get("collision_width", int(_default_collision_width()))),
                "hurtbox_x": _mirror_x_for_pose(int(source_values.get("hurtbox_x", 0)), source_pose, target_pose),
                "hurtbox_y": int(source_values.get("hurtbox_y", _default_hurtbox_y(source_values))),
                "hurtbox_w": int(source_values.get("hurtbox_w", int(source_values.get("collision_width", _default_collision_width())))),
                "hurtbox_h": int(source_values.get("hurtbox_h", int(source_values.get("y_radius", 16)) * 2)),
            }
            target_pose = _apply_box_values_to_pose(target_pose, hurt_values, false)
            target_pose = _ensure_frame_boxes_size(target_pose, _frame_count_for_pose(pose_id))
            var hurt_boxes: Array = _frame_boxes_array(target_pose.get("frame_boxes", []))
            for i in range(hurt_boxes.size()):
                var box: Dictionary = hurt_boxes[i] if typeof(hurt_boxes[i]) == TYPE_DICTIONARY else {}
                box["hurtbox_x"] = int(hurt_values["hurtbox_x"])
                box["hurtbox_y"] = int(hurt_values["hurtbox_y"])
                box["hurtbox_w"] = int(hurt_values["hurtbox_w"])
                box["hurtbox_h"] = int(hurt_values["hurtbox_h"])
                hurt_boxes[i] = box
            target_pose["frame_boxes"] = hurt_boxes
        _poses[pose_id] = target_pose
    dirty = true
    _apply_pose_to_inputs()
    if _preview_anchor != null:
        _preview_anchor.queue_redraw()
    if _undo != null:
        _undo.commit("copy %s to all poses" % box_kind)


func _on_preview_gui_input(event: InputEvent) -> void:
    if not _cut_enabled:
        return
    if _selected_pose_id < 0:
        return
    if event is InputEventMouseButton:
        var mb: InputEventMouseButton = event
        if mb.button_index != MOUSE_BUTTON_LEFT:
            return
        if mb.pressed:
            var current_rect: Rect2 = _current_cut_rect()
            _cut_active = true
            _cut_pointer_start = mb.position
            _cut_origin_rect = current_rect
            _cut_drag_mode = _cut_mode_for_point(current_rect, mb.position)
            if _cut_drag_mode == "new":
                _cut_drag_rect = Rect2(mb.position, Vector2.ZERO)
            else:
                _cut_drag_rect = current_rect
            _preview_anchor.queue_redraw()
        else:
            if _cut_active:
                _update_cut_drag(mb.position)
                _commit_cut()
                _cut_active = false
                _cut_drag_mode = ""
                _preview_anchor.queue_redraw()
    elif event is InputEventMouseMotion and _cut_active:
        _update_cut_drag((event as InputEventMouseMotion).position)
        _preview_anchor.queue_redraw()


func _commit_cut() -> void:
    if _cut_target == "hurtbox":
        _commit_hurtbox_cut()
        return
    _commit_collision_cut()


func _commit_collision_cut() -> void:
    var p: Dictionary = _selected_pose_edit_dict()
    if p.is_empty():
        return
    var s: float = _preview_scale()
    if s <= 0.0:
        return
    var cut_rect: Rect2 = _normalized_rect(_cut_drag_rect)
    var rect_h_px: float = cut_rect.size.y
    var rect_w_px: float = cut_rect.size.x
    if rect_h_px < 4.0 or rect_w_px < 4.0:
        return
    var sprite_center: Vector2 = _preview_sprite.position
    var rect_center: Vector2 = cut_rect.get_center()
    var new_yr: int = int(round((rect_h_px * 0.5) / s))
    if new_yr < 2:
        new_yr = 2
    var new_col_w: int = int(round(rect_w_px / s))
    if new_col_w < 1:
        new_col_w = 1
    var new_collision_x: int = int(round((rect_center.x - sprite_center.x) / s))
    var new_yoff: int = int(round((rect_center.y - sprite_center.y) / s))
    if _undo != null:
        _undo.begin()
    p = _apply_box_values_to_pose(p, {
        "y_radius": new_yr,
        "y_offset": new_yoff,
        "collision_x": new_collision_x,
        "collision_width": new_col_w,
        "hurtbox_x": int(_current_box_values().get("hurtbox_x", 0)),
        "hurtbox_y": int(_current_box_values().get("hurtbox_y", _default_hurtbox_y(p))),
        "hurtbox_w": int(_current_box_values().get("hurtbox_w", new_col_w)),
        "hurtbox_h": int(_current_box_values().get("hurtbox_h", new_yr * 2)),
    }, _selected_strip_idx >= 0, _selected_pose_id)
    _poses[_selected_pose_id] = p
    dirty = true
    _apply_pose_to_inputs()
    if _undo != null:
        _undo.commit("cut collision")


func _commit_hurtbox_cut() -> void:
    var p: Dictionary = _selected_pose_edit_dict()
    if p.is_empty():
        return
    var current_values: Dictionary = _current_box_values()
    var s: float = _preview_scale()
    if s <= 0.0:
        return
    var cut_rect: Rect2 = _normalized_rect(_cut_drag_rect)
    var rect_h_px: float = cut_rect.size.y
    var rect_w_px: float = cut_rect.size.x
    if rect_h_px < 4.0 or rect_w_px < 4.0:
        return
    var center: Vector2 = _preview_sprite.position
    var yr: int = int(current_values.get("y_radius", int(p.get("y_radius", 16))))
    var yoff: int = int(current_values.get("y_offset", int(p.get("y_offset", 0))))
    var body_origin: Vector2 = Vector2(center.x, center.y + float(yoff + yr) * s)
    var rect_center: Vector2 = cut_rect.get_center()
    var new_hurt_x: int = int(round((rect_center.x - body_origin.x) / s))
    var new_hurt_y: int = int(round((rect_center.y - body_origin.y) / s))
    var new_hurt_w: int = maxi(1, int(round(rect_w_px / s)))
    var new_hurt_h: int = maxi(1, int(round(rect_h_px / s)))
    if _undo != null:
        _undo.begin()
    p = _apply_box_values_to_pose(p, {
        "y_radius": yr,
        "y_offset": yoff,
        "collision_x": int(current_values.get("collision_x", int(p.get("collision_x", 0)))),
        "collision_width": int(current_values.get("collision_width", int(p.get("collision_width", _default_collision_width())))),
        "hurtbox_x": new_hurt_x,
        "hurtbox_y": new_hurt_y,
        "hurtbox_w": new_hurt_w,
        "hurtbox_h": new_hurt_h,
    }, _selected_strip_idx >= 0, _selected_pose_id)
    _poses[_selected_pose_id] = p
    dirty = true
    _apply_pose_to_inputs()
    if _undo != null:
        _undo.commit("cut hurtbox")


func _tick_preview(delta: float) -> void:
    if _selected_pose_id < 0 or _preview_sprite == null:
        return
    var p := _selected_pose_dict()
    if p.is_empty():
        return
    var anim_p: Dictionary = _resolved_animation_pose_dict(_selected_pose_id)
    var seq: Array = _resolved_frames_for_pose(_selected_pose_id)
    if seq.is_empty():
        for spr_v in _preview_layer_sprites.values():
            var spr: Sprite2D = spr_v
            if is_instance_valid(spr):
                spr.visible = false
                spr.rotation_degrees = 0.0
        return
    var timing: Array = anim_p.get("timing", [])
    if _preview_anim_idx >= seq.size():
        _preview_anim_idx = 0
    var hold_ticks: int = int(timing[_preview_anim_idx]) if _preview_anim_idx < timing.size() else 10
    var anim_speed: float = _normalized_anim_speed(anim_p.get("anim_speed", p.get("anim_speed", 1.0)))
    var hold_sec: float = (float(hold_ticks) / 60.0) / anim_speed
    _preview_tick += delta
    if _preview_tick >= hold_sec:
        _preview_tick = 0.0
        _preview_anim_idx += 1
        if _preview_anim_idx >= seq.size():
            var loop_from: int = int(anim_p.get("loop_from", 0))
            _preview_anim_idx = clampi(loop_from, 0, seq.size() - 1)

    for spr_v in _preview_layer_sprites.values():
        var hidden_sprite: Sprite2D = spr_v
        if is_instance_valid(hidden_sprite):
            hidden_sprite.visible = false
            hidden_sprite.rotation_degrees = 0.0
    var frame_entry: Dictionary = _normalize_frame_entry(seq[_preview_anim_idx])
    var frame_rotation: float = float(frame_entry.get("rotation_deg", 0.0))
    var display_rotation: float = _display_frame_rotation(_selected_pose_id, frame_rotation)
    for layer_v in _sorted_frame_layers(frame_entry):
        if typeof(layer_v) != TYPE_DICTIONARY:
            continue
        var layer: Dictionary = layer_v
        var sheet_id: String = str(layer.get("sheet", PspIO.BASE_SHEET_ID)).strip_edges()
        var spr: Sprite2D = _preview_layer_sprites.get(sheet_id, null) as Sprite2D
        if spr == null:
            continue
        spr.visible = true
        spr.frame = int(layer.get("index", 0))
        spr.flip_h = _pose_uses_mirrored_fallback(_selected_pose_id)
        spr.rotation_degrees = display_rotation


# ─── Import sheet ────────────────────────────────────────────────────────

func _on_import_pressed() -> void:
    if _file_dialog == null:
        _file_dialog = FileDialog.new()
        _file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        _file_dialog.access = FileDialog.ACCESS_FILESYSTEM
        _file_dialog.filters = PackedStringArray(["*.png ; PNG images"])
        _enable_native_file_dialog(_file_dialog)
        _file_dialog.file_selected.connect(_on_sheet_file_selected)
        add_child(_file_dialog)
    _file_dialog.popup_centered_ratio(0.7)


func _on_sheet_file_selected(path: String) -> void:
    var file_name: String = PspIO.next_import_sheet_file_name(pack_id, path)
    if not PspIO.import_sheet_as(pack_id, path, file_name):
        return
    var base_sheet_id: String = PspIO.sheet_id_from_file_name(file_name)
    var final_sheet_id: String = base_sheet_id
    var counter: int = 2
    while true:
        var exists: bool = false
        for sheet_def_v in _sheet_defs:
            if typeof(sheet_def_v) != TYPE_DICTIONARY:
                continue
            if str((sheet_def_v as Dictionary).get("id", "")).strip_edges() == final_sheet_id:
                exists = true
                break
        if not exists:
            break
        final_sheet_id = "%s_%d" % [base_sheet_id, counter]
        counter += 1
    _sheet_defs.append({
        "id": final_sheet_id,
        "file": file_name,
        "z": _sheet_defs.size(),
    })
    _active_sheet_id = final_sheet_id
    _sheet_textures = PspIO.load_sheet_textures(pack_id, _sheet_defs)
    _sheet_texture = _active_sheet_texture()
    _rebuild_sheet_option()
    _rebuild_preview_layer_sprites()
    _sheet_zoom = 1.0
    _sheet_pan = Vector2.ZERO
    # Re-derive frame W/H from current cols/rows against the new sheet size.
    if _sheet_texture != null:
        var tex_size: Vector2 = _sheet_texture.get_size()
        var cols: int = maxi(1, int(_sheet_meta.get("sheet_cols", 10)))
        var rows: int = maxi(1, int(_sheet_meta.get("sheet_rows", 1)))
        @warning_ignore("integer_division")
        _sheet_meta["frame_width"] = maxi(1, int(tex_size.x) / cols)
        @warning_ignore("integer_division")
        _sheet_meta["frame_height"] = maxi(1, int(tex_size.y) / rows)
        _recompute_center_auto()
    _apply_sheet_meta_to_inputs()
    _apply_preview_sprite_layout()
    _sheet_panel.queue_redraw()
    _strip_panel.queue_redraw()
    dirty = true


func _on_sheet_option_selected(index: int) -> void:
    if index < 0 or index >= _sheet_option.item_count:
        return
    var item_id: int = _sheet_option.get_item_id(index)
    if item_id < 0 or item_id >= _sheet_defs.size():
        return
    var sheet_def_v: Variant = _sheet_defs[item_id]
    if typeof(sheet_def_v) != TYPE_DICTIONARY:
        return
    var sheet_def: Dictionary = sheet_def_v
    _active_sheet_id = str(sheet_def.get("id", PspIO.BASE_SHEET_ID)).strip_edges()
    _sheet_texture = _active_sheet_texture()
    _sheet_zoom = 1.0
    _sheet_pan = Vector2.ZERO
    _apply_sheet_meta_to_inputs()
    _apply_preview_sprite_layout()
    if _sheet_panel != null:
        _sheet_panel.queue_redraw()


func _on_remove_sheet_pressed() -> void:
    if _sheet_defs.size() <= 1:
        return
    var remove_idx: int = -1
    for i in range(_sheet_defs.size()):
        if typeof(_sheet_defs[i]) != TYPE_DICTIONARY:
            continue
        if str((_sheet_defs[i] as Dictionary).get("id", "")).strip_edges() == _active_sheet_id:
            remove_idx = i
            break
    if remove_idx < 0:
        return
    var removed_sheet: Dictionary = _sheet_defs[remove_idx]
    var removed_sheet_id: String = str(removed_sheet.get("id", "")).strip_edges()
    if removed_sheet_id == PspIO.BASE_SHEET_ID:
        return
    if _undo != null:
        _undo.begin()
    _sheet_defs.remove_at(remove_idx)
    for pose_id_v in _frames.keys():
        var pose_id: int = int(pose_id_v)
        var seq: Array = _frames[pose_id]
        for i in range(seq.size()):
            seq[i] = _remove_sheet_from_frame(seq[i], removed_sheet_id)
        _frames[pose_id] = seq
    _ensure_active_sheet_valid()
    _sheet_textures = PspIO.load_sheet_textures(pack_id, _sheet_defs)
    _sheet_texture = _active_sheet_texture()
    _rebuild_sheet_option()
    _rebuild_preview_layer_sprites()
    _apply_preview_sprite_layout()
    if _sheet_panel != null:
        _sheet_panel.queue_redraw()
    if _strip_panel != null:
        _strip_panel.queue_redraw()
    dirty = true
    if _undo != null:
        _undo.commit("remove sheet")


func _enable_native_file_dialog(dialog: FileDialog) -> void:
    for prop_v in dialog.get_property_list():
        if typeof(prop_v) != TYPE_DICTIONARY:
            continue
        var prop: Dictionary = prop_v
        if str(prop.get("name", "")) == "use_native_dialog":
            dialog.set("use_native_dialog", true)
            return

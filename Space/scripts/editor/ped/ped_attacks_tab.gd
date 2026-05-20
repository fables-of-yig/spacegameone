extends Control

const PedIO = preload("res://Space/scripts/shared/ped/ped_io.gd")
const PedUtil = preload("res://Space/scripts/editor/ped/ped_util.gd")
const PspIO = preload("res://Space/scripts/shared/psp/psp_io.gd")

signal edit_projectile_requested(projectile_id: String)

# Player editor — Attacks tab. List + detail editor for attacks.json. Each
# attack is either a melee hitbox spawned during specific animation frames, or
# a projectile spawn referencing a projectile_id from projectiles.json.

var pack_id: String = ""
var dirty: bool = false

var _attacks: Array = []              # Array[Dictionary]
var _projectile_pool: Array = []      # Array[String] — projectile ids
var _projectile_defs: Dictionary = {}
var _selected_idx: int = -1

const ATTACK_TYPES: Array = ["melee", "projectile"]
const HOLD_BEHAVIOR_OPTIONS: Array = [
    {"id": "full_auto", "label": "Full Auto"},
    {"id": "single_press", "label": "Single Press"},
    {"id": "charge_release", "label": "Charge + Release"},
]

# Left column
var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null
var _list_header: Label = null

# Headers
var _detail_header: Label = null
var _visual_header: Label = null
var _timing_header: Label = null
var _melee_header: Label = null
var _projectile_header: Label = null

# Identity
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _type_option: OptionButton = null
var _label_id: Label = null
var _label_name: Label = null
var _label_type: Label = null

# Timing / cost / pose
var _cooldown_edit: LineEdit = null
var _cost_edit: LineEdit = null
var _pose_edit: LineEdit = null
var _hold_behavior_option: OptionButton = null
var _charge_ticks_edit: LineEdit = null
var _charged_attack_edit: LineEdit = null
var _combo_next_edit: LineEdit = null
var _label_cooldown: Label = null
var _label_cost: Label = null
var _label_pose: Label = null
var _label_hold_behavior: Label = null
var _label_charge_ticks: Label = null
var _label_charged_attack: Label = null
var _label_combo_next: Label = null

# Melee
var _hit_frames_edit: LineEdit = null
var _hitbox_x_edit: LineEdit = null
var _hitbox_y_edit: LineEdit = null
var _hitbox_w_edit: LineEdit = null
var _hitbox_h_edit: LineEdit = null
var _damage_edit: LineEdit = null
var _knockback_edit: LineEdit = null
var _label_hit_frames: Label = null
var _label_hitbox_x: Label = null
var _label_hitbox_y: Label = null
var _label_hitbox_w: Label = null
var _label_hitbox_h: Label = null
var _label_damage: Label = null
var _label_knockback: Label = null

# Projectile
var _projectile_option: OptionButton = null
var _muzzle_x_edit: LineEdit = null
var _muzzle_y_edit: LineEdit = null
var _label_projectile: Label = null
var _label_muzzle_x: Label = null
var _label_muzzle_y: Label = null

# Linked projectile visual preview
var _linked_projectile_header: Label = null
var _linked_projectile_meta: Label = null
var _edit_projectile_btn: Button = null
var _linked_projectile_preview: Control = null

# Sprite FX (optional — attack effect like a slash arc; preview also shows
# hitbox rect overlay so author can align art + hitbox together)
var _sprite_header: Label = null
var _sheet_edit: LineEdit = null
var _fw_edit: LineEdit = null
var _fh_edit: LineEdit = null
var _findex_edit: LineEdit = null
var _fcount_edit: LineEdit = null
var _ftick_edit: LineEdit = null
var _label_sheet: Label = null
var _label_fw: Label = null
var _label_fh: Label = null
var _label_findex: Label = null
var _label_fcount: Label = null
var _label_ftick: Label = null
var _sprite_preview: Control = null

# Charge FX preview shown at the projectile muzzle while the button is held.
var _charge_fx_header: Label = null
var _charge_fx_sheet_edit: LineEdit = null
var _charge_fx_fw_edit: LineEdit = null
var _charge_fx_fh_edit: LineEdit = null
var _charge_fx_findex_edit: LineEdit = null
var _charge_fx_fcount_edit: LineEdit = null
var _charge_fx_ftick_edit: LineEdit = null
var _charge_fx_label_sheet: Label = null
var _charge_fx_label_fw: Label = null
var _charge_fx_label_fh: Label = null
var _charge_fx_label_findex: Label = null
var _charge_fx_label_fcount: Label = null
var _charge_fx_label_ftick: Label = null
var _charge_fx_preview: Control = null

var _suppress_events: bool = false
var _undo: RefCounted = null
var _player_frames_data: Dictionary = {}
var _player_poses_data: Dictionary = {}
var _player_sheet_defs: Array = []

const LEFT_W: float = 220.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "attacks": _attacks.duplicate(true),
        "selected_idx": _selected_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var a_v: Variant = snap.get("attacks", null)
    if typeof(a_v) == TYPE_ARRAY:
        _attacks = a_v
    _selected_idx = int(snap.get("selected_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_list()
    if _selected_idx >= 0 and _selected_idx < _attacks.size() and _list != null:
        _list.select(_selected_idx)
    _apply_to_inputs()


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


func _process(_delta: float) -> void:
    if not is_visible_in_tree():
        return
    _update_tooltips()


func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    if _type_option != null and Rect2(_type_option.position, _type_option.size).has_point(mp):
        EditorTooltip.show_text("Attack type. Melee spawns a hitbox on the player during specific animation frames. Projectile spawns a flying bullet from the muzzle offset.")
    elif _cooldown_edit != null and Rect2(_cooldown_edit.position, _cooldown_edit.size).has_point(mp):
        EditorTooltip.show_text("Cooldown in physics ticks (1/60 s) before this attack can be used again after firing.")
    elif _cost_edit != null and Rect2(_cost_edit.position, _cost_edit.size).has_point(mp):
        EditorTooltip.show_text("MP cost per use. The attack fails silently if the player lacks enough MP.")
    elif _pose_edit != null and Rect2(_pose_edit.position, _pose_edit.size).has_point(mp):
        EditorTooltip.show_text("Player pose ID to display during the attack animation. Use the seeded right-facing combat poses from the Sprites tab; the runtime automatically picks the matching left-facing pose when needed.")
    elif _hold_behavior_option != null and Rect2(_hold_behavior_option.position, _hold_behavior_option.size).has_point(mp):
        EditorTooltip.show_text("What happens if the ranged attack button stays held. Full Auto repeats on cooldown while held, Single Press only fires on the initial press, and Charge + Release keeps the old held-charge behavior.")
    elif _charge_ticks_edit != null and Rect2(_charge_ticks_edit.position, _charge_ticks_edit.size).has_point(mp):
        EditorTooltip.show_text("Hold time in physics ticks before a Charge + Release attack swaps to its charged follow-up. Ignored for Full Auto and Single Press.")
    elif _charged_attack_edit != null and Rect2(_charged_attack_edit.position, _charged_attack_edit.size).has_point(mp):
        EditorTooltip.show_text("Charged follow-up attack id used by Charge + Release mode after the hold threshold is reached. Ignored by Full Auto and Single Press.")
    elif _combo_next_edit != null and Rect2(_combo_next_edit.position, _combo_next_edit.size).has_point(mp):
        EditorTooltip.show_text("Optional melee combo follow-up attack id. While this attack is playing, pressing shoot again after its first hit frame queues the follow-up instead of restarting the chain.")
    elif _hit_frames_edit != null and Rect2(_hit_frames_edit.position, _hit_frames_edit.size).has_point(mp):
        EditorTooltip.show_text("Comma-separated frame indices (within the attack pose) during which the melee hitbox is active. e.g. \"2, 3, 4\".")
    elif _damage_edit != null and Rect2(_damage_edit.position, _damage_edit.size).has_point(mp):
        EditorTooltip.show_text("Base damage dealt per hit. The runtime scales this by the player's STR and any equipment modifiers.")
    elif _knockback_edit != null and Rect2(_knockback_edit.position, _knockback_edit.size).has_point(mp):
        EditorTooltip.show_text("Knockback force applied to enemies on hit. Higher values push enemies further away.")
    elif _hitbox_x_edit != null and Rect2(_hitbox_x_edit.position, _hitbox_x_edit.size).has_point(mp):
        EditorTooltip.show_text("Melee hitbox X offset from the player center, in pixels. Positive = forward (in the player's facing direction).")
    elif _hitbox_y_edit != null and Rect2(_hitbox_y_edit.position, _hitbox_y_edit.size).has_point(mp):
        EditorTooltip.show_text("Melee hitbox Y offset from the player center, in pixels. Negative = up.")
    elif _hitbox_w_edit != null and Rect2(_hitbox_w_edit.position, _hitbox_w_edit.size).has_point(mp):
        EditorTooltip.show_text("Melee hitbox width in pixels.")
    elif _hitbox_h_edit != null and Rect2(_hitbox_h_edit.position, _hitbox_h_edit.size).has_point(mp):
        EditorTooltip.show_text("Melee hitbox height in pixels.")
    elif _projectile_option != null and Rect2(_projectile_option.position, _projectile_option.size).has_point(mp):
        EditorTooltip.show_text("Which projectile definition to spawn. The linked projectile preview and edit shortcut are shown in the visuals column.")
    elif _muzzle_x_edit != null and Rect2(_muzzle_x_edit.position, _muzzle_x_edit.size).has_point(mp):
        EditorTooltip.show_text("Muzzle X offset from the player center where the projectile spawns. Positive = forward.")
    elif _muzzle_y_edit != null and Rect2(_muzzle_y_edit.position, _muzzle_y_edit.size).has_point(mp):
        EditorTooltip.show_text("Muzzle Y offset from the player center where the projectile spawns. Negative = up.")
    elif _edit_projectile_btn != null and Rect2(_edit_projectile_btn.position, _edit_projectile_btn.size).has_point(mp):
        EditorTooltip.show_text("Jump to the linked projectile entry so you can edit its sprite, hitbox, trail, and other projectile-only data.")
    elif _charge_fx_sheet_edit != null and Rect2(_charge_fx_sheet_edit.position, _charge_fx_sheet_edit.size).has_point(mp):
        EditorTooltip.show_text("Optional sprite sheet shown at the muzzle while this ranged attack is being charged. Leave blank to disable charge-tip FX.")
    elif _charge_fx_findex_edit != null and Rect2(_charge_fx_findex_edit.position, _charge_fx_findex_edit.size).has_point(mp):
        EditorTooltip.show_text("Starting frame index for the charge FX animation.")
    elif _charge_fx_fcount_edit != null and Rect2(_charge_fx_fcount_edit.position, _charge_fx_fcount_edit.size).has_point(mp):
        EditorTooltip.show_text("Number of charge FX frames. 1 = static glow, more = animated muzzle effect.")
    elif _charge_fx_ftick_edit != null and Rect2(_charge_fx_ftick_edit.position, _charge_fx_ftick_edit.size).has_point(mp):
        EditorTooltip.show_text("Ticks per charge FX frame (1/60 s). Lower values animate the charging effect faster.")


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_data()
    _load_projectile_pool()
    _load_player_preview_data()
    _populate_projectile_option()
    _populate_list()
    if _attacks.size() > 0:
        _list.select(0)
        _on_list_selected(0)
    else:
        _apply_to_inputs()
    dirty = false
    if _undo != null:
        _undo.clear()


func save() -> bool:
    var out := {"attacks": _attacks.duplicate(true)}
    if not PedIO.save_attacks(pack_id, out):
        return false
    dirty = false
    return true


func is_dirty() -> bool:
    return dirty


# ─── Layout ──────────────────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.09, 0.1, 0.13, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _list_header = _make_header("ATTACKS")
    _list = ItemList.new()
    _list.item_selected.connect(_on_list_selected)
    add_child(_list)
    _add_btn = _make_button("+ ATTACK", _on_add_pressed)
    _del_btn = _make_button("- ATTACK", _on_del_pressed)

    _detail_header = _make_header("DETAIL")
    _visual_header = _make_header("VISUALS")

    # Identity
    _label_id = _make_label("ID")
    _id_edit = _make_line_edit("id", "str")
    _label_name = _make_label("Name")
    _name_edit = _make_line_edit("name", "str")
    _label_type = _make_label("Type")
    _type_option = OptionButton.new()
    for t in ATTACK_TYPES:
        _type_option.add_item(str(t))
    _type_option.item_selected.connect(func(_i): _on_type_selected())
    add_child(_type_option)

    # Timing section
    _timing_header = _make_header("TIMING / COST / POSE")
    _label_cooldown = _make_label("Cooldown (t)")
    _cooldown_edit = _make_line_edit("cooldown_ticks", "int")
    _label_cost = _make_label("Cost MP")
    _cost_edit = _make_line_edit("cost_mp", "int")
    _label_pose = _make_label("Player pose")
    _pose_edit = _make_line_edit("player_pose", "int")
    _pose_edit.placeholder_text = "201 (melee_1_right)"
    _label_hold_behavior = _make_label("Hold button")
    _hold_behavior_option = OptionButton.new()
    for entry in HOLD_BEHAVIOR_OPTIONS:
        _hold_behavior_option.add_item(str(entry.get("label", "")))
    _hold_behavior_option.item_selected.connect(func(_i): _on_hold_behavior_selected())
    add_child(_hold_behavior_option)
    _label_charge_ticks = _make_label("Charge (t)")
    _charge_ticks_edit = _make_line_edit("charge_ticks", "int")
    _label_charged_attack = _make_label("Charged id")
    _charged_attack_edit = _make_line_edit("charged_attack_id", "str")
    _label_combo_next = _make_label("Combo next")
    _combo_next_edit = _make_line_edit("combo_next_id", "str")
    _combo_next_edit.placeholder_text = "combo_slash_2"

    # Melee section
    _melee_header = _make_header("MELEE (ignored if type=projectile)")
    _label_hit_frames = _make_label("Hit frames")
    _hit_frames_edit = LineEdit.new()
    _hit_frames_edit.placeholder_text = "2, 3, 4"
    _hit_frames_edit.text_changed.connect(_on_hit_frames_changed)
    add_child(_hit_frames_edit)
    _label_hitbox_x = _make_label("Hitbox X")
    _hitbox_x_edit = _make_line_edit("hitbox_x", "int")
    _label_hitbox_y = _make_label("Hitbox Y")
    _hitbox_y_edit = _make_line_edit("hitbox_y", "int")
    _label_hitbox_w = _make_label("Hitbox W")
    _hitbox_w_edit = _make_line_edit("hitbox_w", "int")
    _label_hitbox_h = _make_label("Hitbox H")
    _hitbox_h_edit = _make_line_edit("hitbox_h", "int")
    _label_damage = _make_label("Damage")
    _damage_edit = _make_line_edit("damage", "int")
    _label_knockback = _make_label("Knockback")
    _knockback_edit = _make_line_edit("knockback", "int")

    # Projectile section
    _projectile_header = _make_header("PROJECTILE (ignored if type=melee)")
    _label_projectile = _make_label("Projectile id")
    _projectile_option = OptionButton.new()
    _projectile_option.item_selected.connect(func(_i): _on_projectile_selected())
    add_child(_projectile_option)
    _label_muzzle_x = _make_label("Muzzle X")
    _muzzle_x_edit = _make_line_edit("muzzle_x", "int")
    _label_muzzle_y = _make_label("Muzzle Y")
    _muzzle_y_edit = _make_line_edit("muzzle_y", "int")

    # Linked projectile preview + jump-to-projectile shortcut
    _linked_projectile_header = _make_header("LINKED PROJECTILE")
    _linked_projectile_meta = _make_label("Pick a projectile attack to preview its sprite.")
    _edit_projectile_btn = _make_button("EDIT PROJECTILE", _on_edit_projectile_pressed)
    _linked_projectile_preview = Control.new()
    _linked_projectile_preview.set_script(preload("res://Space/scripts/editor/ped/ped_sprite_preview.gd"))
    add_child(_linked_projectile_preview)

    # Sprite FX + hitbox overlay preview
    _sprite_header = _make_header("SPRITE FX + HITBOX PREVIEW")
    _label_sheet = _make_label("Sheet")
    _sheet_edit = LineEdit.new()
    _sheet_edit.placeholder_text = "attacks_fx.png (optional)"
    _sheet_edit.text_changed.connect(func(t): _on_sprite_field_edited("sprite_sheet", "str", t))
    add_child(_sheet_edit)
    _label_fw = _make_label("Frame W")
    _fw_edit = LineEdit.new()
    _fw_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_width", "int", t))
    add_child(_fw_edit)
    _label_fh = _make_label("Frame H")
    _fh_edit = LineEdit.new()
    _fh_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_height", "int", t))
    add_child(_fh_edit)
    _label_findex = _make_label("Frame start")
    _findex_edit = LineEdit.new()
    _findex_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_index", "int", t))
    add_child(_findex_edit)
    _label_fcount = _make_label("Frame count")
    _fcount_edit = LineEdit.new()
    _fcount_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_count", "int", t))
    add_child(_fcount_edit)
    _label_ftick = _make_label("Frame tick")
    _ftick_edit = LineEdit.new()
    _ftick_edit.text_changed.connect(func(t): _on_sprite_field_edited("frame_tick", "int", t))
    add_child(_ftick_edit)

    _sprite_preview = Control.new()
    _sprite_preview.set_script(preload("res://Space/scripts/editor/ped/ped_sprite_preview.gd"))
    add_child(_sprite_preview)

    # Charge FX preview shown while holding a chargeable ranged attack
    _charge_fx_header = _make_header("CHARGE FX")
    _charge_fx_label_sheet = _make_label("Sheet")
    _charge_fx_sheet_edit = LineEdit.new()
    _charge_fx_sheet_edit.placeholder_text = "charge_glow.png (optional)"
    _charge_fx_sheet_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_sheet", "str", t))
    add_child(_charge_fx_sheet_edit)
    _charge_fx_label_fw = _make_label("Frame W")
    _charge_fx_fw_edit = LineEdit.new()
    _charge_fx_fw_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_frame_width", "int", t))
    add_child(_charge_fx_fw_edit)
    _charge_fx_label_fh = _make_label("Frame H")
    _charge_fx_fh_edit = LineEdit.new()
    _charge_fx_fh_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_frame_height", "int", t))
    add_child(_charge_fx_fh_edit)
    _charge_fx_label_findex = _make_label("Frame start")
    _charge_fx_findex_edit = LineEdit.new()
    _charge_fx_findex_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_frame_index", "int", t))
    add_child(_charge_fx_findex_edit)
    _charge_fx_label_fcount = _make_label("Frame count")
    _charge_fx_fcount_edit = LineEdit.new()
    _charge_fx_fcount_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_frame_count", "int", t))
    add_child(_charge_fx_fcount_edit)
    _charge_fx_label_ftick = _make_label("Frame tick")
    _charge_fx_ftick_edit = LineEdit.new()
    _charge_fx_ftick_edit.text_changed.connect(func(t): _on_charge_fx_field_edited("charge_fx_frame_tick", "int", t))
    add_child(_charge_fx_ftick_edit)
    _charge_fx_preview = Control.new()
    _charge_fx_preview.set_script(preload("res://Space/scripts/editor/ped/ped_sprite_preview.gd"))
    add_child(_charge_fx_preview)

    _layout_children()


func _make_header(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
    add_child(l)
    return l


func _make_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
    add_child(l)
    return l


func _make_button(text: String, cb: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.pressed.connect(cb)
    add_child(b)
    return b


func _make_line_edit(key: String, kind: String) -> LineEdit:
    var le := LineEdit.new()
    le.text_changed.connect(func(t): _on_field_edited(key, kind, t))
    add_child(le)
    return le


func _layout_children() -> void:
    if _list == null:
        return
    var vw := size.x
    var vh := size.y

    _list_header.position = Vector2(12, 12)
    _list_header.size = Vector2(LEFT_W - 24, 20)
    _list.position = Vector2(12, 40)
    _list.size = Vector2(LEFT_W - 24, vh - 40 - 48)
    _add_btn.position = Vector2(12, vh - 40)
    _add_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)
    _del_btn.position = Vector2(12 + (LEFT_W - 32) * 0.5 + 8, vh - 40)
    _del_btn.size = Vector2((LEFT_W - 32) * 0.5, 28)

    var right_x: float = LEFT_W + 8
    var right_w: float = vw - right_x - 12
    var visual_gap: float = 20.0
    var min_visual_w: float = 360.0
    var detail_w: float = clampf(right_w * 0.42, 300.0, right_w - min_visual_w - visual_gap)
    if right_w < detail_w + min_visual_w + visual_gap:
        detail_w = maxf(260.0, right_w - min_visual_w - visual_gap)
    var visual_x: float = right_x + detail_w + visual_gap
    var visual_w: float = maxf(220.0, right_w - detail_w - visual_gap)
    var label_w: float = 110.0
    var field_x: float = right_x + label_w
    var field_w: float = detail_w - label_w - 8
    var visual_label_w: float = 92.0
    var visual_field_x: float = visual_x + visual_label_w
    var visual_field_w: float = visual_w - visual_label_w - 8
    var row_y: float = 12.0
    var visual_y: float = 12.0
    var row_h: float = 28.0
    var field_h: float = 22.0
    var section_gap: float = 10.0
    var preview_h: float = clampf(vh * 0.18, 96.0, 150.0)

    _detail_header.position = Vector2(right_x, row_y)
    _detail_header.size = Vector2(detail_w, 20)
    _visual_header.position = Vector2(visual_x, visual_y)
    _visual_header.size = Vector2(visual_w, 20)
    row_y += 28.0
    visual_y += 28.0

    _place_row(_label_id, _id_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_name, _name_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_type, _type_option, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Timing / cost / pose
    row_y += section_gap
    _timing_header.position = Vector2(right_x, row_y)
    _timing_header.size = Vector2(detail_w, 20)
    row_y += 22.0
    _place_row(_label_cooldown, _cooldown_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_cost, _cost_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_pose, _pose_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_hold_behavior, _hold_behavior_option, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_charge_ticks, _charge_ticks_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_charged_attack, _charged_attack_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_combo_next, _combo_next_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Melee section
    row_y += section_gap
    _melee_header.position = Vector2(right_x, row_y)
    _melee_header.size = Vector2(detail_w, 20)
    row_y += 22.0
    _place_row(_label_hit_frames, _hit_frames_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_hitbox_x, _hitbox_x_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_hitbox_y, _hitbox_y_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_hitbox_w, _hitbox_w_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_hitbox_h, _hitbox_h_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_damage, _damage_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_knockback, _knockback_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Projectile section
    row_y += section_gap
    _projectile_header.position = Vector2(right_x, row_y)
    _projectile_header.size = Vector2(detail_w, 20)
    row_y += 22.0
    _place_row(_label_projectile, _projectile_option, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_muzzle_x, _muzzle_x_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_muzzle_y, _muzzle_y_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Linked projectile preview
    _linked_projectile_header.position = Vector2(visual_x, visual_y)
    _linked_projectile_header.size = Vector2(visual_w, 20)
    visual_y += 24.0
    _linked_projectile_meta.position = Vector2(visual_x, visual_y)
    _linked_projectile_meta.size = Vector2(visual_w, 18)
    visual_y += 22.0
    _edit_projectile_btn.position = Vector2(visual_x, visual_y)
    _edit_projectile_btn.size = Vector2(minf(150.0, visual_w), 24)
    visual_y += 30.0
    _linked_projectile_preview.position = Vector2(visual_x, visual_y)
    _linked_projectile_preview.size = Vector2(visual_w, preview_h)
    visual_y += preview_h + 8.0

    # Sprite FX + hitbox preview
    visual_y += section_gap
    _sprite_header.position = Vector2(visual_x, visual_y)
    _sprite_header.size = Vector2(visual_w, 20)
    visual_y += 22.0
    _place_row(_label_sheet, _sheet_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_label_fw, _fw_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_label_fh, _fh_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_label_findex, _findex_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_label_fcount, _fcount_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_label_ftick, _ftick_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h + 2.0
    _sprite_preview.position = Vector2(visual_x, visual_y)
    _sprite_preview.size = Vector2(visual_w, preview_h)
    visual_y += preview_h + 8.0

    # Charge FX preview
    visual_y += section_gap
    _charge_fx_header.position = Vector2(visual_x, visual_y)
    _charge_fx_header.size = Vector2(visual_w, 20)
    visual_y += 22.0
    _place_row(_charge_fx_label_sheet, _charge_fx_sheet_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_charge_fx_label_fw, _charge_fx_fw_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_charge_fx_label_fh, _charge_fx_fh_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_charge_fx_label_findex, _charge_fx_findex_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_charge_fx_label_fcount, _charge_fx_fcount_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h
    _place_row(_charge_fx_label_ftick, _charge_fx_ftick_edit, visual_x, visual_field_x, visual_y, visual_label_w, visual_field_w, row_h, field_h); visual_y += row_h + 2.0
    _charge_fx_preview.position = Vector2(visual_x, visual_y)
    _charge_fx_preview.size = Vector2(visual_w, maxf(70.0, vh - visual_y - 10.0))


func _place_row(lbl: Label, widget: Control,
                left_x: float, field_x: float, y: float,
                label_w: float, field_w: float,
                row_h: float, field_h: float) -> void:
    lbl.position = Vector2(left_x, y + 3)
    lbl.size = Vector2(label_w, row_h)
    widget.position = Vector2(field_x, y)
    widget.size = Vector2(field_w, field_h)


# ─── Data load / apply ───────────────────────────────────────────────────

func _load_data() -> void:
    var data := PedIO.load_attacks(pack_id)
    var raw = data.get("attacks", [])
    _attacks.clear()
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                _attacks.append(_normalize_entry(entry))
    _selected_idx = -1
    dirty = false


static func _normalize_entry(src: Dictionary) -> Dictionary:
    var type_str: String = str(src.get("type", "melee"))
    if not ATTACK_TYPES.has(type_str):
        type_str = "melee"
    var hold_behavior: String = _normalize_hold_behavior_value(src)
    var frames_raw = src.get("hit_frames", [])
    var frames: Array = []
    if typeof(frames_raw) == TYPE_ARRAY:
        for f in frames_raw:
            frames.append(int(f))
    return {
        "id":             str(src.get("id", "")),
        "name":           str(src.get("name", "")),
        "type":           type_str,
        "projectile_id":  str(src.get("projectile_id", "")),
        "cooldown_ticks": int(src.get("cooldown_ticks", 10)),
        "cost_mp":        int(src.get("cost_mp", 0)),
        "player_pose":    int(src.get("player_pose", 0)),
        "hold_behavior":  hold_behavior,
        "charge_ticks":   int(src.get("charge_ticks", 0)),
        "charged_attack_id": str(src.get("charged_attack_id", "")),
        "combo_next_id":  str(src.get("combo_next_id", "")),
        "hit_frames":     frames,
        "hitbox_x":       int(src.get("hitbox_x", 0)),
        "hitbox_y":       int(src.get("hitbox_y", 0)),
        "hitbox_w":       int(src.get("hitbox_w", 0)),
        "hitbox_h":       int(src.get("hitbox_h", 0)),
        "damage":         int(src.get("damage", 0)),
        "knockback":      int(src.get("knockback", 0)),
        "muzzle_x":       int(src.get("muzzle_x", 0)),
        "muzzle_y":       int(src.get("muzzle_y", 0)),
        "sprite_sheet":   str(src.get("sprite_sheet", "")),
        "frame_width":    int(src.get("frame_width", 32)),
        "frame_height":   int(src.get("frame_height", 32)),
        "frame_index":    int(src.get("frame_index", 0)),
        "frame_count":    int(src.get("frame_count", 1)),
        "frame_tick":     int(src.get("frame_tick", 6)),
        "charge_fx_sheet": str(src.get("charge_fx_sheet", "")),
        "charge_fx_frame_width": int(src.get("charge_fx_frame_width", 32)),
        "charge_fx_frame_height": int(src.get("charge_fx_frame_height", 32)),
        "charge_fx_frame_index": int(src.get("charge_fx_frame_index", 0)),
        "charge_fx_frame_count": int(src.get("charge_fx_frame_count", 1)),
        "charge_fx_frame_tick": int(src.get("charge_fx_frame_tick", 6)),
    }


func _load_projectile_pool() -> void:
    var data := PedIO.load_projectiles(pack_id)
    _projectile_pool.clear()
    _projectile_defs.clear()
    # Insert a blank entry at index 0 so attacks can clear a stale reference.
    _projectile_pool.append("")
    var raw = data.get("projectiles", [])
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                var projectile_def := entry as Dictionary
                var id_str := str(projectile_def.get("id", ""))
                if not id_str.is_empty():
                    _projectile_pool.append(id_str)
                    _projectile_defs[id_str] = projectile_def.duplicate(true)


func _load_player_preview_data() -> void:
    _player_frames_data.clear()
    _player_poses_data.clear()
    _player_sheet_defs.clear()
    if pack_id.is_empty():
        return
    var sprite_data := PspIO.load_or_init(pack_id)
    var frames_v: Variant = sprite_data.get("frames", {})
    if typeof(frames_v) == TYPE_DICTIONARY:
        _player_frames_data = (frames_v as Dictionary).duplicate(true)
    var poses_v: Variant = sprite_data.get("poses", {})
    if typeof(poses_v) == TYPE_DICTIONARY:
        _player_poses_data = (poses_v as Dictionary).duplicate(true)
    _player_sheet_defs = PspIO.normalize_sheet_defs(_player_frames_data.get("sheets", []))


func _populate_projectile_option() -> void:
    _projectile_option.clear()
    for p in _projectile_pool:
        var label_str: String = "(none)" if (p as String).is_empty() else str(p)
        _projectile_option.add_item(label_str)


func _populate_list() -> void:
    _list.clear()
    for a in _attacks:
        _list.add_item("%s — %s (%s)" % [a.get("id", "?"), a.get("name", "?"), a.get("type", "?")])


func _on_list_selected(idx: int) -> void:
    if idx < 0 or idx >= _attacks.size():
        _selected_idx = -1
        _apply_to_inputs()
        return
    _selected_idx = idx
    _apply_to_inputs()


func _on_add_pressed() -> void:
    if _undo != null:
        _undo.begin()
    var new_id := "attack_%d" % (_attacks.size() + 1)
    while _id_taken(new_id):
        new_id += "_"
    var new_entry := {
        "id": new_id,
        "name": "New Attack",
        "type": "melee",
        "projectile_id": "",
        "cooldown_ticks": 20,
        "cost_mp": 0,
        "player_pose": 0,
        "hold_behavior": "full_auto",
        "charge_ticks": 0,
        "charged_attack_id": "",
        "combo_next_id": "",
        "hit_frames": [],
        "hitbox_x": 0,
        "hitbox_y": 0,
        "hitbox_w": 16,
        "hitbox_h": 16,
        "damage": 10,
        "knockback": 0,
        "muzzle_x": 0,
        "muzzle_y": 0,
        "sprite_sheet": "",
        "frame_width": 32,
        "frame_height": 32,
        "frame_index": 0,
        "frame_count": 1,
        "frame_tick": 6,
        "charge_fx_sheet": "",
        "charge_fx_frame_width": 32,
        "charge_fx_frame_height": 32,
        "charge_fx_frame_index": 0,
        "charge_fx_frame_count": 1,
        "charge_fx_frame_tick": 6,
    }
    _attacks.append(new_entry)
    dirty = true
    _populate_list()
    var new_idx := _attacks.size() - 1
    _list.select(new_idx)
    _on_list_selected(new_idx)
    if _undo != null:
        _undo.commit("add attack")


func _id_taken(id: String) -> bool:
    for a in _attacks:
        if str(a.get("id", "")) == id:
            return true
    return false


func _id_taken_except(id: String, except_idx: int) -> bool:
    for i in range(_attacks.size()):
        if i == except_idx:
            continue
        var a: Dictionary = _attacks[i]
        if str(a.get("id", "")).strip_edges() == id:
            return true
    return false


func _on_del_pressed() -> void:
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    if _undo != null:
        _undo.begin()
    _attacks.remove_at(_selected_idx)
    dirty = true
    _populate_list()
    if _attacks.is_empty():
        _selected_idx = -1
        _apply_to_inputs()
        if _undo != null:
            _undo.commit("delete attack")
        return
    var next_idx: int = mini(_selected_idx, _attacks.size() - 1)
    _list.select(next_idx)
    _on_list_selected(next_idx)
    if _undo != null:
        _undo.commit("delete attack")


func _apply_to_inputs() -> void:
    if _id_edit == null:
        return
    _suppress_events = true
    var have: bool = _selected_idx >= 0 and _selected_idx < _attacks.size()
    var edits: Array = [
        _id_edit, _name_edit,
        _cooldown_edit, _cost_edit, _pose_edit, _charge_ticks_edit, _charged_attack_edit, _combo_next_edit,
        _hit_frames_edit,
        _hitbox_x_edit, _hitbox_y_edit, _hitbox_w_edit, _hitbox_h_edit,
        _damage_edit, _knockback_edit,
        _muzzle_x_edit, _muzzle_y_edit,
        _sheet_edit, _fw_edit, _fh_edit, _findex_edit, _fcount_edit, _ftick_edit,
        _charge_fx_sheet_edit, _charge_fx_fw_edit, _charge_fx_fh_edit,
        _charge_fx_findex_edit, _charge_fx_fcount_edit, _charge_fx_ftick_edit,
    ]
    for e in edits:
        (e as LineEdit).editable = have
    _type_option.disabled = not have
    _hold_behavior_option.disabled = not have
    _projectile_option.disabled = not have

    if not have:
        for e in edits:
            (e as LineEdit).text = ""
        _type_option.select(0)
        _select_hold_behavior("full_auto")
        _projectile_option.select(0)
        _linked_projectile_meta.text = "Pick a projectile attack to preview its sprite."
        _edit_projectile_btn.disabled = true
        _clear_preview(_linked_projectile_preview, "Projectiles")
        _clear_preview(_sprite_preview)
        _clear_preview(_charge_fx_preview)
        _suppress_events = false
        return

    var a: Dictionary = _attacks[_selected_idx]
    _id_edit.text = str(a.get("id", ""))
    _name_edit.text = str(a.get("name", ""))
    _cooldown_edit.text = str(int(a.get("cooldown_ticks", 0)))
    _cost_edit.text = str(int(a.get("cost_mp", 0)))
    _pose_edit.text = str(int(a.get("player_pose", 0)))
    _select_hold_behavior(str(a.get("hold_behavior", "full_auto")))
    _charge_ticks_edit.text = str(int(a.get("charge_ticks", 0)))
    _charged_attack_edit.text = str(a.get("charged_attack_id", ""))
    _combo_next_edit.text = str(a.get("combo_next_id", ""))
    _hit_frames_edit.text = _hit_frames_to_text(a.get("hit_frames", []))
    _hitbox_x_edit.text = str(int(a.get("hitbox_x", 0)))
    _hitbox_y_edit.text = str(int(a.get("hitbox_y", 0)))
    _hitbox_w_edit.text = str(int(a.get("hitbox_w", 0)))
    _hitbox_h_edit.text = str(int(a.get("hitbox_h", 0)))
    _damage_edit.text = str(int(a.get("damage", 0)))
    _knockback_edit.text = str(int(a.get("knockback", 0)))
    _muzzle_x_edit.text = str(int(a.get("muzzle_x", 0)))
    _muzzle_y_edit.text = str(int(a.get("muzzle_y", 0)))
    _sheet_edit.text = str(a.get("sprite_sheet", ""))
    _fw_edit.text = str(int(a.get("frame_width", 32)))
    _fh_edit.text = str(int(a.get("frame_height", 32)))
    _findex_edit.text = str(int(a.get("frame_index", 0)))
    _fcount_edit.text = str(int(a.get("frame_count", 1)))
    _ftick_edit.text = str(int(a.get("frame_tick", 6)))
    _charge_fx_sheet_edit.text = str(a.get("charge_fx_sheet", ""))
    _charge_fx_fw_edit.text = str(int(a.get("charge_fx_frame_width", 32)))
    _charge_fx_fh_edit.text = str(int(a.get("charge_fx_frame_height", 32)))
    _charge_fx_findex_edit.text = str(int(a.get("charge_fx_frame_index", 0)))
    _charge_fx_fcount_edit.text = str(int(a.get("charge_fx_frame_count", 1)))
    _charge_fx_ftick_edit.text = str(int(a.get("charge_fx_frame_tick", 6)))

    var type_idx: int = ATTACK_TYPES.find(str(a.get("type", "melee")))
    _type_option.select(maxi(0, type_idx))

    var proj_id: String = str(a.get("projectile_id", ""))
    var proj_idx: int = _projectile_pool.find(proj_id)
    _projectile_option.select(maxi(0, proj_idx))

    _refresh_preview()
    _refresh_linked_projectile_preview()
    _refresh_charge_fx_preview()
    _suppress_events = false


func _on_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    if field == "id":
        var old_id := str(a.get("id", "")).strip_edges()
        var new_id := text.strip_edges()
        if not old_id.is_empty() and not new_id.is_empty() and old_id != new_id and not _id_taken_except(new_id, _selected_idx):
            _rename_attack_references(old_id, new_id)
            a = _attacks[_selected_idx]
    if kind == "int":
        a[field] = PedUtil.to_int(text, int(a.get(field, 0)))
    else:
        a[field] = text
    _attacks[_selected_idx] = a
    dirty = true
    if field == "id" or field == "name":
        _refresh_list_row(_selected_idx)
    if field.begins_with("hitbox_"):
        _refresh_preview()


func _on_sprite_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    if kind == "int":
        a[field] = PedUtil.to_int(text, int(a.get(field, 0)))
    else:
        a[field] = text
    _attacks[_selected_idx] = a
    dirty = true
    _refresh_preview()


func _on_charge_fx_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    if kind == "int":
        a[field] = PedUtil.to_int(text, int(a.get(field, 0)))
    else:
        a[field] = text
    _attacks[_selected_idx] = a
    dirty = true
    _refresh_charge_fx_preview()


func _refresh_preview() -> void:
    if _sprite_preview == null:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    _sprite_preview.pack_id = pack_id
    _sprite_preview.content_folder = "Sprites"
    _sprite_preview.sheet_name = str(a.get("sprite_sheet", ""))
    _sprite_preview.frame_width = maxi(1, int(a.get("frame_width", 32)))
    _sprite_preview.frame_height = maxi(1, int(a.get("frame_height", 32)))
    _sprite_preview.frame_start = int(a.get("frame_index", 0))
    _sprite_preview.frame_count = maxi(1, int(a.get("frame_count", 1)))
    _sprite_preview.frame_tick = int(a.get("frame_tick", 6))
    _sprite_preview.hitbox_x = int(a.get("hitbox_x", 0))
    _sprite_preview.hitbox_y = int(a.get("hitbox_y", 0))
    _sprite_preview.hitbox_w = int(a.get("hitbox_w", 0))
    _sprite_preview.hitbox_h = int(a.get("hitbox_h", 0))
    _apply_player_pose_reference(_sprite_preview, a)
    _sprite_preview.reload_texture()


func _refresh_linked_projectile_preview() -> void:
    if _linked_projectile_preview == null or _linked_projectile_meta == null or _edit_projectile_btn == null:
        return
    var projectile_def := _linked_projectile_def()
    if projectile_def.is_empty():
        _linked_projectile_meta.text = "No linked projectile selected."
        _edit_projectile_btn.disabled = true
        _clear_preview(_linked_projectile_preview, "Projectiles")
        return
    _linked_projectile_meta.text = "%s - %s" % [
        str(projectile_def.get("id", "")),
        str(projectile_def.get("sprite_sheet", "")),
    ]
    _edit_projectile_btn.disabled = false
    _linked_projectile_preview.pack_id = pack_id
    _linked_projectile_preview.content_folder = "Projectiles"
    _linked_projectile_preview.sheet_name = str(projectile_def.get("sprite_sheet", ""))
    _linked_projectile_preview.frame_width = maxi(1, int(projectile_def.get("frame_width", 16)))
    _linked_projectile_preview.frame_height = maxi(1, int(projectile_def.get("frame_height", 16)))
    _linked_projectile_preview.frame_start = int(projectile_def.get("frame_index", 0))
    _linked_projectile_preview.frame_count = maxi(1, int(projectile_def.get("frame_count", 1)))
    _linked_projectile_preview.frame_tick = maxi(1, int(projectile_def.get("frame_tick", 10)))
    _linked_projectile_preview.hitbox_x = 0
    _linked_projectile_preview.hitbox_y = 0
    _linked_projectile_preview.hitbox_w = 0
    _linked_projectile_preview.hitbox_h = 0
    _linked_projectile_preview.reload_texture()


func _refresh_charge_fx_preview() -> void:
    if _charge_fx_preview == null:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        _clear_preview(_charge_fx_preview)
        return
    var a: Dictionary = _attacks[_selected_idx]
    _charge_fx_preview.pack_id = pack_id
    _charge_fx_preview.content_folder = "Sprites"
    _charge_fx_preview.sheet_name = str(a.get("charge_fx_sheet", ""))
    _charge_fx_preview.frame_width = maxi(1, int(a.get("charge_fx_frame_width", 32)))
    _charge_fx_preview.frame_height = maxi(1, int(a.get("charge_fx_frame_height", 32)))
    _charge_fx_preview.frame_start = int(a.get("charge_fx_frame_index", 0))
    _charge_fx_preview.frame_count = maxi(1, int(a.get("charge_fx_frame_count", 1)))
    _charge_fx_preview.frame_tick = maxi(1, int(a.get("charge_fx_frame_tick", 6)))
    _charge_fx_preview.hitbox_x = 0
    _charge_fx_preview.hitbox_y = 0
    _charge_fx_preview.hitbox_w = 0
    _charge_fx_preview.hitbox_h = 0
    _charge_fx_preview.reload_texture()


func _clear_preview(preview: Control, folder: String = "Sprites") -> void:
    if preview == null:
        return
    preview.pack_id = pack_id
    preview.content_folder = folder
    preview.sheet_name = ""
    preview.frame_width = 16
    preview.frame_height = 16
    preview.frame_start = 0
    preview.frame_count = 1
    preview.frame_tick = 6
    preview.hitbox_x = 0
    preview.hitbox_y = 0
    preview.hitbox_w = 0
    preview.hitbox_h = 0
    preview.reference_sheet_name = ""
    preview.reference_content_folder = "Sprites"
    preview.reference_frame_width = 16
    preview.reference_frame_height = 16
    preview.reference_frame_index = 0
    preview.reference_alpha = 0.4
    preview.reference_label = ""
    preview.reload_texture()


func _linked_projectile_def() -> Dictionary:
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return {}
    var attack: Dictionary = _attacks[_selected_idx]
    var projectile_id := str(attack.get("projectile_id", "")).strip_edges()
    if projectile_id.is_empty():
        return {}
    return (_projectile_defs.get(projectile_id, {}) as Dictionary).duplicate(true)


func _on_type_selected() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var idx := _type_option.selected
    if idx < 0 or idx >= ATTACK_TYPES.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    a["type"] = str(ATTACK_TYPES[idx])
    _attacks[_selected_idx] = a
    dirty = true
    _refresh_list_row(_selected_idx)


func _on_projectile_selected() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var idx := _projectile_option.selected
    if idx < 0 or idx >= _projectile_pool.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    a["projectile_id"] = str(_projectile_pool[idx])
    _attacks[_selected_idx] = a
    dirty = true
    _refresh_linked_projectile_preview()


func _on_hold_behavior_selected() -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var idx := _hold_behavior_option.selected
    if idx < 0 or idx >= HOLD_BEHAVIOR_OPTIONS.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    a["hold_behavior"] = str(HOLD_BEHAVIOR_OPTIONS[idx].get("id", "full_auto"))
    _attacks[_selected_idx] = a
    dirty = true


func _on_edit_projectile_pressed() -> void:
    var projectile_def := _linked_projectile_def()
    var projectile_id := str(projectile_def.get("id", "")).strip_edges()
    if projectile_id.is_empty():
        return
    edit_projectile_requested.emit(projectile_id)


func refresh_external_refs() -> void:
    _load_projectile_pool()
    _load_player_preview_data()
    _populate_projectile_option()
    _refresh_linked_projectile_preview()
    if _selected_idx >= 0 and _selected_idx < _attacks.size():
        _apply_to_inputs()


func _apply_player_pose_reference(preview: Control, attack: Dictionary) -> void:
    if preview == null:
        return
    preview.reference_sheet_name = ""
    preview.reference_content_folder = "Sprites"
    preview.reference_frame_width = 16
    preview.reference_frame_height = 16
    preview.reference_frame_index = 0
    preview.reference_alpha = 0.42
    preview.reference_label = ""
    if _player_frames_data.is_empty():
        return
    var pose_id := int(attack.get("player_pose", -1))
    if pose_id < 0:
        return
    var seq := _player_pose_sequence(pose_id)
    if seq.is_empty():
        return
    var ref_idx := 0
    var hit_frames_v: Variant = attack.get("hit_frames", [])
    if typeof(hit_frames_v) == TYPE_ARRAY and not (hit_frames_v as Array).is_empty():
        ref_idx = maxi(0, int((hit_frames_v as Array)[0]))
    ref_idx = clampi(ref_idx, 0, seq.size() - 1)
    var frame_entry: Dictionary = seq[ref_idx]
    var layers := _player_frame_layers(frame_entry)
    if layers.is_empty():
        return
    var primary: Dictionary = layers[0]
    var sheet_id := str(primary.get("sheet", PspIO.BASE_SHEET_ID)).strip_edges()
    var file_name := _player_sheet_file(sheet_id)
    if file_name.is_empty():
        return
    preview.reference_sheet_name = file_name
    preview.reference_frame_width = maxi(1, int(_player_frames_data.get("frame_width", 16)))
    preview.reference_frame_height = maxi(1, int(_player_frames_data.get("frame_height", 16)))
    preview.reference_frame_index = maxi(0, int(primary.get("index", 0)))
    var pose_name := _player_pose_name(pose_id)
    preview.reference_label = "Player %s f%d" % [
        str(pose_id) if pose_name.is_empty() else pose_name,
        ref_idx,
    ]


func _player_pose_sequence(pose_id: int) -> Array:
    var out: Array = []
    var frames_v: Variant = _player_frames_data.get("frames", [])
    if typeof(frames_v) != TYPE_ARRAY:
        return out
    for entry_v in frames_v as Array:
        if typeof(entry_v) != TYPE_DICTIONARY:
            continue
        var entry: Dictionary = entry_v
        if int(entry.get("pose", -1)) == pose_id:
            out.append(entry.duplicate(true))
    return out


func _player_frame_layers(frame_entry: Dictionary) -> Array:
    var layers_v: Variant = frame_entry.get("layers", [])
    if typeof(layers_v) == TYPE_ARRAY and not (layers_v as Array).is_empty():
        return (layers_v as Array)
    if frame_entry.has("index"):
        return [{
            "sheet": PspIO.BASE_SHEET_ID,
            "index": int(frame_entry.get("index", 0)),
        }]
    return []


func _player_sheet_file(sheet_id: String) -> String:
    var normalized_id := sheet_id if not sheet_id.is_empty() else PspIO.BASE_SHEET_ID
    for sheet_def_v in _player_sheet_defs:
        if typeof(sheet_def_v) != TYPE_DICTIONARY:
            continue
        var sheet_def: Dictionary = sheet_def_v
        if str(sheet_def.get("id", "")).strip_edges() == normalized_id:
            return str(sheet_def.get("file", "")).strip_edges()
    if normalized_id == PspIO.BASE_SHEET_ID:
        return PspIO.BASE_SHEET_FILE
    return ""


func _player_pose_name(pose_id: int) -> String:
    var poses_v: Variant = _player_poses_data.get("poses", {})
    if typeof(poses_v) != TYPE_DICTIONARY:
        return ""
    var pose_entry_v: Variant = (poses_v as Dictionary).get(str(pose_id), {})
    if typeof(pose_entry_v) != TYPE_DICTIONARY:
        return ""
    return str((pose_entry_v as Dictionary).get("name", "")).strip_edges()


func _on_hit_frames_changed(text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[_selected_idx]
    a["hit_frames"] = _text_to_hit_frames(text)
    _attacks[_selected_idx] = a
    dirty = true


func _refresh_list_row(idx: int) -> void:
    if idx < 0 or idx >= _attacks.size():
        return
    var a: Dictionary = _attacks[idx]
    _list.set_item_text(idx, "%s — %s (%s)" % [a.get("id", "?"), a.get("name", "?"), a.get("type", "?")])


# ─── hit_frames text <-> array ──────────────────────────────────────────

func _rename_attack_references(old_id: String, new_id: String) -> void:
    for attack_v in _attacks:
        if typeof(attack_v) != TYPE_DICTIONARY:
            continue
        var attack: Dictionary = attack_v
        if str(attack.get("charged_attack_id", "")).strip_edges() == old_id:
            attack["charged_attack_id"] = new_id
        if str(attack.get("combo_next_id", "")).strip_edges() == old_id:
            attack["combo_next_id"] = new_id
    var refactor := ContentReferenceRefactor.rename_references(pack_id, "attack", old_id, new_id)
    if not bool(refactor.get("ok", false)):
        push_warning("[AttacksTab] attack renamed, but reference update failed: %s" % str(refactor.get("errors", [])))


static func _hit_frames_to_text(frames: Array) -> String:
    var parts: Array = []
    for f in frames:
        parts.append(str(int(f)))
    return ", ".join(parts)


static func _text_to_hit_frames(text: String) -> Array:
    var out: Array = []
    var raw := text.strip_edges()
    if raw.is_empty():
        return out
    var parts := raw.split(",", false)
    for p in parts:
        var s := (p as String).strip_edges()
        if s.is_empty():
            continue
        out.append(s.to_int())
    return out


static func _normalize_hold_behavior_value(src: Dictionary) -> String:
    var hold_behavior: String = str(src.get("hold_behavior", "")).strip_edges()
    for entry in HOLD_BEHAVIOR_OPTIONS:
        if hold_behavior == str(entry.get("id", "")):
            return hold_behavior
    var charged_attack_id := str(src.get("charged_attack_id", "")).strip_edges()
    var charge_ticks := int(src.get("charge_ticks", 0))
    if not charged_attack_id.is_empty() and charge_ticks > 0:
        return "charge_release"
    return "full_auto"


func _select_hold_behavior(hold_behavior: String) -> void:
    var resolved: String = hold_behavior
    var found_idx: int = -1
    for i in range(HOLD_BEHAVIOR_OPTIONS.size()):
        if str(HOLD_BEHAVIOR_OPTIONS[i].get("id", "")) == resolved:
            found_idx = i
            break
    if found_idx < 0:
        found_idx = 0
    if _hold_behavior_option != null:
        _hold_behavior_option.select(found_idx)

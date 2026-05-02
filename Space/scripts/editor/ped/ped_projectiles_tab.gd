extends Control

const PedIO = preload("res://Space/scripts/editor/ped/ped_io.gd")
const PedUtil = preload("res://Space/scripts/editor/ped/ped_util.gd")
const ContentReferenceRefactor = preload("res://Space/scripts/editor/content_reference_refactor.gd")

# Player editor — Projectiles tab. List + detail editor for projectiles.json.
# Each entry owns sprite (sheet path + frame layout + animation tick), physics
# (speed/gravity/lifetime), combat (damage/pierces/hitbox), and optional homing
# behavior. Projectiles are referenced by id from player attacks.

var pack_id: String = ""
var dirty: bool = false

var _projectiles: Array = []
var _selected_idx: int = -1

# Left column
var _list: ItemList = null
var _add_btn: Button = null
var _del_btn: Button = null
var _list_header: Label = null

# Detail headers
var _detail_header: Label = null
var _sprite_header: Label = null
var _physics_header: Label = null
var _combat_header: Label = null
var _explosion_header: Label = null
var _homing_header: Label = null
var _visual_header: Label = null

# Identity
var _id_edit: LineEdit = null
var _name_edit: LineEdit = null
var _label_id: Label = null
var _label_name: Label = null

# Sprite
var _sprite_preview: Control = null
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

# Physics
var _speed_edit: LineEdit = null
var _gravity_edit: LineEdit = null
var _lifetime_edit: LineEdit = null
var _label_speed: Label = null
var _label_gravity: Label = null
var _label_lifetime: Label = null

# Combat
var _damage_edit: LineEdit = null
var _hitbox_w_edit: LineEdit = null
var _hitbox_h_edit: LineEdit = null
var _pierces_check: CheckBox = null
var _label_damage: Label = null
var _label_hitbox_w: Label = null
var _label_hitbox_h: Label = null

# Explosion
var _explosive_check: CheckBox = null
var _explode_on_hit_check: CheckBox = null
var _explode_on_timeout_check: CheckBox = null
var _break_blocks_check: CheckBox = null
var _bomb_jump_check: CheckBox = null
var _blast_radius_edit: LineEdit = null
var _explosion_damage_edit: LineEdit = null
var _bomb_jump_speed_edit: LineEdit = null
var _label_blast_radius: Label = null
var _label_explosion_damage: Label = null
var _label_bomb_jump_speed: Label = null

# Homing
var _homing_check: CheckBox = null
var _homing_strength_edit: LineEdit = null
var _label_homing_strength: Label = null

# Visual
var _rotate_check: CheckBox = null
var _trail_color_edit: LineEdit = null
var _label_trail_color: Label = null

var _suppress_events: bool = false
var _undo: RefCounted = null

const LEFT_W: float = 220.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "projectiles": _projectiles.duplicate(true),
        "selected_idx": _selected_idx,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var p_v: Variant = snap.get("projectiles", null)
    if typeof(p_v) == TYPE_ARRAY:
        _projectiles = p_v
    _selected_idx = int(snap.get("selected_idx", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_list()
    if _selected_idx >= 0 and _selected_idx < _projectiles.size() and _list != null:
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
    if _speed_edit != null and Rect2(_speed_edit.position, _speed_edit.size).has_point(mp):
        EditorTooltip.show_text("Travel speed in pixels per second. Higher values make the projectile fly faster across the room.")
    elif _gravity_edit != null and Rect2(_gravity_edit.position, _gravity_edit.size).has_point(mp):
        EditorTooltip.show_text("Downward acceleration applied each tick. 0 = straight-line travel, positive values create an arc like a grenade.")
    elif _lifetime_edit != null and Rect2(_lifetime_edit.position, _lifetime_edit.size).has_point(mp):
        EditorTooltip.show_text("How many physics ticks (1/60 s) the projectile lives before despawning. 120 = 2 seconds.")
    elif _damage_edit != null and Rect2(_damage_edit.position, _damage_edit.size).has_point(mp):
        EditorTooltip.show_text("Base damage dealt on hit. Stacks with player stats and equipment modifiers.")
    elif _pierces_check != null and Rect2(_pierces_check.position, _pierces_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the projectile passes through enemies instead of being consumed on first hit.")
    elif _homing_check != null and Rect2(_homing_check.position, _homing_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the projectile steers toward the nearest enemy each tick.")
    elif _homing_strength_edit != null and Rect2(_homing_strength_edit.position, _homing_strength_edit.size).has_point(mp):
        EditorTooltip.show_text("How aggressively the projectile turns toward its target. Higher = tighter tracking.")
    elif _hitbox_w_edit != null and Rect2(_hitbox_w_edit.position, _hitbox_w_edit.size).has_point(mp):
        EditorTooltip.show_text("Projectile collision box width in pixels.")
    elif _hitbox_h_edit != null and Rect2(_hitbox_h_edit.position, _hitbox_h_edit.size).has_point(mp):
        EditorTooltip.show_text("Projectile collision box height in pixels.")
    elif _rotate_check != null and Rect2(_rotate_check.position, _rotate_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the sprite rotates to face the direction of travel. Good for arrows and missiles.")
    elif _trail_color_edit != null and Rect2(_trail_color_edit.position, _trail_color_edit.size).has_point(mp):
        EditorTooltip.show_text("HTML hex color for the particle trail behind the projectile. e.g. #88ccff for a light blue trail.")
    elif _explosive_check != null and Rect2(_explosive_check.position, _explosive_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, this projectile can detonate into an area-of-effect blast instead of only dealing direct contact damage.")
    elif _blast_radius_edit != null and Rect2(_blast_radius_edit.position, _blast_radius_edit.size).has_point(mp):
        EditorTooltip.show_text("Explosion radius in pixels. Enemies inside this distance from detonation take explosion damage.")
    elif _explosion_damage_edit != null and Rect2(_explosion_damage_edit.position, _explosion_damage_edit.size).has_point(mp):
        EditorTooltip.show_text("Damage dealt by the explosion. Leave at 0 to reuse the projectile's direct damage value.")
    elif _explode_on_hit_check != null and Rect2(_explode_on_hit_check.position, _explode_on_hit_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the projectile detonates immediately on enemy or world impact.")
    elif _explode_on_timeout_check != null and Rect2(_explode_on_timeout_check.position, _explode_on_timeout_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the projectile detonates when its lifetime expires instead of quietly despawning.")
    elif _break_blocks_check != null and Rect2(_break_blocks_check.position, _break_blocks_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, collision with solid/destructible room blocks asks the room manager to break blocks at the impact point.")
    elif _bomb_jump_check != null and Rect2(_bomb_jump_check.position, _bomb_jump_check.size).has_point(mp):
        EditorTooltip.show_text("When ON, the explosion can boost the player upward if they are inside the blast radius, like a grenade bomb jump.")
    elif _bomb_jump_speed_edit != null and Rect2(_bomb_jump_speed_edit.position, _bomb_jump_speed_edit.size).has_point(mp):
        EditorTooltip.show_text("Upward speed applied to the player when a bomb-jump-capable explosion catches them in its radius.")
    elif _findex_edit != null and Rect2(_findex_edit.position, _findex_edit.size).has_point(mp):
        EditorTooltip.show_text("Starting frame index in the sprite sheet. The animation plays frame_count frames starting from this index.")
    elif _fcount_edit != null and Rect2(_fcount_edit.position, _fcount_edit.size).has_point(mp):
        EditorTooltip.show_text("Number of animation frames. 1 = static sprite, more = animated loop.")
    elif _ftick_edit != null and Rect2(_ftick_edit.position, _ftick_edit.size).has_point(mp):
        EditorTooltip.show_text("Ticks per animation frame (1/60 s). Lower = faster animation cycle.")


func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_data()
    _populate_list()
    if _projectiles.size() > 0:
        _list.select(0)
        _on_list_selected(0)
    else:
        _apply_to_inputs()
    dirty = false
    if _undo != null:
        _undo.clear()


func save() -> bool:
    var out := {"projectiles": _projectiles.duplicate(true)}
    if not PedIO.save_projectiles(pack_id, out):
        return false
    dirty = false
    return true


func is_dirty() -> bool:
    return dirty


func focus_projectile(projectile_id: String) -> void:
    var clean_id := projectile_id.strip_edges()
    if clean_id.is_empty():
        return
    for i in range(_projectiles.size()):
        var projectile_def: Dictionary = _projectiles[i]
        if str(projectile_def.get("id", "")).strip_edges() != clean_id:
            continue
        _selected_idx = i
        if _list != null:
            _list.select(i)
        _apply_to_inputs()
        return


# ─── Layout ──────────────────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.09, 0.1, 0.13, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _list_header = _make_header("PROJECTILES")
    _list = ItemList.new()
    _list.item_selected.connect(_on_list_selected)
    add_child(_list)
    _add_btn = _make_button("+ PROJ", _on_add_pressed)
    _del_btn = _make_button("- PROJ", _on_del_pressed)

    _detail_header = _make_header("DETAIL")

    # Identity
    _label_id = _make_label("ID")
    _id_edit = _make_line_edit("id", "str")
    _label_name = _make_label("Name")
    _name_edit = _make_line_edit("name", "str")

    # Sprite
    _sprite_header = _make_header("SPRITE")
    _label_sheet = _make_label("Sheet")
    _sheet_edit = _make_line_edit("sprite_sheet", "str")
    _sheet_edit.placeholder_text = "projectiles_sheet.png"
    _label_fw = _make_label("Frame W")
    _fw_edit = _make_line_edit("frame_width", "int")
    _label_fh = _make_label("Frame H")
    _fh_edit = _make_line_edit("frame_height", "int")
    _label_findex = _make_label("Frame start")
    _findex_edit = _make_line_edit("frame_index", "int")
    _label_fcount = _make_label("Frame count")
    _fcount_edit = _make_line_edit("frame_count", "int")
    _label_ftick = _make_label("Frame tick")
    _ftick_edit = _make_line_edit("frame_tick", "int")

    _sprite_preview = Control.new()
    _sprite_preview.set_script(preload("res://Space/scripts/editor/ped/ped_sprite_preview.gd"))
    add_child(_sprite_preview)

    # Physics
    _physics_header = _make_header("PHYSICS")
    _label_speed = _make_label("Speed")
    _speed_edit = _make_line_edit("speed", "int")
    _label_gravity = _make_label("Gravity")
    _gravity_edit = _make_line_edit("gravity", "int")
    _label_lifetime = _make_label("Lifetime")
    _lifetime_edit = _make_line_edit("lifetime_ticks", "int")

    # Combat
    _combat_header = _make_header("COMBAT")
    _label_damage = _make_label("Damage")
    _damage_edit = _make_line_edit("damage", "int")
    _label_hitbox_w = _make_label("Hitbox W")
    _hitbox_w_edit = _make_line_edit("hitbox_w", "int")
    _label_hitbox_h = _make_label("Hitbox H")
    _hitbox_h_edit = _make_line_edit("hitbox_h", "int")
    _pierces_check = _make_check("Pierces (passes through enemies)", "pierces")

    # Explosion
    _explosion_header = _make_header("EXPLOSION")
    _explosive_check = _make_check("Explosive projectile", "explosive")
    _label_blast_radius = _make_label("Blast radius")
    _blast_radius_edit = _make_line_edit("blast_radius", "int")
    _label_explosion_damage = _make_label("Blast damage")
    _explosion_damage_edit = _make_line_edit("explosion_damage", "int")
    _explode_on_hit_check = _make_check("Explode on hit", "explode_on_hit")
    _explode_on_timeout_check = _make_check("Explode on timeout", "explode_on_timeout")
    _break_blocks_check = _make_check("Break solid/destructible blocks", "break_blocks")
    _bomb_jump_check = _make_check("Allow bomb jump", "bomb_jump")
    _label_bomb_jump_speed = _make_label("Bomb jump speed")
    _bomb_jump_speed_edit = _make_line_edit("bomb_jump_speed", "int")

    # Homing
    _homing_header = _make_header("HOMING")
    _homing_check = _make_check("Enabled", "homing")
    _label_homing_strength = _make_label("Strength")
    _homing_strength_edit = _make_line_edit("homing_strength", "int")

    # Visual
    _visual_header = _make_header("VISUAL")
    _rotate_check = _make_check("Rotate to velocity", "rotate_to_velocity")
    _label_trail_color = _make_label("Trail color")
    _trail_color_edit = _make_line_edit("trail_color", "str")
    _trail_color_edit.placeholder_text = "#88ccff"

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


func _make_check(text: String, key: String) -> CheckBox:
    var c := CheckBox.new()
    c.text = text
    c.toggled.connect(func(pressed): _on_bool_toggled(key, pressed))
    add_child(c)
    return c


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
    var label_w: float = 110.0
    var field_x: float = right_x + label_w
    var field_w: float = right_w - label_w - 8
    var row_y: float = 12.0
    var row_h: float = 28.0
    var field_h: float = 22.0
    var section_gap: float = 10.0

    _detail_header.position = Vector2(right_x, row_y)
    _detail_header.size = Vector2(right_w, 20)
    row_y += 28.0

    # Identity
    _place_row(_label_id, _id_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_name, _name_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Sprite
    row_y += section_gap
    _sprite_header.position = Vector2(right_x, row_y)
    _sprite_header.size = Vector2(right_w, 20)
    row_y += 22.0
    _place_row(_label_sheet, _sheet_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_fw, _fw_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_fh, _fh_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_findex, _findex_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_fcount, _fcount_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h
    _place_row(_label_ftick, _ftick_edit, right_x, field_x, row_y, label_w, field_w, row_h, field_h); row_y += row_h

    # Sprite preview
    if _sprite_preview != null:
        var preview_h := 90.0
        _sprite_preview.position = Vector2(right_x, row_y + 4)
        _sprite_preview.size = Vector2(right_w, preview_h)
        row_y += preview_h + 8.0

    var lower_y := row_y + section_gap
    var col_gap: float = 20.0
    var col_w: float = (right_w - col_gap) * 0.5
    var col_label_w: float = 98.0
    var left_col_x: float = right_x
    var right_col_x: float = right_x + col_w + col_gap
    var left_field_x: float = left_col_x + col_label_w
    var right_field_x: float = right_col_x + col_label_w
    var left_field_w: float = col_w - col_label_w - 8
    var right_field_w: float = col_w - col_label_w - 8

    var left_y := lower_y
    var right_y := lower_y

    # Physics
    _physics_header.position = Vector2(left_col_x, left_y)
    _physics_header.size = Vector2(col_w, 20)
    left_y += 22.0
    _place_row(_label_speed, _speed_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h
    _place_row(_label_gravity, _gravity_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h
    _place_row(_label_lifetime, _lifetime_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h

    # Combat
    left_y += section_gap
    _combat_header.position = Vector2(left_col_x, left_y)
    _combat_header.size = Vector2(col_w, 20)
    left_y += 22.0
    _place_row(_label_damage, _damage_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h
    _place_row(_label_hitbox_w, _hitbox_w_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h
    _place_row(_label_hitbox_h, _hitbox_h_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h
    _pierces_check.position = Vector2(left_col_x, left_y)
    _pierces_check.size = Vector2(col_w, row_h)
    left_y += row_h

    # Homing
    left_y += section_gap
    _homing_header.position = Vector2(left_col_x, left_y)
    _homing_header.size = Vector2(col_w, 20)
    left_y += 22.0
    _homing_check.position = Vector2(left_col_x, left_y)
    _homing_check.size = Vector2(col_w, row_h)
    left_y += row_h
    _place_row(_label_homing_strength, _homing_strength_edit, left_col_x, left_field_x, left_y, col_label_w, left_field_w, row_h, field_h); left_y += row_h

    # Explosion
    _explosion_header.position = Vector2(right_col_x, right_y)
    _explosion_header.size = Vector2(col_w, 20)
    right_y += 22.0
    _explosive_check.position = Vector2(right_col_x, right_y)
    _explosive_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _place_row(_label_blast_radius, _blast_radius_edit, right_col_x, right_field_x, right_y, col_label_w, right_field_w, row_h, field_h); right_y += row_h
    _place_row(_label_explosion_damage, _explosion_damage_edit, right_col_x, right_field_x, right_y, col_label_w, right_field_w, row_h, field_h); right_y += row_h
    _explode_on_hit_check.position = Vector2(right_col_x, right_y)
    _explode_on_hit_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _explode_on_timeout_check.position = Vector2(right_col_x, right_y)
    _explode_on_timeout_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _break_blocks_check.position = Vector2(right_col_x, right_y)
    _break_blocks_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _bomb_jump_check.position = Vector2(right_col_x, right_y)
    _bomb_jump_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _place_row(_label_bomb_jump_speed, _bomb_jump_speed_edit, right_col_x, right_field_x, right_y, col_label_w, right_field_w, row_h, field_h); right_y += row_h

    # Visual
    right_y += section_gap
    _visual_header.position = Vector2(right_col_x, right_y)
    _visual_header.size = Vector2(col_w, 20)
    right_y += 22.0
    _rotate_check.position = Vector2(right_col_x, right_y)
    _rotate_check.size = Vector2(col_w, row_h)
    right_y += row_h
    _place_row(_label_trail_color, _trail_color_edit, right_col_x, right_field_x, right_y, col_label_w, right_field_w, row_h, field_h)


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
    var data := PedIO.load_projectiles(pack_id)
    var raw = data.get("projectiles", [])
    _projectiles.clear()
    if typeof(raw) == TYPE_ARRAY:
        for entry in raw:
            if typeof(entry) == TYPE_DICTIONARY:
                _projectiles.append(_normalize_entry(entry))
    _selected_idx = -1
    dirty = false


static func _normalize_entry(src: Dictionary) -> Dictionary:
    return {
        "id":                 str(src.get("id", "")),
        "name":               str(src.get("name", "")),
        "sprite_sheet":       str(src.get("sprite_sheet", "")),
        "frame_width":        int(src.get("frame_width", 16)),
        "frame_height":       int(src.get("frame_height", 16)),
        "frame_index":        int(src.get("frame_index", 0)),
        "frame_count":        int(src.get("frame_count", 1)),
        "frame_tick":         int(src.get("frame_tick", 10)),
        "speed":              int(src.get("speed", 200)),
        "gravity":            int(src.get("gravity", 0)),
        "lifetime_ticks":     int(src.get("lifetime_ticks", 120)),
        "damage":             int(src.get("damage", 10)),
        "pierces":            bool(src.get("pierces", false)),
        "explosive":          bool(src.get("explosive", false)),
        "blast_radius":       int(src.get("blast_radius", 44)),
        "explosion_damage":   int(src.get("explosion_damage", 0)),
        "explode_on_hit":     bool(src.get("explode_on_hit", true)),
        "explode_on_timeout": bool(src.get("explode_on_timeout", false)),
        "break_blocks":       bool(src.get("break_blocks", true)),
        "bomb_jump":          bool(src.get("bomb_jump", false)),
        "bomb_jump_speed":    int(src.get("bomb_jump_speed", 280)),
        "homing":             bool(src.get("homing", false)),
        "homing_strength":    int(src.get("homing_strength", 0)),
        "hitbox_w":           int(src.get("hitbox_w", 8)),
        "hitbox_h":           int(src.get("hitbox_h", 8)),
        "rotate_to_velocity": bool(src.get("rotate_to_velocity", false)),
        "trail_color":        str(src.get("trail_color", "#ffffff")),
    }


func _populate_list() -> void:
    _list.clear()
    for p in _projectiles:
        _list.add_item("%s — %s" % [p.get("id", "?"), p.get("name", "?")])


func _on_list_selected(idx: int) -> void:
    if idx < 0 or idx >= _projectiles.size():
        _selected_idx = -1
        _apply_to_inputs()
        return
    _selected_idx = idx
    _apply_to_inputs()


func _on_add_pressed() -> void:
    if _undo != null:
        _undo.begin()
    var new_id := "proj_%d" % (_projectiles.size() + 1)
    while _id_taken(new_id):
        new_id += "_"
    var new_entry := {
        "id": new_id,
        "name": "New Projectile",
        "sprite_sheet": "projectiles_sheet.png",
        "frame_width": 16,
        "frame_height": 16,
        "frame_index": 0,
        "frame_count": 1,
        "frame_tick": 10,
        "speed": 200,
        "gravity": 0,
        "lifetime_ticks": 120,
        "damage": 10,
        "pierces": false,
        "explosive": false,
        "blast_radius": 44,
        "explosion_damage": 0,
        "explode_on_hit": true,
        "explode_on_timeout": false,
        "break_blocks": true,
        "bomb_jump": false,
        "bomb_jump_speed": 280,
        "homing": false,
        "homing_strength": 0,
        "hitbox_w": 8,
        "hitbox_h": 8,
        "rotate_to_velocity": false,
        "trail_color": "#ffffff",
    }
    _projectiles.append(new_entry)
    dirty = true
    _populate_list()
    var new_idx := _projectiles.size() - 1
    _list.select(new_idx)
    _on_list_selected(new_idx)
    if _undo != null:
        _undo.commit("add projectile")


func _id_taken(id: String) -> bool:
    for p in _projectiles:
        if str(p.get("id", "")) == id:
            return true
    return false


func _id_taken_except(id: String, except_idx: int) -> bool:
    for i in range(_projectiles.size()):
        if i == except_idx:
            continue
        var p: Dictionary = _projectiles[i]
        if str(p.get("id", "")).strip_edges() == id:
            return true
    return false


func _on_del_pressed() -> void:
    if _selected_idx < 0 or _selected_idx >= _projectiles.size():
        return
    if _undo != null:
        _undo.begin()
    _projectiles.remove_at(_selected_idx)
    dirty = true
    _populate_list()
    if _projectiles.is_empty():
        _selected_idx = -1
        _apply_to_inputs()
        if _undo != null:
            _undo.commit("delete projectile")
        return
    var next_idx: int = mini(_selected_idx, _projectiles.size() - 1)
    _list.select(next_idx)
    _on_list_selected(next_idx)
    if _undo != null:
        _undo.commit("delete projectile")


func _apply_to_inputs() -> void:
    if _id_edit == null:
        return
    _suppress_events = true
    var have: bool = _selected_idx >= 0 and _selected_idx < _projectiles.size()
    var edits: Array = [
        _id_edit, _name_edit, _sheet_edit,
        _fw_edit, _fh_edit, _findex_edit, _fcount_edit, _ftick_edit,
        _speed_edit, _gravity_edit, _lifetime_edit,
        _damage_edit, _hitbox_w_edit, _hitbox_h_edit,
        _blast_radius_edit, _explosion_damage_edit, _bomb_jump_speed_edit,
        _homing_strength_edit, _trail_color_edit,
    ]
    for e in edits:
        (e as LineEdit).editable = have
    _pierces_check.disabled = not have
    _explosive_check.disabled = not have
    _explode_on_hit_check.disabled = not have
    _explode_on_timeout_check.disabled = not have
    _break_blocks_check.disabled = not have
    _bomb_jump_check.disabled = not have
    _homing_check.disabled = not have
    _rotate_check.disabled = not have

    if not have:
        for e in edits:
            (e as LineEdit).text = ""
        _pierces_check.button_pressed = false
        _explosive_check.button_pressed = false
        _explode_on_hit_check.button_pressed = false
        _explode_on_timeout_check.button_pressed = false
        _break_blocks_check.button_pressed = false
        _bomb_jump_check.button_pressed = false
        _homing_check.button_pressed = false
        _rotate_check.button_pressed = false
        _suppress_events = false
        return

    var p: Dictionary = _projectiles[_selected_idx]
    _id_edit.text = str(p.get("id", ""))
    _name_edit.text = str(p.get("name", ""))
    _sheet_edit.text = str(p.get("sprite_sheet", ""))
    _fw_edit.text = str(int(p.get("frame_width", 16)))
    _fh_edit.text = str(int(p.get("frame_height", 16)))
    _findex_edit.text = str(int(p.get("frame_index", 0)))
    _fcount_edit.text = str(int(p.get("frame_count", 1)))
    _ftick_edit.text = str(int(p.get("frame_tick", 10)))
    _speed_edit.text = str(int(p.get("speed", 0)))
    _gravity_edit.text = str(int(p.get("gravity", 0)))
    _lifetime_edit.text = str(int(p.get("lifetime_ticks", 0)))
    _damage_edit.text = str(int(p.get("damage", 0)))
    _hitbox_w_edit.text = str(int(p.get("hitbox_w", 0)))
    _hitbox_h_edit.text = str(int(p.get("hitbox_h", 0)))
    _blast_radius_edit.text = str(int(p.get("blast_radius", 44)))
    _explosion_damage_edit.text = str(int(p.get("explosion_damage", 0)))
    _bomb_jump_speed_edit.text = str(int(p.get("bomb_jump_speed", 280)))
    _homing_strength_edit.text = str(int(p.get("homing_strength", 0)))
    _trail_color_edit.text = str(p.get("trail_color", ""))
    _pierces_check.button_pressed = bool(p.get("pierces", false))
    _explosive_check.button_pressed = bool(p.get("explosive", false))
    _explode_on_hit_check.button_pressed = bool(p.get("explode_on_hit", true))
    _explode_on_timeout_check.button_pressed = bool(p.get("explode_on_timeout", false))
    _break_blocks_check.button_pressed = bool(p.get("break_blocks", true))
    _bomb_jump_check.button_pressed = bool(p.get("bomb_jump", false))
    _homing_check.button_pressed = bool(p.get("homing", false))
    _rotate_check.button_pressed = bool(p.get("rotate_to_velocity", false))

    # Update sprite preview
    if _sprite_preview != null:
        _sprite_preview.pack_id = pack_id
        _sprite_preview.content_folder = "Projectiles"
        _sprite_preview.sheet_name = str(p.get("sprite_sheet", ""))
        _sprite_preview.frame_width = int(p.get("frame_width", 16))
        _sprite_preview.frame_height = int(p.get("frame_height", 16))
        _sprite_preview.frame_start = int(p.get("frame_index", 0))
        _sprite_preview.frame_count = int(p.get("frame_count", 1))
        _sprite_preview.frame_tick = int(p.get("frame_tick", 10))
        _sprite_preview.reload_texture()

    _suppress_events = false


func _on_field_edited(field: String, kind: String, text: String) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _projectiles.size():
        return
    var p: Dictionary = _projectiles[_selected_idx]
    if field == "id":
        var old_id := str(p.get("id", "")).strip_edges()
        var new_id := text.strip_edges()
        if not old_id.is_empty() and not new_id.is_empty() and old_id != new_id and not _id_taken_except(new_id, _selected_idx):
            _rename_projectile_references(old_id, new_id)
    if kind == "int":
        p[field] = PedUtil.to_int(text, int(p.get(field, 0)))
    elif kind == "float":
        p[field] = PedUtil.to_float(text, float(p.get(field, 0.0)))
    else:
        p[field] = text
    _projectiles[_selected_idx] = p
    dirty = true
    if field == "id" or field == "name":
        _refresh_list_row(_selected_idx)


func _on_bool_toggled(field: String, pressed: bool) -> void:
    if _suppress_events:
        return
    if _selected_idx < 0 or _selected_idx >= _projectiles.size():
        return
    var p: Dictionary = _projectiles[_selected_idx]
    p[field] = pressed
    _projectiles[_selected_idx] = p
    dirty = true


func _rename_projectile_references(old_id: String, new_id: String) -> void:
    var refactor := ContentReferenceRefactor.rename_references(pack_id, "projectile", old_id, new_id)
    if not bool(refactor.get("ok", false)):
        push_warning("[ProjectilesTab] projectile renamed, but reference update failed: %s" % str(refactor.get("errors", [])))


func _refresh_list_row(idx: int) -> void:
    if idx < 0 or idx >= _projectiles.size():
        return
    var p: Dictionary = _projectiles[idx]
    _list.set_item_text(idx, "%s — %s" % [p.get("id", "?"), p.get("name", "?")])

extends Control

const PedIO = preload("res://Space/scripts/editor/ped/ped_io.gd")
const PedUtil = preload("res://Space/scripts/editor/ped/ped_util.gd")

# Player editor — Stats tab. Two sections:
#   1. LEGACY: hardcoded base/growth rows (stats.json) — the leveling system
#   2. STAT EFFECTS: user-defined stats with ManiaVar effect bindings
#      (stats_manifest.json) — each stat can modify physics/gameplay vars.

var pack_id: String = ""
var dirty: bool = false

# ── Legacy (stats.json) ────────────────────────────────────────────────
var _base_data: Dictionary = {}
var _growth_data: Dictionary = {}

const BASE_ROWS: Array = [
    ["Level", "level", "base", "int"], ["Experience", "exp", "base", "int"],
    ["EXP to next", "exp_to_next", "base", "int"], ["Max HP", "hp_max", "base", "int"],
    ["Max MP", "mp_max", "base", "int"], ["Max Heart", "heart_max", "base", "int"],
    ["STR", "str", "base", "int"], ["CON", "con", "base", "int"],
    ["INT", "int", "base", "int"], ["LCK", "lck", "base", "int"],
]
const GROWTH_ROWS: Array = [
    ["HP / level", "hp_per_level", "growth", "int"],
    ["MP / level", "mp_per_level", "growth", "int"],
    ["Heart / level", "heart_per_level", "growth", "int"],
    ["STR / level", "str_per_level", "growth", "int"],
    ["CON / level", "con_per_level", "growth", "int"],
    ["INT / level", "int_per_level", "growth", "int"],
    ["LCK / level", "lck_per_level", "growth", "int"],
    ["EXP curve x", "exp_curve_multiplier", "growth", "float"],
]

var _base_edits: Array = []
var _growth_edits: Array = []
var _base_header: Label = null
var _growth_header: Label = null
var _base_labels: Array = []
var _growth_labels: Array = []

# ── Manifest (stats_manifest.json) ─────────────────────────────────────
var _manifest_stats: Array = []
var _msel: int = -1
var _suppress: bool = false

# Left panel
var _mfst_header: Label = null
var _mfst_list: ItemList = null
var _mfst_add: Button = null
var _mfst_del: Button = null

# Detail panel
var _det_header: Label = null
var _det_id: LineEdit = null
var _det_name: LineEdit = null
var _det_desc: TextEdit = null
var _det_cat: LineEdit = null
var _det_base: LineEdit = null
var _det_grow: LineEdit = null
var _lbl: Array = []  # 6 labels for the detail fields

# Effects
var _fx_header: Label = null
var _fx_add_btn: Button = null
var _fx_rows: Array = []  # [{target, op, value, thresh, del}]

var _undo: RefCounted = null

const LEFT_W: float = 250.0


func _ready() -> void:
    mouse_filter = MOUSE_FILTER_STOP
    _undo = EditorUndo.new(_capture_state, _apply_state)
    _build_layout.call_deferred()
    set_process(true)


func _capture_state() -> Dictionary:
    return {
        "base_data": _base_data.duplicate(true),
        "growth_data": _growth_data.duplicate(true),
        "manifest_stats": _manifest_stats.duplicate(true),
        "msel": _msel,
        "dirty": dirty,
    }


func _apply_state(snap: Dictionary) -> void:
    var b_v: Variant = snap.get("base_data", null)
    if typeof(b_v) == TYPE_DICTIONARY:
        _base_data = b_v
    var g_v: Variant = snap.get("growth_data", null)
    if typeof(g_v) == TYPE_DICTIONARY:
        _growth_data = g_v
    var m_v: Variant = snap.get("manifest_stats", null)
    if typeof(m_v) == TYPE_ARRAY:
        _manifest_stats = m_v
    _msel = int(snap.get("msel", -1))
    dirty = bool(snap.get("dirty", false))
    _populate_mfst_list()
    if _msel >= 0 and _msel < _manifest_stats.size():
        _mfst_list.select(_msel)
    _apply_detail()
    if _base_edits.size() > 0:
        _suppress = true
        for i in BASE_ROWS.size():
            _base_edits[i].text = _disp(_base_data, str(BASE_ROWS[i][1]), str(BASE_ROWS[i][3]))
        for i in GROWTH_ROWS.size():
            _growth_edits[i].text = _disp(_growth_data, str(GROWTH_ROWS[i][1]), str(GROWTH_ROWS[i][3]))
        _suppress = false


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
    if what == NOTIFICATION_RESIZED: _layout_children()

func _process(_d: float) -> void:
    if is_visible_in_tree(): _update_tooltips()

func open(p_pack_id: String) -> void:
    pack_id = p_pack_id
    _load_legacy()
    _load_manifest()
    _populate_mfst_list()
    if _manifest_stats.size() > 0:
        _mfst_list.select(0)
        _on_mfst_sel(0)
    else:
        _apply_detail()
    dirty = false
    if _undo != null:
        _undo.clear()

func save() -> bool:
    if not PedIO.save_stats(pack_id, {"base": _base_data.duplicate(true), "growth": _growth_data.duplicate(true)}):
        return false
    if not PedIO.save_stats_manifest(pack_id, {"stats": _manifest_stats.duplicate(true)}):
        return false
    dirty = false
    return true

func is_dirty() -> bool: return dirty


# ─── Tooltips ───────────────────────────────────────────────────────────

func _update_tooltips() -> void:
    var mp := get_local_mouse_position()
    for i in BASE_ROWS.size():
        if i < _base_edits.size() and Rect2(_base_edits[i].position, _base_edits[i].size).has_point(mp):
            EditorTooltip.show_text("Base value for %s at level 1." % str(BASE_ROWS[i][0])); return
    for i in GROWTH_ROWS.size():
        if i < _growth_edits.size() and Rect2(_growth_edits[i].position, _growth_edits[i].size).has_point(mp):
            EditorTooltip.show_text("Per-level growth for %s." % str(GROWTH_ROWS[i][0])); return
    if _det_base != null and Rect2(_det_base.position, _det_base.size).has_point(mp):
        EditorTooltip.show_text("Starting value for this stat at level 1.")
    elif _det_grow != null and Rect2(_det_grow.position, _det_grow.size).has_point(mp):
        EditorTooltip.show_text("Amount this stat increases per player level.")


# ─── Build ──────────────────────────────────────────────────────────────

func _build_layout() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.09, 0.1, 0.13, 1.0)
    bg.set_anchors_preset(PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    _base_header = _hdr("BASE STATS (Level 1)")
    _growth_header = _hdr("PER-LEVEL GROWTH")
    for row in BASE_ROWS:
        _base_labels.append(_lab(str(row[0])))
        var le := _legacy_edit(row); add_child(le); _base_edits.append(le)
    for row in GROWTH_ROWS:
        _growth_labels.append(_lab(str(row[0])))
        var le := _legacy_edit(row); add_child(le); _growth_edits.append(le)

    _mfst_header = _hdr("STAT EFFECTS (ManiaVars)")
    _mfst_list = ItemList.new(); _mfst_list.item_selected.connect(_on_mfst_sel); add_child(_mfst_list)
    _mfst_add = _btn("+ NEW STAT", _on_mfst_add)
    _mfst_del = _btn("DELETE", _on_mfst_del)

    _det_header = _hdr("STAT DETAIL")
    var fields := ["ID", "Name", "Description", "Category", "Base Value", "Growth / Lvl"]
    for f in fields: _lbl.append(_lab(f))
    _det_id = LineEdit.new(); _det_id.text_changed.connect(func(t): _on_det("id", t)); add_child(_det_id)
    _det_name = LineEdit.new(); _det_name.text_changed.connect(func(t): _on_det("name", t)); add_child(_det_name)
    _det_desc = TextEdit.new(); _det_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
    _det_desc.text_changed.connect(_on_det_desc); add_child(_det_desc)
    _det_cat = LineEdit.new(); _det_cat.placeholder_text = "core|vital|custom"
    _det_cat.text_changed.connect(func(t): _on_det("category", t)); add_child(_det_cat)
    _det_base = LineEdit.new(); _det_base.text_changed.connect(func(t): _on_det_num("base_value", t)); add_child(_det_base)
    _det_grow = LineEdit.new(); _det_grow.text_changed.connect(func(t): _on_det_num("growth_per_level", t)); add_child(_det_grow)

    _fx_header = _hdr("EFFECTS")
    _fx_add_btn = _btn("+ ADD EFFECT", _on_fx_add)
    _layout_children()


func _hdr(text: String) -> Label:
    var l := Label.new(); l.text = text
    l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6)); add_child(l); return l

func _lab(text: String) -> Label:
    var l := Label.new(); l.text = text
    l.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95)); add_child(l); return l

func _btn(text: String, cb: Callable) -> Button:
    var b := Button.new(); b.text = text; b.pressed.connect(cb); add_child(b); return b

func _legacy_edit(row: Array) -> LineEdit:
    var le := LineEdit.new()
    var key := str(row[1]); var sec := str(row[2]); var kind := str(row[3])
    le.text_changed.connect(func(t): _on_legacy_ed(sec, key, kind, t)); return le


# ─── Layout ─────────────────────────────────────────────────────────────

func _layout_children() -> void:
    if _base_header == null: return
    var vw := size.x; var vh := size.y; var m: float = 24.0
    var col_gap: float = 32.0
    var col_w: float = minf((vw - m * 2 - col_gap) * 0.5, 360.0)
    var hy: float = 16.0

    _base_header.position = Vector2(m, hy); _base_header.size = Vector2(col_w, 20)
    _growth_header.position = Vector2(m + col_w + col_gap, hy); _growth_header.size = Vector2(col_w, 20)
    var sy: float = hy + 32.0; var rh: float = 30.0; var lw: float = 120.0; var fh: float = 24.0
    _lay_col(_base_labels, _base_edits, m, sy, col_w, rh, lw, fh)
    _lay_col(_growth_labels, _growth_edits, m + col_w + col_gap, sy, col_w, rh, lw, fh)

    var my: float = sy + maxi(BASE_ROWS.size(), GROWTH_ROWS.size()) * rh + 16.0
    _mfst_header.position = Vector2(m, my); _mfst_header.size = Vector2(vw - m * 2, 20)
    my += 28.0
    var lh: float = maxf(160.0, vh - my - 48.0)
    _mfst_list.position = Vector2(m, my); _mfst_list.size = Vector2(LEFT_W - m - 4, lh)
    var by: float = my + lh + 4.0; var bw: float = (LEFT_W - m - 12) * 0.5
    _mfst_add.position = Vector2(m, by); _mfst_add.size = Vector2(bw, 28)
    _mfst_del.position = Vector2(m + bw + 8, by); _mfst_del.size = Vector2(bw, 28)

    var dx: float = LEFT_W + 4; var dw: float = vw - dx - m
    var dlw: float = 100.0; var dfx: float = dx + dlw; var dfw: float = dw - dlw - 8
    var dy: float = my; var drh: float = 28.0

    _det_header.position = Vector2(dx, dy); _det_header.size = Vector2(dw, 20); dy += 26.0
    var det_widgets: Array = [_det_id, _det_name, null, _det_cat, _det_base, _det_grow]
    for i in det_widgets.size():
        _lbl[i].position = Vector2(dx, dy + 3); _lbl[i].size = Vector2(dlw, drh)
        if i == 2:  # Description (TextEdit, taller)
            _det_desc.position = Vector2(dfx, dy); _det_desc.size = Vector2(dfw, 48); dy += 54
        else:
            det_widgets[i].position = Vector2(dfx, dy); det_widgets[i].size = Vector2(dfw, fh); dy += drh

    _fx_header.position = Vector2(dx, dy + 8); _fx_header.size = Vector2(dw, 20); dy += 32.0
    _layout_fx(dx, dy, dw, fh)


func _lay_col(labels: Array, edits: Array, x: float, sy: float,
              cw: float, rh: float, lw: float, fh: float) -> void:
    for i in labels.size():
        labels[i].position = Vector2(x, sy + i * rh + 3); labels[i].size = Vector2(lw, rh)
        edits[i].position = Vector2(x + lw, sy + i * rh); edits[i].size = Vector2(cw - lw - 8, fh)


func _layout_fx(x: float, sy: float, tw: float, fh: float) -> void:
    var y := sy; var g: float = 6.0
    var tw_t: float = maxf(140.0, tw * 0.3); var tw_o: float = 100.0
    var tw_v: float = 70.0; var tw_th: float = 60.0; var tw_d: float = 28.0
    for r in _fx_rows:
        var cx := x
        r["target"].position = Vector2(cx, y); r["target"].size = Vector2(tw_t, fh); cx += tw_t + g
        r["op"].position = Vector2(cx, y); r["op"].size = Vector2(tw_o, fh); cx += tw_o + g
        r["value"].position = Vector2(cx, y); r["value"].size = Vector2(tw_v, fh); cx += tw_v + g
        r["thresh"].position = Vector2(cx, y); r["thresh"].size = Vector2(tw_th, fh); cx += tw_th + g
        r["del"].position = Vector2(cx, y); r["del"].size = Vector2(tw_d, fh)
        y += fh + 4.0
    _fx_add_btn.position = Vector2(x, y); _fx_add_btn.size = Vector2(140, 26)


# ─── Legacy data ────────────────────────────────────────────────────────

func _load_legacy() -> void:
    var data := PedIO.load_stats(pack_id)
    var defaults := PedIO.default_stats()
    _base_data = _dict_or(data.get("base", {})).duplicate(true)
    _growth_data = _dict_or(data.get("growth", {})).duplicate(true)
    _ensure_keys(_base_data, defaults.get("base", {}))
    _ensure_keys(_growth_data, defaults.get("growth", {}))
    if _base_edits.is_empty(): return
    for i in BASE_ROWS.size():
        _base_edits[i].text = _disp(_base_data, str(BASE_ROWS[i][1]), str(BASE_ROWS[i][3]))
    for i in GROWTH_ROWS.size():
        _growth_edits[i].text = _disp(_growth_data, str(GROWTH_ROWS[i][1]), str(GROWTH_ROWS[i][3]))

func _on_legacy_ed(sec: String, key: String, kind: String, text: String) -> void:
    var t: Dictionary = _base_data if sec == "base" else _growth_data
    if kind == "float":
        t[key] = PedUtil.to_float(text, float(t.get(key, 0.0)))
    else:
        t[key] = PedUtil.to_int(text, int(t.get(key, 0)))
    dirty = true

static func _ensure_keys(t: Dictionary, d: Dictionary) -> void:
    for k in d.keys():
        if not t.has(k): t[k] = d[k]

static func _dict_or(v) -> Dictionary:
    return v if typeof(v) == TYPE_DICTIONARY else {}

static func _disp(d: Dictionary, key: String, kind: String) -> String:
    if kind == "float":
        return "%.3f" % float(d.get(key, 0))
    return str(int(d.get(key, 0)))


# ─── Manifest data ──────────────────────────────────────────────────────

func _load_manifest() -> void:
    var raw = PedIO.load_stats_manifest(pack_id).get("stats", [])
    _manifest_stats.clear()
    if typeof(raw) == TYPE_ARRAY:
        for e in raw:
            if typeof(e) == TYPE_DICTIONARY: _manifest_stats.append(_norm_stat(e))
    _msel = -1

static func _norm_stat(s: Dictionary) -> Dictionary:
    var fx: Array = []
    var raw = s.get("effects", [])
    if typeof(raw) == TYPE_ARRAY:
        for e in raw:
            if typeof(e) == TYPE_DICTIONARY:
                fx.append({"target": str(e.get("target", "gravity")), "operation": str(e.get("operation", "add")),
                    "value": float(e.get("value", 0.0)), "level_threshold": int(e.get("level_threshold", 1))})
    return {"id": str(s.get("id", "")), "name": str(s.get("name", "")),
        "description": str(s.get("description", "")), "category": str(s.get("category", "")),
        "base_value": int(s.get("base_value", 0)), "growth_per_level": float(s.get("growth_per_level", 0)),
        "effects": fx}

func _populate_mfst_list() -> void:
    _mfst_list.clear()
    for s in _manifest_stats:
        _mfst_list.add_item("%s — %s" % [s.get("id", "?"), s.get("name", "?")])

func _on_mfst_sel(idx: int) -> void:
    _msel = idx if idx >= 0 and idx < _manifest_stats.size() else -1
    _apply_detail()

func _on_mfst_add() -> void:
    if _undo != null: _undo.begin()
    var nid := "stat_%d" % (_manifest_stats.size() + 1)
    while _mfst_id_taken(nid): nid += "_"
    _manifest_stats.append({"id": nid, "name": "New Stat", "description": "", "category": "custom",
        "base_value": 0, "growth_per_level": 0, "effects": []})
    dirty = true; _populate_mfst_list()
    _mfst_list.select(_manifest_stats.size() - 1); _on_mfst_sel(_manifest_stats.size() - 1)
    if _undo != null: _undo.commit("add stat")

func _mfst_id_taken(id: String) -> bool:
    for s in _manifest_stats:
        if str(s.get("id", "")) == id: return true
    return false

func _on_mfst_del() -> void:
    if _msel < 0 or _msel >= _manifest_stats.size(): return
    if _undo != null: _undo.begin()
    _manifest_stats.remove_at(_msel); dirty = true; _populate_mfst_list()
    if _manifest_stats.is_empty():
        _msel = -1; _apply_detail()
        if _undo != null: _undo.commit("delete stat")
        return
    var ni: int = mini(_msel, _manifest_stats.size() - 1)
    _mfst_list.select(ni); _on_mfst_sel(ni)
    if _undo != null: _undo.commit("delete stat")

func _apply_detail() -> void:
    if _det_id == null: return
    _suppress = true
    var have: bool = _msel >= 0 and _msel < _manifest_stats.size()
    _det_id.editable = have; _det_name.editable = have; _det_desc.editable = have
    _det_cat.editable = have; _det_base.editable = have; _det_grow.editable = have
    _fx_add_btn.disabled = not have
    _clear_fx_rows()
    if not have:
        for w in [_det_id, _det_name, _det_cat, _det_base, _det_grow]: w.text = ""
        _det_desc.text = ""
        _suppress = false; _layout_children(); return
    var s: Dictionary = _manifest_stats[_msel]
    _det_id.text = str(s.get("id", "")); _det_name.text = str(s.get("name", ""))
    _det_desc.text = str(s.get("description", "")); _det_cat.text = str(s.get("category", ""))
    _det_base.text = str(int(s.get("base_value", 0)))
    _det_grow.text = _fnum(float(s.get("growth_per_level", 0)))
    for fx in s.get("effects", []): _add_fx_widgets(fx)
    _suppress = false; _layout_children()

func _on_det(field: String, text: String) -> void:
    if _suppress or _msel < 0 or _msel >= _manifest_stats.size(): return
    _manifest_stats[_msel][field] = text; dirty = true
    if field == "id" or field == "name": _refresh_mfst(_msel)

func _on_det_desc() -> void:
    if _suppress or _msel < 0 or _msel >= _manifest_stats.size(): return
    _manifest_stats[_msel]["description"] = _det_desc.text; dirty = true

func _on_det_num(field: String, text: String) -> void:
    if _suppress or _msel < 0 or _msel >= _manifest_stats.size(): return
    var cur = _manifest_stats[_msel].get(field, 0)
    if field == "base_value":
        _manifest_stats[_msel][field] = PedUtil.to_int(text, int(cur))
    else:
        _manifest_stats[_msel][field] = PedUtil.to_float(text, float(cur))
    dirty = true

func _refresh_mfst(idx: int) -> void:
    if idx < 0 or idx >= _manifest_stats.size(): return
    var s: Dictionary = _manifest_stats[idx]
    _mfst_list.set_item_text(idx, "%s — %s" % [s.get("id", "?"), s.get("name", "?")])


# ─── Effect rows ────────────────────────────────────────────────────────

func _clear_fx_rows() -> void:
    for r in _fx_rows:
        for k in ["target", "op", "value", "thresh", "del"]: (r[k] as Control).queue_free()
    _fx_rows.clear()

func _add_fx_widgets(fx: Dictionary) -> void:
    var idx: int = _fx_rows.size()
    var var_ids: Array = ManiaVars.get_var_ids()

    var tb := OptionButton.new()
    for vid in var_ids: tb.add_item(str(vid))
    tb.select(maxi(0, var_ids.find(str(fx.get("target", "gravity")))))
    tb.item_selected.connect(func(_i): _on_fx_ch(idx)); add_child(tb)

    var ob := OptionButton.new()
    for o in ManiaVars.OPERATIONS: ob.add_item(ManiaVars.OPERATION_LABELS.get(str(o), str(o)))
    ob.select(maxi(0, (ManiaVars.OPERATIONS as Array).find(str(fx.get("operation", "add")))))
    ob.item_selected.connect(func(_i): _on_fx_ch(idx)); add_child(ob)

    var ve := LineEdit.new(); ve.text = _fnum(float(fx.get("value", 0.0)))
    ve.text_changed.connect(func(_t): _on_fx_ch(idx)); add_child(ve)

    var te := LineEdit.new(); te.text = str(int(fx.get("level_threshold", 1)))
    te.placeholder_text = "Lvl"; te.text_changed.connect(func(_t): _on_fx_ch(idx)); add_child(te)

    var db := Button.new(); db.text = "x"
    db.pressed.connect(func(): _on_fx_del(idx)); add_child(db)

    _fx_rows.append({"target": tb, "op": ob, "value": ve, "thresh": te, "del": db})

func _on_fx_add() -> void:
    if _msel < 0 or _msel >= _manifest_stats.size(): return
    if _undo != null: _undo.begin()
    var nfx := ManiaVars.default_effect()
    _manifest_stats[_msel]["effects"].append(nfx)
    dirty = true; _add_fx_widgets(nfx); _layout_children()
    if _undo != null: _undo.commit("add effect")

func _on_fx_del(idx: int) -> void:
    if _msel < 0 or _msel >= _manifest_stats.size(): return
    var effects: Array = _manifest_stats[_msel].get("effects", [])
    if idx < 0 or idx >= effects.size(): return
    if _undo != null: _undo.begin()
    effects.remove_at(idx); _manifest_stats[_msel]["effects"] = effects
    dirty = true; _clear_fx_rows()
    for fx in effects: _add_fx_widgets(fx)
    _layout_children()
    if _undo != null: _undo.commit("delete effect")

func _on_fx_ch(idx: int) -> void:
    if _suppress or _msel < 0 or _msel >= _manifest_stats.size(): return
    var effects: Array = _manifest_stats[_msel].get("effects", [])
    if idx < 0 or idx >= effects.size() or idx >= _fx_rows.size(): return
    var r: Dictionary = _fx_rows[idx]; var ids: Array = ManiaVars.get_var_ids()
    effects[idx] = {
        "target": str(ids[clampi(r["target"].selected, 0, ids.size() - 1)]),
        "operation": str(ManiaVars.OPERATIONS[clampi(r["op"].selected, 0, ManiaVars.OPERATIONS.size() - 1)]),
        "value": PedUtil.to_float(r["value"].text, float(effects[idx].get("value", 0.0))),
        "level_threshold": PedUtil.to_int(r["thresh"].text, int(effects[idx].get("level_threshold", 1))),
    }
    _manifest_stats[_msel]["effects"] = effects; dirty = true


# ─── Utility ────────────────────────────────────────────────────────────

static func _fnum(v: float) -> String:
    if absf(v - roundf(v)) < 0.0001: return str(int(roundf(v)))
    var s := "%.3f" % v
    while s.ends_with("0"): s = s.substr(0, s.length() - 1)
    if s.ends_with("."): s = s.substr(0, s.length() - 1)
    return s

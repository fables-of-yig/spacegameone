class_name SpaceGalaxyEditor
extends Control

# In-game galaxy editor (Frontier 3 / S2a). Opened from the dev console with
# `galaxyedit` (Space). A fit-to-screen node graph of every system: drag to
# reposition, link/unlink jump connections, add/rename/delete systems, then save
# to systems.json. Systems live in DataManager.systems[id] = {name, position:
# [x,y], star_size, connections:[id...], pois:[...]}. Edits DataManager.systems
# directly; Save persists via SystemIO (copy-on-write). Mounted under a
# CanvasLayer (screen space) — systems aren't in one world, so this is a graph
# view, not the in-system POI editor (mapedit).

const SystemIO := preload("res://Space/scripts/shared/system_io.gd")
const PICK_R := 26.0

var _active := false
var _prev_paused := false
var _mode := "move"          # "move" | "link"
var _selected := ""
var _dragging := ""
var _link_from := ""
var _dirty := false
var _hud: Control = null      # toolbar + side panel host (children, on top of _draw)
var _status: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = NebulaTheme.theme()
	visible = false


func open_editor() -> void:
	_active = true
	visible = true
	_selected = ""
	_link_from = ""
	_mode = "move"
	_dirty = false
	_prev_paused = get_tree().paused
	get_tree().paused = true
	theme = NebulaTheme.theme()
	_build_hud()
	queue_redraw()


func close_editor() -> void:
	_active = false
	visible = false
	get_tree().paused = _prev_paused


# ── Layout transform (galaxy <-> screen) ─────────────────────────────────────

func _draw_rect() -> Rect2:
	# Leave room for the top toolbar and right side panel.
	return Rect2(40, 80, maxf(100.0, size.x - 80 - 360), maxf(100.0, size.y - 140))


func _galaxy_bounds() -> Rect2:
	var first := true
	var r := Rect2()
	for id: String in DataManager.systems:
		var p := _sys_pos(id)
		if first:
			r = Rect2(p, Vector2.ZERO)
			first = false
		else:
			r = r.expand(p)
	if first:
		r = Rect2(Vector2(0, 0), Vector2(1000, 1000))
	r = r.grow(200.0)
	if r.size.x < 1.0:
		r.size.x = 1.0
	if r.size.y < 1.0:
		r.size.y = 1.0
	return r


func _fit_scale() -> float:
	var b := _galaxy_bounds()
	var dr := _draw_rect()
	return minf(dr.size.x / b.size.x, dr.size.y / b.size.y)


func _to_screen(g: Vector2) -> Vector2:
	var b := _galaxy_bounds()
	var dr := _draw_rect()
	var s := _fit_scale()
	var content := b.size * s
	var origin := dr.position + (dr.size - content) * 0.5
	return origin + (g - b.position) * s


func _to_galaxy(scr: Vector2) -> Vector2:
	var b := _galaxy_bounds()
	var dr := _draw_rect()
	var s := _fit_scale()
	var content := b.size * s
	var origin := dr.position + (dr.size - content) * 0.5
	return (scr - origin) / s + b.position


func _sys_pos(id: String) -> Vector2:
	var p: Variant = (DataManager.systems.get(id, {}) as Dictionary).get("position", [0, 0])
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
		return Vector2(float(p[0]), float(p[1]))
	return Vector2.ZERO


func _set_sys_pos(id: String, g: Vector2) -> void:
	var systems: Dictionary = DataManager.systems
	if systems.has(id):
		(systems[id] as Dictionary)["position"] = [g.x, g.y]
		DataManager.systems = systems


# ── Input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseMotion:
		if _dragging != "":
			_set_sys_pos(_dragging, _to_galaxy((event as InputEventMouseMotion).position))
			_dirty = true
			accept_event()
		queue_redraw()  # also refresh hover / pending link line
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var id := _system_at(mb.position)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _mode == "link":
					_handle_link_click(id)
				else:
					_selected = id
					_dragging = id
					_build_hud()
					queue_redraw()
			else:
				_dragging = ""
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if id != "":
				_delete_system(id)
			accept_event()


func _system_at(scr: Vector2) -> String:
	var best := ""
	var best_d := PICK_R
	for id: String in DataManager.systems:
		var d := _to_screen(_sys_pos(id)).distance_to(scr)
		if d <= best_d:
			best_d = d
			best = id
	return best


func _handle_link_click(id: String) -> void:
	if id == "":
		_link_from = ""
	elif _link_from == "":
		_link_from = id
	elif _link_from == id:
		_link_from = ""
	else:
		_toggle_connection(_link_from, id)
		_link_from = ""
	_build_hud()
	queue_redraw()


# ── Edits ────────────────────────────────────────────────────────────────────

func _toggle_connection(a: String, b: String) -> void:
	var systems: Dictionary = DataManager.systems
	var ca: Array = (systems.get(a, {}) as Dictionary).get("connections", [])
	var cb: Array = (systems.get(b, {}) as Dictionary).get("connections", [])
	if ca.has(b):
		ca.erase(b)
		cb.erase(a)
		_set_status("unlinked %s ✕ %s" % [a, b])
	else:
		ca.append(b)
		cb.append(a)
		_set_status("linked %s ↔ %s" % [a, b])
	(systems[a] as Dictionary)["connections"] = ca
	(systems[b] as Dictionary)["connections"] = cb
	DataManager.systems = systems
	_dirty = true


func _add_system() -> void:
	var systems: Dictionary = DataManager.systems
	var n := 1
	var id := "system_1"
	while systems.has(id):
		n += 1
		id = "system_%d" % n
	var center := _to_galaxy(_draw_rect().get_center())
	systems[id] = {"name": "New System", "position": [center.x, center.y], "star_size": 60, "connections": [], "pois": []}
	DataManager.systems = systems
	_selected = id
	_dirty = true
	_build_hud()
	queue_redraw()
	_set_status("added '%s' — drag to place, link to connect" % id)


func _delete_system(id: String) -> void:
	var systems: Dictionary = DataManager.systems
	systems.erase(id)
	for other: String in systems:
		var c: Array = (systems[other] as Dictionary).get("connections", [])
		if c.has(id):
			c.erase(id)
			(systems[other] as Dictionary)["connections"] = c
	DataManager.systems = systems
	if _selected == id:
		_selected = ""
	_dirty = true
	_build_hud()
	queue_redraw()
	_set_status("deleted '%s'" % id)


func _save() -> void:
	if SystemIO.save(_pack_id(), DataManager.systems):
		_dirty = false
		_set_status("saved galaxy to '%s'" % _pack_id())
	else:
		_set_status("save failed", true)


# ── Draw ─────────────────────────────────────────────────────────────────────

const C_LANE := Color(0.5, 0.608, 0.627, 0.34)
const C_LANE_LIT := Color(0.247, 0.827, 1.0, 0.7)
const C_CYAN := Color("#3fd3ff")
const C_CYAN_HI := Color("#b6fdff")
const C_GOLD := Color("#ffcc33")
const C_GOLD_HI := Color("#ffe9a0")


func _draw() -> void:
	if not _active:
		return
	var hover := _system_at(get_local_mouse_position()) if _mode == "move" and _dragging == "" else ""
	# Jump lanes (dedupe a<->b); lit cyan when touching the selected system.
	var drawn: Dictionary = {}
	for id: String in DataManager.systems:
		var ap := _to_screen(_sys_pos(id))
		for conn_v in (DataManager.systems[id] as Dictionary).get("connections", []):
			var conn := str(conn_v)
			if not DataManager.systems.has(conn):
				continue
			var key := id + "|" + conn if id < conn else conn + "|" + id
			if drawn.has(key):
				continue
			drawn[key] = true
			var lit := _selected != "" and (id == _selected or conn == _selected)
			draw_line(ap, _to_screen(_sys_pos(conn)), C_LANE_LIT if lit else C_LANE, 2.0 if lit else 1.3)
	# Pending gold link line follows the cursor in Link mode.
	if _mode == "link" and _link_from != "" and DataManager.systems.has(_link_from):
		draw_dashed_line(_to_screen(_sys_pos(_link_from)), get_local_mouse_position(), Color("#ffd84a"), 2.0, 7.0)
	# System nodes.
	var font := NebulaTheme.font()
	if font == null:
		font = ThemeDB.fallback_font
	for id: String in DataManager.systems:
		var sp := _to_screen(_sys_pos(id))
		var sel := id == _selected or id == _link_from
		var is_cur := id == str(GameManager.current_system)
		var base := C_GOLD if is_cur else C_CYAN
		var rad := clampf(7.0 + float((DataManager.systems[id] as Dictionary).get("star_size", 60)) * 0.10, 9.0, 20.0)
		# bloom
		draw_circle(sp, rad + (9.0 if sel else 5.0), Color(base.r, base.g, base.b, 0.18 if sel else 0.10))
		# disc + highlight + dark rim
		draw_circle(sp, rad, base.darkened(0.1))
		draw_circle(sp - Vector2(rad * 0.26, rad * 0.3), rad * 0.42, base.lightened(0.6))
		draw_arc(sp, rad, 0, TAU, 28, Color(0.02, 0.05, 0.07, 0.9), 1.0)
		if id == hover and not sel:
			draw_arc(sp, rad + 3.0, 0, TAU, 28, Color(base.r, base.g, base.b, 0.65), 1.5)
		if sel:
			draw_arc(sp, rad + 2.0, 0, TAU, 32, Color(0.02, 0.03, 0.05), 2.0)
			draw_arc(sp, rad + 4.0, 0, TAU, 32, C_GOLD_HI if is_cur else C_CYAN_HI, 2.0)
		# label
		var nm := str((DataManager.systems[id] as Dictionary).get("name", id))
		var lcol := C_CYAN_HI if sel else (C_GOLD if is_cur else NebulaTheme.C_BODY)
		var lw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, sp + Vector2(-lw * 0.5 + 1, rad + 16), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.85))
		draw_string(font, sp + Vector2(-lw * 0.5, rad + 15), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lcol)


# ── HUD (toolbar + side panel) ───────────────────────────────────────────────

func _build_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	# Top toolbar.
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = 8
	bar.offset_top = 8
	bar.offset_right = -8
	var box := StyleBoxFlat.new()
	box.bg_color = Color(NebulaTheme.C_PANEL_BG.r, NebulaTheme.C_PANEL_BG.g, NebulaTheme.C_PANEL_BG.b, 0.95)
	box.border_color = NebulaTheme.C_ACCENT
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", box)
	_hud.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	row.add_child(NebulaTheme.title_label("Galaxy"))
	var mv := NebulaUi.button("Move", "primary" if _mode == "move" else "ghost")
	mv.pressed.connect(func(): _set_mode("move"))
	row.add_child(mv)
	var lk := NebulaUi.button("Link", "primary" if _mode == "link" else "ghost")
	lk.pressed.connect(func(): _set_mode("link"))
	row.add_child(lk)
	var addb := NebulaUi.button("＋ System", "ghost")
	addb.pressed.connect(_add_system)
	row.add_child(addb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var save := NebulaUi.button("Save", "primary")
	save.pressed.connect(_save)
	row.add_child(save)
	var close := NebulaUi.button("✕", "ghost")
	close.pressed.connect(close_editor)
	row.add_child(close)
	# Side panel for the selected system.
	if _selected != "" and DataManager.systems.has(_selected):
		_build_side_panel()
	# Bottom-left: mode status pill (mode dot + label + key hints + status text).
	var pill := PanelContainer.new()
	pill.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	pill.position += Vector2(14, -14)
	pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pbox := StyleBoxFlat.new()
	pbox.bg_color = Color(0.031, 0.047, 0.071, 0.84)
	pbox.set_corner_radius_all(16)
	pbox.set_content_margin_all(9)
	pbox.set_border_width_all(1)
	pbox.border_color = Color(0.247, 0.827, 1.0, 0.28)
	pill.add_theme_stylebox_override("panel", pbox)
	_hud.add_child(pill)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	pill.add_child(prow)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", NebulaTheme.C_ACCENT_2 if _mode == "link" else NebulaTheme.C_TITLE)
	prow.add_child(dot)
	var mlbl := Label.new()
	mlbl.text = "LINK MODE" if _mode == "link" else "MOVE MODE"
	mlbl.add_theme_color_override("font_color", NebulaTheme.C_ACCENT_2 if _mode == "link" else NebulaTheme.C_TITLE)
	prow.add_child(mlbl)
	var hints := Label.new()
	hints.text = ("Click·first   Click·to link   Esc·cancel" if _mode == "link" else "Drag·move   Click·select   Click bg·deselect")
	hints.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	prow.add_child(hints)
	_status = Label.new()
	_status.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	prow.add_child(_status)


func _build_side_panel() -> void:
	var sys: Dictionary = DataManager.systems[_selected]
	var margin := MarginContainer.new()
	margin.anchor_left = 1.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.offset_left = -316
	margin.offset_top = 70
	margin.offset_right = -18
	margin.offset_bottom = -64
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(margin)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	margin.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 13)
	frame.add_child(vb)

	# Header: INSPECTOR + CURRENT chip.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var htitle := NebulaTheme.title_label("Inspector")
	htitle.add_theme_font_size_override("font_size", NebulaTheme.size("section"))
	head.add_child(htitle)
	if _selected == str(GameManager.current_system):
		var chip := Label.new()
		chip.text = " CURRENT "
		chip.add_theme_color_override("font_color", NebulaTheme.C_ACCENT_2)
		chip.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		head.add_child(chip)
	vb.add_child(head)

	var nm := LineEdit.new()
	nm.text = str(sys.get("name", ""))
	nm.text_changed.connect(func(t):
		(DataManager.systems[_selected] as Dictionary)["name"] = t
		_dirty = true
		queue_redraw())
	vb.add_child(NebulaUi.labeled("System name", nm, 100))

	# Star size (real star_size field; slider).
	var ss := HSlider.new()
	ss.min_value = 10
	ss.max_value = 300
	ss.step = 5
	ss.value = float(sys.get("star_size", 60))
	ss.custom_minimum_size = Vector2(0, 18)
	var ss_read := Label.new()
	ss_read.text = "%d" % int(ss.value)
	ss_read.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	ss.value_changed.connect(func(v):
		(DataManager.systems[_selected] as Dictionary)["star_size"] = int(v)
		ss_read.text = "%d" % int(v)
		_dirty = true
		queue_redraw())
	var ss_row := HBoxContainer.new()
	ss_row.add_theme_constant_override("separation", 10)
	var ss_lbl := Label.new()
	ss_lbl.text = "STAR SIZE"
	ss_lbl.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	ss_lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	ss_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ss_row.add_child(ss_lbl)
	ss_row.add_child(ss_read)
	vb.add_child(ss_row)
	vb.add_child(ss)

	# Jump lanes chip list + count.
	var conns: Array = sys.get("connections", [])
	var lh := HBoxContainer.new()
	var lh_lbl := Label.new()
	lh_lbl.text = "JUMP LANES"
	lh_lbl.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	lh_lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	lh_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lh_lbl)
	var lh_n := Label.new()
	lh_n.text = str(conns.size())
	lh_n.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	lh.add_child(lh_n)
	vb.add_child(lh)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	if conns.is_empty():
		var none := Label.new()
		none.text = "No links — use Link mode."
		none.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		none.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		chips.add_child(none)
	else:
		for cid_v in conns:
			var cid := str(cid_v)
			var o: Dictionary = DataManager.systems.get(cid, {})
			var chip := PanelContainer.new()
			chip.add_theme_stylebox_override("panel", NebulaTheme.well_box())
			var cl := Label.new()
			cl.text = str(o.get("name", cid))
			cl.add_theme_color_override("font_color", NebulaTheme.C_BODY)
			cl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
			chip.add_child(cl)
			chips.add_child(chip)
	vb.add_child(chips)

	# POI count + star class wells.
	var wells := HBoxContainer.new()
	wells.add_theme_constant_override("separation", 10)
	wells.add_child(_well("POINTS OF INTEREST", str((sys.get("pois", []) as Array).size())))
	wells.add_child(_well("STAR CLASS", _star_class(int(sys.get("star_size", 60)))))
	vb.add_child(wells)

	var del := NebulaUi.button("Delete system", "gold")
	del.pressed.connect(func(): _delete_system(_selected))
	vb.add_child(del)


func _well(label: String, value: String) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", NebulaTheme.well_box())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	p.add_child(vb)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	vb.add_child(v)
	return p


func _star_class(star_size: int) -> String:
	if star_size < 50:
		return "M"
	if star_size < 90:
		return "K"
	if star_size < 150:
		return "G"
	return "F"


func _set_mode(m: String) -> void:
	_mode = m
	_link_from = ""
	_build_hud()
	queue_redraw()


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


func _set_status(msg: String, is_err := false) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_ACCENT)

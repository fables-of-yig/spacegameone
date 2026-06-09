class_name SpaceMapEditor
extends Node2D

# In-game Space (SSB) map editor (Frontier 3 / S1). Toggled from the dev console
# with `mapedit`. Freezes the system (pauses the tree so POIs stop orbiting),
# lets you drag POIs to reposition them (orbit_dist/orbit_angle recomputed from
# the star), place new ones, rename, and delete — then save to systems.json.
#
# POIs live in DataManager.systems[sys].pois[] as {id,type,name,orbit_dist,
# orbit_angle(deg),...}; world pos = star + from_angle(deg2rad(angle))*dist.
# Markers (group "pois", poi_marker.gd) carry poi_id; tree-pause stops their
# orbit so drags are stable. Reuses SpawnManager.clear_pois/spawn_system_pois
# (live respawn) + SystemIO.save (copy-on-write).

const SystemIO := preload("res://Space/scripts/shared/system_io.gd")
const PLACE_TYPES := ["station", "resource", "anomaly", "ruin", "salvage"]
const PICK_RADIUS := 700.0

var _host: Node2D = null
var _active := false
var _prev_paused := false
var _hud: CanvasLayer = null
var _status: Label = null
var _sel_host: VBoxContainer = null
var _selected_id := ""
var _dragging := false
var _dirty := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 4000
	z_as_relative = false
	visible = false


func setup(host: Node2D) -> void:
	_host = host


func toggle() -> void:
	if _active:
		close()
	else:
		open()


func open() -> void:
	if _host == null:
		return
	if str(GameManager.current_system).is_empty():
		push_warning("SpaceMapEditor: no current system to edit")
		return
	_active = true
	visible = true
	_selected_id = ""
	_dirty = false
	_prev_paused = get_tree().paused
	get_tree().paused = true
	_build_hud()
	_hud.visible = true
	queue_redraw()


func close() -> void:
	_active = false
	visible = false
	get_tree().paused = _prev_paused
	if _hud != null:
		_hud.visible = false


# ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var mpos := get_global_mouse_position()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var m := _marker_at(mpos)
				_selected_id = str(m.poi_id) if m != null else ""
				_dragging = m != null
				_build_hud()
				queue_redraw()
			elif _dragging:
				_dragging = false
				_commit_drag()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var m := _marker_at(mpos)
			if m != null:
				_delete_poi(str(m.poi_id))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(get_global_mouse_position())
		queue_redraw()


# ── POI ops ──────────────────────────────────────────────────────────────────

func _marker_at(world: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := PICK_RADIUS
	for n in get_tree().get_nodes_in_group("pois"):
		var node := n as Node2D
		if node == null:
			continue
		var d := node.global_position.distance_to(world)
		if d <= best_d:
			best_d = d
			best = node
	return best


func _selected_marker() -> Node2D:
	if _selected_id.is_empty():
		return null
	for n in get_tree().get_nodes_in_group("pois"):
		if str((n as Node).get("poi_id")) == _selected_id:
			return n as Node2D
	return null


func _drag_to(world: Vector2) -> void:
	var m := _selected_marker()
	if m == null:
		return
	var rel := world - _star_center()
	m.set("orbit_dist", rel.length())
	m.set("orbit_angle", rel.angle())
	m.global_position = world


func _commit_drag() -> void:
	var m := _selected_marker()
	if m == null:
		return
	var rel: Vector2 = m.global_position - _star_center()
	if _set_poi_fields(_selected_id, {"orbit_dist": rel.length(), "orbit_angle": rad_to_deg(rel.angle())}):
		_dirty = true
		_set_status("moved '%s' (unsaved)" % _selected_id, false)


func _add_poi(poi_type: String) -> void:
	var sys := str(GameManager.current_system)
	var systems: Dictionary = DataManager.systems
	var sysd: Dictionary = systems.get(sys, {})
	var pois: Array = sysd.get("pois", [])
	var pid := "%s_%d" % [poi_type, Time.get_ticks_msec()]
	pois.append({
		"id": pid, "name": poi_type.capitalize(), "type": poi_type,
		"description": "placed in-game", "event_id": "",
		"orbit_dist": 3000.0 + float(pois.size()) * 400.0,
		"orbit_angle": float(pois.size()) * 40.0,
		"sprite": "", "visual_scale": 1.0, "anim_frames": 1, "anim_fps": 0.0, "gravity_radius": 0,
	})
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	_respawn()
	_selected_id = pid
	_dirty = true
	_build_hud()
	queue_redraw()
	_set_status("added %s — drag to position, then Save" % poi_type)


func _delete_poi(pid: String) -> void:
	var sys := str(GameManager.current_system)
	var systems: Dictionary = DataManager.systems
	var sysd: Dictionary = systems.get(sys, {})
	var pois: Array = sysd.get("pois", [])
	for i in range(pois.size() - 1, -1, -1):
		if str((pois[i] as Dictionary).get("id", "")) == pid:
			pois.remove_at(i)
			break
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	if pid == _selected_id:
		_selected_id = ""
	_respawn()
	_dirty = true
	_build_hud()
	queue_redraw()
	_set_status("deleted '%s' (unsaved)" % pid)


func _set_poi_fields(pid: String, fields: Dictionary) -> bool:
	var sys := str(GameManager.current_system)
	var systems: Dictionary = DataManager.systems
	var sysd: Dictionary = systems.get(sys, {})
	var pois: Array = sysd.get("pois", [])
	for i in pois.size():
		var poi: Dictionary = pois[i]
		if str(poi.get("id", "")) == pid:
			for k in fields:
				poi[k] = fields[k]
			pois[i] = poi
			sysd["pois"] = pois
			systems[sys] = sysd
			DataManager.systems = systems
			return true
	return false


func _save() -> void:
	if SystemIO.save(_pack_id(), DataManager.systems):
		_dirty = false
		_set_status("saved systems to '%s'" % _pack_id())
	else:
		_set_status("save failed", true)


func _respawn() -> void:
	var spawn: Variant = _host.get("_spawn")
	if spawn != null and is_instance_valid(spawn):
		spawn.clear_pois()
		spawn.spawn_system_pois(str(GameManager.current_system))


func _star_center() -> Vector2:
	var swp: Variant = _host.get("system_world_positions")
	if typeof(swp) == TYPE_DICTIONARY:
		return (swp as Dictionary).get(str(GameManager.current_system), Vector2.ZERO)
	return Vector2.ZERO


# ── Draw (world space) ───────────────────────────────────────────────────────

func _draw() -> void:
	if not _active:
		return
	var star := _star_center()
	draw_circle(star, 28, Color(1.0, 0.9, 0.4, 0.5))
	for n in get_tree().get_nodes_in_group("pois"):
		var node := n as Node2D
		if node == null:
			continue
		var sel := str(node.get("poi_id")) == _selected_id
		var col := NebulaTheme.C_ACCENT_2 if sel else NebulaTheme.C_ACCENT
		draw_arc(star, node.global_position.distance_to(star), 0, TAU, 64, Color(col.r, col.g, col.b, 0.12), 2.0)
		draw_circle(node.global_position, 60 if sel else 40, Color(col.r, col.g, col.b, 0.25))
		draw_arc(node.global_position, 90, 0, TAU, 32, col, 2.0)


# ── HUD ──────────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	if _hud == null:
		_hud = CanvasLayer.new()
		_hud.layer = 130
		_hud.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_hud)
	for c in _hud.get_children():
		c.queue_free()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = NebulaTheme.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	# Top toolbar.
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = 8
	bar.offset_top = 8
	bar.offset_right = -8
	var box := StyleBoxFlat.new()
	box.bg_color = Color(NebulaTheme.C_PANEL_BG.r, NebulaTheme.C_PANEL_BG.g, NebulaTheme.C_PANEL_BG.b, 0.94)
	box.border_color = NebulaTheme.C_ACCENT
	box.set_border_width_all(1)
	box.border_width_bottom = 2
	box.set_corner_radius_all(6)
	box.set_content_margin_all(8)
	bar.add_theme_stylebox_override("panel", box)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var lbl := NebulaTheme.title_label("Map Editor")
	row.add_child(lbl)
	for t in PLACE_TYPES:
		var b := NebulaUi.button("＋ " + str(t).capitalize(), "ghost")
		b.pressed.connect(_add_poi.bind(str(t)))
		row.add_child(b)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var save := NebulaUi.button("Save", "primary")
	save.pressed.connect(_save)
	row.add_child(save)
	var close_btn := NebulaUi.button("✕", "ghost")
	close_btn.pressed.connect(close)
	row.add_child(close_btn)

	# Selected-POI panel (right).
	if not _selected_id.is_empty():
		_build_selected_panel(root)

	# Bottom hint + status.
	var bl := VBoxContainer.new()
	bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	bl.position += Vector2(10, -10)
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bl)
	var hint := Label.new()
	hint.text = "drag a POI to move · click to select · RMB delete · Save persists"
	hint.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	bl.add_child(hint)
	_status = Label.new()
	_status.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	bl.add_child(_status)


func _build_selected_panel(root: Control) -> void:
	var sys := str(GameManager.current_system)
	var poi := _poi_record(_selected_id)
	var margin := MarginContainer.new()
	margin.anchor_left = 1.0
	margin.anchor_right = 1.0
	margin.offset_left = -360
	margin.offset_top = 70
	margin.offset_right = -8
	margin.offset_bottom = 220
	root.add_child(margin)
	var frame := PanelContainer.new()
	margin.add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	frame.add_child(vb)
	vb.add_child(NebulaUi.section_header("POI · %s" % str(poi.get("type", "?"))))
	var nm := LineEdit.new()
	nm.text = str(poi.get("name", ""))
	nm.placeholder_text = "name"
	nm.text_changed.connect(func(t):
		_set_poi_fields(_selected_id, {"name": t})
		_dirty = true)
	vb.add_child(NebulaUi.labeled("Name", nm, 80))
	var del := NebulaUi.button("🗑 Delete POI", "gold")
	del.pressed.connect(func(): _delete_poi(_selected_id))
	vb.add_child(del)


func _poi_record(pid: String) -> Dictionary:
	var sysd: Dictionary = DataManager.systems.get(str(GameManager.current_system), {})
	for poi_v in sysd.get("pois", []):
		if str((poi_v as Dictionary).get("id", "")) == pid:
			return poi_v
	return {}


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

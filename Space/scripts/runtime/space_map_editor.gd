class_name SpaceMapEditor
extends Node2D

# In-game Space (SSB) map editor (Frontier 3 / S1), rebuilt to the Claude Design
# "System Map Editor" handoff: a full-screen three-column schematic editor.
#   LEFT   Bodies rail (star + every POI) + a per-body sprite-sheet importer
#          (browse PNG -> cols/rows/frames/fps -> animated preview, saved into the
#          pack and onto the body's sprite fields).
#   CENTER schematic system view -- star at center, orbit rings, POI markers at
#          (orbit_dist, orbit_angle); click select, drag move (r/a), RMB delete.
#   RIGHT  selected-body inspector -- name, kind (read-only), interaction
#          (Land / Dialogue) + reference, orbit/bearing, delete.
#
# Toggled from the dev console with `mapedit`; mounted in Space main; saves to
# systems.json via SystemIO. POIs live in DataManager.systems[sys].pois[].
#
# RUNTIME MAPPING (honest scope): orbit_dist/orbit_angle, name, type, and the
# sprite block (sprite path + anim_frames + anim_fps, single-row strip) are
# consumed by poi_marker.gd today. `kind` mirrors `type` (planet/station; other
# existing types are preserved, not clobbered). `interaction`/`ref` are persisted
# but NOT yet consumed by the runtime (landing is region-based via planet_data;
# POI dialogue isn't a runtime feature yet) -- authored ahead of the hookup.

const SystemIO := preload("res://Space/scripts/shared/system_io.gd")

const RING_RADII := [88.0, 152.0, 216.0, 280.0, 332.0]
const PLANET_TINTS := ["#5dd6c0", "#7fb4ff", "#c8804a", "#b07b4a", "#8a7fd4", "#d9b14a"]
const LAND_SCENES := ["colony_hub", "station_interior", "barren_surface", "jungle_world", "ice_field", "ruined_city"]
const DIALOGUES := ["hail_hauler", "ghost_signal", "rift_echo", "customs_check", "distress_call", "first_contact"]
# kind -> {label, type (runtime poi_type), accent, land-default}
const KINDS := {
	"planet": {"label": "Planet", "type": "planet", "color": Color("#7fb4ff"), "land": true},
	"station": {"label": "Station", "type": "station", "color": Color("#3fd3ff"), "land": true},
	"dialogue": {"label": "Dialogue", "type": "anomaly", "color": Color("#ffcc33"), "land": false},
}
const KIND_ORDER := ["planet", "station", "dialogue"]
const C_LAND := Color("#3fd3ff")
const C_TALK := Color("#ffcc33")

var _host: Node2D = null
var _active := false
var _prev_paused := false
var _dirty := false

var _hud: CanvasLayer = null
var _field: Control = null          # center schematic view (draws + handles mouse)
var _left: Control = null           # bodies rail host (rebuilt on selection)
var _right: Control = null          # inspector host (rebuilt on selection)
var _status: Label = null

var _selected_id := ""              # "" none, "sun" star, else poi id
var _dragging := false
var _field_center := Vector2.ZERO
var _ring_scale := 1.0

# sprite-importer animated preview state
var _imp_tex: Texture2D = null
var _imp_frame := 0
var _imp_accum := 0.0
var _file_dialog: FileDialog = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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


func close() -> void:
	_active = false
	visible = false
	get_tree().paused = _prev_paused
	if _hud != null:
		_hud.visible = false


func _process(delta: float) -> void:
	if not _active:
		return
	# Drive the sprite-importer animated preview.
	if _imp_tex != null:
		var body := _selected_body()
		var fps := float(body.get("anim_fps", 8))
		var frames: int = maxi(1, int(body.get("anim_frames", 1)))
		if fps > 0.0 and frames > 1:
			_imp_accum += delta
			if _imp_accum >= 1.0 / fps:
				_imp_accum = 0.0
				_imp_frame = (_imp_frame + 1) % frames
				if _imp_preview != null:
					_imp_preview.queue_redraw()


# ── data helpers ───────────────────────────────────────────────────────────────

func _system() -> Dictionary:
	return DataManager.systems.get(str(GameManager.current_system), {})


func _pois() -> Array:
	return _system().get("pois", [])


func _poi(pid: String) -> Dictionary:
	for p in _pois():
		if str((p as Dictionary).get("id", "")) == pid:
			return p
	return {}


func _selected_body() -> Dictionary:
	if _selected_id == "sun":
		return _system()
	return _poi(_selected_id)


func _kind_of(poi: Dictionary) -> String:
	var k := str(poi.get("kind", ""))
	if k in KINDS:
		return k
	match str(poi.get("type", "")):
		"planet": return "planet"
		"station", "hostile_station": return "station"
		_: return "dialogue"


func _accent_of(poi: Dictionary) -> Color:
	return C_LAND if str(poi.get("interaction", "land")) == "land" else C_TALK


func _commit(fields: Dictionary, pid := "") -> void:
	var target := pid if pid != "" else _selected_id
	var systems: Dictionary = DataManager.systems
	var sys := str(GameManager.current_system)
	var sysd: Dictionary = systems.get(sys, {})
	if target == "sun":
		for k in fields:
			sysd[k] = fields[k]
		systems[sys] = sysd
		DataManager.systems = systems
		_dirty = true
		return
	var pois: Array = sysd.get("pois", [])
	for i in pois.size():
		var poi: Dictionary = pois[i]
		if str(poi.get("id", "")) == target:
			for k in fields:
				poi[k] = fields[k]
			pois[i] = poi
			sysd["pois"] = pois
			systems[sys] = sysd
			DataManager.systems = systems
			_dirty = true
			return


func _add_poi(kind: String) -> void:
	var k: Dictionary = KINDS[kind]
	var systems: Dictionary = DataManager.systems
	var sys := str(GameManager.current_system)
	var sysd: Dictionary = systems.get(sys, {})
	var pois: Array = sysd.get("pois", [])
	var n := 0
	for p in pois:
		if _kind_of(p) == kind:
			n += 1
	var pid := "%s_%d" % [kind, Time.get_ticks_msec()]
	var poi := {
		"id": pid, "name": "%s %d" % [k["label"], n + 1],
		"type": k["type"], "kind": kind,
		"interaction": "land" if k["land"] else "talk",
		"ref": (LAND_SCENES[0] if k["land"] else DIALOGUES[0]),
		"description": "placed in-game", "event_id": "",
		"orbit_dist": RING_RADII[2] * 12.0, "orbit_angle": float(n) * 47.0,
		"sprite": "", "visual_scale": 1.0, "anim_frames": 1, "anim_fps": 0.0,
		"sprite_cols": 1, "sprite_rows": 1, "gravity_radius": 0,
	}
	if kind == "planet":
		poi["tint"] = PLANET_TINTS[n % PLANET_TINTS.size()]
	pois.append(poi)
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	_selected_id = pid
	_dirty = true
	_refresh()
	_set_status("added %s — drag to position, then Save" % kind)


func _delete_poi(pid: String) -> void:
	var systems: Dictionary = DataManager.systems
	var sys := str(GameManager.current_system)
	var sysd: Dictionary = systems.get(sys, {})
	var pois: Array = sysd.get("pois", [])
	for i in range(pois.size() - 1, -1, -1):
		if str((pois[i] as Dictionary).get("id", "")) == pid:
			pois.remove_at(i)
			break
	sysd["pois"] = pois
	systems[sys] = sysd
	DataManager.systems = systems
	if _selected_id == pid:
		_selected_id = ""
	_dirty = true
	_refresh()
	_set_status("deleted '%s' (unsaved)" % pid)


func _save() -> void:
	if SystemIO.save(_pack_id(), DataManager.systems):
		_dirty = false
		var spawn: Variant = _host.get("_spawn")
		if spawn != null and is_instance_valid(spawn):
			spawn.clear_pois()
			spawn.spawn_system_pois(str(GameManager.current_system))
		_set_status("saved systems to '%s'" % _pack_id())
	else:
		_set_status("save failed", true)


func _pack_id() -> String:
	if MvPackLoader.current_pack != null:
		return str(MvPackLoader.current_pack.pack_id)
	if not str(PlanetaryInterface.pending_pack_id).is_empty():
		return str(PlanetaryInterface.pending_pack_id)
	return "demo"


# ── HUD build ──────────────────────────────────────────────────────────────────

func _build_hud() -> void:
	if _hud == null:
		_hud = CanvasLayer.new()
		_hud.layer = 130
		_hud.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_hud)
	for c in _hud.get_children():
		c.queue_free()
	_imp_tex = null
	_imp_preview = null

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = NebulaTheme.theme()
	_hud.add_child(root)

	# Dim space backdrop behind everything.
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.07, 0.62)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Center schematic field (bottom of the z-order; panels sit on top).
	_field = Control.new()
	_field.set_anchors_preset(Control.PRESET_FULL_RECT)
	_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_field.draw.connect(_draw_field)
	_field.gui_input.connect(_on_field_input)
	root.add_child(_field)

	_build_toolbar(root)
	_build_left(root)
	_build_right(root)
	_build_bottom(root)
	_recompute_field_metrics()
	_field.queue_redraw()


func _recompute_field_metrics() -> void:
	var vp := _field.size if _field != null else Vector2(1920, 1080)
	if vp == Vector2.ZERO:
		vp = get_viewport().get_visible_rect().size
	var left_w := 300.0
	var right_w := 298.0
	var top := 58.0
	_field_center = Vector2(left_w + (vp.x - left_w - right_w) * 0.5, top + (vp.y - top) * 0.5)
	# Fit the largest ring into the available vertical half-span.
	var avail := minf((vp.x - left_w - right_w) * 0.5, (vp.y - top) * 0.5) - 60.0
	_ring_scale = clampf(avail / RING_RADII[RING_RADII.size() - 1], 0.4, 3.0)


func _build_toolbar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	bar.offset_left = 0
	bar.offset_top = 0
	bar.offset_right = 0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.114, 0.165, 0.212, 0.95)
	box.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.18)
	box.border_width_bottom = 2
	box.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", box)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	row.add_child(NebulaTheme.title_label("Map Editor"))
	for kind in KIND_ORDER:
		var b := NebulaUi.button("＋ " + str(KINDS[kind]["label"]), "ghost")
		b.pressed.connect(_add_poi.bind(kind))
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


func _build_left(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 58
	panel.offset_left = 0
	panel.offset_right = 300
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.039, 0.059, 0.086, 0.74)
	box.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.16)
	box.border_width_right = 2
	box.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", box)
	root.add_child(panel)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 0)
	panel.add_child(_left)
	_rebuild_left()


func _rebuild_left() -> void:
	if _left == null:
		return
	for c in _left.get_children():
		c.queue_free()
	# Header.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 14)
	mc.add_theme_constant_override("margin_top", 12)
	mc.add_theme_constant_override("margin_bottom", 6)
	mc.add_child(head)
	var h := Label.new()
	h.text = "BODIES"
	h.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	head.add_child(h)
	var sub := Label.new()
	sub.text = "Pick a body, then set its spritesheet below"
	sub.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	sub.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	head.add_child(sub)
	_left.add_child(mc)

	# Scrollable body list.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lm := MarginContainer.new()
	lm.add_theme_constant_override("margin_left", 12)
	lm.add_theme_constant_override("margin_right", 12)
	lm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lm.add_child(list)
	scroll.add_child(lm)

	list.add_child(_body_row("sun", "%s" % str(_system().get("name", "Star")), "Star", Color("#ffd84a"), _sun_summary()))
	for p in _pois():
		var poi: Dictionary = p
		var kind := _kind_of(poi)
		list.add_child(_body_row(str(poi.get("id", "")), str(poi.get("name", "?")),
			str(KINDS.get(kind, {"label": "POI"})["label"]), _accent_of(poi), _poi_summary(poi)))

	# Sprite importer for the selected body.
	if not _selected_id.is_empty():
		_left.add_child(_build_sprite_importer())


func _body_row(id: String, name: String, kind_label: String, accent: Color, summary: String) -> Control:
	var sel := id == _selected_id
	var btn := Button.new()
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 52)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.247, 0.827, 1.0, 0.10) if sel else Color(1, 1, 1, 0.015)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.247, 0.827, 1.0, 0.5) if sel else Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.12)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.add_child(hb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	var nm := Label.new()
	nm.text = name
	nm.add_theme_color_override("font_color", NebulaTheme.C_BODY if not sel else NebulaTheme.C_TITLE)
	top.add_child(nm)
	var tag := Label.new()
	tag.text = kind_label.to_upper()
	tag.add_theme_color_override("font_color", accent)
	tag.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	top.add_child(tag)
	vb.add_child(top)
	var sm := Label.new()
	sm.text = summary
	sm.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	sm.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(sm)
	btn.pressed.connect(func() -> void:
		_selected_id = id
		_imp_frame = 0
		_imp_tex = null
		_refresh())
	return btn


func _sun_summary() -> String:
	var s := _system()
	return _sheet_summary(str(s.get("star_sprite", "")), int(s.get("star_anim_frames", 1)),
		int(s.get("star_sprite_cols", 1)), int(s.get("star_sprite_rows", 1)), int(s.get("star_anim_fps", 0)))


func _poi_summary(poi: Dictionary) -> String:
	return _sheet_summary(str(poi.get("sprite", "")), int(poi.get("anim_frames", 1)),
		int(poi.get("sprite_cols", 1)), int(poi.get("sprite_rows", 1)), int(poi.get("anim_fps", 0)))


func _sheet_summary(path: String, frames: int, cols: int, rows: int, fps: int) -> String:
	if path.is_empty():
		return "— no sprite —"
	return "%df · %d×%d · %dfps" % [maxi(1, frames), maxi(1, cols), maxi(1, rows), fps]


# ── sprite importer ────────────────────────────────────────────────────────────

var _imp_preview: Control = null

func _build_sprite_importer() -> Control:
	var wrap := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.031, 0.047, 0.071, 0.55)
	box.border_color = Color(NebulaTheme.C_BORDER.r, NebulaTheme.C_BORDER.g, NebulaTheme.C_BORDER.b, 0.16)
	box.border_width_top = 2
	box.set_content_margin_all(12)
	wrap.add_theme_stylebox_override("panel", box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	wrap.add_child(vb)

	var title := Label.new()
	title.text = "SPRITE SHEET"
	title.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	vb.add_child(title)

	var browse := NebulaUi.button("⬆ Browse PNG…", "primary")
	browse.pressed.connect(_open_sprite_dialog)
	vb.add_child(browse)

	var body := _selected_body()
	var path := _body_sprite_path(body)
	var name_lbl := Label.new()
	name_lbl.text = path.get_file() if not path.is_empty() else "no file chosen"
	name_lbl.add_theme_color_override("font_color", NebulaTheme.C_BODY if not path.is_empty() else NebulaTheme.C_DIM)
	name_lbl.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	name_lbl.clip_text = true
	vb.add_child(name_lbl)

	if path.is_empty():
		var hint := Label.new()
		hint.text = "Browse a PNG spritesheet, then set its columns, rows and FPS."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		hint.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
		vb.add_child(hint)
		return wrap

	_imp_tex = _load_tex(path)
	# Animated preview pane.
	_imp_preview = Control.new()
	_imp_preview.custom_minimum_size = Vector2(0, 64)
	_imp_preview.draw.connect(_draw_importer_preview)
	vb.add_child(_imp_preview)

	# cols / rows / frames / fps spinners
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 7)
	vb.add_child(grid)
	grid.add_child(_num_field("COLUMNS", int(_imp_get(body, "cols")), 1, 64, func(v): _set_sprite(body, "cols", v)))
	grid.add_child(_num_field("ROWS", int(_imp_get(body, "rows")), 1, 64, func(v): _set_sprite(body, "rows", v)))
	grid.add_child(_num_field("FRAMES", int(_imp_get(body, "frames")), 1, 4096, func(v): _set_sprite(body, "frames", v)))
	grid.add_child(_num_field("FPS", int(_imp_get(body, "fps")), 0, 60, func(v): _set_sprite(body, "fps", v)))

	var note := Label.new()
	note.text = "Runtime renders a single row (cols = frames). Multi-row sheets are stored for later."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	note.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(note)
	return wrap


func _num_field(label: String, value: int, lo: int, hi: int, on_change: Callable) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	l.add_theme_font_size_override("font_size", NebulaTheme.size("hint"))
	vb.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = 1
	sb.value = clampi(value, lo, hi)
	sb.custom_minimum_size = Vector2(110, 0)
	sb.value_changed.connect(func(v: float) -> void: on_change.call(int(v)))
	vb.add_child(sb)
	return vb


# Sprite block is stored on POIs as sprite/anim_frames/anim_fps/sprite_cols/rows,
# and on the star (system) as star_* equivalents.
func _body_sprite_path(body: Dictionary) -> String:
	return str(body.get("star_sprite", "")) if _selected_id == "sun" else str(body.get("sprite", ""))


func _imp_get(body: Dictionary, key: String) -> int:
	var pre := "star_" if _selected_id == "sun" else ""
	match key:
		"cols": return maxi(1, int(body.get(pre + "sprite_cols", 1)))
		"rows": return maxi(1, int(body.get(pre + "sprite_rows", 1)))
		"frames": return maxi(1, int(body.get(pre + "anim_frames", 1)))
		"fps": return int(body.get(pre + "anim_fps", 0))
	return 1


func _set_sprite(_body: Dictionary, key: String, v: int) -> void:
	var body := _selected_body()
	var pre := "star_" if _selected_id == "sun" else ""
	var cols := _imp_get(body, "cols")
	var rows := _imp_get(body, "rows")
	var fields := {}
	match key:
		"cols":
			cols = v
			fields[pre + "sprite_cols"] = v
			fields[pre + "anim_frames"] = v * rows
		"rows":
			rows = v
			fields[pre + "sprite_rows"] = v
			fields[pre + "anim_frames"] = cols * v
		"frames":
			fields[pre + "anim_frames"] = maxi(1, mini(v, cols * rows))
		"fps":
			fields[pre + "anim_fps"] = v
	_commit(fields)
	_imp_frame = 0
	# Refresh the left list summary without rebuilding the importer focus.
	_rebuild_left()


func _open_sprite_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.filters = PackedStringArray(["*.png ; PNG image"])
		_file_dialog.use_native_dialog = true
		_file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		_file_dialog.file_selected.connect(_on_sprite_chosen)
		_hud.add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(900, 600))


func _on_sprite_chosen(src_path: String) -> void:
	var img := Image.new()
	if img.load(src_path) != OK:
		_set_status("could not load PNG", true)
		return
	var w := img.get_width()
	var h := img.get_height()
	# Copy into the pack so it ships with the content.
	var dir := "user://Packs/%s/Sprites" % _pack_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var dest := "%s/%s_%d.png" % [dir, ("star" if _selected_id == "sun" else _selected_id), Time.get_ticks_msec()]
	img.save_png(dest)
	# Default grid guess (square frames -> single row of N).
	var cols := 1
	var rows := 1
	if w >= h:
		cols = maxi(1, int(round(float(w) / float(maxi(h, 1)))))
	else:
		rows = maxi(1, int(round(float(h) / float(maxi(w, 1)))))
	var pre := "star_" if _selected_id == "sun" else ""
	var sprite_key := "star_sprite" if _selected_id == "sun" else "sprite"
	_commit({
		sprite_key: dest,
		pre + "sprite_cols": cols, pre + "sprite_rows": rows,
		pre + "anim_frames": cols * rows, pre + "anim_fps": (6 if _selected_id == "sun" else 8),
	})
	_imp_frame = 0
	_set_status("imported %s (%d×%d)" % [dest.get_file(), w, h])
	_refresh()


func _draw_importer_preview() -> void:
	if _imp_preview == null or _imp_tex == null:
		return
	var body := _selected_body()
	var cols: int = maxi(1, _imp_get(body, "cols"))
	var rows: int = maxi(1, _imp_get(body, "rows"))
	var tex_size := _imp_tex.get_size()
	var fw := tex_size.x / float(cols)
	var fh := tex_size.y / float(rows)
	var frame := _imp_frame % maxi(1, cols * rows)
	var fc := frame % cols
	var fr := int(floor(float(frame) / float(cols)))
	var src := Rect2(fc * fw, fr * fh, fw, fh)
	var box := Rect2(Vector2(0, 0), _imp_preview.size)
	# Checker backdrop.
	_imp_preview.draw_rect(box, Color(0.055, 0.086, 0.125))
	var scale := minf(box.size.y / maxf(fh, 1.0), box.size.x / maxf(fw, 1.0))
	var dsz := Vector2(fw, fh) * scale
	var dpos := box.position + (box.size - dsz) * 0.5
	_imp_preview.draw_texture_rect_region(_imp_tex, Rect2(dpos, dsz), src)


# ── right inspector ────────────────────────────────────────────────────────────

func _build_right(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -298
	panel.offset_right = -18
	panel.offset_top = 76
	panel.offset_bottom = -100
	panel.add_theme_stylebox_override("panel", NebulaTheme.theme().get_stylebox("panel", "PanelContainer"))
	root.add_child(panel)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 12)
	panel.add_child(_right)
	_rebuild_right()


func _rebuild_right() -> void:
	if _right == null:
		return
	for c in _right.get_children():
		c.queue_free()
	if _selected_id == "sun":
		_right.add_child(NebulaUi.section_header("Selected Star"))
		var nm := LineEdit.new()
		nm.text = str(_system().get("name", ""))
		nm.text_changed.connect(func(t): _commit({"name": t}, "sun"); _rebuild_left())
		_right.add_child(NebulaUi.labeled("Name", nm, 80))
		var note := Label.new()
		note.text = "Central star. Set its sprite in the Bodies panel."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		_right.add_child(note)
		return
	var poi := _poi(_selected_id)
	if poi.is_empty():
		var empty := Label.new()
		empty.text = "Click a marker or a body to edit it."
		empty.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		_right.add_child(empty)
		return
	var kind := _kind_of(poi)
	_right.add_child(NebulaUi.section_header("Selected POI"))
	var nm2 := LineEdit.new()
	nm2.text = str(poi.get("name", ""))
	nm2.text_changed.connect(func(t): _commit({"name": t}); _rebuild_left())
	_right.add_child(NebulaUi.labeled("Name", nm2, 80))

	var kind_lbl := Label.new()
	kind_lbl.text = "KIND   %s  (read-only)" % str(KINDS.get(kind, {"label": kind})["label"]).to_upper()
	kind_lbl.add_theme_color_override("font_color", _accent_of(poi))
	_right.add_child(kind_lbl)

	# Interaction segmented (Land / Dialogue).
	_right.add_child(_interaction_seg(poi))

	# Reference picker swaps with interaction.
	var is_land := str(poi.get("interaction", "land")) == "land"
	var ref_opt := OptionButton.new()
	var opts: Array = LAND_SCENES if is_land else DIALOGUES
	var cur := str(poi.get("ref", ""))
	for i in opts.size():
		ref_opt.add_item(str(opts[i]))
		if str(opts[i]) == cur:
			ref_opt.select(i)
	ref_opt.item_selected.connect(func(i: int): _commit({"ref": str(opts[i])}))
	_right.add_child(NebulaUi.labeled("Landing scene" if is_land else "Dialogue", ref_opt, 110))

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	stats.add_child(_stat_well("ORBIT", "%du" % int(round(float(poi.get("orbit_dist", 0)) / 12.0))))
	var ang := int(round(float(poi.get("orbit_angle", 0))))
	stats.add_child(_stat_well("BEARING", "%d°" % (((ang % 360) + 360) % 360)))
	_right.add_child(stats)

	var del := NebulaUi.button("Delete POI", "gold")
	del.pressed.connect(func(): _delete_poi(_selected_id))
	_right.add_child(del)


func _interaction_seg(poi: Dictionary) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	var cur := str(poi.get("interaction", "land"))
	for entry in [["land", "◎ Land", C_LAND], ["talk", "◌ Dialogue", C_TALK]]:
		var v := str(entry[0])
		var b := Button.new()
		b.text = str(entry[1])
		b.toggle_mode = true
		b.button_pressed = cur == v
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var col: Color = entry[2]
		var on := StyleBoxFlat.new()
		on.bg_color = col
		on.set_corner_radius_all(999)
		on.set_content_margin_all(8)
		var off := StyleBoxFlat.new()
		off.bg_color = Color(0.04, 0.06, 0.086, 0.6)
		off.set_corner_radius_all(999)
		off.set_content_margin_all(8)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_color_override("font_color", NebulaTheme.C_DIM)
		b.add_theme_color_override("font_pressed_color", NebulaTheme.C_INK)
		if cur == v:
			b.add_theme_stylebox_override("normal", on)
			b.add_theme_color_override("font_color", NebulaTheme.C_INK)
		b.pressed.connect(func() -> void:
			_commit({"interaction": v, "ref": (LAND_SCENES[0] if v == "land" else DIALOGUES[0])})
			_rebuild_right()
			_rebuild_left()
			_field.queue_redraw())
		hb.add_child(b)
	return NebulaUi.labeled("Interaction", hb, 0)


func _stat_well(label: String, value: String) -> Control:
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


func _build_bottom(root: Control) -> void:
	var pill := PanelContainer.new()
	pill.anchor_top = 1.0
	pill.anchor_bottom = 1.0
	pill.offset_left = 316
	pill.offset_top = -44
	pill.offset_bottom = -12
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.031, 0.047, 0.071, 0.84)
	box.set_corner_radius_all(16)
	box.set_content_margin_all(8)
	box.set_border_width_all(1)
	box.border_color = Color(0.247, 0.827, 1.0, 0.28)
	pill.add_theme_stylebox_override("panel", box)
	root.add_child(pill)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pill.add_child(hb)
	var count := Label.new()
	count.text = "%d POIs" % _pois().size()
	count.add_theme_color_override("font_color", NebulaTheme.C_TITLE)
	hb.add_child(count)
	var hint := Label.new()
	hint.text = "Drag·move   Click·select   RMB·delete   Save·write"
	hint.add_theme_color_override("font_color", NebulaTheme.C_DIM)
	hb.add_child(hint)
	_status = Label.new()
	_status.add_theme_color_override("font_color", NebulaTheme.C_ACCENT)
	hb.add_child(_status)


func _refresh() -> void:
	_rebuild_left()
	_rebuild_right()
	if _field != null:
		_field.queue_redraw()


func _set_status(msg: String, is_err := false) -> void:
	if _status != null:
		_status.text = msg
		_status.add_theme_color_override("font_color", NebulaTheme.C_ERROR if is_err else NebulaTheme.C_ACCENT)


# ── center schematic field ─────────────────────────────────────────────────────

func _poi_screen(poi: Dictionary) -> Vector2:
	var r := float(poi.get("orbit_dist", 0)) / 12.0 * _ring_scale
	var a := deg_to_rad(float(poi.get("orbit_angle", 0)))
	return _field_center + Vector2(cos(a), sin(a)) * r


func _draw_field() -> void:
	if not _active:
		return
	_recompute_field_metrics()
	var ci := _field
	# Orbit rings.
	for rr in RING_RADII:
		ci.draw_arc(_field_center, rr * _ring_scale, 0, TAU, 96, Color(0.5, 0.608, 0.627, 0.16), 1.0)
	# Selected POI orbit guide.
	var selp := _poi(_selected_id) if (_selected_id != "" and _selected_id != "sun") else {}
	if not selp.is_empty():
		var acc := _accent_of(selp)
		ci.draw_arc(_field_center, float(selp.get("orbit_dist", 0)) / 12.0 * _ring_scale, 0, TAU, 96, Color(acc.r, acc.g, acc.b, 0.5), 1.6)
	# Star.
	var star_sel := _selected_id == "sun"
	ci.draw_circle(_field_center, 30.0, Color(1.0, 0.8, 0.2, 0.22))
	ci.draw_circle(_field_center, 18.0, Color(1.0, 0.85, 0.35))
	if star_sel:
		ci.draw_arc(_field_center, 24.0, 0, TAU, 48, Color("#ffd84a"), 2.0)
	_draw_label(ci, str(_system().get("name", "Star")), _field_center + Vector2(0, 34), Color("#ffd84a"))
	# POIs.
	for p in _pois():
		var poi: Dictionary = p
		var pos := _poi_screen(poi)
		var kind := _kind_of(poi)
		var sel := str(poi.get("id", "")) == _selected_id
		var land := str(poi.get("interaction", "land")) == "land"
		var acc := _accent_of(poi)
		if land:
			_draw_reticle(ci, pos, 26.0, acc)
		match kind:
			"planet":
				var tint := Color(str(poi.get("tint", "#7fb4ff")))
				ci.draw_circle(pos, 17.0, tint)
				ci.draw_circle(pos, 17.0, Color(0, 0, 0, 0.0))
				ci.draw_arc(pos, 17.0, 0, TAU, 32, tint.lightened(0.3), 1.5)
			"station":
				_draw_badge(ci, pos, KINDS["station"]["color"])
				var c := KINDS["station"]["color"] as Color
				ci.draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), Color(c.r, c.g, c.b, 0.0), false, 1.6)
				ci.draw_rect(Rect2(pos - Vector2(6, 6), Vector2(12, 12)), c, false, 1.6)
				ci.draw_circle(pos, 2.0, c)
			_:
				_draw_badge(ci, pos, C_TALK)
				ci.draw_arc(pos, 8.0, PI * 0.15, PI * 1.6, 16, C_TALK, 1.6)
		if sel:
			ci.draw_arc(pos, 22.0, 0, TAU, 40, Color("#ffd84a"), 2.0)
		_draw_label(ci, str(poi.get("name", "")), pos + Vector2(0, 26), NebulaTheme.C_BODY if not sel else Color("#ffd84a"))


func _draw_badge(ci: CanvasItem, pos: Vector2, accent: Color) -> void:
	ci.draw_circle(pos, 16.0, Color(0.086, 0.122, 0.165))
	ci.draw_arc(pos, 16.0, 0, TAU, 28, Color(accent.r, accent.g, accent.b, 0.5), 1.4)


func _draw_reticle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var h := s
	var corner := s * 0.4
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cn := c + Vector2(sx * h, sy * h)
			ci.draw_line(cn, cn - Vector2(sx * corner, 0), col, 1.4)
			ci.draw_line(cn, cn - Vector2(0, sy * corner), col, 1.4)


func _draw_label(ci: CanvasItem, text: String, pos: Vector2, col: Color) -> void:
	var f := NebulaTheme.font()
	if f == null:
		f = ThemeDB.fallback_font
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	ci.draw_string(f, pos + Vector2(-w * 0.5 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.8))
	ci.draw_string(f, pos + Vector2(-w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _hit_poi(local: Vector2) -> String:
	var best := ""
	var best_d := 28.0
	if _field_center.distance_to(local) <= 26.0:
		return "sun"
	for p in _pois():
		var poi: Dictionary = p
		var d := _poi_screen(poi).distance_to(local)
		if d <= best_d:
			best_d = d
			best = str(poi.get("id", ""))
	return best


func _on_field_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var local := _field.get_local_mouse_position()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var hit := _hit_poi(local)
				_selected_id = hit
				_dragging = hit != "" and hit != "sun"
				_imp_tex = null
				_imp_frame = 0
				_refresh()
			else:
				_dragging = false
			_field.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var hit2 := _hit_poi(local)
			if hit2 != "" and hit2 != "sun":
				_delete_poi(hit2)
			_field.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var local2 := _field.get_local_mouse_position()
		var rel := local2 - _field_center
		var r_units := clampf(rel.length() / maxf(_ring_scale, 0.01) * 12.0, 720.0, 4320.0)
		_commit({"orbit_dist": r_units, "orbit_angle": rad_to_deg(rel.angle())})
		_field.queue_redraw()
		_field.accept_event()


func _load_tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var loaded: Variant = load(path) if ResourceLoader.exists(path) else null
	if loaded is Texture2D:
		return loaded
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)

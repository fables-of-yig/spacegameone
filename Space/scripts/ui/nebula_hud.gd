class_name NebulaHud
extends RefCounted

# Immediate-mode renderer for the Nebula runtime HUD, ported 1:1 from the
# Claude Design handoff (design_handoff_ui_overlays: TankGauge, SpellBar/
# WeaponBar, Minimap). Both game HUDs already draw in immediate mode, so the
# components live here as static draw_*() calls that take the caller's
# CanvasItem `ci` and draw from its _draw(). Godot has no box-shadow /
# conic-gradient, so glows are layered translucent outlines and the cooldown
# sweep is a polygon wedge — the recipe the existing HUDs already use.
#
# Spec + decided caps live in memory: reference_nebula_hud_spec.

# --- tank tones (exact rgba from TankGauge TONES) ------------------------------
const TONES := {
	"energy":  {  # HP / Hull — red
		"glow": Color(1.0, 0.353, 0.157, 0.85), "ring": Color(1.0, 0.353, 0.157),
		"lit": Color(1.0, 0.353, 0.157, 0.16), "fill": Color(1.0, 0.353, 0.157, 0.5),
		"fill_strong": Color(1.0, 0.471, 0.235, 0.85)},
	"magic":   {  # Energy / mana — cyan
		"glow": Color(0.247, 0.827, 1.0, 0.85), "ring": Color(0.247, 0.827, 1.0),
		"lit": Color(0.247, 0.827, 1.0, 0.16), "fill": Color(0.247, 0.827, 1.0, 0.5),
		"fill_strong": Color(0.471, 0.941, 1.0, 0.85)},
	"crystal": {  # danger — purple
		"glow": Color(0.482, 0.247, 0.831, 0.9), "ring": Color(0.604, 0.361, 1.0),
		"lit": Color(0.482, 0.247, 0.831, 0.2), "fill": Color(0.482, 0.247, 0.831, 0.55),
		"fill_strong": Color(0.690, 0.482, 1.0, 0.95)},
	"shield":  {  # shields — green
		"glow": Color(0.365, 0.839, 0.173, 0.85), "ring": Color(0.365, 0.839, 0.173),
		"lit": Color(0.365, 0.839, 0.173, 0.16), "fill": Color(0.365, 0.839, 0.173, 0.5),
		"fill_strong": Color(0.588, 0.941, 0.353, 0.9)},
	"gold":    {  # generic
		"glow": Color(1.0, 0.8, 0.2, 0.85), "ring": Color(1.0, 0.8, 0.2),
		"lit": Color(1.0, 0.8, 0.2, 0.16), "fill": Color(1.0, 0.8, 0.2, 0.5),
		"fill_strong": Color(1.0, 0.878, 0.471, 0.9)},
}

# --- surface / text tokens -----------------------------------------------------
const C_SLOT := Color(0.039, 0.055, 0.071)      # recessed pip/slot fill
const C_STEEL := Color(0.243, 0.329, 0.345)     # #3e5458 steel-700 (empty ring)
const C_STEEL_HI := Color(0.812, 0.878, 0.890)  # #cfe0e3 bevel highlight
const C_FRAME := Color(0.306, 0.404, 0.424)     # #4e676c steel-600 frame
const C_TEXT_BRIGHT := Color(0.918, 0.965, 1.0) # #eaf6ff
const C_TEXT_DIM := Color(0.435, 0.525, 0.580)  # #6f8694
const C_TEXT_CYAN := Color(0.447, 1.0, 0.973)   # #72fff8
const C_INK := Color(0.012, 0.133, 0.169)       # #03222b on-cyan ink
const C_GOLD := Color(1.0, 0.847, 0.290)        # #ffd84a
const C_RED := Color(1.0, 0.353, 0.290)         # #ff5a4a
const C_ACCENT := Color(0.247, 0.827, 1.0)      # #3fd3ff
const C_MAP_BG := Color(0.020, 0.031, 0.047)    # grid well

# Font sizes (design tokens, 1080p px — the game renders native so they apply 1:1).
const FS_LABEL := 13
const FS_VALUE := 15
const FS_SMALL := 11
const FS_DIM := 11
const FS_KEY := 11
const FS_AMMO := 12

const PIP_GAP := 5.0
const HEAD_GAP := 6.0

static var _icon_cache: Dictionary = {}


static func font() -> Font:
	var f: Font = NebulaTheme.font()
	return f if f != null else ThemeDB.fallback_font


static func icon(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if _icon_cache.has(name):
		return _icon_cache[name]
	var path := "res://Assets/UI/nebula/hud/%s.png" % name
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_icon_cache[name] = tex
	return tex


# --- low-level rounded rect + glow --------------------------------------------

static func _rrect(ci: CanvasItem, rect: Rect2, bg: Color, border_col: Color, border_w: float, radius: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0.0:
		sb.border_color = border_col
		sb.set_border_width_all(int(border_w))
	ci.draw_style_box(sb, rect)


static func _glow(ci: CanvasItem, rect: Rect2, color: Color, radius: int, layers := 3) -> void:
	for i in layers:
		var g := float(i + 1) * 2.0
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_corner_radius_all(radius + int(g))
		sb.border_color = Color(color.r, color.g, color.b, maxf(0.0, color.a * (0.22 - i * 0.06)))
		sb.set_border_width_all(2)
		ci.draw_style_box(sb, rect.grow(g))


# --- tank gauge ----------------------------------------------------------------
# opts: label:String, value:int, max:int, total:int (tank count), tone:String,
#       danger_tone:String="", danger_at:float=0.2, per_row:int=7, size:float=30,
#       low_at:float=1, glyph:String ("hp"/"bolt"/"shield"/"")
# Returns the Vector2 block size drawn (so the caller can place the next gauge).
static func draw_tank_gauge(ci: CanvasItem, origin: Vector2, opts: Dictionary) -> Vector2:
	var f := font()
	var label := str(opts.get("label", ""))
	var value := int(opts.get("value", 0))
	var maxv := int(opts.get("max", 100))
	var total := maxi(1, int(opts.get("total", 1)))
	var tone_name := str(opts.get("tone", "energy"))
	var danger_tone := str(opts.get("danger_tone", ""))
	var danger_at := float(opts.get("danger_at", 0.2))
	var per_row := maxi(1, int(opts.get("per_row", 7)))
	var pip := float(opts.get("size", 30.0))
	var low_at := float(opts.get("low_at", 1.0))
	var glyph := str(opts.get("glyph", ""))

	var filled := float(value) / 100.0
	var ratio := filled / float(total)
	var danger: bool = danger_tone != "" and filled > 0.0 and ratio < danger_at
	var t: Dictionary = TONES.get(danger_tone if danger else tone_name, TONES["energy"])
	var cols := mini(per_row, total)
	var rows := int(ceil(float(total) / float(cols)))
	var full_count := int(floor(filled + 1e-6))
	var frac := clampf(filled - float(full_count), 0.0, 1.0)
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 0.9) < 0.45

	# Head: label + value / max.
	var head_h := float(FS_VALUE) + 4.0
	var lx := origin.x
	var ly := origin.y + float(FS_LABEL)
	ci.draw_string(f, Vector2(lx, ly), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_LABEL, C_TEXT_CYAN)
	var label_w := f.get_string_size(label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_LABEL).x
	var vstr := "%d" % value
	var vx := lx + label_w + 10.0
	ci.draw_string(f, Vector2(vx, ly), vstr, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_VALUE, C_TEXT_BRIGHT)
	var vw := f.get_string_size(vstr, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_VALUE).x
	ci.draw_string(f, Vector2(vx + vw + 4.0, ly), "/ %d" % maxv, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, C_TEXT_DIM)

	# Pips.
	var py0 := origin.y + head_h + HEAD_GAP
	for i in total:
		var col := i % cols
		var row := int(floor(float(i) / float(cols)))
		var px := origin.x + float(col) * (pip + PIP_GAP)
		var py := py0 + float(row) * (pip + PIP_GAP)
		var rect := Rect2(px, py, pip, pip)
		var is_full := i < full_count
		var is_partial := i == full_count and frac > 0.001
		var low: bool = is_full and filled <= low_at

		if is_full:
			var bg := C_SLOT.lerp(t["lit"], 0.6)
			if low and not blink:
				bg = bg.darkened(0.4)
			_glow(ci, rect, t["glow"], 5)
			_rrect(ci, rect, bg, t["ring"], 2.0, 5)
		else:
			_rrect(ci, rect, C_SLOT, C_STEEL, 2.0, 5)

		if is_partial:
			var inner := rect.grow(-2.0)
			var fh := inner.size.y * frac
			var fill_rect := Rect2(inner.position.x, inner.position.y + inner.size.y - fh, inner.size.x, fh)
			_rrect(ci, fill_rect, t["fill_strong"], Color(0, 0, 0, 0), 0.0, 3)
			ci.draw_rect(Rect2(fill_rect.position, Vector2(fill_rect.size.x, 1.5)),
				Color(t["fill_strong"].r, t["fill_strong"].g, t["fill_strong"].b, 0.9))

		# Pip glyph icon (vector — no pack art for HP/bolt at this size).
		if glyph != "":
			var op := 0.22
			if is_full:
				op = 1.0
			elif is_partial:
				op = 0.4 + 0.6 * frac
			_draw_glyph(ci, rect.get_center(), pip * 0.5, glyph, Color(t["ring"].r, t["ring"].g, t["ring"].b, op))

	var pips_w := float(cols) * pip + float(cols - 1) * PIP_GAP
	var pips_h := float(rows) * pip + float(rows - 1) * PIP_GAP
	var head_w := label_w + 10.0 + vw + 4.0 + f.get_string_size("/ %d" % maxv, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL).x
	return Vector2(maxf(pips_w, head_w), head_h + HEAD_GAP + pips_h)


static func _draw_glyph(ci: CanvasItem, c: Vector2, sz: float, kind: String, col: Color) -> void:
	match kind:
		"hp":
			var aw := sz * 0.30
			var al := sz * 0.92
			ci.draw_rect(Rect2(c.x - aw * 0.5, c.y - al * 0.5, aw, al), col)
			ci.draw_rect(Rect2(c.x - al * 0.5, c.y - aw * 0.5, al, aw), col)
		"bolt":
			var pts := PackedVector2Array([
				c + Vector2(sz * 0.10, -sz * 0.55),
				c + Vector2(-sz * 0.30, sz * 0.10),
				c + Vector2(-sz * 0.02, sz * 0.10),
				c + Vector2(-sz * 0.10, sz * 0.55),
				c + Vector2(sz * 0.32, -sz * 0.12),
				c + Vector2(sz * 0.04, -sz * 0.12),
			])
			ci.draw_colored_polygon(pts, col)
		"shield":
			var pts2 := PackedVector2Array([
				c + Vector2(-sz * 0.5, -sz * 0.42),
				c + Vector2(sz * 0.5, -sz * 0.42),
				c + Vector2(sz * 0.5, sz * 0.05),
				c + Vector2(0.0, sz * 0.55),
				c + Vector2(-sz * 0.5, sz * 0.05),
			])
			ci.draw_colored_polygon(pts2, col)
		_:
			ci.draw_circle(c, sz * 0.4, col)


# --- ability bar (spells / weapons) -------------------------------------------
# title: centered dim caption ("SPELLS"/"WEAPONS").
# slots: Array of {key:String, tex:Texture2D, glow:Color, cd:float (0..1 remaining),
#         selected:bool, ammo:int (-1 = none/∞), ammo_max:int (-1 = infinite)}
# slot_px: 54 spells / 52 weapons. show_ammo: draw the ammo readout row.
# Anchored so the row is centered on center_x with its top at top_y.
static func draw_ability_bar(ci: CanvasItem, center_x: float, top_y: float, title: String, slots: Array, slot_px: float, show_ammo: bool) -> void:
	var f := font()
	var gap := 10.0
	var n := slots.size()
	if n <= 0:
		return
	# Title.
	var tw := f.get_string_size(title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_DIM).x
	ci.draw_string(f, Vector2(center_x - tw * 0.5, top_y + float(FS_DIM)), title.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, FS_DIM, C_TEXT_DIM)
	var row_w := float(n) * slot_px + float(n - 1) * gap
	var sx := center_x - row_w * 0.5
	var sy := top_y + float(FS_DIM) + 8.0
	for i in n:
		var s: Dictionary = slots[i]
		var x := sx + float(i) * (slot_px + gap)
		_draw_ability_slot(ci, Rect2(x, sy, slot_px, slot_px), s)
		var below := sy + slot_px + 3.0
		if show_ammo and s.has("ammo_max"):
			var ammo := int(s.get("ammo", -1))
			var ammo_max := int(s.get("ammo_max", -1))
			var astr := "∞"
			var acol := C_TEXT_CYAN
			if ammo_max >= 0:
				astr = "%d / %d" % [ammo, ammo_max]
				if ammo <= 0:
					acol = C_RED
				elif ammo <= int(float(ammo_max) * 0.25):
					acol = C_GOLD
				else:
					acol = C_TEXT_BRIGHT
			var aw := f.get_string_size(astr, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_AMMO).x
			below += float(FS_AMMO)
			ci.draw_string(f, Vector2(x + slot_px * 0.5 - aw * 0.5, below), astr, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_AMMO, acol)
			below += 4.0
		# Optional name caption (the weapon roster keeps its names; spells omit it).
		if s.has("name"):
			var nm := str(s["name"]).to_upper()
			var nw := minf(f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL).x, slot_px + gap)
			below += float(FS_SMALL)
			ci.draw_string(f, Vector2(x + slot_px * 0.5 - nw * 0.5, below), nm, HORIZONTAL_ALIGNMENT_LEFT, int(slot_px + gap), FS_SMALL, C_TEXT_DIM)


static func _draw_ability_slot(ci: CanvasItem, rect: Rect2, s: Dictionary) -> void:
	var selected := bool(s.get("selected", false))
	var cd := clampf(float(s.get("cd", 0.0)), 0.0, 1.0)
	var ready := cd <= 0.001
	var out := int(s.get("ammo_max", -1)) >= 0 and int(s.get("ammo", -1)) <= 0
	var glow: Color = s.get("glow", C_ACCENT)
	# Steel frame.
	if selected:
		_glow(ci, rect, C_ACCENT, 10)
	_rrect(ci, rect, C_FRAME, C_STEEL_HI, 1.0, 10)
	ci.draw_rect(Rect2(rect.position + Vector2(3, 2), Vector2(rect.size.x - 6, 1.5)), Color(C_STEEL_HI.r, C_STEEL_HI.g, C_STEEL_HI.b, 0.5))
	# Recessed inner slot.
	var inner := rect.grow(-4.0)
	_rrect(ci, inner, C_SLOT, Color(0, 0, 0, 0.55), 1.0, 7)
	if selected:
		_rrect(ci, rect, Color(0, 0, 0, 0), C_ACCENT, 2.0, 10)
	# Icon.
	var tex: Texture2D = s.get("tex", null)
	if tex != null:
		var isz := inner.size * 0.66
		var ipos := inner.get_center() - isz * 0.5
		var mod := Color(1, 1, 1, 1)
		if out or not ready:
			mod = Color(0.5, 0.52, 0.55, 0.85)
		ci.draw_texture_rect(tex, Rect2(ipos, isz), false, mod)
	# Cooldown wedge (dark, covers cd fraction clockwise from 12 o'clock).
	if not ready:
		var c := inner.get_center()
		var r := inner.size.x * 0.62
		var steps := maxi(2, int(cd * 24.0))
		var pts := PackedVector2Array([c])
		for j in steps + 1:
			var a := -PI * 0.5 + (cd * TAU) * (float(j) / float(steps))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(pts, Color(0.02, 0.031, 0.047, 0.72))
	# Hotkey badge top-left.
	var key := str(s.get("key", ""))
	if key != "":
		var f := font()
		var b := Rect2(rect.position + Vector2(-7, -7), Vector2(18, 18))
		_rrect(ci, b, C_ACCENT, Color(0, 0, 0, 0), 0.0, 5)
		var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, FS_KEY).x
		ci.draw_string(f, b.get_center() + Vector2(-kw * 0.5, float(FS_KEY) * 0.4), key,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FS_KEY, C_INK)


# --- minimap (platformer room grid) -------------------------------------------
# top_right: the top-right corner the map aligns to.
# cells: Array of {col:int, row:int, w:int, h:int, state:String("cur"/"exp"/"unx"), marker:String("item"/"save"/"boss"/"")}
# grid is laid out at `cell` px; returns nothing. Frame + title per Minimap spec.
static func draw_minimap(ci: CanvasItem, top_right: Vector2, cells: Array, cols: int, rows: int, cell: float, title: String, area: String) -> void:
	var f := font()
	var pad := 8.0
	var grid_pad := 4.0
	var head_h := float(FS_SMALL) + 8.0
	var grid_w := float(cols) * cell + grid_pad * 2.0
	var grid_h := float(rows) * cell + grid_pad * 2.0
	var panel_w := grid_w + pad * 2.0
	var panel_h := head_h + grid_h + pad
	var px := top_right.x - panel_w
	var py := top_right.y
	var panel := Rect2(px, py, panel_w, panel_h)
	# Frame.
	_rrect(ci, panel, Color(0.051, 0.078, 0.102, 0.92), C_FRAME, 1.0, 10)
	ci.draw_rect(Rect2(panel.position + Vector2(3, 2), Vector2(panel.size.x - 6, 1.5)), Color(C_STEEL_HI.r, C_STEEL_HI.g, C_STEEL_HI.b, 0.4))
	# Head.
	ci.draw_string(f, Vector2(px + pad, py + pad + float(FS_SMALL)), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FS_SMALL, C_TEXT_CYAN)
	if area != "":
		var aw := f.get_string_size(area, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		ci.draw_string(f, Vector2(px + panel_w - pad - aw, py + pad + float(FS_SMALL)), area, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, C_TEXT_DIM)
	# Grid well.
	var grid := Rect2(px + pad, py + head_h, grid_w, grid_h)
	_rrect(ci, grid, C_MAP_BG, Color(0, 0, 0, 0.6), 1.0, 4)
	var gx := grid.position.x + grid_pad
	var gy := grid.position.y + grid_pad
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	for cell_data in cells:
		var cd2: Dictionary = cell_data
		var cw := maxi(1, int(cd2.get("w", 1)))
		var ch := maxi(1, int(cd2.get("h", 1)))
		var cr := Rect2(gx + float(cd2.get("col", 0)) * cell, gy + float(cd2.get("row", 0)) * cell,
			float(cw) * cell - 2.0, float(ch) * cell - 2.0)
		var state := str(cd2.get("state", "unx"))
		match state:
			"cur":
				_rrect(ci, cr, Color(0.18, 0.78, 0.9).lerp(Color(0.5, 0.94, 1.0), pulse), Color(0.71, 0.99, 1.0), 1.0, 2)
			"exp":
				_rrect(ci, cr, Color(0.106, 0.235, 0.353, 0.7), Color(0.247, 0.827, 1.0, 0.35), 1.0, 2)
			_:
				_rrect(ci, cr, Color(0.176, 0.259, 0.329, 0.35), Color(0.5, 0.608, 0.627, 0.12), 1.0, 2)
		var marker := str(cd2.get("marker", ""))
		if marker != "" and state != "void":
			var mc := cr.get_center()
			match marker:
				"item":
					ci.draw_circle(mc, 2.5, C_GOLD)
				"save":
					ci.draw_circle(mc, 2.5, Color(0.365, 0.839, 0.173))
				"boss":
					ci.draw_colored_polygon(PackedVector2Array([
						mc + Vector2(-3.5, 3.0), mc + Vector2(3.5, 3.0), mc + Vector2(0, -3.5)]), C_RED)

class_name NebulaTheme
extends RefCounted

# Nebula sci-fi game-UI design system, expressed as a scale-aware Godot Theme +
# token palette. Source of truth: nebulous/guidelines/godot/design-tokens.json +
# nine-slice.md (the Claude Design handoff). The in-game authoring overlays
# (DevConsole, MvCombatWorkshop, MvPlayerWizard, MvEditMode) assign theme() to
# their root Control.
#
# SCALE PROFILES — load-bearing. MV runs its UI in a 480x270 content-scale space
# upscaled ~4x to the window (Space/main.gd sets content_scale_size = GAME_VIEWPORT),
# while Space renders UI at full 1080p. The design tokens are specified in 1080p
# screen pixels, so applying them verbatim in MV makes fonts ~4x too big and the
# painted 9-slice frame corners (~56px of art) dwarf a 480-wide panel. So:
#   - "full"    (scale ~1x, Space): painted 9-slice window frames + cyan capsule
#                button textures + token-size fonts. The art at its native size.
#   - "compact" (scale >=1.5x, MV): flat token-driven panels + flat cyan pill
#                buttons + small fonts matching MV's existing HUD convention.
# Same palette/font/brand either way. Overlays must (re)assign theme() at OPEN
# time, not just build time — the active engine (and thus profile) can differ
# between when an overlay is constructed (autoload _ready, in Space) and shown.

# --- Token palette (hex -> Color), referenced directly by the overlays. ---
const C_PANEL_BG := Color("#161f28")
const C_PANEL_ALT := Color("#1d2a36")
const C_PANEL_DARK := Color("#0a0f16")
const C_BORDER := Color("#7f9ba0")
const C_ACCENT := Color("#3fd3ff")
const C_ACCENT_2 := Color("#ffcc33")
const C_ACCENT_PRESS := Color("#04778b")
const C_ACCENT_GLOW := Color("#72fff8")
const C_TITLE := Color("#72fff8")
const C_BODY := Color("#b8ccd6")
const C_DIM := Color("#6f8694")
const C_INK := Color("#03222b")
const C_INK_HOVER := Color("#052b35")
const C_ERROR := Color("#ff5a4a")
const C_SUCCESS := Color("#5dd62c")

const FONT_PATH := "res://Assets/UI/nebula/fonts/RobynBrutalistDigital-Regular.ttf"
const FRAME_LANDSCAPE := "res://Assets/UI/nebula/frames/window-landscape.png"
const FRAME_SETTINGS := "res://Assets/UI/nebula/frames/window-settings.png"
const FRAME_BANNER := "res://Assets/UI/nebula/frames/window-banner.png"
const BTN_CYAN := "res://Assets/UI/nebula/buttons/button-cyan.png"
const BTN_CAPSULE := "res://Assets/UI/nebula/buttons/button-capsule.png"
const ICON_CLOSE := "res://Assets/UI/nebula/icons/close.png"

# Per-profile font sizes (in that profile's UI-coordinate units, so they land at
# a sensible ON-SCREEN size once the engine's content scale is applied).
const SIZES := {
	"full": {"title": 28, "section": 18, "body": 16, "button": 18, "hint": 12},
	"compact": {"title": 14, "section": 11, "body": 9, "button": 10, "hint": 8},
}

static var _themes: Dictionary = {}
static var _font: FontFile = null


# --- Scale detection -----------------------------------------------------------

# Window-to-UI scale factor: how many real pixels one UI unit spans. ~1 in Space,
# ~4 in standalone MV (480x270 design space in a 1080p window).
static func ui_scale() -> float:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root := (ml as SceneTree).root
		if root != null:
			var css := root.content_scale_size
			var rs := root.size
			if css.y > 0 and rs.y > 0:
				return clampf(float(rs.y) / float(css.y), 1.0, 8.0)
	return 1.0


static func profile() -> String:
	return "compact" if ui_scale() >= 1.5 else "full"


static func size(role: String) -> int:
	return int((SIZES[profile()] as Dictionary).get(role, 12))


# --- Theme (one cached Theme per profile) --------------------------------------

static func theme() -> Theme:
	var p := profile()
	if _themes.has(p):
		return _themes[p]
	var t := _build(p)
	_themes[p] = t
	return t


static func font() -> FontFile:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


static func _build(p: String) -> Theme:
	var compact := p == "compact"
	var t := Theme.new()
	var f := font()
	if f != null:
		t.default_font = f
	t.default_font_size = int((SIZES[p] as Dictionary)["body"])

	_apply_panels(t, compact)
	_apply_buttons(t, compact)
	_apply_inputs(t, compact)
	_apply_text(t, p)
	return t


# --- Panels: painted 9-slice at full scale, flat token panel when compact. ------
static func _apply_panels(t: Theme, compact: bool) -> void:
	var box: StyleBox = null
	if compact:
		box = _flat(C_PANEL_BG, C_BORDER, 1, 4, 8)
	else:
		# window-landscape.png 566x364, recommended slice margin T48 R56 B48 L56.
		var win := _tex_box(FRAME_LANDSCAPE, 48, 56, 48, 56)
		if win != null:
			win.content_margin_left = 28.0
			win.content_margin_right = 28.0
			win.content_margin_top = 24.0
			win.content_margin_bottom = 24.0
		box = win if win != null else _flat(C_PANEL_BG, C_BORDER, 1, 8, 12)
	t.set_stylebox("panel", "PanelContainer", box)
	t.set_stylebox("panel", "Panel", box)


# --- Buttons: cyan capsule texture at full scale, flat cyan pill when compact. --
static func _apply_buttons(t: Theme, compact: bool) -> void:
	var normal: StyleBox
	var hover: StyleBox
	var pressed: StyleBox
	var disabled: StyleBox
	var focus: StyleBox
	if compact:
		normal = _pill(C_ACCENT, 6, 3)
		hover = _pill(C_ACCENT_GLOW, 6, 3)
		pressed = _pill(C_ACCENT_PRESS, 6, 3)
		disabled = _pill(C_BORDER.darkened(0.3), 6, 3)
		focus = _pill(C_ACCENT, 6, 3)
		(focus as StyleBoxFlat).set_border_width_all(1)
		(focus as StyleBoxFlat).border_color = C_ACCENT_GLOW
	else:
		var base := _tex_box(BTN_CYAN, 16, 16, 16, 16)
		if base == null:
			normal = _pill(C_ACCENT, 18, 9)
			hover = _pill(C_ACCENT_GLOW, 18, 9)
			pressed = _pill(C_ACCENT_PRESS, 18, 9)
			disabled = _pill(C_BORDER.darkened(0.3), 18, 9)
			focus = normal
		else:
			base.content_margin_left = 18.0
			base.content_margin_right = 18.0
			base.content_margin_top = 9.0
			base.content_margin_bottom = 9.0
			normal = base
			hover = base.duplicate()
			(hover as StyleBoxTexture).modulate_color = Color(1.08, 1.08, 1.08, 1.0)
			pressed = base.duplicate()
			(pressed as StyleBoxTexture).modulate_color = Color(0.9, 0.9, 0.9, 1.0)
			disabled = base.duplicate()
			(disabled as StyleBoxTexture).modulate_color = Color(0.55, 0.6, 0.62, 0.75)
			focus = base.duplicate()
			(focus as StyleBoxTexture).modulate_color = Color(1.04, 1.04, 1.04, 1.0)

	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, C_INK)
		t.set_color("font_hover_color", type, C_INK_HOVER)
		t.set_color("font_pressed_color", type, C_INK)
		t.set_color("font_focus_color", type, C_INK)
		t.set_color("font_disabled_color", type, Color(C_INK.r, C_INK.g, C_INK.b, 0.6))
		t.set_font_size("font_size", type, int((SIZES[profile()] as Dictionary)["button"]))


# --- Inputs: recessed dark slots with a cyan focus ring. -----------------------
static func _apply_inputs(t: Theme, compact: bool) -> void:
	var pad := 4 if compact else 8
	var slot := _slot_box(false, pad)
	var focus := _slot_box(true, pad)
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		t.set_stylebox("normal", type, slot)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("read_only", type, slot)
		t.set_color("font_color", type, C_BODY)
		t.set_color("font_readonly_color", type, C_DIM)
		t.set_color("font_placeholder_color", type, C_DIM)
		t.set_color("caret_color", type, C_ACCENT)
		t.set_color("selection_color", type, Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.3))


# --- Text colors for Labels / rich text. ---------------------------------------
static func _apply_text(t: Theme, p: String) -> void:
	t.set_color("font_color", "Label", C_BODY)
	t.set_color("default_color", "RichTextLabel", C_BODY)
	t.set_color("font_color", "CheckBox", C_BODY)
	t.set_color("font_color", "CheckButton", C_BODY)
	t.set_font_size("font_size", "RichTextLabel", int((SIZES[p] as Dictionary)["body"]))


# --- Builders the overlays reuse for ad-hoc nodes (all scale-aware). -----------

# Lightweight card surface (rule rows, list rows) — flat, not the window frame.
static func card_box(selected := false) -> StyleBoxFlat:
	var pad := 5 if profile() == "compact" else 10
	var b := _flat(C_PANEL_ALT, C_ACCENT if selected else Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.35), 1, 6, pad)
	if selected:
		b.border_width_left = 3
	return b


# Recessed inset well behind lists / logs / previews.
static func well_box() -> StyleBoxFlat:
	var pad := 4 if profile() == "compact" else 8
	return _flat(C_PANEL_DARK, Color(0, 0, 0, 0.55), 1, 6, pad)


# Title label: UPPERCASE cyan-glow heading at the current profile's title size.
static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", C_TITLE)
	l.add_theme_font_size_override("font_size", size("title"))
	var f := font()
	if f != null:
		l.add_theme_font_override("font", f)
	return l


# --- Low-level stylebox builders. ----------------------------------------------

static func _flat(bg: Color, border: Color, border_w: int, radius: int, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(float(pad))
	b.border_color = border
	b.set_border_width_all(border_w)
	return b


static func _pill(bg: Color, pad_h: int, pad_v: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(999)
	b.content_margin_left = float(pad_h)
	b.content_margin_right = float(pad_h)
	b.content_margin_top = float(pad_v)
	b.content_margin_bottom = float(pad_v)
	return b


static func _slot_box(focused: bool, pad: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = C_PANEL_DARK
	b.set_corner_radius_all(4)
	b.set_content_margin_all(float(pad))
	b.border_color = C_ACCENT if focused else C_ACCENT_PRESS
	b.set_border_width_all(2 if focused else 1)
	return b


# StyleBoxTexture from a 9-slice frame PNG. Margins are (top, right, bottom, left).
static func _tex_box(path: String, top: int, right: int, bottom: int, left: int) -> StyleBoxTexture:
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var b := StyleBoxTexture.new()
	b.texture = tex
	b.texture_margin_top = float(top)
	b.texture_margin_right = float(right)
	b.texture_margin_bottom = float(bottom)
	b.texture_margin_left = float(left)
	return b

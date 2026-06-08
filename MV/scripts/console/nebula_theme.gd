class_name NebulaTheme
extends RefCounted

# Nebula sci-fi game-UI design system, expressed as a Godot Theme + token palette.
# Source of truth: nebulous/guidelines/godot/design-tokens.json + nine-slice.md
# (the Claude Design handoff). This builds ONE cached Theme that the in-game
# authoring overlays (DevConsole, MvCombatWorkshop, MvEditMode) assign to their
# root Control. Items not set here fall back to the project default theme, so
# the Theme is intentionally focused on the surfaces that define the brand:
# framed armored windows, glossy cyan capsule buttons, recessed input slots,
# and the Robyn Brutalist Digital face.

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

const SIZE_TITLE := 28
const SIZE_BODY := 16
const SIZE_HINT := 12
const SIZE_BUTTON := 18

static var _theme: Theme = null
static var _font: FontFile = null


# Returns the shared Nebula Theme, built once and cached.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var f := font()
	if f != null:
		t.default_font = f
	t.default_font_size = SIZE_BODY

	_apply_panels(t)
	_apply_buttons(t)
	_apply_inputs(t)
	_apply_text(t)

	_theme = t
	return t


static func font() -> FontFile:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


# --- Panel surfaces: armored 9-slice window for PanelContainer/Panel. ---
static func _apply_panels(t: Theme) -> void:
	# window-landscape.png 566x364, recommended slice margin T48 R56 B48 L56.
	var win := _tex_box(FRAME_LANDSCAPE, 48, 56, 48, 56)
	if win != null:
		win.content_margin_left = 28.0
		win.content_margin_right = 28.0
		win.content_margin_top = 24.0
		win.content_margin_bottom = 24.0
		t.set_stylebox("panel", "PanelContainer", win)
		t.set_stylebox("panel", "Panel", win)


# --- Buttons: glossy cyan capsule; states derived via modulation (no extra art). ---
static func _apply_buttons(t: Theme) -> void:
	var normal := _tex_box(BTN_CYAN, 16, 16, 16, 16)
	if normal == null:
		return
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 9.0
	normal.content_margin_bottom = 9.0

	var hover := normal.duplicate()
	hover.modulate_color = Color(1.08, 1.08, 1.08, 1.0)
	var pressed := normal.duplicate()
	pressed.modulate_color = Color(0.9, 0.9, 0.9, 1.0)
	var disabled := normal.duplicate()
	disabled.modulate_color = Color(0.55, 0.6, 0.62, 0.75)
	var focus := normal.duplicate()
	focus.modulate_color = Color(1.04, 1.04, 1.04, 1.0)

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
		t.set_font_size("font_size", type, SIZE_BUTTON)


# --- Inputs: recessed dark slots with a cyan focus ring. ---
static func _apply_inputs(t: Theme) -> void:
	var slot := _slot_box(false)
	var focus := _slot_box(true)
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		t.set_stylebox("normal", type, slot)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("read_only", type, slot)
		t.set_color("font_color", type, C_BODY)
		t.set_color("font_readonly_color", type, C_DIM)
		t.set_color("font_placeholder_color", type, C_DIM)
		t.set_color("caret_color", type, C_ACCENT)
		t.set_color("selection_color", type, Color(C_ACCENT.r, C_ACCENT.g, C_ACCENT.b, 0.3))


# --- Text colors for Labels / rich text. ---
static func _apply_text(t: Theme) -> void:
	t.set_color("font_color", "Label", C_BODY)
	t.set_color("default_color", "RichTextLabel", C_BODY)
	t.set_color("font_color", "CheckBox", C_BODY)
	t.set_color("font_color", "CheckButton", C_BODY)


# --- Builders the overlays can reuse for ad-hoc nodes. ---

# Lightweight card surface (rule rows, list rows) — flat, not the heavy window frame.
static func card_box(selected := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = C_PANEL_ALT
	b.set_corner_radius_all(6)
	b.set_content_margin_all(10)
	b.border_color = C_ACCENT if selected else Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.35)
	b.set_border_width_all(1)
	if selected:
		b.border_width_left = 3
	return b


# Recessed inset well behind lists / logs / previews.
static func well_box() -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = C_PANEL_DARK
	b.set_corner_radius_all(6)
	b.set_content_margin_all(8)
	b.border_color = Color(0, 0, 0, 0.55)
	b.set_border_width_all(1)
	return b


# Title label: UPPERCASE cyan-glow heading.
static func title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", C_TITLE)
	l.add_theme_font_size_override("font_size", SIZE_TITLE)
	var f := font()
	if f != null:
		l.add_theme_font_override("font", f)
	return l


static func _slot_box(focused: bool) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = C_PANEL_DARK
	b.set_corner_radius_all(6)
	b.set_content_margin_all(8)
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

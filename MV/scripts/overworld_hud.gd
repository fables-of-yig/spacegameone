extends Control

const HUD_TEXTURE_CANDIDATES: Array[String] = [
	"res://Assets/UI/overworld_hud.png",
	"res://Assets/UI/overworld_hud.png.png",
	"res://Assets/UI/overworld_hud.webp",
	"res://Assets/UI/overworld_hud.jpg",
]

var _panel: Control = null
var _overlay_rect: TextureRect = null
var _region_name: String = ""
var _can_land: bool = false
var _ship_col: int = 0
var _ship_row: int = 0
var _grid_w: int = 32
var _grid_h: int = 32


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = Control.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.draw.connect(_draw_hud)
	_panel.set_process(true)
	add_child(_panel)
	_overlay_rect = TextureRect.new()
	_overlay_rect.anchor_right = 1.0
	_overlay_rect.anchor_bottom = 1.0
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay_rect.texture = _load_default_hud_texture()
	add_child(_overlay_rect)


func _process(_delta: float) -> void:
	if _panel != null:
		_panel.queue_redraw()


func update_info(region_name: String, can_land: bool,
		col: int, row: int, grid_w: int, grid_h: int) -> void:
	_region_name = region_name
	_can_land = can_land
	_ship_col = col
	_ship_row = row
	_grid_w = grid_w
	_grid_h = grid_h


func _draw_hud() -> void:
	return


func _load_default_hud_texture() -> Texture2D:
	for path in HUD_TEXTURE_CANDIDATES:
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			return tex
	return null

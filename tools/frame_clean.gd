extends SceneTree

# Surgically removes the decorative corner ✕ and the two bottom "vents" from the
# Nebula armored window frame (window-landscape.png), keeping the armored look.
#   - vents sit in the dotted inner-fill band just above the bottom border, so a
#     clean vertical slice from BETWEEN the vents tiles over them seamlessly.
#   - the ✕ is a cyan button on the busy top-right corner junction; there's no
#     clean adjacent patch, so we MIRROR the clean top-left corner into it.
#
#   godot --headless --path <proj> --script res://tools/frame_clean.gd -- preview
#   godot --headless --path <proj> --script res://tools/frame_clean.gd -- apply
#
# preview = _frame_preview.png with boxes outlined (red=target, green=tile source,
#           blue=mirror source) + zoomed raw crops to measure pixel positions.
# apply   = backs up the original to window-landscape.orig.png (once) and rewrites
#           window-landscape.png cleaned.

const SRC := "res://Assets/UI/nebula/frames/window-landscape.png"
const BACKUP := "res://Assets/UI/nebula/frames/window-landscape.orig.png"
const PREVIEW := "res://Assets/UI/nebula/frames/_frame_preview.png"

const TARGETS := [
	{"name": "close_x", "method": "mirror", "box": Rect2i(494, 24, 42, 44), "src": Rect2i(30, 24, 42, 44)},
	{"name": "vent_l", "method": "tile", "box": Rect2i(118, 313, 122, 31), "slice_x": 258, "slice_w": 20},
	{"name": "vent_r", "method": "tile", "box": Rect2i(330, 313, 122, 31), "slice_x": 258, "slice_w": 20},
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := str(args[0]) if args.size() > 0 else "preview"

	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	if img == null:
		var tex: Texture2D = load(SRC)
		if tex != null:
			img = tex.get_image()
	if img == null:
		push_error("FRAMECLEAN: could not load %s" % SRC)
		quit(1)
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	print("FRAMECLEAN: source size = %dx%d, mode = %s" % [img.get_width(), img.get_height(), mode])

	if mode == "preview":
		_preview(img)
	elif mode == "apply":
		_apply(img)
	else:
		push_error("FRAMECLEAN: unknown mode '%s'" % mode)
		quit(1)
		return
	quit(0)


func _preview(img: Image) -> void:
	var out := img.duplicate() as Image
	for t_v in TARGETS:
		var t: Dictionary = t_v
		var box: Rect2i = t["box"]
		_outline(out, box, Color(1, 0, 0, 1))
		if str(t["method"]) == "tile":
			_outline(out, Rect2i(int(t["slice_x"]), box.position.y, int(t["slice_w"]), box.size.y), Color(0, 1, 0, 1))
		elif str(t["method"]) == "mirror":
			_outline(out, t["src"], Color(0.3, 0.6, 1, 1))
	out.save_png(ProjectSettings.globalize_path(PREVIEW))
	print("FRAMECLEAN: preview -> %s" % PREVIEW)
	_save_crop(img, Rect2i(456, 6, 110, 100), 4, "res://Assets/UI/nebula/frames/_crop_x.png")
	_save_crop(img, Rect2i(0, 6, 110, 100), 4, "res://Assets/UI/nebula/frames/_crop_tl.png")
	_save_crop(img, Rect2i(100, 308, 360, 56), 3, "res://Assets/UI/nebula/frames/_crop_vents.png")


func _apply(img: Image) -> void:
	if not FileAccess.file_exists(ProjectSettings.globalize_path(BACKUP)):
		img.save_png(ProjectSettings.globalize_path(BACKUP))
		print("FRAMECLEAN: backed up original -> %s" % BACKUP)

	var src := img.duplicate() as Image  # read clean source pixels from an untouched copy
	for t_v in TARGETS:
		var t: Dictionary = t_v
		var box: Rect2i = t["box"]
		match str(t["method"]):
			"tile":
				_tile_fill(img, src, box, int(t["slice_x"]), int(t["slice_w"]))
			"mirror":
				var patch := src.get_region(t["src"]) as Image
				patch.flip_x()
				img.blit_rect(patch, Rect2i(0, 0, patch.get_width(), patch.get_height()), box.position)
		print("FRAMECLEAN: cleaned %s (%s) %s" % [str(t["name"]), str(t["method"]), str(box)])

	img.save_png(ProjectSettings.globalize_path(SRC))
	print("FRAMECLEAN: wrote cleaned frame -> %s" % SRC)


func _tile_fill(dst: Image, src: Image, box: Rect2i, slice_x: int, slice_w: int) -> void:
	var x := box.position.x
	while x < box.position.x + box.size.x:
		var w := mini(slice_w, box.position.x + box.size.x - x)
		dst.blit_rect(src, Rect2i(slice_x, box.position.y, w, box.size.y), Vector2i(x, box.position.y))
		x += slice_w


func _save_crop(img: Image, region: Rect2i, scale: int, path: String) -> void:
	var crop := img.get_region(region)
	crop.resize(region.size.x * scale, region.size.y * scale, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(path))
	print("FRAMECLEAN: crop %s (region %s x%d)" % [path.get_file(), str(region), scale])


func _outline(img: Image, box: Rect2i, col: Color) -> void:
	var x0 := maxi(box.position.x, 0)
	var y0 := maxi(box.position.y, 0)
	var x1 := mini(box.position.x + box.size.x - 1, img.get_width() - 1)
	var y1 := mini(box.position.y + box.size.y - 1, img.get_height() - 1)
	for x in range(x0, x1 + 1):
		img.set_pixel(x, y0, col)
		img.set_pixel(x, y1, col)
	for y in range(y0, y1 + 1):
		img.set_pixel(x0, y, col)
		img.set_pixel(x1, y, col)

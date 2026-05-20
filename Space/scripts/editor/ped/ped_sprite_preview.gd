extends Control

# Reusable sprite sheet preview + frame picker for the player editor.
# Dropped into the attacks and projectiles tabs to give visual feedback
# on sprite_sheet / frame_width / frame_height / frame_start / frame_count.
#
# The host sets the properties, then this control draws the sheet with a
# grid overlay, highlights the selected frame range, and animates a preview.

const PspIO = preload("res://Space/scripts/shared/psp/psp_io.gd")
const PackPaths = preload("res://Space/scripts/shared/pack_paths.gd")

signal frame_clicked(frame_idx: int)

var pack_id: String = ""
var sheet_name: String = ""
var content_folder: String = "Sprites"
var frame_width: int = 16
var frame_height: int = 16
var frame_start: int = 0
var frame_count: int = 1
var frame_tick: int = 6  # ticks per frame for animation

# Optional hitbox overlay (draws a translucent red rect on the animation preview,
# positioned relative to the preview frame center). hitbox_w <= 0 disables.
var hitbox_x: int = 0
var hitbox_y: int = 0
var hitbox_w: int = 0
var hitbox_h: int = 0

# Optional reference sprite drawn under the animated preview. Used by the
# attacks tab so melee hitboxes can be aligned against a live player pose.
var reference_sheet_name: String = ""
var reference_content_folder: String = "Sprites"
var reference_frame_width: int = 16
var reference_frame_height: int = 16
var reference_frame_index: int = 0
var reference_alpha: float = 0.4
var reference_label: String = ""

var _texture: Texture2D = null
var _reference_texture: Texture2D = null
var _anim_timer: float = 0.0
var _anim_frame: int = 0
var _sheet_cols: int = 1
var _sheet_rows: int = 1
var _total_frames: int = 0
var _cell_rects: Array = []  # [{idx, rect}]


func _ready():
    mouse_filter = MOUSE_FILTER_STOP
    set_process(true)


func _process(delta: float) -> void:
    if not visible:
        return
    # Animate preview
    if frame_count > 1 and frame_tick > 0:
        _anim_timer += delta
        var dur := float(frame_tick) / 60.0
        if _anim_timer >= dur:
            _anim_timer -= dur
            _anim_frame = (_anim_frame + 1) % frame_count
    queue_redraw()


func reload_texture() -> void:
    _texture = _load_texture(pack_id, content_folder, sheet_name)
    _reference_texture = _load_texture(pack_id, reference_content_folder, reference_sheet_name)
    _recalc_grid()


func _load_texture(target_pack_id: String, folder_name: String, file_name: String) -> Texture2D:
    if target_pack_id.is_empty() or file_name.is_empty():
        return null
    var folder := folder_name.strip_edges()
    if folder.is_empty():
        folder = "Sprites"
    # Try to load from user pack sprites, then shipped
    for base in [
        PackPaths.writable_pack_dir(target_pack_id) + folder + "/",
        "res://Content/%s/%s/" % [target_pack_id, folder],
    ]:
        var path: String = base + file_name
        if FileAccess.file_exists(path):
            var f := FileAccess.open(path, FileAccess.READ)
            if f != null:
                var bytes := f.get_buffer(f.get_length())
                f.close()
                var img := Image.new()
                if img.load_png_from_buffer(bytes) == OK:
                    return ImageTexture.create_from_image(img)
    return null


func _recalc_grid() -> void:
    if _texture == null or frame_width <= 0 or frame_height <= 0:
        _sheet_cols = 0
        _sheet_rows = 0
        _total_frames = 0
        return
    @warning_ignore("integer_division")
    _sheet_cols = _texture.get_width() / frame_width
    @warning_ignore("integer_division")
    _sheet_rows = _texture.get_height() / frame_height
    _total_frames = _sheet_cols * _sheet_rows


func _gui_input(event):
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        for entry in _cell_rects:
            if (entry["rect"] as Rect2).has_point(event.position):
                frame_clicked.emit(int(entry["idx"]))
                accept_event()
                return


func _draw():
    var bg := Color(0.08, 0.09, 0.12, 1.0)
    draw_rect(Rect2(Vector2.ZERO, size), bg)
    var preview_w: float = minf(size.x * 0.42, 144.0)
    preview_w = maxf(preview_w, 92.0)
    var grid_w: float = maxf(0.0, size.x - preview_w - 8.0)
    var prev_x := grid_w + 8.0
    var prev_size := minf(preview_w - 8.0, size.y - 20.0)

    if _texture == null or _sheet_cols <= 0:
        var font := ThemeDB.fallback_font
        draw_string(font, Vector2(8, 20), "No sheet loaded",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.5, 0.6))
        if not sheet_name.is_empty():
            draw_string(font, Vector2(8, 36), sheet_name,
                HORIZONTAL_ALIGNMENT_LEFT, int(size.x - 16), 10, Color(0.4, 0.45, 0.55))
        if prev_size > 8.0 and (_reference_texture != null or hitbox_w > 0 and hitbox_h > 0):
            var blank := Rect2(prev_x, 4, prev_size, prev_size)
            draw_rect(blank, Color(0.12, 0.14, 0.18, 1.0))
            draw_rect(blank, Color(0.3, 0.4, 0.55, 0.6), false, 1.0)
            _draw_reference_on(blank)
            _draw_hitbox_overlay_on(blank)
            if not reference_label.is_empty():
                draw_string(font, Vector2(prev_x, prev_size + 18),
                    reference_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                    Color(0.72, 0.78, 0.88))
        return

    # Split: left = sheet grid, right = animation preview
    var grid_h: float = size.y

    # Calculate cell draw size to fit the grid area
    var cell_draw_w := minf(grid_w / float(_sheet_cols), grid_h / float(_sheet_rows))
    cell_draw_w = minf(cell_draw_w, 32.0)
    var cell_draw_h := cell_draw_w * (float(frame_height) / float(frame_width))

    _cell_rects.clear()
    var mouse_pos := get_local_mouse_position()

    for r in _sheet_rows:
        for c in _sheet_cols:
            var idx := r * _sheet_cols + c
            var dx := float(c) * cell_draw_w
            var dy := float(r) * cell_draw_h
            if dx + cell_draw_w > grid_w or dy + cell_draw_h > grid_h:
                continue
            var dst := Rect2(dx, dy, cell_draw_w, cell_draw_h)
            var src := Rect2(c * frame_width, r * frame_height, frame_width, frame_height)
            draw_texture_rect_region(_texture, dst, src)
            _cell_rects.append({"idx": idx, "rect": dst})

            # Highlight selected range
            var in_range := idx >= frame_start and idx < frame_start + frame_count
            if in_range:
                draw_rect(dst, Color(0.2, 0.85, 1.0, 0.25))
                draw_rect(dst, Color(0.3, 0.9, 1.0, 0.8), false, 1.5)
            elif dst.has_point(mouse_pos):
                draw_rect(dst, Color(1, 1, 1, 0.15))

    # Grid lines
    for c in range(_sheet_cols + 1):
        var x := float(c) * cell_draw_w
        if x <= grid_w:
            draw_line(Vector2(x, 0), Vector2(x, minf(float(_sheet_rows) * cell_draw_h, grid_h)),
                Color(0.3, 0.35, 0.45, 0.4), 1.0)
    for r in range(_sheet_rows + 1):
        var y := float(r) * cell_draw_h
        if y <= grid_h:
            draw_line(Vector2(0, y), Vector2(minf(float(_sheet_cols) * cell_draw_w, grid_w), y),
                Color(0.3, 0.35, 0.45, 0.4), 1.0)

    # Animation preview (right side)
    if prev_size > 8.0 and frame_count > 0:
        var cur_idx := frame_start + (_anim_frame % frame_count)
        if cur_idx < _total_frames:
            @warning_ignore("integer_division")
            var sr := cur_idx / _sheet_cols
            var sc := cur_idx % _sheet_cols
            var src := Rect2(sc * frame_width, sr * frame_height, frame_width, frame_height)
            var dst := Rect2(prev_x, 4, prev_size, prev_size)
            _draw_reference_on(dst)
            draw_texture_rect_region(_texture, dst, src)
            draw_rect(dst, Color(0.4, 0.5, 0.7, 0.4), false, 1.0)
            _draw_hitbox_overlay_on(dst)

        var font := ThemeDB.fallback_font
        draw_string(font, Vector2(prev_x, prev_size + 18), "Preview",
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
        draw_string(font, Vector2(prev_x, prev_size + 32),
            "f%d/%d" % [_anim_frame + 1, frame_count],
            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.6, 0.7))
        if not reference_label.is_empty():
            draw_string(font, Vector2(prev_x, prev_size + 46),
                reference_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
                Color(0.72, 0.78, 0.88))


# Overlay a translucent red hitbox rect onto a preview frame `dst`, positioning
# it by hitbox_x/y as offsets from the frame center. Scales to the preview's
# display size. No-op when hitbox_w/h <= 0 or frame_width/height <= 0.
func _draw_hitbox_overlay_on(dst: Rect2) -> void:
    if hitbox_w <= 0 or hitbox_h <= 0:
        return
    if frame_width <= 0 or frame_height <= 0:
        return
    var sx := dst.size.x / float(frame_width)
    var sy := dst.size.y / float(frame_height)
    var cx := dst.position.x + dst.size.x * 0.5
    var cy := dst.position.y + dst.size.y * 0.5
    var hb := Rect2(
        cx + (float(hitbox_x) - float(hitbox_w) * 0.5) * sx,
        cy + (float(hitbox_y) - float(hitbox_h) * 0.5) * sy,
        float(hitbox_w) * sx,
        float(hitbox_h) * sy
    )
    draw_rect(hb, Color(1.0, 0.3, 0.3, 0.25))
    draw_rect(hb, Color(1.0, 0.4, 0.4, 0.9), false, 1.5)


func _draw_reference_on(dst: Rect2) -> void:
    if _reference_texture == null or reference_frame_width <= 0 or reference_frame_height <= 0:
        return
    @warning_ignore("integer_division")
    var ref_cols := maxi(1, _reference_texture.get_width() / reference_frame_width)
    var idx := maxi(0, reference_frame_index)
    @warning_ignore("integer_division")
    var src_row := idx / ref_cols
    var src_col := idx % ref_cols
    var src := Rect2(
        float(src_col * reference_frame_width),
        float(src_row * reference_frame_height),
        float(reference_frame_width),
        float(reference_frame_height)
    )
    draw_texture_rect_region(_reference_texture, dst, src, Color(1.0, 1.0, 1.0, clampf(reference_alpha, 0.0, 1.0)))

extends RefCounted

# Module sprite loader with player-color remapping. Extracted from
# GameManager. The sprite cache + color state live on GameManager and
# are passed in — this keeps the helper pure and leaves save/load of
# the cache unchanged.

static func get_sprite(sprite_name: String, cache: Dictionary, primary: Color, secondary: Color) -> Texture2D:
    var key = sprite_name
    if cache.has(key):
        return cache[key]
    var path = "res://Space/art/modules/" + sprite_name + ".png"
    var base_tex = load(path)
    if base_tex == null:
        cache[key] = null
        return null
    var img: Image = base_tex.get_image()
    if img == null:
        cache[key] = null
        return null

    # Auto-detect whether this module sprite uses the red/green player-color
    # mask convention. Asset-pack modules from external packs almost never
    # do — they're solid pixel art with no mask channels — so we fast-path
    # them by caching the texture as-is and skipping the per-pixel scan.
    # Sampling 256 pixels (16x16 grid) is enough to catch any sprite that
    # uses the mask, since masked sprites have many such pixels.
    if not _has_color_mask(img):
        cache[key] = base_tex
        return base_tex

    for y in img.get_height():
        for x in img.get_width():
            var px = img.get_pixel(x, y)
            if px.a < 0.01:
                continue
            if px.r > 0.9 and px.g < 0.1 and px.b < 0.1:
                img.set_pixel(x, y, Color(primary.r, primary.g, primary.b, px.a))
            elif px.g > 0.9 and px.r < 0.1 and px.b < 0.1:
                img.set_pixel(x, y, Color(secondary.r, secondary.g, secondary.b, px.a))
    var tex = ImageTexture.create_from_image(img)
    cache[key] = tex
    return tex

# Sample 256 pixels in a uniform grid, looking for the pure-red or pure-green
# mask pixels that indicate this sprite was authored for player coloring.
# Returns true on the first hit; returns false after scanning the whole grid.
# False positives are harmless (we just do unnecessary work); false negatives
# would mean a masked sprite displays uncolored, which would be visible to
# the user. The grid step is small enough (image_dim/16) that any meaningful
# mask region will hit at least one sample point.
static func _has_color_mask(img: Image) -> bool:
    var w := img.get_width()
    var h := img.get_height()
    if w <= 0 or h <= 0:
        return false
    var step_x: int = maxi(1, w / 16)
    var step_y: int = maxi(1, h / 16)
    var y := 0
    while y < h:
        var x := 0
        while x < w:
            var px := img.get_pixel(x, y)
            if px.a >= 0.01:
                if px.r > 0.9 and px.g < 0.1 and px.b < 0.1:
                    return true
                if px.g > 0.9 and px.r < 0.1 and px.b < 0.1:
                    return true
            x += step_x
        y += step_y
    return false

from __future__ import annotations

import json
import math
import os
import random
import struct
import zlib


OUT_DIR = os.path.join("D:\\spacegame2", "Content", "demo", "Backdrops", "Parallax")
REF_W = 240
REF_H = 136
DETAIL_SCALE = 4
OUTPUT_SCALE = 2
BASE_W = REF_W * DETAIL_SCALE
BASE_H = REF_H * DETAIL_SCALE


def clamp(v: int, lo: int = 0, hi: int = 255) -> int:
    return lo if v < lo else hi if v > hi else v


def rgba(r: int, g: int, b: int, a: int = 255) -> tuple[int, int, int, int]:
    return (clamp(r), clamp(g), clamp(b), clamp(a))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(c1: tuple[int, int, int, int], c2: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    return (
        int(lerp(c1[0], c2[0], t)),
        int(lerp(c1[1], c2[1], t)),
        int(lerp(c1[2], c2[2], t)),
        int(lerp(c1[3], c2[3], t)),
    )


def sx(v: int) -> int:
    return int(round(v * DETAIL_SCALE))


def sy(v: int) -> int:
    return int(round(v * DETAIL_SCALE))


class Canvas:
    def __init__(self, w: int, h: int, bg: tuple[int, int, int, int] = (0, 0, 0, 0)) -> None:
        self.w = w
        self.h = h
        self.pixels = bytearray(w * h * 4)
        self.fill(bg)

    def copy(self) -> "Canvas":
        out = Canvas(self.w, self.h)
        out.pixels[:] = self.pixels
        return out

    def fill(self, color: tuple[int, int, int, int]) -> None:
        row = bytes(color) * self.w
        for y in range(self.h):
            start = y * self.w * 4
            self.pixels[start:start + self.w * 4] = row

    def set(self, x: int, y: int, color: tuple[int, int, int, int]) -> None:
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        idx = (y * self.w + x) * 4
        self.pixels[idx:idx + 4] = bytes(color)

    def get(self, x: int, y: int) -> tuple[int, int, int, int]:
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return (0, 0, 0, 0)
        idx = (y * self.w + x) * 4
        return tuple(self.pixels[idx:idx + 4])  # type: ignore[return-value]

    def blend(self, x: int, y: int, color: tuple[int, int, int, int]) -> None:
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        src_a = color[3]
        if src_a <= 0:
            return
        idx = (y * self.w + x) * 4
        dst_r, dst_g, dst_b, dst_a = self.pixels[idx:idx + 4]
        if src_a >= 255 or dst_a == 0:
            self.pixels[idx:idx + 4] = bytes(color)
            return
        out_a = src_a + (dst_a * (255 - src_a) // 255)
        if out_a <= 0:
            self.pixels[idx:idx + 4] = b"\x00\x00\x00\x00"
            return
        src_part = src_a * 255
        dst_part = dst_a * (255 - src_a)
        out_r = (color[0] * src_part + dst_r * dst_part) // (out_a * 255)
        out_g = (color[1] * src_part + dst_g * dst_part) // (out_a * 255)
        out_b = (color[2] * src_part + dst_b * dst_part) // (out_a * 255)
        self.pixels[idx:idx + 4] = bytes((out_r, out_g, out_b, out_a))

    def rect(self, x: int, y: int, w: int, h: int, color: tuple[int, int, int, int], fill: bool = True) -> None:
        if w <= 0 or h <= 0:
            return
        if fill:
            for yy in range(y, y + h):
                for xx in range(x, x + w):
                    self.blend(xx, yy, color)
        else:
            for xx in range(x, x + w):
                self.blend(xx, y, color)
                self.blend(xx, y + h - 1, color)
            for yy in range(y, y + h):
                self.blend(x, yy, color)
                self.blend(x + w - 1, yy, color)

    def line(self, x0: int, y0: int, x1: int, y1: int, color: tuple[int, int, int, int]) -> None:
        dx = abs(x1 - x0)
        sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0)
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.blend(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            e2 = err * 2
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def circle(self, cx: int, cy: int, r: int, color: tuple[int, int, int, int], fill: bool = True) -> None:
        if r <= 0:
            return
        rr = r * r
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                d = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                if fill:
                    if d <= rr:
                        self.blend(x, y, color)
                else:
                    if abs(d - rr) <= r:
                        self.blend(x, y, color)

    def vertical_gradient(self, y0: int, y1: int, colors: list[tuple[int, int, int, int]]) -> None:
        span = max(1, y1 - y0)
        for y in range(max(0, y0), min(self.h, y1)):
            t = (y - y0) / float(span)
            pos = t * (len(colors) - 1)
            idx = min(len(colors) - 2, max(0, int(pos)))
            local_t = pos - idx
            col = lerp_color(colors[idx], colors[idx + 1], local_t)
            for x in range(self.w):
                self.set(x, y, col)


def write_png(path: str, canvas: Canvas) -> None:
    raw = bytearray()
    row_bytes = canvas.w * 4
    for y in range(canvas.h):
        raw.append(0)
        start = y * row_bytes
        raw.extend(canvas.pixels[start:start + row_bytes])
    compressed = zlib.compress(bytes(raw), level=9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = bytearray()
    png.extend(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack(">IIBBBBB", canvas.w, canvas.h, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", compressed))
    png.extend(chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def scale_nearest(src: Canvas, factor: int) -> Canvas:
    out = Canvas(src.w * factor, src.h * factor, (0, 0, 0, 0))
    for y in range(src.h):
        for x in range(src.w):
            color = src.get(x, y)
            ox = x * factor
            oy = y * factor
            for yy in range(factor):
                for xx in range(factor):
                    out.set(ox + xx, oy + yy, color)
    return out


def composite(layers: list[Canvas]) -> Canvas:
    out = Canvas(layers[0].w, layers[0].h, (0, 0, 0, 0))
    for layer in layers:
        for y in range(layer.h):
            for x in range(layer.w):
                out.blend(x, y, layer.get(x, y))
    return out


def make_terrain_heights(rng: random.Random, base_y: int, min_y: int, max_y: int, step_min: int, step_max: int) -> list[int]:
    heights: list[int] = []
    y = sy(base_y)
    x = 0
    while x < BASE_W:
        seg = rng.randint(sx(step_min), sx(step_max))
        drift = rng.randint(-sy(3), sy(3))
        y = max(sy(min_y), min(sy(max_y), y + drift))
        for _ in range(seg):
            if x >= BASE_W:
                break
            heights.append(y)
            x += 1
    return heights


def fill_below(canvas: Canvas, heights: list[int], color: tuple[int, int, int, int], start_y: int | None = None) -> None:
    for x, y0 in enumerate(heights):
        top = y0 if start_y is None else max(y0, start_y)
        for y in range(top, canvas.h):
            canvas.blend(x, y, color)


def draw_highlight_line(canvas: Canvas, heights: list[int], offset: int, color: tuple[int, int, int, int], dash: int = 1) -> None:
    for x, y in enumerate(heights):
        if dash > 1 and (x // dash) % 2 == 1:
            continue
        canvas.blend(x, y + offset, color)


def add_sky_streaks(canvas: Canvas, rng: random.Random, y0: int, y1: int, count: int,
                    color: tuple[int, int, int, int], length_min: int, length_max: int) -> None:
    for _ in range(count):
        x = rng.randint(0, canvas.w - sx(24))
        y = rng.randint(y0, y1)
        length = rng.randint(length_min, length_max)
        thickness = rng.randint(sy(1), sy(3))
        for i in range(length):
            alpha = max(0, color[3] - int((i / float(max(1, length))) * color[3]))
            for t in range(thickness):
                canvas.blend(x + i, y + t, rgba(color[0], color[1], color[2], alpha))


def add_surface_ripples(canvas: Canvas, heights: list[int], rng: random.Random,
                        color: tuple[int, int, int, int], count: int,
                        dx_min: int, dx_max: int, dy_min: int, dy_max: int) -> None:
    for _ in range(count):
        x0 = rng.randint(0, max(0, canvas.w - sx(20)))
        x1 = min(canvas.w - 1, x0 + rng.randint(dx_min, dx_max))
        y_base = heights[min(canvas.w - 1, x0)]
        y = y_base - rng.randint(dy_min, dy_max)
        canvas.line(x0, y, x1, y - rng.randint(0, sy(2)), color)


def add_pixel_noise(canvas: Canvas, rng: random.Random, y0: int, y1: int,
                    every_x: int, every_y: int, colors: list[tuple[int, int, int, int]]) -> None:
    for y in range(max(0, y0), min(canvas.h, y1), max(1, every_y)):
        for x in range(0, canvas.w, max(1, every_x)):
            if rng.random() < 0.22:
                col = colors[rng.randrange(len(colors))]
                canvas.blend(x + rng.randint(0, max(0, every_x - 1)),
                             y + rng.randint(0, max(0, every_y - 1)), col)


def draw_scrap_cluster(canvas: Canvas, x: int, y: int, rng: random.Random,
                       base: tuple[int, int, int, int], accent: tuple[int, int, int, int]) -> None:
    widths = [sx(6), sx(9), sx(12)]
    heights = [sy(3), sy(4), sy(5)]
    for i in range(rng.randint(2, 4)):
        ox = x + rng.randint(-sx(4), sx(4))
        oy = y - rng.randint(0, sy(6))
        w = widths[(i + rng.randint(0, 2)) % len(widths)]
        h = heights[(i + rng.randint(0, 2)) % len(heights)]
        canvas.rect(ox, oy, w, h, base)
        canvas.rect(ox + sx(1), oy + sy(1), max(sx(1), w - sx(2)), sy(1), accent)
        if rng.random() < 0.7:
            canvas.line(ox, oy + h, ox + w + sx(3), oy - sy(2), rgba(35, 44, 50, 180))


def draw_hull_window_strip(canvas: Canvas, x: int, y: int, count: int, pitch: int,
                           body: tuple[int, int, int, int], glow: tuple[int, int, int, int]) -> None:
    for i in range(count):
        px = x + i * pitch
        canvas.rect(px, y, sx(5), sy(2), body)
        canvas.rect(px + sx(1), y + sy(1), sx(3), sy(1), glow)


def draw_broken_column(canvas: Canvas, x: int, top: int, h: int,
                       outer: tuple[int, int, int, int], inner: tuple[int, int, int, int]) -> None:
    canvas.rect(x, top, sx(9), h, outer)
    canvas.rect(x + sx(2), top + sy(3), sx(5), max(sy(6), h - sy(6)), inner)
    canvas.rect(x - sx(2), top, sx(13), sy(3), rgba(outer[0] + 12, outer[1] + 12, outer[2] + 12, outer[3]))
    canvas.rect(x + sx(1), top + h - sy(2), sx(6), sy(2), rgba(inner[0] + 8, inner[1] + 8, inner[2] + 8, inner[3]))


def draw_desert_ocean() -> tuple[dict, list[Canvas]]:
    far = Canvas(BASE_W, BASE_H)
    far.vertical_gradient(0, BASE_H, [
        rgba(28, 25, 44),
        rgba(68, 49, 72),
        rgba(151, 105, 99),
        rgba(232, 188, 134),
    ])
    add_sky_streaks(far, random.Random(501), sy(16), sy(62), 18, rgba(255, 213, 170, 34), sx(22), sx(88))
    add_pixel_noise(far, random.Random(502), sy(18), sy(84), sx(18), sy(8), [
        rgba(255, 226, 182, 14),
        rgba(255, 202, 154, 12),
        rgba(125, 97, 96, 10),
    ])

    far.circle(sx(178), sy(29), sy(12), rgba(255, 230, 186, 255), fill=True)
    far.circle(sx(178), sy(29), sy(17), rgba(255, 230, 186, 42), fill=False)

    horizon_y = sy(70)
    far.rect(0, horizon_y, BASE_W, sy(26), rgba(64, 112, 146, 255))
    far.rect(0, horizon_y + sy(5), BASE_W, sy(8), rgba(80, 136, 164, 255))
    for x in range(0, BASE_W, sx(4)):
        far.rect(x, horizon_y + sy(10) + (x // sx(13)) % sy(2), sx(2), sy(1), rgba(183, 219, 223, 170))

    shore = make_terrain_heights(random.Random(10), 73, 68, 82, 6, 16)
    fill_below(far, shore, rgba(89, 82, 74, 255), start_y=sy(72))
    draw_highlight_line(far, shore, 0, rgba(126, 117, 103, 180), dash=sx(3))
    add_surface_ripples(far, shore, random.Random(503), rgba(113, 104, 91, 120), 18, sx(12), sx(42), sy(2), sy(6))

    for x in (42, 87, 139, 205):
        px = sx(x)
        far.rect(px, horizon_y - sy(6), sx(2), sy(10), rgba(53, 43, 42, 255))
        far.rect(px - sx(2), horizon_y - sy(2), sx(6), sy(2), rgba(71, 58, 54, 255))

    mid = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    rng = random.Random(22)
    dunes_back = make_terrain_heights(rng, 88, 80, 98, 8, 18)
    fill_below(mid, dunes_back, rgba(174, 131, 84, 255))
    draw_highlight_line(mid, dunes_back, 0, rgba(216, 180, 118, 255), dash=sx(4))
    draw_highlight_line(mid, dunes_back, sy(3), rgba(131, 96, 62, 200), dash=sx(2))
    add_surface_ripples(mid, dunes_back, random.Random(504), rgba(230, 196, 130, 115), 28, sx(16), sx(58), sy(4), sy(12))

    dunes_front = make_terrain_heights(rng, 102, 94, 112, 10, 20)
    fill_below(mid, dunes_front, rgba(136, 101, 67, 255))
    draw_highlight_line(mid, dunes_front, 0, rgba(189, 147, 93, 255), dash=sx(5))
    add_surface_ripples(mid, dunes_front, random.Random(505), rgba(204, 160, 102, 100), 34, sx(18), sx(64), sy(4), sy(11))

    for x in (51, 116, 182):
        px = sx(x)
        mid.rect(px, dunes_front[px] - sy(12), sx(3), sy(12), rgba(96, 74, 60, 255))
        mid.rect(px - sx(3), dunes_front[px] - sy(13), sx(8), sy(2), rgba(129, 102, 79, 255))
        mid.line(px + sx(1), dunes_front[px] - sy(6), px + sx(8), dunes_front[px] - sy(10), rgba(158, 124, 87, 190))
    for x in (28, 74, 151, 214):
        px = sx(x)
        py = dunes_front[min(BASE_W - 1, px)]
        mid.line(px, py - sy(4), px + sx(14), py - sy(10), rgba(112, 86, 65, 190))
        mid.line(px + sx(3), py - sy(1), px + sx(12), py - sy(6), rgba(196, 154, 102, 110))

    near = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    rng = random.Random(38)
    foreground = make_terrain_heights(rng, 116, 108, 128, 9, 21)
    fill_below(near, foreground, rgba(78, 57, 43, 255))
    draw_highlight_line(near, foreground, 0, rgba(129, 97, 70, 255), dash=sx(3))
    add_surface_ripples(near, foreground, random.Random(506), rgba(142, 110, 80, 95), 42, sx(14), sx(40), sy(3), sy(10))
    for x in range(sx(12), BASE_W, sx(12)):
        y = foreground[min(BASE_W - 1, x)]
        near.rect(x, y - sy(3), sx(3), sy(3), rgba(52, 39, 31, 255))
        if (x // sx(18)) % 3 == 0:
            near.rect(x + sx(4), y - sy(8), sx(1), sy(8), rgba(67, 58, 49, 255))
            near.line(x + sx(4), y - sy(7), x + sx(7), y - sy(9), rgba(86, 76, 64, 255))
        if (x // sx(12)) % 2 == 0:
            near.rect(x + sx(6), y - sy(2), sx(5), sy(1), rgba(104, 83, 60, 180))
    for x in range(sx(16), BASE_W - sx(20), sx(54)):
        draw_scrap_cluster(near, x, foreground[x], random.Random(600 + x), rgba(54, 40, 31, 255), rgba(118, 92, 68, 190))
    for x in (22, 96, 164, 219):
        px = sx(x)
        py = foreground[min(BASE_W - 1, px)]
        near.rect(px, py - sy(15), sx(2), sy(15), rgba(57, 47, 40, 255))
        near.line(px, py - sy(13), px + sx(6), py - sy(17), rgba(96, 82, 68, 220))
        near.line(px, py - sy(9), px - sx(5), py - sy(12), rgba(84, 72, 58, 180))

    meta = {
        "theme": "desert_ocean",
        "description": "Vast empty desert meeting a distant ocean horizon.",
        "layers": [
            {"file": "desert_ocean_far.png", "speed": [0.18, 0.12]},
            {"file": "desert_ocean_mid.png", "speed": [0.42, 0.18]},
            {"file": "desert_ocean_near.png", "speed": [0.72, 0.24]},
            {"file": "desert_ocean_composite.png", "speed": [0.94, 0.97]},
        ],
    }
    return meta, [far, mid, near]


def draw_ruined_hull_bay() -> tuple[dict, list[Canvas]]:
    far = Canvas(BASE_W, BASE_H)
    far.vertical_gradient(0, BASE_H, [
        rgba(14, 17, 26),
        rgba(22, 30, 43),
        rgba(30, 40, 56),
        rgba(17, 21, 29),
    ])
    for x in range(0, BASE_W, sx(24)):
        far.rect(x, sy(26), sx(8), sy(90), rgba(24, 34, 47, 255))
        far.rect(x + sx(2), sy(32), sx(4), sy(78), rgba(15, 21, 30, 255))
    for x in range(0, BASE_W, sx(12)):
        far.line(x, sy(24), x + sx(18), sy(6), rgba(42, 52, 69, 255))
        far.line(x, sy(24), x + sx(18), sy(42), rgba(42, 52, 69, 255))
    add_pixel_noise(far, random.Random(701), sy(18), sy(116), sx(14), sy(10), [
        rgba(79, 100, 120, 18),
        rgba(37, 52, 71, 22),
        rgba(122, 78, 59, 12),
    ])

    hull = make_terrain_heights(random.Random(111), 74, 60, 84, 8, 16)
    fill_below(far, hull, rgba(35, 43, 53, 255), start_y=sy(58))
    for x in range(sx(52), sx(188), sx(16)):
        y = hull[x]
        far.rect(x, y - sy(9), sx(6), sy(3), rgba(90, 113, 118, 220))
        far.rect(x + sx(1), y - sy(8), sx(4), sy(1), rgba(175, 207, 198, 200))
        far.rect(x + sx(2), y - sy(6), sx(2), sy(8), rgba(44, 58, 68, 200))
    for x in (26, 72, 134, 188):
        px = sx(x)
        py = hull[min(BASE_W - 1, px)]
        far.line(px - sx(10), py - sy(16), px + sx(20), py - sy(28), rgba(67, 80, 89, 210))
        far.line(px - sx(7), py - sy(9), px + sx(17), py - sy(22), rgba(36, 46, 56, 190))

    mid = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    for x in (22, 58, 96, 142, 183, 214):
        px = sx(x)
        draw_broken_column(mid, px, sy(62), sy(74), rgba(49, 61, 74, 255), rgba(24, 30, 39, 255))
    catwalk_y = sy(86)
    mid.rect(0, catwalk_y, BASE_W, sy(4), rgba(68, 84, 93, 255))
    for x in range(0, BASE_W, sx(12)):
        mid.rect(x, catwalk_y + sy(4), sx(2), sy(6), rgba(54, 64, 72, 255))
    mid.rect(sx(24), sy(71), sx(78), sy(7), rgba(53, 70, 78, 255))
    mid.rect(sx(130), sy(67), sx(62), sy(8), rgba(43, 57, 66, 255))
    draw_hull_window_strip(mid, sx(30), sy(73), 8, sx(9), rgba(84, 96, 98, 230), rgba(255, 214, 145, 165))
    draw_hull_window_strip(mid, sx(136), sy(69), 6, sx(9), rgba(71, 83, 86, 220), rgba(129, 203, 216, 155))
    for x in (34, 92, 156, 202):
        px = sx(x)
        mid.rect(px, sy(78), sx(18), sy(3), rgba(86, 66, 54, 255))
        mid.rect(px + sx(1), sy(79), sx(16), sy(1), rgba(148, 106, 77, 255))
    mid.line(sx(12), sy(98), sx(38), sy(68), rgba(64, 77, 90, 255))
    mid.line(sx(116), sy(102), sx(144), sy(70), rgba(64, 77, 90, 255))
    mid.line(sx(173), sy(104), sx(204), sy(74), rgba(64, 77, 90, 255))
    for x in range(sx(44), sx(204), sx(20)):
        mid.circle(x, sy(74), sy(2), rgba(255, 186, 99, 255))
        mid.rect(x - sx(1), sy(76), sx(3), sy(1), rgba(255, 220, 160, 200))
    for x in (31, 68, 118, 172, 225):
        px = sx(x)
        mid.line(px, sy(52), px + sx(12), sy(96), rgba(41, 49, 57, 210))
        mid.line(px + sx(4), sy(56), px - sx(8), sy(104), rgba(84, 54, 39, 120))

    near = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    floor = make_terrain_heights(random.Random(212), 116, 108, 128, 8, 18)
    fill_below(near, floor, rgba(25, 28, 34, 255))
    draw_highlight_line(near, floor, 0, rgba(49, 58, 68, 255), dash=sx(4))
    for x in (16, 61, 104, 148, 191, 226):
        px = sx(x)
        near.rect(px, sy(90), sx(8), sy(46), rgba(38, 45, 54, 255))
        near.rect(px + sx(1), sy(94), sx(6), sy(42), rgba(16, 20, 26, 255))
    for x in (28, 73, 119, 166, 208):
        px = sx(x)
        near.line(px, 0, px - sx(6), sy(46), rgba(56, 72, 82, 200))
        near.line(px + sx(3), 0, px + sx(9), sy(38), rgba(36, 47, 56, 200))
    near.rect(0, sy(112), BASE_W, sy(6), rgba(30, 34, 42, 255))
    for x in range(sx(6), BASE_W, sx(12)):
        near.rect(x, sy(118), sx(6), sy(3), rgba(56, 63, 71, 255))
        if (x // sx(24)) % 2 == 0:
            near.rect(x + sx(2), sy(114), sx(2), sy(2), rgba(160, 103, 66, 120))
    for x in range(sx(14), BASE_W - sx(16), sx(46)):
        draw_scrap_cluster(near, x, floor[min(BASE_W - 1, x)], random.Random(800 + x), rgba(40, 48, 56, 255), rgba(135, 92, 61, 165))
    for x in (18, 77, 145, 213):
        px = sx(x)
        py = floor[min(BASE_W - 1, px)]
        near.rect(px, py - sy(22), sx(3), sy(22), rgba(34, 41, 46, 255))
        near.rect(px - sx(3), py - sy(3), sx(10), sy(3), rgba(70, 79, 88, 220))
        near.line(px, py - sy(17), px + sx(16), py - sy(23), rgba(86, 98, 104, 170))

    meta = {
        "theme": "ruined_hull_bay",
        "description": "Underground ruin with crashed ship hull segments and failing catwalks.",
        "layers": [
            {"file": "ruined_hull_bay_far.png", "speed": [0.16, 0.1]},
            {"file": "ruined_hull_bay_mid.png", "speed": [0.46, 0.18]},
            {"file": "ruined_hull_bay_near.png", "speed": [0.76, 0.24]},
            {"file": "ruined_hull_bay_composite.png", "speed": [0.94, 0.97]},
        ],
    }
    return meta, [far, mid, near]


def draw_ruined_reactor_trench() -> tuple[dict, list[Canvas]]:
    far = Canvas(BASE_W, BASE_H)
    far.vertical_gradient(0, BASE_H, [
        rgba(10, 15, 18),
        rgba(12, 24, 31),
        rgba(18, 37, 46),
        rgba(8, 11, 15),
    ])
    for x in range(sx(8), BASE_W, sx(28)):
        far.rect(x, sy(24), sx(10), sy(92), rgba(17, 31, 36, 255))
        far.rect(x + sx(2), sy(28), sx(6), sy(84), rgba(8, 13, 17, 255))
    add_pixel_noise(far, random.Random(901), sy(22), sy(118), sx(12), sy(9), [
        rgba(56, 133, 136, 12),
        rgba(28, 52, 61, 18),
        rgba(92, 126, 122, 14),
    ])
    trench = make_terrain_heights(random.Random(305), 80, 70, 94, 10, 20)
    for x, y in enumerate(trench):
        for yy in range(y, BASE_H):
            shade = 40 if ((x + yy) // sx(4)) % 2 == 0 else 28
            far.blend(x, yy, rgba(8, shade, shade + 8, 255))
    for x in range(sx(12), BASE_W - sx(12), sx(16)):
        y = trench[x]
        far.rect(x, y - sy(10), sx(5), sy(2), rgba(71, 100, 98, 190))
        far.rect(x + sx(1), y - sy(9), sx(3), sy(1), rgba(166, 207, 200, 160))
    for x in range(0, BASE_W, sx(10)):
        far.rect(x, sy(96) + (x // sx(20)) % sy(3), sx(6), sy(1), rgba(80, 221, 199, 70))
    for x in (20, 81, 140, 193):
        px = sx(x)
        py = trench[min(BASE_W - 1, px)]
        far.line(px - sx(8), py - sy(14), px + sx(18), py - sy(34), rgba(45, 86, 88, 210))
        far.line(px, py - sy(10), px + sx(22), py - sy(22), rgba(103, 227, 208, 70))

    mid = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    for x in (18, 52, 89, 128, 166, 204):
        px = sx(x)
        draw_broken_column(mid, px, sy(56), sy(80), rgba(47, 64, 67, 255), rgba(16, 22, 25, 255))
    for y in (64, 82, 100):
        py = sy(y)
        mid.rect(0, py, BASE_W, sy(3), rgba(54, 77, 81, 255))
        for x in range(sx(4), BASE_W, sx(14)):
            mid.rect(x, py + sy(3), sx(2), sy(5), rgba(39, 51, 54, 255))
    mid.rect(sx(34), sy(60), sx(56), sy(6), rgba(27, 52, 58, 255))
    mid.rect(sx(118), sy(88), sx(67), sy(7), rgba(31, 59, 63, 255))
    draw_hull_window_strip(mid, sx(40), sy(62), 5, sx(10), rgba(43, 73, 76, 230), rgba(119, 252, 222, 155))
    draw_hull_window_strip(mid, sx(126), sy(90), 6, sx(9), rgba(43, 72, 76, 230), rgba(255, 191, 112, 135))
    for x in (38, 94, 145, 188):
        px = sx(x)
        mid.line(px, sy(60), px + sx(20), sy(84), rgba(72, 96, 100, 255))
        mid.line(px + sx(8), sy(60), px - sx(14), sy(92), rgba(52, 72, 74, 255))
    for x in (27, 76, 123, 171, 219):
        px = sx(x)
        mid.rect(px, sy(73), sx(10), sy(4), rgba(40, 63, 68, 255))
        mid.rect(px + sx(2), sy(74), sx(6), sy(2), rgba(80, 226, 199, 170))
    for x in (26, 64, 112, 176, 228):
        px = sx(x)
        mid.line(px, sy(30), px + sx(10), sy(118), rgba(24, 43, 46, 220))
        mid.line(px + sx(3), sy(38), px - sx(7), sy(110), rgba(93, 134, 130, 90))

    near = Canvas(BASE_W, BASE_H, (0, 0, 0, 0))
    floor = make_terrain_heights(random.Random(407), 118, 108, 128, 8, 18)
    fill_below(near, floor, rgba(15, 18, 21, 255))
    draw_highlight_line(near, floor, 0, rgba(38, 47, 49, 255), dash=sx(3))
    for x in (13, 44, 72, 108, 142, 176, 212):
        px = sx(x)
        near.rect(px, sy(86), sx(7), sy(50), rgba(29, 40, 42, 255))
        near.rect(px + sx(1), sy(90), sx(5), sy(46), rgba(8, 11, 13, 255))
    for x in (26, 88, 152, 206):
        px = sx(x)
        near.line(px, sy(10), px - sx(8), sy(52), rgba(59, 84, 88, 210))
        near.line(px + sx(6), 0, px + sx(16), sy(46), rgba(39, 59, 63, 190))
    near.rect(0, sy(108), BASE_W, sy(5), rgba(20, 25, 28, 255))
    for x in range(sx(8), BASE_W, sx(16)):
        near.rect(x, sy(109), sx(5), sy(2), rgba(79, 200, 182, 120))
        if (x // sx(32)) % 2 == 0:
            near.rect(x + sx(2), sy(105), sx(1), sy(3), rgba(114, 255, 221, 90))
    for x in range(sx(12), BASE_W - sx(18), sx(42)):
        draw_scrap_cluster(near, x, floor[min(BASE_W - 1, x)], random.Random(950 + x), rgba(20, 29, 31, 255), rgba(98, 215, 190, 130))
    for x in (22, 86, 157, 219):
        px = sx(x)
        py = floor[min(BASE_W - 1, px)]
        near.rect(px, py - sy(26), sx(4), sy(26), rgba(23, 30, 33, 255))
        near.rect(px - sx(4), py - sy(5), sx(12), sy(4), rgba(48, 64, 66, 220))
        near.line(px + sx(2), py - sy(20), px + sx(18), py - sy(30), rgba(90, 223, 198, 80))

    meta = {
        "theme": "ruined_reactor_trench",
        "description": "Collapsed underground installation with reactor light and broken industrial supports.",
        "layers": [
            {"file": "ruined_reactor_trench_far.png", "speed": [0.14, 0.1]},
            {"file": "ruined_reactor_trench_mid.png", "speed": [0.44, 0.18]},
            {"file": "ruined_reactor_trench_near.png", "speed": [0.78, 0.24]},
            {"file": "ruined_reactor_trench_composite.png", "speed": [0.94, 0.97]},
        ],
    }
    return meta, [far, mid, near]


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest: dict[str, object] = {
        "size": [BASE_W * OUTPUT_SCALE, BASE_H * OUTPUT_SCALE],
        "themes": [],
    }

    for meta, layers in [
        draw_desert_ocean(),
        draw_ruined_hull_bay(),
        draw_ruined_reactor_trench(),
    ]:
        upscaled_layers = [scale_nearest(layer, OUTPUT_SCALE) for layer in layers]
        composite_image = composite(upscaled_layers)

        theme = str(meta["theme"])
        layer_files = meta["layers"]
        for layer_meta, image in zip(layer_files[:3], upscaled_layers):
            write_png(os.path.join(OUT_DIR, layer_meta["file"]), image)
        write_png(os.path.join(OUT_DIR, layer_files[3]["file"]), composite_image)
        manifest["themes"].append(meta)

    manifest_path = os.path.join(OUT_DIR, "parallax_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)


if __name__ == "__main__":
    main()

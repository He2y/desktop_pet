from __future__ import annotations

import json
import math
import random
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


SIZE = 512
SCALE = 2
CANVAS = SIZE * SCALE
OUT_DIR = Path("assets/sprites")
FRAME_COUNT = 16


CREAM_ORANGE = (219, 171, 111, 255)
LIGHT_ORANGE = (235, 199, 145, 255)
DEEP_ORANGE = (174, 121, 70, 255)
WARM_WHITE = (248, 245, 235, 255)
SHADOW_WHITE = (226, 218, 205, 255)
PINK = (214, 145, 135, 255)
AMBER = (210, 169, 64, 255)
DARK = (54, 38, 28, 255)
WHISKER = (255, 255, 248, 220)


def sx(value: float) -> int:
    return int(round(value * SCALE))


def sc_rect(rect: Sequence[float]) -> tuple[int, int, int, int]:
    return tuple(sx(v) for v in rect)  # type: ignore[return-value]


def new_canvas() -> Image.Image:
    return Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))


def ellipse_mask(rect: Sequence[float], blur: float = 0.0) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse(sc_rect(rect), fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(sx(blur)))
    return mask


def polygon_mask(points: Sequence[tuple[float, float]], blur: float = 0.0) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(mask)
    d.polygon([(sx(x), sx(y)) for x, y in points], fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(sx(blur)))
    return mask


def rounded_rect_mask(rect: Sequence[float], radius: float, blur: float = 0.0) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle(sc_rect(rect), radius=sx(radius), fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(sx(blur)))
    return mask


def curve_mask(
    points: Sequence[tuple[float, float]],
    width: float,
    blur: float = 0.0,
) -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    d = ImageDraw.Draw(mask)
    scaled = [(sx(x), sx(y)) for x, y in points]
    if len(points) == 2:
        d.line(scaled, fill=255, width=sx(width))
    else:
        samples: list[tuple[int, int]] = []
        for i in range(50):
            t = i / 49
            x, y = bezier(points, t)
            samples.append((sx(x), sx(y)))
        d.line(samples, fill=255, width=sx(width), joint="curve")
    radius = sx(width / 2)
    for x, y in scaled:
        d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    if blur:
        mask = mask.filter(ImageFilter.GaussianBlur(sx(blur)))
    return mask


def bezier(points: Sequence[tuple[float, float]], t: float) -> tuple[float, float]:
    pts = list(points)
    while len(pts) > 1:
        pts = [
            (a[0] * (1 - t) + b[0] * t, a[1] * (1 - t) + b[1] * t)
            for a, b in zip(pts, pts[1:])
        ]
    return pts[0]


def textured_fill(
    base: Image.Image,
    mask: Image.Image,
    color: tuple[int, int, int, int],
    seed: int,
    highlight: float = 0.12,
    shadow: float = 0.12,
) -> None:
    layer = Image.new("RGBA", (CANVAS, CANVAS), color)
    layer.putalpha(ImageChops.multiply(mask, Image.new("L", (CANVAS, CANVAS), color[3])))
    base.alpha_composite(layer)

    highlight_layer = Image.new("RGBA", (CANVAS, CANVAS), (255, 244, 215, int(42 * highlight / 0.12)))
    highlight_mask = ellipse_mask((112, 98, 390, 286), 34)
    highlight_mask = ImageChops.multiply(highlight_mask, mask)
    highlight_layer.putalpha(highlight_mask.point(lambda p: int(p * 0.26)))
    base.alpha_composite(highlight_layer)

    shadow_layer = Image.new("RGBA", (CANVAS, CANVAS), (86, 53, 32, int(42 * shadow / 0.12)))
    shadow_mask = ellipse_mask((80, 258, 438, 402), 38)
    shadow_mask = ImageChops.multiply(shadow_mask, mask)
    shadow_layer.putalpha(shadow_mask.point(lambda p: int(p * 0.22)))
    base.alpha_composite(shadow_layer)

    rng = random.Random(seed)
    speckles = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(speckles)
    for _ in range(90):
        x = rng.randrange(40 * SCALE, CANVAS - 40 * SCALE)
        y = rng.randrange(40 * SCALE, CANVAS - 40 * SCALE)
        r = rng.uniform(0.45, 1.35) * SCALE
        lift = rng.randint(-18, 18)
        d.ellipse(
            (x - r, y - r, x + r, y + r),
            fill=(
                max(0, min(255, color[0] + lift)),
                max(0, min(255, color[1] + lift)),
                max(0, min(255, color[2] + lift)),
                rng.randint(16, 34),
            ),
        )
    r, g, b, a = speckles.split()
    speckles.putalpha(ImageChops.multiply(a, mask))
    base.alpha_composite(speckles)


def composite_color(base: Image.Image, mask: Image.Image, color: tuple[int, int, int, int]) -> None:
    layer = Image.new("RGBA", (CANVAS, CANVAS), color)
    layer.putalpha(ImageChops.multiply(mask, Image.new("L", (CANVAS, CANVAS), color[3])))
    base.alpha_composite(layer)


def draw_part(
    base: Image.Image,
    mask: Image.Image,
    color: tuple[int, int, int, int],
    seed: int,
    fur: bool = True,
    angle: float = 0.0,
    stroke_count: int = 70,
) -> None:
    textured_fill(base, mask, color, seed)
    if fur:
        add_fur(base, mask, color, seed + 1009, angle, stroke_count)


def add_fur(
    base: Image.Image,
    mask: Image.Image,
    color: tuple[int, int, int, int],
    seed: int,
    angle: float,
    count: int,
) -> None:
    rng = random.Random(seed)
    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    mask_px = mask.load()
    for _ in range(count):
        for _attempt in range(20):
            x = rng.randrange(20 * SCALE, CANVAS - 20 * SCALE)
            y = rng.randrange(20 * SCALE, CANVAS - 20 * SCALE)
            if mask_px[x, y] > 24:
                break
        else:
            continue
        length = rng.uniform(3.0, 9.0) * SCALE
        theta = angle + rng.uniform(-0.75, 0.75)
        dx = math.cos(theta) * length
        dy = math.sin(theta) * length
        lift = rng.randint(-20, 22)
        alpha = rng.randint(45, 95)
        stroke = (
            max(0, min(255, color[0] + lift)),
            max(0, min(255, color[1] + lift)),
            max(0, min(255, color[2] + lift)),
            alpha,
        )
        d.line((x - dx / 2, y - dy / 2, x + dx / 2, y + dy / 2), fill=stroke, width=max(1, SCALE))
    r, g, b, a = layer.split()
    layer.putalpha(ImageChops.multiply(a, mask))
    base.alpha_composite(layer)


def draw_soft_shadow(img: Image.Image, rect: Sequence[float], alpha: int = 34) -> None:
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.ellipse(sc_rect(rect), fill=(45, 35, 25, alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(sx(5)))
    img.alpha_composite(shadow)


def draw_eye(draw: ImageDraw.ImageDraw, cx: float, cy: float, radius: float, lid: float = 0.0) -> None:
    box = (sx(cx - radius), sx(cy - radius * 0.85), sx(cx + radius), sx(cy + radius * 0.85))
    draw.ellipse(box, fill=AMBER, outline=(70, 48, 28, 255), width=sx(1.2))
    draw.ellipse(
        (sx(cx - radius * 0.25), sx(cy - radius * 0.65), sx(cx + radius * 0.25), sx(cy + radius * 0.65)),
        fill=(33, 28, 22, 255),
    )
    draw.ellipse(
        (sx(cx - radius * 0.48), sx(cy - radius * 0.48), sx(cx - radius * 0.22), sx(cy - radius * 0.22)),
        fill=(255, 246, 186, 220),
    )
    if lid:
        draw.arc(box, start=188, end=352, fill=(109, 75, 45, 220), width=sx(1.6))


def draw_closed_eye(draw: ImageDraw.ImageDraw, cx: float, cy: float, w: float, tilt: float = 0.0) -> None:
    draw.arc(sc_rect((cx - w, cy - 5 + tilt, cx + w, cy + 7 - tilt)), 195, 345, fill=(87, 59, 42, 230), width=sx(1.5))


def draw_whiskers(draw: ImageDraw.ImageDraw, x: float, y: float, direction: int = 1) -> None:
    for off, curve in [(-7, -10), (0, -3), (7, 5)]:
        draw.line(
            (sx(x), sx(y + off), sx(x + direction * 58), sx(y + off + curve)),
            fill=WHISKER,
            width=sx(1),
        )


def draw_ears(img: Image.Image, left: tuple[float, float], right: tuple[float, float], scale: float = 1.0) -> None:
    for idx, (cx, cy, flip) in enumerate([(left[0], left[1], -1), (right[0], right[1], 1)]):
        outer = [
            (cx, cy - 42 * scale),
            (cx + flip * 36 * scale, cy + 18 * scale),
            (cx - flip * 19 * scale, cy + 16 * scale),
        ]
        inner = [
            (cx + flip * 1 * scale, cy - 25 * scale),
            (cx + flip * 20 * scale, cy + 9 * scale),
            (cx - flip * 9 * scale, cy + 8 * scale),
        ]
        draw_part(img, polygon_mask(outer, 0.6), LIGHT_ORANGE, 300 + idx, True, -0.6 * flip, 18)
        composite_color(img, polygon_mask(inner, 0.5), (224, 158, 151, 210))


def draw_tail(
    img: Image.Image,
    points: Sequence[tuple[float, float]],
    width: float,
    seed: int,
    ring_angle: float = 0.0,
) -> None:
    mask = curve_mask(points, width, 0.7)
    draw_part(img, mask, LIGHT_ORANGE, seed, True, 0.05, 55)
    ring_layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(ring_layer)
    for t in np.linspace(0.15, 0.88, 5):
        x, y = bezier(points, float(t)) if len(points) > 2 else (
            points[0][0] * (1 - t) + points[-1][0] * t,
            points[0][1] * (1 - t) + points[-1][1] * t,
        )
        length = width * 1.45
        d.line(
            (
                sx(x - math.sin(ring_angle) * length / 2),
                sx(y + math.cos(ring_angle) * length / 2),
                sx(x + math.sin(ring_angle) * length / 2),
                sx(y - math.cos(ring_angle) * length / 2),
            ),
            fill=(154, 103, 58, 82),
            width=sx(3.4),
        )
    r, g, b, a = ring_layer.split()
    ring_layer.putalpha(ImageChops.multiply(a, mask))
    img.alpha_composite(ring_layer)


def draw_white_paw(img: Image.Image, cx: float, cy: float, rx: float, ry: float, seed: int) -> None:
    mask = ellipse_mask((cx - rx, cy - ry, cx + rx, cy + ry), 0.5)
    draw_part(img, mask, WARM_WHITE, seed, True, 0.1, 22)
    d = ImageDraw.Draw(img)
    for off in [-7, 0, 7]:
        d.arc(sc_rect((cx + off - 3, cy + ry * 0.2, cx + off + 5, cy + ry * 0.8)), 205, 340, fill=(202, 187, 174, 145), width=sx(0.8))


def draw_side_face(img: Image.Image, x: float, y: float, facing: int = 1, open_eyes: bool = True) -> None:
    d = ImageDraw.Draw(img)
    draw_ears(img, (x - 19 * facing, y - 29), (x + 23 * facing, y - 25), 0.72)
    head_mask = ellipse_mask((x - 47, y - 42, x + 50, y + 45), 0.6)
    draw_part(img, head_mask, LIGHT_ORANGE, 710, True, -0.1, 62)
    muzzle = ellipse_mask((x + 12 * facing - 32, y + 7, x + 12 * facing + 39, y + 42), 0.4)
    draw_part(img, muzzle, WARM_WHITE, 711, True, 0.0, 24)
    blaze = polygon_mask([(x - 7, y - 33), (x + 16 * facing, y + 12), (x - 8, y + 40), (x - 23 * facing, y + 4)], 0.9)
    composite_color(img, blaze, (248, 243, 230, 168))
    if open_eyes:
        draw_eye(d, x + 15 * facing, y - 6, 9.2)
        draw_eye(d, x - 16 * facing, y - 8, 7.4, 0.15)
    else:
        draw_closed_eye(d, x + 14 * facing, y - 8, 11)
        draw_closed_eye(d, x - 15 * facing, y - 9, 9)
    d.polygon(
        [(sx(x + 31 * facing), sx(y + 17)), (sx(x + 21 * facing), sx(y + 11)), (sx(x + 21 * facing), sx(y + 23))],
        fill=PINK,
    )
    draw_whiskers(d, x + 22 * facing, y + 20, facing)
    for off in [-18, -5, 9]:
        d.arc(sc_rect((x - 21 + off, y - 31, x + 10 + off, y - 8)), 205, 326, fill=(145, 94, 52, 110), width=sx(1.2))


def draw_front_face(
    img: Image.Image,
    x: float,
    y: float,
    head_shift: tuple[float, float] = (0, 0),
    eye_target: float = 0.0,
    sleepy: bool = False,
) -> None:
    x += head_shift[0]
    y += head_shift[1]
    d = ImageDraw.Draw(img)
    draw_ears(img, (x - 43, y - 34), (x + 43, y - 34), 0.85)
    head_mask = ellipse_mask((x - 72, y - 61, x + 72, y + 70), 0.8)
    draw_part(img, head_mask, LIGHT_ORANGE, 1300, True, 0.0, 90)
    muzzle = ellipse_mask((x - 47, y + 10, x + 47, y + 63), 0.5)
    draw_part(img, muzzle, WARM_WHITE, 1301, True, 0.0, 36)
    chin = ellipse_mask((x - 38, y + 41, x + 38, y + 84), 0.3)
    composite_color(img, chin, (250, 247, 238, 210))
    blaze = polygon_mask([(x - 13, y - 55), (x + 17, y - 55), (x + 12, y + 17), (x, y + 31), (x - 14, y + 16)], 0.8)
    composite_color(img, blaze, (250, 245, 235, 135))
    if sleepy:
        draw_closed_eye(d, x - 30, y - 5, 13)
        draw_closed_eye(d, x + 30, y - 5, 13)
    else:
        draw_eye(d, x - 31 + eye_target * 2.2, y - 6, 11.5)
        draw_eye(d, x + 31 + eye_target * 2.2, y - 6, 11.5)
    d.ellipse(sc_rect((x - 8, y + 19, x + 8, y + 31)), fill=PINK)
    d.arc(sc_rect((x - 25, y + 24, x, y + 48)), 10, 72, fill=(100, 68, 50, 190), width=sx(1.1))
    d.arc(sc_rect((x, y + 24, x + 25, y + 48)), 108, 170, fill=(100, 68, 50, 190), width=sx(1.1))
    draw_whiskers(d, x - 27, y + 26, -1)
    draw_whiskers(d, x + 27, y + 26, 1)
    for off in [-24, -7, 10]:
        d.arc(sc_rect((x - 21 + off, y - 49, x + 17 + off, y - 18)), 205, 332, fill=(145, 94, 52, 115), width=sx(1.3))


def render_walk_frame(i: int) -> Image.Image:
    phase = 2 * math.pi * i / FRAME_COUNT
    img = new_canvas()
    bob = math.sin(phase) * 3.5
    draw_soft_shadow(img, (115, 340, 415, 386), 30)
    draw_tail(img, [(132, 248 + bob), (87, 234 + math.sin(phase + 0.8) * 8), (74, 213 + math.sin(phase) * 5)], 23, 900 + i, -0.7)
    body_mask = ellipse_mask((130, 203 + bob, 365, 328 + bob), 0.9)
    draw_part(img, body_mask, CREAM_ORANGE, 901, True, 0.03, 110)
    belly_mask = ellipse_mask((168, 258 + bob, 354, 341 + bob), 0.5)
    draw_part(img, belly_mask, WARM_WHITE, 902, True, 0.05, 48)
    d = ImageDraw.Draw(img)
    for off in [-40, -10, 25, 57]:
        d.arc(sc_rect((180 + off, 216 + bob, 232 + off, 250 + bob)), 195, 335, fill=(139, 93, 55, 105), width=sx(1.6))

    leg_data = [
        (188, 304, math.sin(phase), 0),
        (238, 305, math.sin(phase + math.pi), 1),
        (298, 301, math.sin(phase + math.pi), 2),
        (340, 299, math.sin(phase), 3),
    ]
    for lx, ly, swing, idx in leg_data:
        foot_x = lx + swing * 15
        foot_y = ly + 44 - abs(swing) * 4
        leg_mask = curve_mask([(lx, ly + bob), (lx + swing * 8, ly + 30 + bob), (foot_x, foot_y + bob)], 14, 0.4)
        color = WARM_WHITE if idx in (2, 3) else (232, 210, 180, 255)
        draw_part(img, leg_mask, color, 980 + idx, True, 1.35, 24)
        draw_white_paw(img, foot_x, foot_y + bob, 17, 8, 990 + idx)
    draw_side_face(img, 374, 214 + bob * 0.45, 1, True)
    return finalize(img)


def render_sleep_frame(i: int) -> Image.Image:
    phase = 2 * math.pi * i / FRAME_COUNT
    breath = math.sin(phase)
    img = new_canvas()
    draw_soft_shadow(img, (96, 321, 430, 371), 26)
    body_top = 219 - breath * 2.2
    body_bottom = 342 + breath * 3.2
    body_mask = ellipse_mask((142, body_top, 388, body_bottom), 1.0)
    draw_part(img, body_mask, CREAM_ORANGE, 400, True, -0.08, 120)
    belly_mask = ellipse_mask((165, 274 + breath * 1.8, 358, 354 + breath * 2.5), 0.6)
    draw_part(img, belly_mask, WARM_WHITE, 401, True, 0.05, 52)
    draw_tail(
        img,
        [
            (344, 275 + breath * 1.5),
            (405, 277 + breath),
            (431, 302 + breath),
            (387, 323 + breath * 1.5),
        ],
        24,
        402,
        -0.2,
    )
    draw_side_face(img, 154, 252 + breath * 0.7, -1, False)
    draw_white_paw(img, 218, 333 + breath * 1.6, 27, 12, 403)
    draw_white_paw(img, 274, 338 + breath * 1.8, 24, 11, 404)
    d = ImageDraw.Draw(img)
    d.arc(sc_rect((194, 287 + breath, 252, 319 + breath)), 190, 350, fill=(180, 137, 95, 90), width=sx(1.2))
    return finalize(img)


def draw_sitting_body(img: Image.Image, seed: int = 0, body_y: float = 0.0) -> None:
    draw_soft_shadow(img, (144, 351 + body_y, 375, 398 + body_y), 28)
    draw_tail(img, [(326, 329 + body_y), (398, 345 + body_y), (421, 384 + body_y)], 22, 1500 + seed, -0.7)
    body_mask = ellipse_mask((178, 190 + body_y, 344, 371 + body_y), 0.8)
    draw_part(img, body_mask, CREAM_ORANGE, 1510 + seed, True, math.pi / 2, 105)
    chest_mask = ellipse_mask((203, 218 + body_y, 323, 382 + body_y), 0.6)
    draw_part(img, chest_mask, WARM_WHITE, 1511 + seed, True, math.pi / 2, 62)
    draw_white_paw(img, 220, 368 + body_y, 30, 14, 1512 + seed)
    draw_white_paw(img, 301, 368 + body_y, 30, 14, 1513 + seed)


def render_scratch_frame(i: int) -> Image.Image:
    phase = 2 * math.pi * i / FRAME_COUNT
    img = new_canvas()
    head_dx = math.sin(phase) * 3.0
    head_dy = -abs(math.sin(phase)) * 2.0
    draw_sitting_body(img, 30, 0)
    thigh_mask = ellipse_mask((311, 284, 373, 352), 0.5)
    draw_part(img, thigh_mask, (230, 197, 151, 255), 1601, True, -0.9, 34)
    foot_x = 330 + math.sin(phase * 2) * 15
    foot_y = 193 + math.cos(phase * 2) * 9
    leg_mask = curve_mask([(330, 310), (363, 260), (foot_x, foot_y)], 17, 0.5)
    draw_part(img, leg_mask, WARM_WHITE, 1602, True, -1.2, 32)
    draw_white_paw(img, foot_x, foot_y, 18, 12, 1603)
    draw_front_face(img, 258, 158, (head_dx, head_dy), eye_target=-0.2)
    d = ImageDraw.Draw(img)
    for j in range(3):
        arc_y = 180 + j * 7 + math.sin(phase * 2) * 2
        d.arc(sc_rect((321, arc_y, 367, arc_y + 24)), 210, 315, fill=(150, 96, 62, 120), width=sx(1.0))
    return finalize(img)


def render_teaser_frame(i: int) -> Image.Image:
    phase = 2 * math.pi * i / FRAME_COUNT
    img = new_canvas()
    draw_sitting_body(img, 60, 0)
    target_x = 350 + math.cos(phase) * 34
    target_y = 90 + math.sin(phase * 1.35) * 22
    gaze = max(-1.0, min(1.0, (target_x - 258) / 88))
    paw_raise = (math.sin(phase - 0.8) + 1) / 2
    paw_x = 304 + paw_raise * 30
    paw_y = 272 - paw_raise * 94
    foreleg_mask = curve_mask([(294, 290), (302, 235 - paw_raise * 42), (paw_x, paw_y)], 16, 0.4)
    draw_part(img, foreleg_mask, WARM_WHITE, 1701, True, -1.0, 32)
    draw_white_paw(img, paw_x, paw_y, 18, 12, 1702)
    draw_front_face(img, 258, 158, (math.sin(phase) * 2, -paw_raise * 1.5), eye_target=gaze)

    d = ImageDraw.Draw(img)
    wand_tip = (target_x, target_y)
    handle = (430, 38 + math.sin(phase) * 5)
    d.line((sx(handle[0]), sx(handle[1]), sx(wand_tip[0]), sx(wand_tip[1])), fill=(93, 62, 42, 210), width=sx(2.0))
    d.line((sx(wand_tip[0]), sx(wand_tip[1]), sx(target_x - 22), sx(target_y + 24)), fill=(180, 180, 180, 190), width=sx(1.0))
    feather_colors = [(226, 71, 82, 235), (245, 185, 72, 230), (72, 160, 151, 220)]
    for n, col in enumerate(feather_colors):
        ang = phase + n * 2.1
        dx = math.cos(ang) * 20
        dy = math.sin(ang) * 10
        d.ellipse(sc_rect((target_x - 10 + dx * 0.2, target_y + 13 + dy * 0.2, target_x + 18 + dx, target_y + 35 + dy)), fill=col)
    return finalize(img)


def render_frame(action: str, i: int) -> Image.Image:
    if action == "walk":
        return render_walk_frame(i)
    if action == "sleep":
        return render_sleep_frame(i)
    if action == "scratch":
        return render_scratch_frame(i)
    if action == "teaser":
        return render_teaser_frame(i)
    raise ValueError(action)


def finalize(img: Image.Image) -> Image.Image:
    small = img.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    arr = np.array(small)
    alpha = arr[:, :, 3]
    alpha[alpha < 3] = 0
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, "RGBA")


def save_frames() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for action in ["sleep", "scratch", "teaser", "walk", "walk_left"]:
        (OUT_DIR / action).mkdir(parents=True, exist_ok=True)

    for action in ["sleep", "scratch", "teaser", "walk"]:
        for i in range(FRAME_COUNT):
            img = render_frame(action, i)
            img.save(OUT_DIR / action / f"frame_{i:03d}.png")

    for i in range(FRAME_COUNT):
        img = Image.open(OUT_DIR / "walk" / f"frame_{i:03d}.png").convert("RGBA")
        img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        img.save(OUT_DIR / "walk_left" / f"frame_{i:03d}.png")


def validate() -> dict[str, object]:
    report: dict[str, object] = {
        "canvas": f"{SIZE}x{SIZE}",
        "frame_count_per_action": FRAME_COUNT,
        "actions": {},
        "walk_left_is_horizontal_mirror_of_walk": True,
    }
    actions: dict[str, object] = {}
    for action in ["sleep", "scratch", "teaser", "walk", "walk_left"]:
        files = sorted((OUT_DIR / action).glob("*.png"))
        frames = []
        for path in files:
            img = Image.open(path).convert("RGBA")
            alpha = np.array(img)[:, :, 3]
            ys, xs = np.where(alpha > 8)
            bbox = None
            margin = None
            if len(xs) and len(ys):
                bbox = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
                margin = int(min(xs.min(), ys.min(), SIZE - 1 - xs.max(), SIZE - 1 - ys.max()))
            frames.append(
                {
                    "file": path.name,
                    "size": img.size,
                    "mode": img.mode,
                    "alpha_pixels": int((alpha > 0).sum()),
                    "bbox": bbox,
                    "min_margin_px": margin,
                }
            )
        actions[action] = {"png_count": len(files), "frames": frames}

    for i in range(FRAME_COUNT):
        right = Image.open(OUT_DIR / "walk" / f"frame_{i:03d}.png").convert("RGBA")
        left = Image.open(OUT_DIR / "walk_left" / f"frame_{i:03d}.png").convert("RGBA")
        expected = right.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if ImageChops.difference(left, expected).getbbox() is not None:
            report["walk_left_is_horizontal_mirror_of_walk"] = False
            break

    report["actions"] = actions
    return report


def main() -> None:
    save_frames()
    report = validate()
    Path("assets/sprite_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "actions"}, indent=2))
    for action, data in report["actions"].items():  # type: ignore[union-attr]
        print(action, data["png_count"])  # type: ignore[index]


if __name__ == "__main__":
    main()

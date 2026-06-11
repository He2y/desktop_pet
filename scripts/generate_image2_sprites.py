from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter


SIZE = 512
FRAME_COUNT = 16
KEYFRAMES = Path("assets/image2_keyframes_alpha")
OUT_DIR = Path("assets/sprites")


ACTION_TARGETS = {
    "sleep": {"max_w": 390, "max_h": 205, "center": (256, 283)},
    "walk": {"max_w": 405, "max_h": 245, "center": (256, 276)},
    "scratch": {"max_w": 310, "max_h": 350, "center": (256, 268)},
    "teaser": {"max_w": 315, "max_h": 360, "center": (256, 276)},
}


def alpha_bbox(img: Image.Image, threshold: int = 8) -> tuple[int, int, int, int]:
    alpha = np.array(img.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0 or len(ys) == 0:
        raise ValueError("image has no visible alpha")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def trim(img: Image.Image) -> Image.Image:
    return img.convert("RGBA").crop(alpha_bbox(img))


def remove_green_fringes(img: Image.Image) -> Image.Image:
    arr = np.array(img.convert("RGBA")).astype(np.int16)
    alpha = arr[:, :, 3]
    edge = (alpha > 0) & (alpha < 245)
    green_dominant = (arr[:, :, 1] > arr[:, :, 0] + 12) & (arr[:, :, 1] > arr[:, :, 2] + 12)
    mask = edge & green_dominant
    arr[:, :, 1][mask] = np.maximum(arr[:, :, 0][mask], arr[:, :, 2][mask])
    arr[:, :, :4] = np.clip(arr[:, :, :4], 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def normalize(action: str) -> Image.Image:
    spec = ACTION_TARGETS[action]
    subject = remove_green_fringes(trim(Image.open(KEYFRAMES / f"{action}.png")))
    scale = min(spec["max_w"] / subject.width, spec["max_h"] / subject.height)
    w = max(1, int(round(subject.width * scale)))
    h = max(1, int(round(subject.height * scale)))
    subject = subject.resize((w, h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cx, cy = spec["center"]
    canvas.alpha_composite(subject, (int(round(cx - w / 2)), int(round(cy - h / 2))))
    return remove_green_fringes(canvas)


def transform_subject(
    base: Image.Image,
    scale_x: float = 1.0,
    scale_y: float = 1.0,
    rotate: float = 0.0,
    dx: float = 0.0,
    dy: float = 0.0,
    anchor_bottom: bool = True,
) -> Image.Image:
    bbox = alpha_bbox(base)
    subject = base.crop(bbox)
    new_w = max(1, int(round(subject.width * scale_x)))
    new_h = max(1, int(round(subject.height * scale_y)))
    subject = subject.resize((new_w, new_h), Image.Resampling.LANCZOS)
    if abs(rotate) > 0.01:
        subject = subject.rotate(rotate, resample=Image.Resampling.BICUBIC, expand=True)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    old_cx = (bbox[0] + bbox[2]) / 2
    old_cy = (bbox[1] + bbox[3]) / 2
    if anchor_bottom:
        x = old_cx + dx - subject.width / 2
        y = bbox[3] + dy - subject.height
    else:
        x = old_cx + dx - subject.width / 2
        y = old_cy + dy - subject.height / 2
    canvas.alpha_composite(remove_green_fringes(subject), (int(round(x)), int(round(y))))
    return remove_green_fringes(canvas)


def draw_teaser_wand(frame: Image.Image, i: int) -> Image.Image:
    phase = 2 * math.pi * i / FRAME_COUNT
    out = frame.copy()
    d = ImageDraw.Draw(out)
    tip_x = 345 + math.cos(phase) * 44
    tip_y = 105 + math.sin(phase * 1.25) * 26
    handle_x = 455
    handle_y = 45 + math.sin(phase + 0.8) * 10
    d.line((handle_x, handle_y, tip_x, tip_y), fill=(72, 54, 46, 230), width=3)
    d.line((tip_x, tip_y, tip_x - 18, tip_y + 24), fill=(150, 130, 150, 210), width=2)
    colors = [(235, 71, 82, 245), (246, 185, 60, 235), (78, 128, 220, 230)]
    for n, color in enumerate(colors):
        ang = phase + n * 2.05
        cx = tip_x - 17 + math.cos(ang) * 12
        cy = tip_y + 25 + math.sin(ang) * 8
        d.ellipse((cx - 8, cy - 5, cx + 14, cy + 9), fill=color)
    return out


def generate_sleep(base: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(FRAME_COUNT):
        breath = math.sin(2 * math.pi * i / FRAME_COUNT)
        frames.append(transform_subject(base, 1.0 + 0.006 * breath, 1.0 + 0.018 * breath, 0, 0, -2.0 * breath, True))
    return frames


def generate_walk(base: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(FRAME_COUNT):
        phase = 2 * math.pi * i / FRAME_COUNT
        bob = -4.0 * abs(math.sin(phase))
        tilt = 1.1 * math.sin(phase)
        stretch = 1.0 + 0.010 * math.sin(phase + math.pi / 2)
        frame = transform_subject(base, stretch, 1.0 - 0.006 * math.sin(phase), tilt, 0, bob, True)
        frames.append(frame)
    return frames


def generate_scratch(base: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(FRAME_COUNT):
        phase = 2 * math.pi * i / FRAME_COUNT
        frame = transform_subject(
            base,
            1.0,
            1.0,
            1.8 * math.sin(phase * 2.0),
            2.0 * math.sin(phase * 2.0),
            -1.5 * abs(math.sin(phase * 2.0)),
            True,
        )
        frames.append(frame)
    return frames


def generate_teaser(base: Image.Image) -> list[Image.Image]:
    frames = []
    # Keep the cat sprite exactly the same size and placement. Only the toy moves.
    fixed_cat = base.copy()
    for i in range(FRAME_COUNT):
        frames.append(draw_teaser_wand(fixed_cat, i))
    return frames


def write_frames(action: str, frames: list[Image.Image]) -> None:
    action_dir = OUT_DIR / action
    action_dir.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames):
        arr = np.array(frame.convert("RGBA"))
        alpha = arr[:, :, 3]
        alpha[alpha < 3] = 0
        arr[:, :, 3] = alpha
        Image.fromarray(arr, "RGBA").save(action_dir / f"frame_{i:03d}.png")


def validate() -> dict[str, object]:
    report: dict[str, object] = {
        "generator": "image2 keyframes + local sprite animation",
        "canvas": f"{SIZE}x{SIZE}",
        "frame_count_per_action": FRAME_COUNT,
        "walk_left_is_horizontal_mirror_of_walk": True,
        "teaser_cat_body_constant": True,
        "actions": {},
    }
    actions: dict[str, object] = {}
    for action in ["sleep", "scratch", "teaser", "walk", "walk_left"]:
        files = sorted((OUT_DIR / action).glob("frame_*.png"))
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
            frames.append({"file": path.name, "size": img.size, "mode": img.mode, "bbox": bbox, "min_margin_px": margin})
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
    bases = {action: normalize(action) for action in ACTION_TARGETS}
    write_frames("sleep", generate_sleep(bases["sleep"]))
    write_frames("scratch", generate_scratch(bases["scratch"]))
    write_frames("teaser", generate_teaser(bases["teaser"]))
    walk_frames = generate_walk(bases["walk"])
    write_frames("walk", walk_frames)
    write_frames("walk_left", [f.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for f in walk_frames])
    report = validate()
    Path("assets/sprite_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "actions"}, indent=2))
    for action, data in report["actions"].items():  # type: ignore[union-attr]
        margins = [f["min_margin_px"] for f in data["frames"] if f["min_margin_px"] is not None]  # type: ignore[index]
        print(action, data["png_count"], "min_margin", min(margins))  # type: ignore[index]


if __name__ == "__main__":
    main()

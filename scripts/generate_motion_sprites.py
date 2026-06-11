from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


SIZE = 512
FRAME_COUNT = 16
KEYFRAME_ROOT = Path("assets/image2_motion_alpha")
OUT_DIR = Path("assets/sprites")

ACTION_SPECS = {
    "stand": {"max_w": 330, "max_h": 355, "center": (256, 274), "mode": "idle"},
    "walk": {"max_w": 410, "max_h": 255, "center": (256, 278), "mode": "walk"},
    "lie": {"max_w": 410, "max_h": 255, "center": (256, 292), "mode": "lie"},
    "eat": {"max_w": 380, "max_h": 355, "center": (256, 286), "mode": "eat"},
    "drag": {"max_w": 380, "max_h": 380, "center": (256, 260), "mode": "drag"},
    "scratch": {"max_w": 350, "max_h": 365, "center": (256, 278), "mode": "scratch"},
    "teaser": {"max_w": 395, "max_h": 390, "center": (256, 278), "mode": "teaser"},
}

SEQUENCES = {
    "idle": [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 0, 1, 0],
    "walk": [0, 1, 2, 3] * 4,
    "lie": [0, 1, 2, 3, 2, 1, 0, 0, 1, 2, 3, 2, 1, 0, 0, 0],
    "eat": [0, 1, 2, 3] * 4,
    "drag": [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3],
    "scratch": [0, 1, 2, 1, 2, 1, 3, 0, 1, 2, 1, 2, 3, 0, 0, 0],
    "teaser": [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0, 1, 2, 3],
}


def alpha_bbox(img: Image.Image, threshold: int = 8) -> tuple[int, int, int, int]:
    alpha = np.array(img.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0 or len(ys) == 0:
        raise ValueError("image has no visible alpha")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def remove_green_fringes(img: Image.Image) -> Image.Image:
    arr = np.array(img.convert("RGBA")).astype(np.int16)
    alpha = arr[:, :, 3]
    edge = (alpha > 0) & (alpha < 245)
    green_dominant = (arr[:, :, 1] > arr[:, :, 0] + 10) & (arr[:, :, 1] > arr[:, :, 2] + 10)
    mask = edge & green_dominant
    arr[:, :, 1][mask] = np.maximum(arr[:, :, 0][mask], arr[:, :, 2][mask])
    arr[:, :, :4] = np.clip(arr[:, :, :4], 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def load_normalized_keyframes(action: str) -> list[Image.Image]:
    spec = ACTION_SPECS[action]
    frames: list[Image.Image] = []
    for path in sorted((KEYFRAME_ROOT / action).glob("key_*.png")):
        source = remove_green_fringes(Image.open(path).convert("RGBA"))
        cropped = source.crop(alpha_bbox(source))
        scale = min(spec["max_w"] / cropped.width, spec["max_h"] / cropped.height)
        size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
        resized = cropped.resize(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        cx, cy = spec["center"]
        canvas.alpha_composite(resized, (round(cx - resized.width / 2), round(cy - resized.height / 2)))
        frames.append(remove_green_fringes(canvas))
    if len(frames) != 4:
        raise RuntimeError(f"{action}: expected 4 keyframes, got {len(frames)}")
    return frames


def transform(frame: Image.Image, action: str, index: int) -> Image.Image:
    phase = 2 * math.pi * index / FRAME_COUNT
    bbox = alpha_bbox(frame)
    subject = frame.crop(bbox)

    if action == "walk":
        dx = math.sin(phase) * 1.2
        dy = -abs(math.sin(phase)) * 3.0
        rot = math.sin(phase) * 0.9
        sx = 1.0 + math.sin(phase + math.pi / 2) * 0.006
        sy = 1.0 - math.sin(phase + math.pi / 2) * 0.004
    elif action == "drag":
        dx = math.sin(phase * 1.5) * 3.2
        dy = math.cos(phase * 1.5) * 2.2
        rot = math.sin(phase * 1.5) * 2.6
        sx = 1.0
        sy = 1.0
    elif action == "scratch":
        dx = math.sin(phase * 2.0) * 1.8
        dy = -abs(math.sin(phase * 2.0)) * 2.2
        rot = math.sin(phase * 2.0) * 1.4
        sx = 1.0
        sy = 1.0
    elif action == "teaser":
        dx = math.sin(phase * 1.3) * 2.5
        dy = -abs(math.sin(phase * 1.3)) * 2.4
        rot = math.sin(phase * 1.3) * 1.2
        sx = 1.0
        sy = 1.0
    elif action == "eat":
        dx = 0
        dy = math.sin(phase * 2.0) * 2.0
        rot = math.sin(phase * 2.0) * 0.7
        sx = 1.0
        sy = 1.0
    elif action == "lie":
        dx = math.sin(phase) * 1.4
        dy = math.sin(phase) * 1.3
        rot = math.sin(phase) * 0.8
        sx = 1.0 + math.sin(phase) * 0.004
        sy = 1.0 + math.sin(phase) * 0.008
    else:
        dx = math.sin(phase) * 1.0
        dy = math.sin(phase * 1.3) * 1.4
        rot = math.sin(phase) * 0.6
        sx = 1.0
        sy = 1.0

    resized = subject.resize(
        (max(1, round(subject.width * sx)), max(1, round(subject.height * sy))),
        Image.Resampling.LANCZOS,
    )
    if abs(rot) > 0.01:
        resized = resized.rotate(rot, resample=Image.Resampling.BICUBIC, expand=True)

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    old_cx = (bbox[0] + bbox[2]) / 2
    old_bottom = bbox[3]
    x = round(old_cx + dx - resized.width / 2)
    y = round(old_bottom + dy - resized.height)
    canvas.alpha_composite(remove_green_fringes(resized), (x, y))
    arr = np.array(canvas.convert("RGBA"))
    alpha = arr[:, :, 3]
    alpha[alpha < 3] = 0
    arr[:, :, 3] = alpha
    return Image.fromarray(arr, "RGBA")


def write_action(action: str) -> list[Image.Image]:
    keyframes = load_normalized_keyframes(action)
    sequence = SEQUENCES[ACTION_SPECS[action]["mode"]]
    frames = [transform(keyframes[key], action, i) for i, key in enumerate(sequence)]
    action_dir = OUT_DIR / action
    action_dir.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames):
        frame.save(action_dir / f"frame_{i:03d}.png")
    return frames


def validate(actions: list[str]) -> dict[str, object]:
    report: dict[str, object] = {
        "generator": "image2 multi-keyframe motion sprites",
        "canvas": f"{SIZE}x{SIZE}",
        "frame_count_per_action": FRAME_COUNT,
        "walk_left_is_horizontal_mirror_of_walk": True,
        "actions": {},
    }
    actions_report: dict[str, object] = {}
    for action in actions + ["walk_left"]:
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
        actions_report[action] = {"png_count": len(files), "frames": frames}

    for i in range(FRAME_COUNT):
        right = Image.open(OUT_DIR / "walk" / f"frame_{i:03d}.png").convert("RGBA")
        left = Image.open(OUT_DIR / "walk_left" / f"frame_{i:03d}.png").convert("RGBA")
        expected = right.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if ImageChops.difference(left, expected).getbbox() is not None:
            report["walk_left_is_horizontal_mirror_of_walk"] = False
            break

    report["actions"] = actions_report
    return report


def main() -> None:
    actions = list(ACTION_SPECS)
    for action in actions:
        write_action(action)
    walk_frames = sorted((OUT_DIR / "walk").glob("frame_*.png"))
    left_dir = OUT_DIR / "walk_left"
    left_dir.mkdir(parents=True, exist_ok=True)
    for path in walk_frames:
        img = Image.open(path).convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        img.save(left_dir / path.name)

    report = validate(actions)
    Path("assets/motion_sprite_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "actions"}, indent=2))
    for action, data in report["actions"].items():  # type: ignore[union-attr]
        margins = [f["min_margin_px"] for f in data["frames"] if f["min_margin_px"] is not None]  # type: ignore[index]
        print(action, data["png_count"], "min_margin", min(margins))  # type: ignore[index]


if __name__ == "__main__":
    main()

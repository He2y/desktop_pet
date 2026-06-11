from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


SPRITE_ROOT = Path("assets/sprites")
REPORT_PATH = Path("assets/video_sprite_report.json")
RUNTIME_SIZE = 384


def bbox_for(image: Image.Image, threshold: int = 8) -> tuple[int, int, int, int]:
    alpha = np.array(image.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0 or len(ys) == 0:
        return (0, 0, image.width, image.height)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def optimize_frame(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    if image.size != (RUNTIME_SIZE, RUNTIME_SIZE):
        image = image.resize((RUNTIME_SIZE, RUNTIME_SIZE), Image.Resampling.LANCZOS)
    image.save(path, optimize=True, compress_level=9)


def validate(actions: list[str]) -> dict[str, object]:
    report: dict[str, object] = {
        "generator": "video source sprites optimized for runtime",
        "canvas": f"{RUNTIME_SIZE}x{RUNTIME_SIZE}",
        "actions": {},
        "walk_left_is_horizontal_mirror_of_walk": True,
    }
    actions_report: dict[str, object] = {}
    for action in actions:
        files = sorted((SPRITE_ROOT / action).glob("frame_*.png"))
        widths: list[int] = []
        heights: list[int] = []
        margins: list[int] = []
        bottom_margins: list[int] = []
        sizes: set[tuple[int, int]] = set()
        for path in files:
            image = Image.open(path).convert("RGBA")
            sizes.add(image.size)
            box = bbox_for(image)
            widths.append(box[2] - box[0])
            heights.append(box[3] - box[1])
            margins.append(min(box[0], box[1], RUNTIME_SIZE - box[2], RUNTIME_SIZE - box[3]))
            bottom_margins.append(RUNTIME_SIZE - box[3])
        actions_report[action] = {
            "png_count": len(files),
            "sizes": sorted([list(size) for size in sizes]),
            "min_margin_px": int(min(margins)) if margins else None,
            "bottom_margin_min_mean_max": (
                [
                    int(min(bottom_margins)),
                    round(float(np.mean(bottom_margins)), 1),
                    int(max(bottom_margins)),
                ]
                if bottom_margins
                else None
            ),
            "width_min_mean_max": (
                [
                    int(min(widths)),
                    round(float(np.mean(widths)), 1),
                    int(max(widths)),
                ]
                if widths
                else None
            ),
            "height_min_mean_max": (
                [
                    int(min(heights)),
                    round(float(np.mean(heights)), 1),
                    int(max(heights)),
                ]
                if heights
                else None
            ),
        }

    for right_path in sorted((SPRITE_ROOT / "walk").glob("frame_*.png")):
        left_path = SPRITE_ROOT / "walk_left" / right_path.name
        right = Image.open(right_path).convert("RGBA")
        left = Image.open(left_path).convert("RGBA")
        expected = right.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if ImageChops.difference(left, expected).getbbox() is not None:
            report["walk_left_is_horizontal_mirror_of_walk"] = False
            break

    report["actions"] = actions_report
    return report


def main() -> None:
    actions = ["walk", "walk_left", "teaser", "eat", "scratch", "drag", "sleep", "pet"]
    for action in actions:
        paths = sorted((SPRITE_ROOT / action).glob("frame_*.png"))
        if not paths:
            raise RuntimeError(f"{action}: no frames found")
        for path in paths:
            optimize_frame(path)

    report = validate(actions)
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k != "actions"}, indent=2))
    for action, data in report["actions"].items():  # type: ignore[union-attr]
        print(action, data)


if __name__ == "__main__":
    main()

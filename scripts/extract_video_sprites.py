from __future__ import annotations

import json
import shutil
import subprocess
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops


SIZE = 512
RUNTIME_SIZE = 384
TMP_ROOT = Path("tmp/video_frames")
OUT_ROOT = Path("assets/sprites")
REPORT_PATH = Path("assets/video_sprite_report.json")


@dataclass(frozen=True)
class ActionConfig:
    source: Path
    keep_components: int
    target_long_edge: int = 430
    bottom_margin: int = 28
    crop_pad: int = 18
    min_component_area: int = 160
    source_crop: tuple[int, int, int, int] | None = None
    frame_stride: int = 1


SOURCES: dict[str, ActionConfig] = {
    "walk": ActionConfig(
        source=Path("source_videos/walk_source.mp4"),
        keep_components=1,
        target_long_edge=430,
        bottom_margin=26,
    ),
    "teaser": ActionConfig(
        source=Path("source_videos/teaser_source.mp4"),
        keep_components=5,
        target_long_edge=430,
        bottom_margin=26,
    ),
    "eat": ActionConfig(
        source=Path("source_videos/eat_source.mp4"),
        keep_components=2,
        target_long_edge=430,
        bottom_margin=26,
    ),
    "scratch": ActionConfig(
        source=Path("source_videos/scratch_source.mp4"),
        keep_components=1,
        target_long_edge=430,
        bottom_margin=26,
    ),
    "drag": ActionConfig(
        source=Path("source_videos/drag_source.mp4"),
        keep_components=1,
        target_long_edge=430,
        bottom_margin=36,
        source_crop=(70, 120, 650, 1180),
    ),
    "sleep": ActionConfig(
        source=Path("source_videos/sleep_source.mp4"),
        keep_components=1,
        target_long_edge=430,
        bottom_margin=28,
        frame_stride=2,
    ),
    "pet": ActionConfig(
        source=Path("source_videos/pet_source.mp4"),
        keep_components=1,
        target_long_edge=430,
        bottom_margin=26,
        frame_stride=2,
    ),
}


def run_ffmpeg(source: Path, target: Path) -> None:
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            str(source),
            str(target / "raw_%04d.png"),
        ],
        check=True,
    )


def crop_source(image: Image.Image, crop: tuple[int, int, int, int] | None) -> Image.Image:
    if crop is None:
        return image
    left, top, right, bottom = crop
    return image.crop((left, top, right, bottom))


def chroma_key(image: Image.Image, config: ActionConfig) -> Image.Image:
    rgba = image.convert("RGBA")
    arr = np.array(rgba).astype(np.int16)
    rgb = arr[:, :, :3]
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]
    max_rb = np.maximum(r, b)
    green_score = g - max_rb

    hard = (g > 118) & (green_score > 42)
    soft = (g > 88) & (green_score > 18)

    alpha = np.full(g.shape, 255, dtype=np.uint8)
    alpha[hard] = 0
    edge = soft & ~hard
    alpha[edge] = np.clip(((42 - green_score[edge]) / 24) * 255, 0, 255).astype(np.uint8)

    despill = (alpha > 0) & (g > max_rb)
    arr[:, :, 1][despill] = max_rb[despill]
    arr[:, :, 3] = alpha
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return remove_small_components(
        out,
        keep_components=config.keep_components,
        min_component_area=config.min_component_area,
    )


def remove_small_components(image: Image.Image, keep_components: int, min_component_area: int) -> Image.Image:
    arr = np.array(image.convert("RGBA"))
    visible = arr[:, :, 3] > 28
    height, width = visible.shape
    visited = np.zeros_like(visible, dtype=bool)
    components: list[tuple[int, list[tuple[int, int]]]] = []

    ys, xs = np.where(visible)
    for start_x, start_y in zip(xs.tolist(), ys.tolist()):
        if visited[start_y, start_x] or not visible[start_y, start_x]:
            continue
        queue: deque[tuple[int, int]] = deque([(start_x, start_y)])
        visited[start_y, start_x] = True
        pixels: list[tuple[int, int]] = []
        while queue:
            x, y = queue.popleft()
            pixels.append((x, y))
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if nx < 0 or ny < 0 or nx >= width or ny >= height:
                    continue
                if visited[ny, nx] or not visible[ny, nx]:
                    continue
                visited[ny, nx] = True
                queue.append((nx, ny))
        components.append((len(pixels), pixels))

    components.sort(key=lambda item: item[0], reverse=True)
    keep = np.zeros_like(visible, dtype=bool)
    for area, pixels in components[:keep_components]:
        if area < min_component_area:
            continue
        for x, y in pixels:
            keep[y, x] = True

    arr[:, :, 3][~keep] = 0
    return Image.fromarray(arr, "RGBA")


def bbox_for(image: Image.Image, threshold: int = 8) -> tuple[int, int, int, int]:
    alpha = np.array(image.convert("RGBA"))[:, :, 3]
    ys, xs = np.where(alpha > threshold)
    if len(xs) == 0 or len(ys) == 0:
        return (0, 0, image.width, image.height)
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def union_bbox(boxes: list[tuple[int, int, int, int]], pad: int, width: int, height: int) -> tuple[int, int, int, int]:
    x0 = max(0, min(box[0] for box in boxes) - pad)
    y0 = max(0, min(box[1] for box in boxes) - pad)
    x1 = min(width, max(box[2] for box in boxes) + pad)
    y1 = min(height, max(box[3] for box in boxes) + pad)
    return x0, y0, x1, y1


def normalize(
    frame: Image.Image,
    crop_box: tuple[int, int, int, int],
    visible_box: tuple[int, int, int, int],
    target_long_edge: int,
    bottom_margin: int,
) -> Image.Image:
    cropped = frame.crop(crop_box)
    visible_width = max(1, visible_box[2] - visible_box[0])
    visible_height = max(1, visible_box[3] - visible_box[1])
    scale = target_long_edge / max(visible_width, visible_height)
    resized = cropped.resize(
        (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale))),
        Image.Resampling.LANCZOS,
    )

    rel_x0 = (visible_box[0] - crop_box[0]) * scale
    rel_y1 = (visible_box[3] - crop_box[1]) * scale
    visible_resized_width = visible_width * scale

    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    x = round((SIZE - visible_resized_width) / 2 - rel_x0)
    y = round(SIZE - bottom_margin - rel_y1)
    canvas.alpha_composite(resized, (x, y))

    arr = np.array(canvas.convert("RGBA"))
    arr[:, :, 3][arr[:, :, 3] < 3] = 0
    return Image.fromarray(arr, "RGBA")


def process_action(action: str, config: ActionConfig) -> int:
    if not config.source.exists():
        raise FileNotFoundError(config.source)

    raw_dir = TMP_ROOT / action
    run_ffmpeg(config.source, raw_dir)

    raw_paths = sorted(raw_dir.glob("raw_*.png"))[::config.frame_stride]
    if not raw_paths:
        raise RuntimeError(f"No frames extracted for {action}")

    keyed = [
        chroma_key(crop_source(Image.open(path), config.source_crop), config)
        for path in raw_paths
    ]
    boxes = [bbox_for(frame) for frame in keyed]
    width, height = keyed[0].size
    visible_box = union_bbox(boxes, pad=0, width=width, height=height)
    crop_box = union_bbox(boxes, pad=config.crop_pad, width=width, height=height)

    out_dir = OUT_ROOT / action
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for index, frame in enumerate(keyed):
        normalized = normalize(
            frame,
            crop_box=crop_box,
            visible_box=visible_box,
            target_long_edge=config.target_long_edge,
            bottom_margin=config.bottom_margin,
        )
        normalized.resize((RUNTIME_SIZE, RUNTIME_SIZE), Image.Resampling.LANCZOS).save(
            out_dir / f"frame_{index:03d}.png",
            optimize=True,
            compress_level=9,
        )

    return len(keyed)


def mirror_walk() -> int:
    source_dir = OUT_ROOT / "walk"
    target_dir = OUT_ROOT / "walk_left"
    if target_dir.exists():
        shutil.rmtree(target_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for path in sorted(source_dir.glob("frame_*.png")):
        img = Image.open(path).convert("RGBA").transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        img.save(target_dir / path.name, optimize=True, compress_level=9)
        count += 1
    return count


def validate(actions: list[str]) -> dict[str, object]:
    report: dict[str, object] = {
        "generator": "video source sprites optimized for runtime",
        "canvas": f"{RUNTIME_SIZE}x{RUNTIME_SIZE}",
        "actions": {},
        "walk_left_is_horizontal_mirror_of_walk": True,
    }
    actions_report: dict[str, object] = {}
    for action in actions:
        files = sorted((OUT_ROOT / action).glob("frame_*.png"))
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
            margins.append(min(box[0], box[1], image.width - box[2], image.height - box[3]))
            bottom_margins.append(image.height - box[3])
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

    for right_path in sorted((OUT_ROOT / "walk").glob("frame_*.png")):
        left_path = OUT_ROOT / "walk_left" / right_path.name
        right = Image.open(right_path).convert("RGBA")
        left = Image.open(left_path).convert("RGBA")
        expected = right.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if ImageChops.difference(left, expected).getbbox() is not None:
            report["walk_left_is_horizontal_mirror_of_walk"] = False
            break

    report["actions"] = actions_report
    return report


def main() -> None:
    counts = {action: process_action(action, config) for action, config in SOURCES.items()}
    counts["walk_left"] = mirror_walk()
    actions = ["walk", "walk_left", "teaser", "eat", "scratch", "drag", "sleep", "pet"]
    report = validate(actions)
    REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"counts": counts, **{k: v for k, v in report.items() if k != "actions"}}, indent=2))
    for action, data in report["actions"].items():  # type: ignore[union-attr]
        print(action, data)


if __name__ == "__main__":
    main()

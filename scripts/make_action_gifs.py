from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


SPRITE_DIR = Path("assets/sprites")
OUT_DIR = Path("assets/gifs")
ACTIONS = ["walk", "walk_left", "teaser", "eat", "scratch", "drag", "sleep", "pet"]
TRANSPARENT_INDEX = 255
FRAME_DURATION_MS = {
    "walk": 42,
    "walk_left": 42,
    "teaser": 42,
    "eat": 42,
    "scratch": 42,
    "drag": 42,
    "sleep": 84,
    "pet": 42,
}


def rgba_to_transparent_gif_frame(frame: Image.Image, tick: int) -> Image.Image:
    rgba = frame.convert("RGBA")
    arr = np.array(rgba)
    transparent = arr[:, :, 3] < 24

    # GIF has binary transparency. Keep antialiased edge colors opaque where
    # possible, and reserve palette index 255 for fully transparent pixels.
    arr[:, :, 3] = 255
    arr[transparent, 0:3] = [0, 255, 0]
    opaque_rgba = Image.fromarray(arr, "RGBA")

    paletted = opaque_rgba.convert(
        "P",
        palette=Image.Palette.ADAPTIVE,
        colors=255,
        dither=Image.Dither.NONE,
    )

    palette = paletted.getpalette() or []
    palette = palette[: 255 * 3]
    palette.extend([0] * (255 * 3 - len(palette)))
    palette.extend([0, 255, 0])
    paletted.putpalette(palette)

    indexed = np.array(paletted)
    indexed[transparent] = TRANSPARENT_INDEX
    # Keep visually transparent timing pixels changing so Pillow does not merge
    # near-identical frames in long video-derived loops.
    indexed[0, tick % 16] = TRANSPARENT_INDEX
    indexed[1, tick % 16] = TRANSPARENT_INDEX
    out = Image.fromarray(indexed.astype(np.uint8), "P")
    out.putpalette(palette)
    out.info["transparency"] = TRANSPARENT_INDEX
    out.info["disposal"] = 2
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for action in ACTIONS:
        frames = []
        for tick, path in enumerate(sorted((SPRITE_DIR / action).glob("frame_*.png"))):
            source = Image.open(path)
            frames.append(rgba_to_transparent_gif_frame(source, tick))
        if not frames:
            raise RuntimeError(f"{action}: no frames found")
        frames[0].save(
            OUT_DIR / f"{action}.gif",
            save_all=True,
            append_images=frames[1:],
            duration=FRAME_DURATION_MS.get(action, 75),
            loop=0,
            transparency=TRANSPARENT_INDEX,
            disposal=2,
            optimize=False,
        )
        print(OUT_DIR / f"{action}.gif")


if __name__ == "__main__":
    main()

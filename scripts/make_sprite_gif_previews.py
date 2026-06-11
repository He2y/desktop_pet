from pathlib import Path

from PIL import Image, ImageDraw


SPRITE_DIR = Path("assets/sprites")
OUT_DIR = Path("assets/previews")
ACTIONS = ["sleep", "scratch", "teaser", "walk", "walk_left"]


def checker(size: tuple[int, int], tile: int = 16) -> Image.Image:
    img = Image.new("RGBA", size, (238, 241, 245, 255))
    draw = ImageDraw.Draw(img)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                draw.rectangle((x, y, x + tile - 1, y + tile - 1), fill=(218, 224, 231, 255))
    return img


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for action in ACTIONS:
        frames = []
        for path in sorted((SPRITE_DIR / action).glob("frame_*.png")):
            bg = checker((512, 512))
            sprite = Image.open(path).convert("RGBA")
            bg.alpha_composite(sprite)
            frames.append(bg.convert("P", palette=Image.Palette.ADAPTIVE))
        frames[0].save(
            OUT_DIR / f"{action}.gif",
            save_all=True,
            append_images=frames[1:],
            duration=75,
            loop=0,
            disposal=2,
        )
    print(OUT_DIR)


if __name__ == "__main__":
    main()

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SPRITE_DIR = Path("assets/sprites")
OUT = Path("assets/sprite_preview_contact_sheet.png")
ACTIONS = ["sleep", "scratch", "teaser", "walk", "walk_left"]
FRAMES = [0, 4, 8, 12]
CELL = 168
LABEL = 34
PAD = 20


def checker(size: tuple[int, int], tile: int = 12) -> Image.Image:
    img = Image.new("RGBA", size, (236, 239, 242, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, size[1], tile):
        for x in range(0, size[0], tile):
            if (x // tile + y // tile) % 2:
                d.rectangle((x, y, x + tile - 1, y + tile - 1), fill=(215, 220, 226, 255))
    return img


def main() -> None:
    width = PAD * 2 + CELL * len(FRAMES)
    height = PAD * 2 + (CELL + LABEL) * len(ACTIONS)
    sheet = Image.new("RGBA", (width, height), (250, 250, 248, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for row, action in enumerate(ACTIONS):
        y = PAD + row * (CELL + LABEL)
        draw.text((PAD, y), action, fill=(34, 34, 34, 255), font=font)
        for col, frame in enumerate(FRAMES):
            x = PAD + col * CELL
            bg = checker((CELL - 10, CELL - 10))
            sprite = Image.open(SPRITE_DIR / action / f"frame_{frame:03d}.png").convert("RGBA")
            sprite.thumbnail((CELL - 10, CELL - 10), Image.Resampling.LANCZOS)
            bg.alpha_composite(sprite, ((CELL - 10 - sprite.width) // 2, (CELL - 10 - sprite.height) // 2))
            sheet.alpha_composite(bg, (x, y + LABEL))
            draw.rectangle((x, y + LABEL, x + CELL - 10, y + LABEL + CELL - 10), outline=(184, 190, 198, 255), width=1)
            draw.text((x + 6, y + LABEL + 6), f"{frame:03d}", fill=(42, 42, 42, 255), font=font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()

"""Build the toast textures in Media/Toasts from the source art in art/toasts.

WoW needs power-of-two textures. Each 3:1 source image is scaled to 1024x341
and placed at the top of a transparent 1024x512 canvas. The addon crops it
with SetTexCoord(0, 1, 0, 341/512).

Usage (from the repo root, needs Pillow):  python3 art/build_toasts.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "toasts"
OUT = ROOT / "Media" / "Toasts"
WIDTH, HEIGHT, CANVAS_H = 1024, 341, 512


def build(name: str) -> None:
    img = Image.open(SRC / f"{name}.webp").convert("RGBA")
    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
    canvas = Image.new("RGBA", (WIDTH, CANVAS_H), (0, 0, 0, 0))
    canvas.paste(img, (0, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    # Uncompressed 32-bit TGA, top-left origin, like the other addon textures
    canvas.save(OUT / f"{name}.tga", compression=None, orientation=1)
    print(f"{name}.tga written")


if __name__ == "__main__":
    for n in ("death", "levelup"):
        build(n)

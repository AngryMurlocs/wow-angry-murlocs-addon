"""Build the class head pins in Media/PinsHeads from art/pins.

Each source is 1024x1024 RGBA. The map pin is at most 24 px, so the texture
stays 128x128. RGB is resized premultiplied so the black outlines stay black,
then lightly sharpened. Alpha is only resized.

Usage (from the repo root, needs Pillow):  python art/build_pins.py
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "pins"
OUT = ROOT / "Media" / "PinsHeads"
SIZE = 128
CLASSES = (
    "DEATHKNIGHT",
    "DEMONHUNTER",
    "DRUID",
    "EVOKER",
    "HUNTER",
    "MAGE",
    "MONK",
    "PALADIN",
    "PRIEST",
    "ROGUE",
    "SHAMAN",
    "WARLOCK",
    "WARRIOR",
)


def resize_icon(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    r, g, b, a = img.split()
    r = ImageChops.multiply(r, a).resize((SIZE, SIZE), Image.LANCZOS)
    g = ImageChops.multiply(g, a).resize((SIZE, SIZE), Image.LANCZOS)
    b = ImageChops.multiply(b, a).resize((SIZE, SIZE), Image.LANCZOS)
    a = a.resize((SIZE, SIZE), Image.LANCZOS)
    # Unpremultiply. Alpha stays as resized; sharpen only the color.
    r = unpremultiply(r, a)
    g = unpremultiply(g, a)
    b = unpremultiply(b, a)
    rgb = Image.merge("RGB", (r, g, b))
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=0.8, percent=60, threshold=2))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def unpremultiply(channel: Image.Image, alpha: Image.Image) -> Image.Image:
    src = channel.load()
    mask = alpha.load()
    out = Image.new("L", channel.size)
    dst = out.load()
    w, h = channel.size
    for y in range(h):
        for x in range(w):
            av = mask[x, y]
            if av == 0:
                dst[x, y] = 0
            else:
                dst[x, y] = min(255, (src[x, y] * 255 + av // 2) // av)
    return out


def alpha_bounds(img: Image.Image):
    px = img.load()
    w, h = img.size
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 8:
                if x < minx:
                    minx = x
                if y < miny:
                    miny = y
                if x > maxx:
                    maxx = x
                if y > maxy:
                    maxy = y
    return minx, miny, maxx, maxy


def uv_from_bounds(bounds):
    """Cover every opaque pixel. One pixel of margin only where it fits."""
    minx, miny, maxx, maxy = bounds
    left = max(0, minx - 1)
    top = max(0, miny - 1)
    right = min(SIZE, maxx + 2)
    bottom = min(SIZE, maxy + 2)
    return (left / SIZE, right / SIZE, top / SIZE, bottom / SIZE)


def build(name: str) -> Image.Image:
    img = resize_icon(Image.open(SRC / f"{name}.png"))
    OUT.mkdir(parents=True, exist_ok=True)
    # Uncompressed 32-bit TGA, top-left origin, like the other addon textures
    img.save(OUT / f"{name}.tga", compression=None, orientation=1)
    print(f"{name}.tga written")
    return img


if __name__ == "__main__":
    union = (SIZE, SIZE, -1, -1)
    for name in CLASSES:
        img = build(name)
        b = alpha_bounds(img)
        print(f"  bounds {b} uv {tuple(round(v, 4) for v in uv_from_bounds(b))}")
        union = (
            min(union[0], b[0]),
            min(union[1], b[1]),
            max(union[2], b[2]),
            max(union[3], b[3]),
        )
    shared = tuple(round(v, 4) for v in uv_from_bounds(union))
    print(f"shared uv {shared}")

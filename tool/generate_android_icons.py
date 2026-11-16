"""Generates Finder's Android launcher + notification icons.

    python3 tool/generate_icons.py          # master icon first
    python3 tool/generate_android_icons.py

Inputs:  assets/icons/app_icon_1024.png (monochrome tile + white glyph).
Outputs (android/app/src/main/res):
  mipmap-*/ic_launcher.png               legacy launcher icon
  mipmap-*/ic_launcher_foreground.png    adaptive-icon foreground (white glyph)
  mipmap-anydpi-v26/ic_launcher.xml      adaptive icon (#111111 background,
                                         glyph foreground, themed monochrome)
  drawable-*/ic_stat_finder.png       notification small icon (white glyph)
The glyph is extracted from the master icon's white pixels, so it always
matches the brand mark.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def glyph(master: Image.Image) -> Image.Image:
    """White glyph on transparent, cropped tight."""
    rgba = master.convert("RGBA")
    alpha = Image.new("L", rgba.size, 0)
    src, dst = rgba.load(), alpha.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            # Anti-aliased glyph edges blend white into the dark tile: map the
            # darkest channel to opacity (tile pixels stay transparent).
            m = min(r, g, b)
            v = max(0, min(255, int((m - 90) * 255 / (255 - 90)))) if a > 0 else 0
            dst[x, y] = v * a // 255
    out = Image.new("RGBA", rgba.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out.crop(alpha.getbbox())


def fit(g: Image.Image, canvas: int, extent: float) -> Image.Image:
    """Centers [g] on a square canvas, its longer side = extent * canvas."""
    scale = extent * canvas / max(g.size)
    gs = g.resize((max(1, round(g.width * scale)), max(1, round(g.height * scale))), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 0))
    out.alpha_composite(gs, ((canvas - gs.width) // 2, (canvas - gs.height) // 2))
    return out


def main() -> None:
    master = Image.open(ROOT / "assets" / "icons" / "app_icon_1024.png").convert("RGBA")
    g = glyph(master)
    for name, d in DENSITIES.items():
        mip = RES / f"mipmap-{name}"
        mip.mkdir(parents=True, exist_ok=True)
        master.resize((round(48 * d),) * 2, Image.LANCZOS).save(mip / "ic_launcher.png")
        # Adaptive icons: 108dp canvas, only the inner ~66dp circle is safe.
        fit(g, round(108 * d), 0.46).save(mip / "ic_launcher_foreground.png")
        dr = RES / f"drawable-{name}"
        dr.mkdir(parents=True, exist_ok=True)
        fit(g, round(24 * d), 0.84).save(dr / "ic_stat_finder.png")
    print("android icons written")


if __name__ == "__main__":
    main()

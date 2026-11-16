"""Generates Finder's app icons (macOS asset catalog + Windows .ico).

    python3 tool/generate_icons.py

Design: monochrome rounded square (subtle charcoal → black gradient) with a
white "download into crate" glyph (arrow dropping into an open crate).
The same image is used as the in-app logo mark. Drawn at 4x and downsampled
for clean anti-aliasing.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
# Monochrome brand: charcoal → near-black (matches the light-mode palette).
PURPLE = (52, 52, 52)     # charcoal   #343434
INDIGO = (26, 26, 26)     # graphite   #1A1A1A
BLUE = (6, 6, 6)          # near-black #060606
WHITE = (255, 255, 255, 255)


def render(size: int, macos_margin: bool) -> Image.Image:
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # macOS Big Sur+ icons sit inside the canvas with room for a shadow.
    inset = int(s * 0.098) if macos_margin else int(s * 0.02)
    box = (inset, inset, s - inset, s - inset)
    w = box[2] - box[0]
    radius = int(w * 0.225)

    if macos_margin:
        shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            (box[0], box[1] + int(s * 0.012), box[2], box[3] + int(s * 0.012)),
            radius, fill=(0, 0, 0, 90))
        img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.014)))

    # Diagonal charcoal → black gradient clipped to the rounded square.
    grad = Image.new("RGBA", (s, s))
    px = grad.load()
    step = 4  # fill 4x4 blocks; the final downsample smooths them
    for y in range(0, s, step):
        for x in range(0, s, step):
            t = min(max(((x - box[0]) + (y - box[1])) / (2 * max(w, 1)), 0), 1)
            if t < 0.5:
                a, b, u = PURPLE, INDIGO, t / 0.5
            else:
                a, b, u = INDIGO, BLUE, (t - 0.5) / 0.5
            c = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,)
            for yy in range(y, min(y + step, s)):
                for xx in range(x, min(x + step, s)):
                    px[xx, yy] = c
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Soft top sheen for depth (kept subtle).
    sheen = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        (box[0] - w * 0.3, box[1] - w * 0.75, box[2] + w * 0.3, box[1] + w * 0.42),
        fill=(255, 255, 255, 22))
    sheen = sheen.filter(ImageFilter.GaussianBlur(s * 0.03))
    sheen_mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(sheen_mask).rounded_rectangle(box, radius, fill=255)
    img.paste(sheen, (0, 0), Image.composite(sheen.getchannel("A"), Image.new("L", (s, s), 0), sheen_mask))

    # Glyph: arrow dropping into an open crate.
    d = ImageDraw.Draw(img)
    cx = s / 2
    stroke = w * 0.08
    r = stroke / 2

    def dot(x, y):
        d.ellipse((x - r, y - r, x + r, y + r), fill=WHITE)

    def seg(x1, y1, x2, y2):
        d.line([(x1, y1), (x2, y2)], fill=WHITE, width=int(stroke))
        dot(x1, y1)
        dot(x2, y2)

    # Arrow
    top, tip = box[1] + w * 0.19, box[1] + w * 0.55
    seg(cx, top, cx, tip)
    hw = w * 0.17
    seg(cx - hw, tip - hw, cx, tip)
    seg(cx + hw, tip - hw, cx, tip)
    # Crate: open-top box
    cw, ct, cb = w * 0.29, box[1] + w * 0.50, box[1] + w * 0.80
    seg(cx - cw, ct, cx - cw, cb)
    seg(cx - cw, cb, cx + cw, cb)
    seg(cx + cw, cb, cx + cw, ct)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    icons = ROOT / "assets" / "icons"
    icons.mkdir(parents=True, exist_ok=True)
    render(1024, macos_margin=False).save(icons / "app_icon_1024.png")
    # Small copy for the in-app logo mark (keeps the bundle light).
    render(256, macos_margin=False).save(icons / "logo_256.png")

    mac = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        render(size, macos_margin=True).save(mac / f"app_icon_{size}.png")

    win = render(256, macos_margin=False)
    win.save(ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icons written")


if __name__ == "__main__":
    main()
